import TableProPluginKit
@testable import TablePro
import Testing

struct SSLSectionsTests {
    @Test("Trino port 443 warns only while TLS is disabled")
    func trinoHTTPSPortWarning() {
        #expect(SSLSections.trinoTLSWarning(databaseType: .trino, serverPort: 443, sslMode: .disabled) != nil)
        #expect(SSLSections.trinoTLSWarning(databaseType: .trino, serverPort: 443, sslMode: .verifyIdentity) == nil)
        #expect(SSLSections.trinoTLSWarning(databaseType: .trino, serverPort: 8080, sslMode: .disabled) == nil)
        #expect(SSLSections.trinoTLSWarning(databaseType: .postgresql, serverPort: 443, sslMode: .disabled) == nil)
    }
}
