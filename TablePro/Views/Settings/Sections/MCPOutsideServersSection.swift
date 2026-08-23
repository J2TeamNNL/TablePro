//
//  MCPOutsideServersSection.swift
//  TablePro
//

import SwiftUI

/// Servers TablePro calls, as opposed to the one it runs.
///
/// The two directions live in one pane because a reader looking for "MCP" does not know which of
/// them they need, and the sentence about what leaves the machine belongs next to the list of places
/// it can go.
internal struct MCPOutsideServersSection: View {
    private let store = MCPServerStore.shared

    @State private var name: String = ""
    @State private var endpoint: String = ""
    @State private var token: String = ""
    @State private var error: MCPServerConfigurationError?
    @State private var probeResult: String?
    @State private var isProbing = false

    internal var body: some View {
        Section(String(localized: "Outside MCP Servers")) {
            Text(String(localized: """
                A session can call these servers as tools. Whatever the assistant hands one, \
                including schema and query results, leaves this Mac.
                """))
                .font(.callout)
                .foregroundStyle(.secondary)

            ForEach(store.servers) { server in
                serverRow(server)
            }

            if store.servers.isEmpty {
                Text(String(localized: "No servers added."))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }

        Section(String(localized: "Add a Server")) {
            TextField(String(localized: "Name"), text: $name)
            TextField(String(localized: "Endpoint"), text: $endpoint, prompt: Text(verbatim: "https://example.com/mcp"))
            SecureField(String(localized: "Bearer token"), text: $token)

            if let error {
                Text(Self.message(for: error))
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            if let probeResult {
                Text(probeResult)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button(String(localized: "Add")) { add() }
                    .disabled(name.isEmpty || endpoint.isEmpty)
                Button(String(localized: "Test")) { Task { await test() } }
                    .disabled(isProbing || endpoint.isEmpty || token.isEmpty)
                if isProbing {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
        }

        Section {
            Text(String(localized: """
                A tool from an outside server always waits for your approval, in every chat mode, \
                and every call is recorded in the audit log with the size of what was sent.
                """))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func serverRow(_ server: MCPServerConfiguration) -> some View {
        LabeledContent {
            Button(String(localized: "Remove"), role: .destructive) {
                store.remove(id: server.id)
            }
            .buttonStyle(.link)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                Text(verbatim: server.endpoint.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    server.allowedConnectionIds.isEmpty
                        ? String(localized: "Not allowed on any connection yet")
                        : String(
                            format: String(localized: "Allowed on %d connections"),
                            server.allowedConnectionIds.count
                        )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func draft() -> MCPServerConfiguration? {
        guard let url = URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return MCPServerConfiguration(name: name.trimmingCharacters(in: .whitespacesAndNewlines), endpoint: url)
    }

    private func add() {
        probeResult = nil
        guard let configuration = draft() else {
            error = .invalidEndpoint
            return
        }
        error = store.upsert(configuration, token: token)
        guard error == nil else { return }
        name = ""
        endpoint = ""
        token = ""
    }

    /// Test writes the server first, because the credential lives in the Keychain under the server's
    /// id and there is nothing to read a token from until it does. A test that fails leaves the entry
    /// in place with no connection allowed, which reaches nothing.
    private func test() async {
        probeResult = nil
        guard let configuration = draft() else {
            error = .invalidEndpoint
            return
        }
        error = store.upsert(configuration, token: token)
        guard error == nil else { return }
        isProbing = true
        defer { isProbing = false }
        switch await MCPRemoteToolCoordinator.shared.probe(configuration) {
        case .success(let tools):
            probeResult = String(
                format: String(localized: "Answered with %d tools."),
                tools.count
            )
        case .failure(let failure):
            probeResult = failure.localizedMessage
        }
    }

    private static func message(for error: MCPServerConfigurationError) -> String {
        switch error {
        case .emptyName:
            return String(localized: "Give the server a name.")
        case .reservedName:
            return String(localized: "That name is reserved for TablePro's own MCP server. Pick another.")
        case .invalidEndpoint:
            return String(localized: "The endpoint must be an http or https URL with a host.")
        case .insecureEndpoint:
            return String(localized: "Plain http is only allowed for a server on this Mac. Use https.")
        }
    }
}
