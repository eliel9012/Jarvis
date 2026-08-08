import Foundation

/// Gerencia o processo do backend Python local (127.0.0.1:8765).
/// Detecta se já está ativo, inicia caso contrário, monitora e reinicia.
@MainActor
final class BackendManager: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var startedByApp = false

    static let backendURL = URL(string: "http://127.0.0.1:8765")!

    private let projectDir: URL
    private let pythonPath: URL
    private let serverPath: URL
    private var process: Process?
    private var monitorTask: Task<Void, Never>?
    private var isStarting = false
    private var lastStartAttempt: Date?
    /// Backend python carrega libs pesadas (transformers/scipy) — boot pode passar de 30s.
    private let startupGracePeriod: TimeInterval = 45

    init(
        projectDir: URL = URL(fileURLWithPath: NSString(string: "~/Developer/Jarvis").expandingTildeInPath)
    ) {
        self.projectDir = projectDir
        self.pythonPath = projectDir
            .appendingPathComponent("Backend/.venv/bin/python")
        self.serverPath = projectDir
            .appendingPathComponent("Backend/api/server.py")
    }

    deinit {
        monitorTask?.cancel()
    }

    func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let healthy = await self.isBackendHealthy()
                self.isRunning = healthy
                if !healthy {
                    self.startBackendIfNeeded()
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func isBackendHealthy() async -> Bool {
        var request = URLRequest(url: BackendManager.backendURL.appendingPathComponent("health"))
        request.timeoutInterval = 3
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            return false
        }
        return true
    }

    func startBackendIfNeeded() {
        guard !isRunning else { return }
        // Processo anterior ainda vivo (subindo ou travado) -> não duplica.
        if let proc = process, proc.isRunning { return }
        // Dentro do grace period do último start -> ainda pode estar carregando libs pesadas.
        if let last = lastStartAttempt, Date().timeIntervalSince(last) < startupGracePeriod { return }
        guard !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        // `process` é nil aqui, então nada nosso está de pé: se algo ainda segura a porta
        // é lixo órfão de uma sessão anterior (ex: Xcode manda SIGKILL no app e o filho
        // Python sobrevive). Limpa antes de tentar subir, senão o bind falha pra sempre.
        killStaleListener()

        let exists = FileManager.default.fileExists(atPath: pythonPath.path)
        guard exists else {
            lastError = "Backend Python não encontrado em \(pythonPath.path)"
            return
        }
        let proc = Process()
        proc.executableURL = pythonPath
        proc.arguments = [serverPath.path]
        proc.currentDirectoryURL = serverPath.deletingLastPathComponent()

        let logURL = projectDir.appendingPathComponent("Logs/backend.out.log")
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let outHandle = FileHandle(forWritingAtPath: logURL.path)
        proc.standardOutput = outHandle
        proc.standardError = outHandle
        proc.terminationHandler = { [weak self] terminated in
            Task { @MainActor in
                guard let self, self.process === terminated else { return }
                self.process = nil
            }
        }

        do {
            try proc.run()
            startedByApp = true
            process = proc
            lastStartAttempt = Date()
            lastError = nil
            print("[BackendManager] backend iniciado (pid \(proc.processIdentifier))")
        } catch {
            lastError = "Falha ao iniciar backend: \(error.localizedDescription)"
        }
    }

    /// Mata qualquer processo escutando em 127.0.0.1:8765 que não seja o `process` que rastreamos.
    /// Só chamado quando `process` já é nil, ou seja: o que estiver lá é órfão de sessão anterior.
    private func killStaleListener() {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        lsof.arguments = ["-ti", "tcp:8765"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        lsof.standardError = FileHandle.nullDevice
        do {
            try lsof.run()
        } catch {
            return
        }
        lsof.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return }
        let pids = output.split(separator: "\n").compactMap { Int32($0) }
        guard !pids.isEmpty else { return }
        for pid in pids {
            print("[BackendManager] matando listener órfão na porta 8765 (pid \(pid))")
            kill(pid, SIGKILL)
        }
    }

    func stopBackend() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        startedByApp = false
        isRunning = false
    }
}
