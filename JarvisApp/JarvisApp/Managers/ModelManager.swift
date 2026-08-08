import Foundation

/// Status dos modelos locais (instalado/faltando/carregando/carregado).
@MainActor
final class ModelManager: ObservableObject {
    struct ModelStatus: Identifiable {
        let id: String
        let name: String
        let kind: Kind
        var installed: Bool
        var sizeBytes: Int64
        var loaded: Bool

        enum Kind: String { case llm, stt, tts }
    }

    @Published private(set) var models: [ModelStatus] = []
    private let hfCache = URL(fileURLWithPath: NSString(string: "~/Library/Caches/huggingface/hub").expandingTildeInPath)

    init() {
        refresh()
    }

    func refresh() {
        let candidates: [(String, String, ModelStatus.Kind)] = [
            ("qwen/qwen3.6-35b-a3b", "Qwen 3.6 35B A3B (Quality)", .llm),
            ("qwen/qwen3.5-9b", "Qwen 3.5 9B (Fast)", .llm),
            ("mlx-community/whisper-large-v3-turbo-asr-fp16", "Whisper Large v3 Turbo", .stt),
            ("mlx-community/fish-audio-s2-pro-bf16", "Fish S2 Pro BF16", .tts),
            ("mlx-community/fish-audio-s2-pro-8bit", "Fish S2 Pro 8-bit", .tts),
        ]
        models = candidates.map { id, name, kind in
            let installed = modelInstalled(id)
            return ModelStatus(
                id: id,
                name: name,
                kind: kind,
                installed: installed.0,
                sizeBytes: installed.1,
                loaded: false
            )
        }
    }

    private func modelInstalled(_ repoID: String) -> (Bool, Int64) {
        let folderName = "models--" + repoID.replacingOccurrences(of: "/", with: "--")
        let dir = hfCache.appendingPathComponent(folderName)
        guard FileManager.default.fileExists(atPath: dir.path) else { return (false, 0) }
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
            for case let file as URL in enumerator {
                if let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]),
                   let size = values.totalFileAllocatedSize {
                    total += Int64(size)
                }
            }
        }
        let hasWeights = total > 1_000_000
        return (hasWeights, total)
    }
}
