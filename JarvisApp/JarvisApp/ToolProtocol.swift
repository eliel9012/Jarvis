import Foundation

/// Contrato de ferramentas para expansão futura. Nenhuma ferramenta é
/// exposta ao LLM nesta versão (ver FASE 24 do projeto).
protocol ToolProtocol {
    var name: String { get }
    var description: String { get }
    func execute(input: [String: Any]) async throws -> String
}
