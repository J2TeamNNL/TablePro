import Foundation
import Security
import TableProPluginKit
import TableProTrinoCore

enum TrinoSSLMapping {
    static func tlsOptions(for ssl: SSLConfiguration) throws -> TrinoTLSOptions {
        let mode: TrinoTLSOptions.VerificationMode
        switch ssl.mode {
        case .disabled, .preferred, .required:
            mode = .insecure
        case .verifyCa:
            mode = .caOnly
        case .verifyIdentity:
            mode = .full
        }
        return TrinoTLSOptions(
            mode: mode,
            anchorCertificate: try anchorCertificate(at: ssl.caCertificatePath, for: mode),
            clientCertificatePath: ssl.clientCertificatePath,
            clientKeyPath: ssl.clientKeyPath
        )
    }

    static func anchorCertificate(at path: String, for mode: TrinoTLSOptions.VerificationMode) throws -> Data? {
        let trimmedPath = path.trimmingCharacters(in: .whitespaces)
        guard mode != .insecure, !trimmedPath.isEmpty else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: trimmedPath)),
              let der = PEMCertificateDecoder.certificateDER(from: data),
              SecCertificateCreateWithData(nil, der as CFData) != nil else {
            throw TrinoError.invalidConfiguration(String(
                format: String(localized: "The CA certificate at %@ could not be read as a PEM or DER certificate."),
                trimmedPath
            ))
        }
        return der
    }
}

extension TrinoTLSFailureKind {
    func sslHandshakeError(serverMessage: String) -> SSLHandshakeError {
        switch self {
        case .serverRejectedPlaintext: return .serverRejectedPlaintext(serverMessage: serverMessage)
        case .untrustedCertificate: return .untrustedCertificate(serverMessage: serverMessage)
        case .hostnameMismatch: return .hostnameMismatch(serverMessage: serverMessage)
        case .clientCertificateUnusable: return .clientKeyInvalid(serverMessage: serverMessage)
        }
    }
}
