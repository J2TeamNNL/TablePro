//
//  ConnectionURLParserTLSPortTests.swift
//  TableProTests
//

import Foundation
import TableProPluginKit
import Testing

@testable import TablePro

@MainActor
struct ConnectionURLParserTLSPortTests {
    private func parse(_ urlString: String) throws -> ParsedConnectionURL {
        guard case .success(let parsed) = ConnectionURLParser.parse(urlString) else {
            throw ConnectionURLParseError.invalidURL
        }
        return parsed
    }

    @Test("trino on port 443 with no SSL parameter implies Verify Identity")
    func trinoOn443ImpliesVerifyIdentity() throws {
        let parsed = try parse("trino://analyst@trino.example.com:443/hive")
        #expect(parsed.sslMode == nil)
        #expect(parsed.portImpliedSSLMode == .verifyIdentity)
    }

    @Test("An explicit ssl=false keeps port 443 on plain HTTP, as the Trino JDBC driver does")
    func explicitSSLFalseWinsOverThePort() throws {
        for url in [
            "trino://trino.example.com:443/hive?SSL=false",
            "trino://trino.example.com:443/hive?ssl=false",
            "trino://trino.example.com:443/hive?tls=false"
        ] {
            let parsed = try parse(url)
            #expect(parsed.disablesTLS, "\(url)")
            #expect(parsed.portImpliedSSLMode == nil, "\(url)")
        }
    }

    @Test("An explicit SSL mode is kept and the port adds nothing")
    func explicitModeIsKept() throws {
        let parsed = try parse("trino://trino.example.com:443/hive?sslmode=require")
        #expect(parsed.sslMode == .required)
        #expect(parsed.portImpliedSSLMode == nil)
    }

    @Test("trino on 8443 or its default port implies nothing, since no Trino client infers TLS there")
    func trinoOtherPortsImplyNothing() throws {
        #expect(try parse("trino://trino.example.com:8443/hive").portImpliedSSLMode == nil)
        #expect(try parse("trino://trino.example.com:8080/hive").portImpliedSSLMode == nil)
        #expect(try parse("trino://trino.example.com/hive").portImpliedSSLMode == nil)
    }

    @Test("ClickHouse on 443 or 8443 implies Verify Identity, and on 8123 nothing")
    func clickHouseTLSPorts() throws {
        #expect(try parse("clickhouse://default@ch.example.com:8443/default").portImpliedSSLMode == .verifyIdentity)
        #expect(try parse("clickhouse://default@ch.example.com:443/default").portImpliedSSLMode == .verifyIdentity)
        #expect(try parse("clickhouse://default@ch.example.com:8123/default").portImpliedSSLMode == nil)
    }

    @Test("A deep link to trino on port 443 opens with Verify Identity")
    func transientConnectionUsesTheImpliedMode() throws {
        let connection = TransientConnectionFactory.build(from: try parse("trino://trino.example.com:443/hive"))
        #expect(connection.sslConfig.mode == .verifyIdentity)
    }

    @Test("A deep link to trino on port 443 with ssl=false stays on plain HTTP")
    func transientConnectionHonoursSSLFalse() throws {
        let connection = TransientConnectionFactory.build(from: try parse("trino://trino.example.com:443/hive?SSL=false"))
        #expect(connection.sslConfig.mode == .disabled)
    }
}
