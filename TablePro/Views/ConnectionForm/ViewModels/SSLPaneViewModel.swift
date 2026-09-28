//
//  SSLPaneViewModel.swift
//  TablePro
//

import Combine
import Foundation
import TableProPluginKit

enum SSLModeOrigin: Equatable {
    case typeDefault
    case impliedByPort
    case chosen
}

@MainActor
final class SSLPaneViewModel: ObservableObject {
    @Published private(set) var mode: SSLMode = .disabled
    private(set) var origin: SSLModeOrigin = .typeDefault
    @Published var caCertPath: String = ""
    @Published var clientCertPath: String = ""
    @Published var clientKeyPath: String = ""
    @Published var clientKeyPassphrase: String = ""

    @Published var coordinator: WeakCoordinatorRef?

    /// Silent on a driver that renders no SSL section, so a stored mode the form cannot show
    /// cannot disable Save over a certificate field the user has no way to reach.
    var validationIssues: [String] {
        guard coordinator?.value?.supportsSSL ?? true else { return [] }
        let type = coordinator?.value?.network.type
        guard type?.supportsPerConnectionCertificatePaths ?? true else { return [] }
        var issues: [String] = []
        let requiresCA = type?.requiresCACertificate(for: mode) ?? (mode == .verifyCa || mode == .verifyIdentity)
        if requiresCA, caCertPath.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(String(localized: "CA certificate is required for verification modes"))
        }
        let hasClientCert = !clientCertPath.trimmingCharacters(in: .whitespaces).isEmpty
        let hasClientKey = !clientKeyPath.trimmingCharacters(in: .whitespaces).isEmpty
        if hasClientCert && !hasClientKey {
            issues.append(String(localized: "Client key is required when client certificate is set"))
        }
        return issues
    }

    func select(_ newMode: SSLMode) {
        mode = newMode
        origin = .chosen
    }

    func applyImported(_ importedMode: SSLMode?, disablesTLS: Bool, port: Int, type: DatabaseType) {
        if let explicitMode = importedMode ?? (disablesTLS ? .disabled : nil) {
            select(explicitMode)
            return
        }
        mode = type.defaultSSLMode
        origin = .typeDefault
        reconcile(port: port, type: type)
    }

    func reconcile(port: Int, type: DatabaseType) {
        let impliedMode = type.impliedSSLMode(forPort: port)
        switch origin {
        case .chosen:
            return
        case .typeDefault:
            guard let impliedMode else { return }
            mode = impliedMode
            origin = .impliedByPort
        case .impliedByPort:
            guard let impliedMode else {
                mode = type.defaultSSLMode
                origin = .typeDefault
                return
            }
            mode = impliedMode
        }
    }

    func load(from connection: DatabaseConnection) {
        mode = connection.sslConfig.mode
        origin = mode == connection.type.defaultSSLMode ? .typeDefault : .chosen
        caCertPath = connection.sslConfig.caCertificatePath
        clientCertPath = connection.sslConfig.clientCertificatePath
        clientKeyPath = connection.sslConfig.clientKeyPath
        clientKeyPassphrase = ConnectionStorage.shared.loadSSLClientKeyPassphrase(for: connection.id) ?? ""
    }

    func resetForType(_ type: DatabaseType) {
        mode = type.defaultSSLMode
        origin = .typeDefault
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
