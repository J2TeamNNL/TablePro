import Foundation

protocol HanaSession: AnyObject, Sendable {
    var hasLostConnection: Bool { get }

    func connect(_ configuration: HanaConnectConfiguration) async throws -> HanaConnectResult
    func disconnect()
    func ping() async throws
    func execute(sql: String, parameters: [HanaBridgeCell]?, rowCap: Int) async throws -> HanaResultEnvelope
    func explain(sql: String) async throws -> HanaResultEnvelope
    func cancelRunning()
    func applyQueryTimeout(seconds: Int)
}
