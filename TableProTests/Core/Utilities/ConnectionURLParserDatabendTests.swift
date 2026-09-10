import Foundation
@testable import TablePro
import TableProPluginKit
import Testing

@Suite("Connection URL Parser - Databend")
struct ConnectionURLParserDatabendTests {
    @Test("Full databend URL with default port")
    func testFullURLDefaultPort() {
        let result = ConnectionURLParser.parse("databend://root:pass@host:3307/default")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .databend)
        #expect(parsed.host == "host")
        #expect(parsed.port == nil)
        #expect(parsed.database == "default")
        #expect(parsed.username == "root")
        #expect(parsed.password == "pass")
    }

    @Test("Case-insensitive Databend scheme")
    func testCaseInsensitiveScheme() {
        let result = ConnectionURLParser.parse("Databend://root@host/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .databend)
        #expect(parsed.host == "host")
        #expect(parsed.username == "root")
    }

    @Test("Databend non-default port preserved")
    func testNonDefaultPortPreserved() {
        let result = ConnectionURLParser.parse("databend://root:pass@host:3306/db")
        guard case .success(let parsed) = result else {
            Issue.record("Expected success"); return
        }
        #expect(parsed.type == .databend)
        #expect(parsed.port == 3_306)
        #expect(parsed.host == "host")
        #expect(parsed.database == "db")
    }
}
