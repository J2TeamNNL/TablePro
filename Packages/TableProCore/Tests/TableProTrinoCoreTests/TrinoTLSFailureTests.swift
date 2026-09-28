import Foundation
@testable import TableProTrinoCore
import Testing

private let nginxPlaintextRejection = """
<html>
<head><title>400 The plain HTTP request was sent to HTTPS port</title></head>
<body>
<center><h1>400 Bad Request</h1></center>
<center>The plain HTTP request was sent to HTTPS port</center>
<hr><center>nginx</center>
</body>
</html>
"""

private let goPlaintextRejection = "Client sent an HTTP request to an HTTPS server.\n"

private func client(_ transport: StubTransport, useTLS: Bool) -> TrinoStatementClient {
    let config = TrinoClientConfig(host: "trino.example.com", port: 443, useTLS: useTLS, user: "u")
    return TrinoStatementClient(transport: transport, config: config, session: TrinoSessionState())
}

private func failure(of transport: StubTransport, useTLS: Bool) async -> TrinoError? {
    do {
        _ = try await client(transport, useTLS: useTLS).execute("SELECT version()")
        return nil
    } catch let error as TrinoError {
        return error
    } catch {
        return nil
    }
}

struct TrinoResponseTextTests {
    @Test("An HTML error page reads as its title")
    func htmlReadsAsTitle() {
        #expect(TrinoResponseText.readable(nginxPlaintextRejection) == "400 The plain HTTP request was sent to HTTPS port")
    }

    @Test("A body that is not HTML is kept as it is")
    func plainBodyIsKept() {
        #expect(TrinoResponseText.readable("Query exceeded limit") == "Query exceeded limit")
        #expect(TrinoResponseText.readable(goPlaintextRejection) == goPlaintextRejection)
    }

    @Test("An HTML page with no title reads as its visible text rather than as markup")
    func untitledHTMLReadsAsVisibleText() {
        let page = "<html><body><h1>413 Request Entity Too Large</h1><hr><center>nginx</center></body></html>"
        #expect(TrinoResponseText.readable(page) == "413 Request Entity Too Large nginx")
    }

    @Test("A body that only mentions HTML is not treated as a page")
    func bodyQuotingHTMLIsKept() {
        let body = "Unsupported content type: <html> is not accepted"
        #expect(TrinoResponseText.readable(body) == body)
    }

    @Test("nginx's and Go's replies to plain HTTP on a TLS port are recognised, and only as a 400")
    func plaintextRejectionMarkers() {
        #expect(TrinoResponseText.isPlaintextRejection(statusCode: 400, body: nginxPlaintextRejection))
        #expect(TrinoResponseText.isPlaintextRejection(statusCode: 400, body: goPlaintextRejection))
        #expect(!TrinoResponseText.isPlaintextRejection(statusCode: 404, body: nginxPlaintextRejection))
        #expect(!TrinoResponseText.isPlaintextRejection(statusCode: 400, body: "line 1:8: mismatched input"))
    }
}

