import Foundation
import TableProPluginKit

extension PluginMetadataRegistry {
    func kingbaseESPluginDefaults() -> [(typeId: String, snapshot: PluginMetadataSnapshot)] {
        guard let postgres = Self.curatedDefaults().first(where: { $0.typeId == "PostgreSQL" })?.snapshot else {
            return []
        }
        return [("KingbaseES", PluginMetadataSnapshot(
            displayName: "KingbaseES", iconName: "postgresql-icon", defaultPort: 54_321,
            requiresAuthentication: true, supportsForeignKeys: postgres.supportsForeignKeys,
            supportsSchemaEditing: postgres.supportsSchemaEditing, isDownloadable: true,
            primaryUrlScheme: "kingbase", parameterStyle: .dollar,
            navigationModel: postgres.navigationModel, explainVariants: postgres.explainVariants,
            pathFieldRole: .database, supportsHealthMonitor: postgres.supportsHealthMonitor,
            urlSchemes: ["kingbase", "kingbase8"], postConnectActions: postgres.postConnectActions,
            brandColorHex: "#C9141E", queryLanguageName: "SQL", editorLanguage: .sql,
            connectionMode: .network, supportsDatabaseSwitching: postgres.supportsDatabaseSwitching,
            structureEditing: postgres.structureEditing,
            capabilities: postgres.capabilities, schema: postgres.schema, editor: postgres.editor,
            connection: PluginMetadataSnapshot.ConnectionConfig(
                additionalConnectionFields: postgres.connection.additionalConnectionFields.filter {
                    ["usePgpass", "connectionOptions"].contains($0.id)
                },
                category: .relational,
                tagline: postgres.connection.tagline
            )
        ).withSystemNames(
            databases: postgres.schema.systemDatabaseNames,
            schemas: postgres.schema.systemSchemaNames + ["sys_catalog"]
        ))]
    }
}
