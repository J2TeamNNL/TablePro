//
//  MCPClientSession.swift
//  TablePro
//

import Foundation
import os

internal struct MCPRemoteTool: Equatable, Sendable {
    internal let name: String
    internal let description: String
    internal let inputSchema: JsonValue
}

internal enum MCPClientError: Error, Equatable, Sendable {
    case notConfigured
    case timedOut
    case transport(String)
    case server(code: Int, message: String)
    case malformedResponse

    internal var localizedMessage: String {
        switch self {
        case .notConfigured:
            return String(localized: "This server has no credential. Add its token in Settings > Integrations.")
        case .timedOut:
            return String(localized: "The server did not answer in time.")
        case .transport(let detail):
            return detail
        case .server(_, let message):
            return message
        case .malformedResponse:
            return String(localized: "The server's answer could not be read.")
        }
    }
}

/// One conversation with an outside MCP server: initialize, list its tools, call one.
///
/// The transport underneath is fire-and-forget with a single inbound stream, so request and response
/// are correlated here by JSON-RPC id. Every call carries its own deadline, because a server that
/// never answers must fail the call rather than park the chat stream behind it for as long as URLSession
/// is willing to wait.
internal actor MCPClientSession {
    nonisolated private static let logger = Logger(subsystem: "com.TablePro", category: "MCPClientSession")

    /// Short on purpose. This sits inside a chat turn, and a reader watching a reply stop is a worse
    /// outcome than a tool call that reports a timeout the model can work around.
    internal static let defaultTimeout: Duration = .seconds(30)

    private let configuration: MCPServerConfiguration
    private let transport: MCPStreamableHttpClientTransport
    private let timeout: Duration

    private var pending: [JsonRpcId: CheckedContinuation<JsonValue, Error>] = [:]
    private var readerTask: Task<Void, Never>?
    private var nextRequestId = 1
    private var didInitialize = false
    private var isClosed = false

    internal init(
        configuration: MCPServerConfiguration,
        transport: MCPStreamableHttpClientTransport,
        timeout: Duration = MCPClientSession.defaultTimeout
    ) {
        self.configuration = configuration
        self.transport = transport
        self.timeout = timeout
    }

    /// Builds a session against a stored server, or nil when it has no credential. A server with no
    /// token is not called with none: an unauthenticated request to a URL the user configured for an
    /// authenticated one is a request they did not ask for.
    @MainActor
    internal static func make(
        configuration: MCPServerConfiguration,
        store: MCPServerStore = .shared,
        timeout: Duration = MCPClientSession.defaultTimeout
    ) -> MCPClientSession? {
        guard let token = store.token(for: configuration.id) else { return nil }
        let credentials = MCPUpstreamCredentials(endpoint: configuration.endpoint, bearerToken: token)
        let provider = MCPCachedUpstreamCredentialsProvider(initial: credentials) { credentials }
        return MCPClientSession(
            configuration: configuration,
            transport: MCPStreamableHttpClientTransport(credentialsProvider: provider),
            timeout: timeout
        )
    }

    internal func listTools() async throws -> [MCPRemoteTool] {
        try await initializeIfNeeded()
        let result = try await send(method: "tools/list", params: nil)
        guard case .object(let fields) = result, case .array(let rawTools)? = fields["tools"] else {
            throw MCPClientError.malformedResponse
        }
        return rawTools.compactMap(Self.decodeTool)
    }

    /// Calls one tool and returns its content as text.
    ///
    /// The result is text, never parsed for anything the app then acts on. A remote server's answer
    /// is data: a result that reads like an instruction is shown to the reader and ignored by
    /// everything else.
    internal func callTool(name: String, arguments: JsonValue) async throws -> String {
        try await initializeIfNeeded()
        let result = try await send(
            method: "tools/call",
            params: .object(["name": .string(name), "arguments": arguments])
        )
        return Self.flattenContent(result)
    }

    internal func close() async {
        guard !isClosed else { return }
        isClosed = true
        readerTask?.cancel()
        readerTask = nil
        let outstanding = pending
        pending.removeAll()
        for (_, continuation) in outstanding {
            continuation.resume(throwing: MCPClientError.transport(
                String(localized: "The connection to the server was closed.")
            ))
        }
        await transport.close()
    }

    // MARK: - Protocol

    private func initializeIfNeeded() async throws {
        guard !didInitialize else { return }
        didInitialize = true
        _ = try await send(
            method: "initialize",
            params: .object([
                "protocolVersion": .string(MCPProtocolVersion.latest.rawValue),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("TablePro"),
                    "version": .string(Bundle.main.appVersion)
                ])
            ])
        )
    }

    private func send(method: String, params: JsonValue?) async throws -> JsonValue {
        guard !isClosed else { throw MCPClientError.transport(String(localized: "The session is closed.")) }
        startReaderIfNeeded()

        let id = JsonRpcId.number(Int64(nextRequestId))
        nextRequestId += 1
        let request = JsonRpcRequest(id: id, method: method, params: params)
        let body: Data
        do {
            body = try JsonRpcCodec.encode(.request(request))
        } catch {
            throw MCPClientError.malformedResponse
        }

        let deadline = Task { [timeout, weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            await self?.failPending(id: id, error: .timedOut)
        }
        defer { deadline.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do {
                    try await transport.send(
                        MCPUpstreamFrame(body: body, method: method, name: nil, requestId: id)
                    )
                } catch {
                    await self.failPending(id: id, error: .transport(String(describing: error)))
                }
            }
        }
    }

    private func startReaderIfNeeded() {
        guard readerTask == nil else { return }
        readerTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await payload in await self.transport.inbound {
                    await self.receive(payload)
                }
            } catch {
                await self.failAll(error: .transport(String(describing: error)))
            }
        }
    }

    private func receive(_ payload: Data) {
        guard let message = try? JsonRpcCodec.decode(payload) else { return }
        switch message {
        case .successResponse(let response):
            pending.removeValue(forKey: response.id)?.resume(returning: response.result)
        case .errorResponse(let response):
            guard let id = response.id else { return }
            pending.removeValue(forKey: id)?.resume(
                throwing: MCPClientError.server(code: response.error.code, message: response.error.message)
            )
        case .request, .notification:
            /// A server-initiated request is not answered. TablePro is the client here, and a client
            /// that served a sampling or elicitation request would be letting the server drive the
            /// session, which is the whole thing the approval gate exists to prevent.
            Self.logger.debug("Ignoring server-initiated message from an outside MCP server")
        }
    }

    private func failPending(id: JsonRpcId, error: MCPClientError) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func failAll(error: MCPClientError) {
        let outstanding = pending
        pending.removeAll()
        for (_, continuation) in outstanding {
            continuation.resume(throwing: error)
        }
    }

    // MARK: - Decoding

    private static func decodeTool(_ value: JsonValue) -> MCPRemoteTool? {
        guard case .object(let fields) = value,
              case .string(let name)? = fields["name"],
              !name.isEmpty
        else { return nil }
        let description: String
        if case .string(let text)? = fields["description"] {
            description = text
        } else {
            description = ""
        }
        return MCPRemoteTool(
            name: name,
            description: description,
            inputSchema: fields["inputSchema"] ?? .object([:])
        )
    }

    /// MCP returns content as an array of typed parts. Only text is taken: an image or an embedded
    /// resource from an outside server would be a second thing to trust, and the tool result the
    /// model reads is text either way.
    internal static func flattenContent(_ result: JsonValue) -> String {
        guard case .object(let fields) = result else { return "" }
        guard case .array(let parts)? = fields["content"] else {
            return fields["structuredContent"]?.jsonString(prettyPrinted: true) ?? ""
        }
        let texts: [String] = parts.compactMap { part in
            guard case .object(let partFields) = part,
                  case .string("text")? = partFields["type"],
                  case .string(let text)? = partFields["text"]
            else { return nil }
            return text
        }
        return texts.joined(separator: "\n")
    }
}
