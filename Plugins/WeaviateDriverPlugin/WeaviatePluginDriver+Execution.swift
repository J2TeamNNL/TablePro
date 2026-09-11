import Foundation
import TableProPluginKit
import TableProWeaviateCore

extension WeaviatePluginDriver {
    func execute(query: String) async throws -> PluginQueryResult {
        let started = Date()
        let client = try requireClient()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.lowercased() == "select 1" {
            try await client.ping()
            return PluginQueryResult(
                columns: ["ok"],
                columnTypeNames: ["int"],
                rows: [[.text("1")]],
                rowsAffected: 0,
                executionTime: Date().timeIntervalSince(started)
            )
        }

        if WeaviateBrowseQuery.isTagged(trimmed) {
            return try await executeSearch(trimmed, client: client, started: started)
        }
        if WeaviateWriteCodec.isTagged(trimmed) {
            return try await executeWrite(trimmed, client: client, started: started)
        }
        if let console = WeaviateConsoleParser.parse(trimmed) {
            return try await executeConsole(console, client: client, started: started)
        }
        if WeaviateGraphQL.looksLikeGraphQL(trimmed) {
            return try await executeGraphQL(trimmed, client: client, started: started)
        }

        throw WeaviateError.malformedResponse(
            String(localized: "Enter a GraphQL query, or a request like GET /v1/schema.")
        )
    }

    private func executeSearch(
        _ query: String,
        client: WeaviateClient,
        started: Date
    ) async throws -> PluginQueryResult {
        guard let parsed = WeaviateBrowseQuery.parse(query) else {
            throw WeaviateError.malformedResponse("Invalid browse request.")
        }
        let collection = try await cachedCollection(parsed.collection)
        let objects: [WeaviateObject]
        if parsed.usesGraphQL {
            let graphql = WeaviateGraphQL.getQuery(
                collection: parsed.collection,
                properties: parsed.propertyNames,
                limit: parsed.limit,
                offset: parsed.offset,
                sorts: parsed.sorts,
                filters: parsed.filters,
                logicMode: parsed.logicMode
            )
            let response = try await client.graphql(graphql)
            objects = WeaviateObjectCodec.objects(fromGraphQL: response.json as Any)
        } else {
            objects = try await client.objects(
                collection: parsed.collection,
                limit: parsed.limit,
                offset: parsed.offset
            )
        }
        return render(objects: objects, collection: collection, columns: parsed.propertyNames, started: started)
    }

    private func executeWrite(
        _ statement: String,
        client: WeaviateClient,
        started: Date
    ) async throws -> PluginQueryResult {
        guard let request = WeaviateWriteCodec.decode(statement) else {
            throw WeaviateError.malformedResponse("Invalid write request.")
        }
        let response = try await client.execute(write: request)
        let outcome: String
        if let json = WeaviateJSON.dictionary(response.json), let id = json["id"] as? String {
            outcome = id
        } else if response.statusCode == 204 {
            outcome = "deleted"
        } else {
            outcome = "ok"
        }
        return PluginQueryResult(
            columns: ["result"],
            columnTypeNames: ["text"],
            rows: [[.text(outcome)]],
            rowsAffected: 1,
            executionTime: Date().timeIntervalSince(started)
        )
    }

    private func executeConsole(
        _ request: WeaviateConsoleRequest,
        client: WeaviateClient,
        started: Date
    ) async throws -> PluginQueryResult {
        if request.method == "POST", request.path.hasPrefix("/v1/graphql"), let body = request.body {
            return try await executeGraphQL(body, client: client, started: started)
        }
        let response = try await client.execute(console: request)
        if request.path.hasPrefix("/v1/objects"), let json = response.json {
            let objects = WeaviateObject.parseList(json)
            if !objects.isEmpty {
                let collectionName = objects.first?.className ?? ""
                let collection = (try? await cachedCollection(collectionName))
                    ?? WeaviateCollection(name: collectionName, properties: [])
                let columns = WeaviateSchema.columns(for: collection).map(\.name)
                return render(objects: objects, collection: collection, columns: columns, started: started)
            }
        }
        return renderJSON(response, started: started)
    }

    private func executeGraphQL(
        _ query: String,
        client: WeaviateClient,
        started: Date
    ) async throws -> PluginQueryResult {
        let response = try await client.graphql(query)
        let objects = WeaviateObjectCodec.objects(fromGraphQL: response.json as Any)
        if !objects.isEmpty {
            let collectionName = objects.first?.className ?? ""
            let collection = (try? await cachedCollection(collectionName))
                ?? WeaviateCollection(name: collectionName, properties: [])
            var columns = WeaviateSchema.columns(for: collection).map(\.name)
            if columns.count <= WeaviateSchema.metaColumns.count {
                var seen = Set<String>()
                columns = []
                for name in [WeaviateSchema.uuidColumn]
                    + objects.flatMap({ $0.properties.keys.sorted() })
                    + [WeaviateSchema.vectorColumn]
                {
                    if seen.insert(name).inserted {
                        columns.append(name)
                    }
                }
            }
            return render(objects: objects, collection: collection, columns: columns, started: started)
        }
        return renderJSON(response, started: started)
    }

    private func render(
        objects: [WeaviateObject],
        collection: WeaviateCollection,
        columns: [String],
        started: Date
    ) -> PluginQueryResult {
        let resolved = columns.isEmpty
            ? WeaviateSchema.columns(for: collection).map(\.name)
            : columns
        let rows = objects.map { object in
            WeaviateObjectCodec.row(for: object, columns: resolved).map { value in
                value.map(PluginCellValue.text) ?? .null
            }
        }
        return PluginQueryResult(
            columns: resolved,
            columnTypeNames: resolved.map { typeName(for: $0, collection: collection) },
            rows: rows,
            rowsAffected: 0,
            executionTime: Date().timeIntervalSince(started)
        )
    }

    private func renderJSON(_ response: WeaviateHTTPResponse, started: Date) -> PluginQueryResult {
        let pretty: String
        if let json = response.json, JSONSerialization.isValidJSONObject(json),
           let text = try? WeaviateJSON.text(json, pretty: true) {
            pretty = text
        } else {
            pretty = response.text
        }
        return PluginQueryResult(
            columns: ["response"],
            columnTypeNames: ["json"],
            rows: [[.text(pretty)]],
            rowsAffected: 0,
            executionTime: Date().timeIntervalSince(started)
        )
    }
}