struct TrinoTLSFailureTests {
    @Test("A plain HTTP request refused by a TLS port reports the TLS failure, not the page (#3166)")
    func plaintextRejectionIsATLSFailure() async {
        let transport = StubTransport([canned(nginxPlaintextRejection, status: 400)])

        let error = await failure(of: transport, useTLS: false)

        #expect(error == .tlsHandshakeFailed(
            kind: .serverRejectedPlaintext,
            serverMessage: "400 The plain HTTP request was sent to HTTPS port"
        ))
        #expect(error?.errorDescription?.contains("<html>") == false)
    }

    @Test("Go's reply to plain HTTP on a TLS port reports the same TLS failure")
    func goPlaintextRejectionIsATLSFailure() async {
        let transport = StubTransport([canned(goPlaintextRejection, status: 400)])

        let error = await failure(of: transport, useTLS: false)

        guard case .tlsHandshakeFailed(.serverRejectedPlaintext, _)? = error else {
            Issue.record("Expected a plaintext rejection, got \(String(describing: error))")
            return
        }
    }

    @Test("With TLS already on, the same page never blames the SSL mode")
    func tlsOnDoesNotBlameTheSSLMode() async {
        let transport = StubTransport([canned(nginxPlaintextRejection, status: 400)])

        let error = await failure(of: transport, useTLS: true)

        #expect(error == .httpStatus(code: 400, body: "400 The plain HTTP request was sent to HTTPS port"))
    }

    @Test("An HTML sign-in page from a proxy reads as its title")
    func htmlAuthenticationFailureReadsAsTitle() async {
        let page = "<html><head><title>401 Authorization Required</title></head><body>nginx</body></html>"
        let transport = StubTransport([canned(page, status: 401)])

        let error = await failure(of: transport, useTLS: true)

        #expect(error == .authenticationFailed("401 Authorization Required"))
    }

    @Test("An http:// nextUri on an HTTPS connection is refused before any credential is sent over it")
    func downgradedNextUriIsNotFollowed() async {
        let transport = StubTransport([
            canned(#"{"id":"q1","nextUri":"http://trino.example.com:443/v1/statement/executing/q1/1"}"#)
        ])
        let config = TrinoClientConfig(
            host: "trino.example.com", port: 443, useTLS: true, user: "u", auth: .basic(password: "secret")
        )
        let client = TrinoStatementClient(transport: transport, config: config, session: TrinoSessionState())

        do {
            _ = try await client.execute("SELECT 1")
            Issue.record("Expected the downgraded nextUri to be refused")
        } catch let error as TrinoError {
            guard case .invalidResponse(let detail) = error else {
                Issue.record("Expected invalidResponse, got \(error)")
                return
            }
            #expect(detail.contains("http-server.process-forwarded"))
        } catch {
            Issue.record("Unexpected error \(error)")
        }
        #expect(transport.requests.allSatisfy { $0.url.scheme == "https" })
    }

    @Test("An https:// nextUri on a plain HTTP connection is followed")
    func upgradedNextUriIsFollowed() async throws {
        let transport = StubTransport([
            canned(#"{"id":"q1","nextUri":"https://trino.example.com/v1/statement/executing/q1/1"}"#),
            canned(#"{"id":"q1"}"#)
        ])
        _ = try await client(transport, useTLS: false).execute("SELECT 1")
        #expect(transport.requests.count == 2)
    }

    @Test("A certificate the request refused reports as a TLS failure, not as a cancel")
    func refusedTrustIsNotACancel() {
        let refusal = TrinoTrustRefusal(kind: .hostnameMismatch, message: "certificate is for otherhost")

        #expect(URLSessionTrinoTransport.failure(for: URLError(.cancelled), refusedTrust: refusal)
            == .tlsHandshakeFailed(kind: .hostnameMismatch, serverMessage: "certificate is for otherhost"))
        #expect(URLSessionTrinoTransport.failure(for: URLError(.cancelled), refusedTrust: nil) == .cancelled)
    }

    @Test("A certificate URLSession itself rejected reports as an untrusted certificate")
    func systemTrustFailureIsUntrusted() {
        for code in [
            URLError.Code.serverCertificateUntrusted,
            .serverCertificateHasBadDate,
            .serverCertificateHasUnknownRoot,
            .serverCertificateNotYetValid
        ] {
            guard case .tlsHandshakeFailed(.untrustedCertificate, _) =
                URLSessionTrinoTransport.failure(for: URLError(code), refusedTrust: nil) else {
                Issue.record("\(code.rawValue) should be an untrusted certificate")
                continue
            }
        }
        guard case .transport = URLSessionTrinoTransport.failure(for: URLError(.timedOut), refusedTrust: nil) else {
            Issue.record("A timeout is not a TLS failure")
            return
        }
    }
}
