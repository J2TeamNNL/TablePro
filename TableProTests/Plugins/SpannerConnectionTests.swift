import Foundation
@testable import TablePro
import TableProPluginKit
import Testing

@Suite("Spanner connection config")
struct SpannerConnectionTests {
    @Test("Connect config requires project, instance, and database")
    func missingIdentityFields() {
        let empty = DriverConnectionConfig(
            host: "", port: 0, username: "", password: "", database: "",
            additionalFields: [:]
        )
        #expect(throws: SpannerError.self) {
            _ = try SpannerConnection(config: empty)
        }

        let partial = DriverConnectionConfig(
            host: "", port: 0, username: "", password: "", database: "",
            additionalFields: ["spProjectId": "proj"]
        )
        #expect(throws: SpannerError.self) {
            _ = try SpannerConnection(config: partial)
        }
    }

    @Test("Valid identity fields construct a production client")
    func validIdentity() throws {
        let config = DriverConnectionConfig(
            host: "", port: 0, username: "", password: "", database: "",
            additionalFields: [
                "spProjectId": "proj",
                "spInstanceId": "inst",
                "spDatabaseId": "db"
            ]
        )
        let conn = try SpannerConnection(config: config)
        #expect(conn.gcpProjectId == "proj")
        #expect(conn.instance == "inst")
        #expect(conn.database == "db")
        #expect(conn.databasePath == "projects/proj/instances/inst/databases/db")
        #expect(conn.dialect == .googleSQL)
    }
}

@Suite("Spanner registry snapshot")
struct SpannerRegistrySnapshotTests {
    @Test("Cloud defaults hide the built-in password and require instance plus database")
    func snapshotFields() throws {
        let defaults = PluginMetadataRegistry.shared.registryPluginDefaults()
        let entry = try #require(defaults.first { $0.typeId == "Spanner" })
        #expect(entry.snapshot.connection.hidesBuiltInPassword)
        #expect(entry.snapshot.connectionMode == .apiOnly)
        #expect(entry.snapshot.defaultPort == 0)
        #expect(entry.snapshot.schema.containerEntityName == "Schema")
        let ids = entry.snapshot.connection.additionalConnectionFields.map(\.id)
        #expect(ids.contains("spProjectId"))
        #expect(ids.contains("spInstanceId"))
        #expect(ids.contains("spDatabaseId"))
        #expect(ids.contains("spAuthMethod"))
        #expect(ids.contains("spEndpoint"))
    }
}
