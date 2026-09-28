import Foundation
import TableProPluginKit
import XCTest

final class HanaPluginDriverTests: XCTestCase {
    func testMetadataDescribesNativeHanaTransportAndSafeScope() {
        XCTAssertEqual(HanaPlugin.databaseTypeId, "SAP HANA")
        XCTAssertEqual(HanaPlugin.defaultPort, 443)
        XCTAssertTrue(HanaPlugin.isDownloadable)
        XCTAssertTrue(HanaPlugin.supportsSSL)
        XCTAssertFalse(HanaPlugin.supportsSSH)
        XCTAssertFalse(HanaPlugin.supportsSchemaEditing)
        XCTAssertFalse(HanaPlugin.supportsAddColumn)
        XCTAssertFalse(HanaPlugin.supportsModifyColumn)
        XCTAssertFalse(HanaPlugin.supportsDropColumn)
        XCTAssertFalse(HanaPlugin.supportsAddIndex)
        XCTAssertFalse(HanaPlugin.supportsDropIndex)
        XCTAssertFalse(HanaPlugin.supportsForeignKeys)
        XCTAssertTrue(HanaPlugin.additionalConnectionFields.contains { $0.id == HanaMetadata.tlsServerNameField })
    }

    func testIdentifierAndLiteralQuotingCannotEscapeTheirContext() {
        XCTAssertEqual(HanaPluginDriver.quoteIdentifier("a\"b"), "\"a\"\"b\"")
        XCTAssertEqual(HanaPluginDriver.quoteLiteral("a'b"), "'a''b'")
    }

    func testCatalogQueriesUseSchemaLiteralsAndQualifiedIdentifiers() {
        let driver = HanaPluginDriver(config: DriverConnectionConfig(
            host: "hana.example", port: 443, username: "USER", password: "test-only", database: "APP"
        ))
        XCTAssertEqual(driver.currentSchema, "APP")
        XCTAssertEqual(HanaPluginDriver.quoteIdentifier("APP"), "\"APP\"")
    }
}
