import Foundation

public struct TrinoQueryError: Decodable, Sendable, Equatable {
    public let message: String
    public let errorCode: Int?
    public let errorName: String?
    public let errorType: String?

    public init(message: String, errorCode: Int? = nil, errorName: String? = nil, errorType: String? = nil) {
        self.message = message
        self.errorCode = errorCode
        self.errorName = errorName
        self.errorType = errorType
    }

    private enum CodingKeys: String, CodingKey {
        case message, errorCode, errorName, errorType
    }
}

public enum TrinoTLSFailureKind: Sendable, Equatable {
    case serverRejectedPlaintext
    case untrustedCertificate
    case hostnameMismatch
    case clientCertificateUnusable
}

public enum TrinoError: Error, LocalizedError, Equatable {
    case invalidConfiguration(String)
    case notConnected
    case transport(String)
    case httpStatus(code: Int, body: String)
    case tlsHandshakeFailed(kind: TrinoTLSFailureKind, serverMessage: String)
    case authenticationFailed(String)
    case query(TrinoQueryError)
    case invalidResponse(String)
    case cancelled
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let detail):
            return detail
        case .notConnected:
            return "Not connected to Trino"
        case .transport(let detail):
            return detail
        case .httpStatus(let code, let body):
            return body.isEmpty ? "HTTP \(code)" : "HTTP \(code): \(body)"
        case .tlsHandshakeFailed(let kind, let serverMessage):
            return Self.describe(kind, serverMessage: serverMessage)
        case .authenticationFailed(let detail):
            return detail
        case .query(let error):
            if let name = error.errorName, !name.isEmpty {
                return "\(name): \(error.message)"
            }
            return error.message
        case .invalidResponse(let detail):
            return detail
        case .cancelled:
            return "Query was cancelled"
        case .timedOut:
            return "Timed out waiting for Trino"
        }
    }

    private static func describe(_ kind: TrinoTLSFailureKind, serverMessage: String) -> String {
        let reason: String
        switch kind {
        case .serverRejectedPlaintext:
            reason = "The server accepts only HTTPS, and SSL is off for this connection. Set SSL Mode to Verify Identity."
        case .untrustedCertificate:
            reason = "The server's TLS certificate is not trusted."
        case .hostnameMismatch:
            reason = "The server's TLS certificate does not match the host."
        case .clientCertificateUnusable:
            reason = "The client certificate and key could not be read as a certificate identity."
        }
        return serverMessage.isEmpty ? reason : "\(reason) \(serverMessage)"
    }
}
