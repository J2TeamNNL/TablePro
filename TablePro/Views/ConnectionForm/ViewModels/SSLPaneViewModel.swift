//
//  SSLPaneViewModel.swift
//  TablePro
//

import Combine
import Foundation
import TableProPluginKit

@MainActor
final class SSLPaneViewModel: ObservableObject {
    @Published var mode: SSLMode = .disabled
    @Published var caCertPath: String = ""
    @Published var clientCertPath: String = ""
    @Published var clientKeyPath: String = ""
    @Published var clientKeyPassphrase: String = ""

    @Published var coordinator: WeakCoordinatorRef?

    /// Silent on a driver that renders no SSL section, so a stored mode the form cannot show
    /// cannot disable Save over a certificate field the user has no way to reach.
    var validationIssues: [String] {
        let owner = coordinator?.value
        guard owner?.supportsSSL ?? true else { return [] }
        let trustsSystemRoots = owner?.network.type.verifiesTLSWithSystemTrustStore ?? false
        return caCertificateIssues(trustsSystemRoots: trustsSystemRoots) + clientKeyIssues
    }

    private func caCertificateIssues(trustsSystemRoots: Bool) -> [String] {
        guard mode == .verifyCa || mode == .verifyIdentity, !trustsSystemRoots else { return [] }
        guard caCertPath.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return [String(localized: "CA certificate is required for verification modes")]
    }

    private var clientKeyIssues: [String] {
        let hasClientCert = !clientCertPath.trimmingCharacters(in: .whitespaces).isEmpty
        let hasClientKey = !clientKeyPath.trimmingCharacters(in: .whitespaces).isEmpty
        guard hasClientCert, !hasClientKey else { return [] }
        return [String(localized: "Client key is required when client certificate is set")]
    }

    func load(from connection: DatabaseConnection) {
        mode = connection.sslConfig.mode
        caCertPath = connection.sslConfig.caCertificatePath
        clientCertPath = connection.sslConfig.clientCertificatePath
        clientKeyPath = connection.sslConfig.clientKeyPath
        clientKeyPassphrase = ConnectionStorage.shared.loadSSLClientKeyPassphrase(for: connection.id) ?? ""
    }

    func resetForType(_ type: DatabaseType) {
        mode = type.defaultSSLMode
        caCertPath = ""
        clientCertPath = ""
        clientKeyPath = ""
        clientKeyPassphrase = ""
    }

    func buildConfig() -> SSLConfiguration {
        SSLConfiguration(
            mode: mode,
            caCertificatePath: caCertPath,
            clientCertificatePath: clientCertPath,
            clientKeyPath: clientKeyPath
        )
    }
}
