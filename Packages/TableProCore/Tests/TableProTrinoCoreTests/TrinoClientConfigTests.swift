import Foundation
@testable import TableProTrinoCore
import Testing

@Suite("TrinoClientConfig")
struct TrinoClientConfigTests {
    @Test("The TLS setting alone picks the scheme, so an explicit SSL off on 443 stays plain HTTP")
    func statementURLScheme() {
        let plainHTTP = TrinoClientConfig(host: "trino.example.com", port: 443, user: "tablepro")
        let https = TrinoClientConfig(host: "trino.example.com", port: 443, useTLS: true, user: "tablepro")

        #expect(plainHTTP.statementURL?.absoluteString == "http://trino.example.com:443/v1/statement")
        #expect(https.statementURL?.absoluteString == "https://trino.example.com:443/v1/statement")
    }
}
