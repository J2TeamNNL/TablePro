import Foundation
import TableProPluginKit

// Run by check-neo4j.sh against a live server. Exits 1 on the first expectation that fails.

let environment = ProcessInfo.processInfo.environment
var ssl = SSLConfiguration()
ssl.mode = SSLMode(rawValue: environment["TP_NEO4J_SSL_MODE"] ?? "") ?? .disabled
ssl.caCertificatePath = environment["TP_NEO4J_CA"] ?? ""
let driver = Neo4jPluginDriver(config: DriverConnectionConfig(
    host: environment["TP_NEO4J_HOST"] ?? "127.0.0.1",
    port: Int(environment["TP_NEO4J_PORT"] ?? "") ?? 7_687,
    username: environment["TP_NEO4J_USER"] ?? "neo4j",
    password: environment["TP_NEO4J_PASSWORD"] ?? "",
    database: "",
    ssl: ssl
))
let label = "TableProProbe\(Int.random(in: 100_000 ... 999_999))"
var failures = 0

func expect(_ condition: Bool, _ message: String) {
    print(condition ? "ok   \(message)" : "FAIL \(message)")
    if !condition { failures += 1 }
}

func text(_ result: PluginQueryResult) -> [[String?]] {
    result.rows.map { $0.map(\.asText) }
}

func run() async throws {
    try await driver.connect()
    print("server: \(driver.serverVersion ?? "unknown"), database: \(driver.currentDatabase)")

    _ = try await driver.execute(query: """
    CREATE (a:\(label) {name: 'Ann', age: 30, born: date('1994-05-01')}),
           (b:\(label) {name: 'Bo', email: 'bo@example.com'}),
           (a)-[:\(label)_KNOWS {since: 2020}]->(b)
    """)

    let databases = try await driver.fetchDatabases()
    expect(databases.contains(driver.currentDatabase), "the current database is listed: \(databases)")

    let tables = try await driver.fetchTablesInAllSchemas() ?? []
    expect(tables.contains { $0.name == label && $0.schema == "Labels" }, "the label is listed under Labels")
    expect(tables.contains { $0.name == "\(label)_KNOWS" && $0.schema == "Relationship Types" },
           "the relationship type is listed under Relationship Types")

    let columns = try await driver.fetchColumns(table: label, schema: "Labels").map(\.name)
    expect(columns == ["<id>", "<labels>", "age", "born", "email", "name"], "columns: \(columns)")
    let count = try await driver.fetchApproximateRowCount(table: label, schema: "Labels")
    expect(count == 2, "row count: \(String(describing: count))")

    let nameIndex = try require(columns.firstIndex(of: "name"))
    let browse = try require(driver.buildBrowseQuery(
        table: label, schema: "Labels", sortColumns: [(nameIndex, true)], columns: columns, limit: 200, offset: 0
    ))
    let page = try await driver.execute(query: browse)
    expect(page.columns == columns, "browse columns: \(page.columns)")
    expect(text(page).map { $0[nameIndex] } == ["Ann", "Bo"], "browse sorts by name")
    expect(text(page).first?[columns.firstIndex(of: "born") ?? 0] == "1994-05-01", "a date reads as Cypher writes it")

    let relationships = try await driver.execute(query: try require(driver.buildBrowseQuery(
        table: "\(label)_KNOWS", schema: "Relationship Types", sortColumns: [], columns: [], limit: 200, offset: 0
    )))
    expect(relationships.columns == ["<id>", "<start>", "<end>", "since"], "relationship columns: \(relationships.columns)")

    let capped = try await driver.executeUserQuery(query: "UNWIND range(1, 50) AS x RETURN x", rowCap: 10, parameters: nil)
    expect(capped.rows.count == 10 && capped.isTruncated, "a row cap truncates on the server")
    let afterCap = try await driver.execute(query: "RETURN 3 AS ok")
    expect(text(afterCap) == [["3"]], "the next statement runs after a capped one")

    let cappedWrite = try await driver.executeUserQuery(
        query: "UNWIND range(1, 12) AS x CREATE (n:\(label) {seq: x}) RETURN n", rowCap: 10, parameters: nil
    )
    expect(cappedWrite.rows.count == 10 && cappedWrite.isTruncated, "a capped write returns the capped rows")
    expect(cappedWrite.rowsAffected == 12, "a capped write counts every node it created: \(cappedWrite.rowsAffected)")
    _ = try await driver.execute(query: "MATCH (n:\(label)) WHERE n.seq IS NOT NULL DELETE n")

    let setOnly = try await driver.execute(query: "MATCH (n:\(label) {name: 'Ann'}) SET n.a = 1, n.b = 2")
    expect(setOnly.rowsAffected == 0 && setOnly.statusMessage == "2 property value(s) set",
           "a property update reports its counter: \(setOnly.rowsAffected), \(setOnly.statusMessage ?? "nil")")

    let duration = try await driver.execute(query: "RETURN duration({seconds: 10000000000}) AS d")
    expect(text(duration) == [["PT2777777H46M40S"]], "a long duration formats: \(text(duration))")

    let path = try await driver.execute(
        query: "MATCH p = (:\(label) {name: 'Bo'})<-[:\(label)_KNOWS]-(:\(label) {name: 'Ann'}) RETURN p"
    )
    let pathObject = try require(text(path).first?.first.flatMap { $0 }.flatMap {
        try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
    })
    let pathNodes = (pathObject["nodes"] as? [[String: Any]] ?? []).compactMap { $0["elementId"] as? String }
    let pathStep = (pathObject["relationships"] as? [[String: Any]])?.first
    expect(pathNodes.count == 2 && pathStep?["startElementId"] as? String == pathNodes.last
               && pathStep?["endElementId"] as? String == pathNodes.first,
           "a path walked against its relationship keeps the relationship's direction")

    try driver.cancelQuery()
    let afterIdleCancel = try await driver.execute(query: "RETURN 4 AS ok")
    expect(text(afterIdleCancel) == [["4"]], "a cancel with nothing running leaves the next statement alone")

    do {
        _ = try await driver.execute(query: "MATCH (n RETURN n")
        expect(false, "a syntax error throws")
    } catch {
        expect(true, "a syntax error throws: \(error.localizedDescription.prefix(60))")
    }
    let afterError = try await driver.execute(query: "RETURN 1 AS ok")
    expect(text(afterError) == [["1"]], "the connection recovers after an error")

    let slow = Task { try await driver.execute(query: "UNWIND range(1, 1000000000) AS x WITH x WHERE x < 0 RETURN count(x)") }
    try await Task.sleep(nanoseconds: 500_000_000)
    try driver.cancelQuery()
    do {
        _ = try await slow.value
        expect(false, "cancel stops a running query")
    } catch {
        expect(true, "cancel stops a running query")
    }
    let afterCancel = try await driver.execute(query: "RETURN 2 AS ok")
    expect(text(afterCancel) == [["2"]], "the connection recovers after a cancel")
}

struct RequireError: Error {}

func require<T>(_ value: T?) throws -> T {
    guard let value else { throw RequireError() }
    return value
}

let done = DispatchSemaphore(value: 0)
Task {
    do {
        try await run()
        _ = try? await driver.execute(query: "MATCH (n:\(label)) DETACH DELETE n")
    } catch {
        print("FAIL \(error.localizedDescription)")
        failures += 1
    }
    driver.disconnect()
    done.signal()
}
done.wait()
exit(failures == 0 ? 0 : 1)
