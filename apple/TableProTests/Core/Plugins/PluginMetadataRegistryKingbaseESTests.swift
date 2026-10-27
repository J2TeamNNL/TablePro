import Foundation
@testable import TablePro
import TableProPluginKit
import Testing

@MainActor
struct PluginMetadataRegistryKingbaseESTests {
    @Test("KingbaseES is offered before installation and resolves to its own registry plugin")
    func registryIdentity() throws {
        let registry = PluginMetadataRegistry.shared
        #expect(registry.allRegisteredTypeIds().contains("KingbaseES"))
        #expect(registry.pluginTypeId(for: "KingbaseES") == "KingbaseES")
        #expect(DatabaseType.kingbasees.isDownloadablePlugin)
        let snapshot = try #require(registry.snapshot(forRegisteredTypeId: "KingbaseES"))
        #expect(snapshot.displayName == "KingbaseES")
        #expect(snapshot.defaultPort == 54_321)
        #expect(snapshot.urlSchemes == ["kingbase", "kingbase8"])
        #expect(snapshot.parameterStyle == .dollar)
        #expect(snapshot.schema.systemSchemaNames.contains("sys_catalog"))
        #expect(snapshot.capabilities.supportsSchemaSwitching)
        #expect(snapshot.connection.additionalConnectionFields.map(\.id) == ["usePgpass", "connectionOptions"])
    }
}
