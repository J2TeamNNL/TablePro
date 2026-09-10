import Foundation
import os
import TableProPluginKit

internal struct SpannerExecuteResult: Sendable {
    let fields: [SpannerField]
    let rows: [[SpannerJSONValue]]
    let rowsAffected: Int
    let transactionId: String?
}

internal struct SpannerResultSet: Decodable {
    let metadata: Metadata?
    let rows: [[SpannerJSONValue]]?
    let stats: Stats?

    struct Metadata: Decodable {
        let rowType: RowType?
        let transaction: Transaction?

        struct RowType: Decodable {
            let fields: [SpannerField]?
        }

        struct Transaction: Decodable {
            let id: String?
        }
    }

    struct Stats: Decodable {
        let rowCountExact: String?
    }
}

private struct SpannerAPIErrorBody: Decodable {
    let error: Detail?

    struct Detail: Decodable {
        let code: Int?
        let message: String?
        let status: String?
    }
}

internal final class SpannerConnection: @unchecked Sendable {
    private let config: DriverConnectionConfig
    private let lock = NSLock()
    private var _session: URLSession?
    private var _authProvider: SpannerAuthProvider?
    private var _currentTask: URLSessionDataTask?
    private var _queryTimeoutSeconds: Int = 300
    private let _queryTimeout = HttpQueryTimeoutBox()
    private var _spannerSession: String?
    private var _transactionId: String?
    private var _seqno: Int = 0
    private var _dialect: SpannerDialectKind = .googleSQL
    private let projectId: String
    private let instanceId: String
    private let databaseId: String
    private let baseURL: URL
    private let usesEmulator: Bool
    private static let logger = Logger(subsystem: "com.TablePro", category: "SpannerConnection")
    private static let productionHost = "https://spanner.googleapis.com"

    var dialect: SpannerDialectKind {
        lock.withLock { _dialect }
    }

    var gcpProjectId: String { projectId }
    var instance: String { instanceId }
    var database: String { databaseId }

    var databasePath: String {
        "projects/\(projectId)/instances/\(instanceId)/databases/\(databaseId)"
    }

    func setQueryTimeout(_ seconds: Int) {
        lock.withLock { _queryTimeoutSeconds = max(seconds, 30) }
        _queryTimeout.set(serverTimeoutSeconds: seconds)
    }

    init(config: DriverConnectionConfig) throws {
        self.config = config
        let project = (config.additionalFields["spProjectId"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let instance = (config.additionalFields["spInstanceId"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let database = (config.additionalFields["spDatabaseId"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if project.isEmpty {
            throw SpannerError.missingConfiguration("Project ID is required")
        }
        if instance.isEmpty {
            throw SpannerError.missingConfiguration("Instance ID is required")
        }
        if database.isEmpty {
            throw SpannerError.missingConfiguration("Database is required")
        }
        self.projectId = project
        self.instanceId = instance
        self.databaseId = database

        let endpoint = (config.additionalFields["spEndpoint"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if endpoint.isEmpty {
            guard let url = URL(string: Self.productionHost) else {
                throw SpannerError.invalidResponse("Invalid production endpoint")
            }
            self.baseURL = url
            self.usesEmulator = false
        } else if let url = URL(string: endpoint) {
            self.baseURL = url
            self.usesEmulator = endpoint.lowercased().hasPrefix("http://")
        } else {
            throw SpannerError.missingConfiguration("REST Endpoint is not a valid URL")
        }
    }

    func connect() async throws {
        let authProvider = try createAuthProvider()
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = HttpQueryTimeout.sessionBootstrapRequestTimeout
        sessionConfig.timeoutIntervalForResource = HttpQueryTimeout.sessionResourceTimeout
        let urlSession = URLSession(configuration: sessionConfig)

        lock.withLock {
            _authProvider = authProvider
            _session = urlSession
        }

        do {
            let dialectRaw = try await fetchDatabaseDialect()
            let sessionName = try await createSession()
            lock.withLock {
                _dialect = SpannerDialectKind.parse(dialectRaw)
                _spannerSession = sessionName
            }
            _ = try await executeSQL("SELECT 1", transaction: readOnlySingleUse(), queryMode: nil, seqno: nil)
        } catch {
            disconnect()
            throw error
        }
    }

    func disconnect() {
        let (sessionName, urlSession): (String?, URLSession?) = lock.withLock {
            let name = _spannerSession
            let url = _session
            _currentTask?.cancel()
            _currentTask = nil
            _spannerSession = nil
            _transactionId = nil
            _seqno = 0
            _session = nil
            _authProvider = nil
            return (name, url)
        }
        if let sessionName, let urlSession {
            Task {
                try? await deleteSession(sessionName, session: urlSession)
            }
        }
        urlSession?.invalidateAndCancel()
    }

    func ping() async throws {
        _ = try await executeSQL("SELECT 1", transaction: readOnlySingleUse(), queryMode: nil, seqno: nil)
    }

    func cancelCurrentRequest() {
        lock.withLock {
            _currentTask?.cancel()
            _currentTask = nil
        }
    }

    func beginReadWriteTransaction() async throws {
        try await ensureSession()
        let body: [String: Any] = ["options": ["readWrite": [String: Any]()]]
        let payload = try await postJSON(path: ":beginTransaction", relativeToSession: true, body: body)
        guard let id = payload["id"] as? String, !id.isEmpty else {
            throw SpannerError.invalidResponse("beginTransaction returned no id")
        }
        lock.withLock {
            _transactionId = id
            _seqno = 0
        }
    }

    func commitTransaction() async throws {
        let txn = lock.withLock { _transactionId }
        guard let txn else { return }
        let body: [String: Any] = ["transactionId": txn]
        _ = try await postJSON(path: ":commit", relativeToSession: true, body: body)
        lock.withLock {
            _transactionId = nil
            _seqno = 0
        }
    }

    func rollbackTransaction() async throws {
        let txn = lock.withLock { _transactionId }
        guard let txn else { return }
        let body: [String: Any] = ["transactionId": txn]
        _ = try await postJSON(path: ":rollback", relativeToSession: true, body: body)
        lock.withLock {
            _transactionId = nil
            _seqno = 0
        }
    }

    var hasOpenTransaction: Bool {
        lock.withLock { _transactionId != nil }
    }

    func execute(_ sql: String, queryMode: String? = nil) async throws -> SpannerExecuteResult {
        let kind = SpannerSQLClassification.classify(sql)
        switch kind {
        case .begin:
            try await beginReadWriteTransaction()
            return SpannerExecuteResult(fields: [], rows: [], rowsAffected: 0, transactionId: lock.withLock { _transactionId })
        case .commit:
            try await commitTransaction()
            return SpannerExecuteResult(fields: [], rows: [], rowsAffected: 0, transactionId: nil)
        case .rollback:
            try await rollbackTransaction()
            return SpannerExecuteResult(fields: [], rows: [], rowsAffected: 0, transactionId: nil)
        case .ddl:
            try await updateDDL([sql])
            return SpannerExecuteResult(fields: [], rows: [], rowsAffected: 0, transactionId: nil)
        case .dml:
            return try await executeDML(sql)
        case .query:
            let txn = lock.withLock { _transactionId }
            let selector: [String: Any]
            if let txn {
                selector = ["id": txn]
            } else {
                selector = readOnlySingleUse()
            }
            return try await executeSQL(sql, transaction: selector, queryMode: queryMode, seqno: nil)
        }
    }

    func executeReadOnly(_ sql: String) async throws -> SpannerExecuteResult {
        try await executeSQL(sql, transaction: readOnlySingleUse(), queryMode: nil, seqno: nil)
    }

    func fetchDDL() async throws -> [String] {
        let payload = try await getJSON(path: "/v1/\(databasePath)/ddl", relativeToSession: false)
        return payload["statements"] as? [String] ?? []
    }

    private func executeDML(_ sql: String) async throws -> SpannerExecuteResult {
        if lock.withLock({ _transactionId != nil }) {
            let seq = lock.withLock { _seqno += 1; return _seqno }
            let txn = lock.withLock { _transactionId } ?? ""
            return try await executeSQL(sql, transaction: ["id": txn], queryMode: nil, seqno: seq)
        }

        var lastError: Error = SpannerError.invalidResponse("DML failed")
        for _ in 0..<2 {
            do {
                try await ensureSession()
                let seq = 1
                let result = try await executeSQL(
                    sql,
                    transaction: ["begin": ["readWrite": [String: Any]()]],
                    queryMode: nil,
                    seqno: seq
                )
                if let txn = result.transactionId {
                    lock.withLock { _transactionId = txn }
                    try await commitTransaction()
                }
                return result
            } catch let error as SpannerError {
                lastError = error
                if case .aborted = error {
                    lock.withLock {
                        _transactionId = nil
                        _seqno = 0
                    }
                    try? await refreshSession()
                    continue
                }
                if case .sessionExpired = error {
                    try await refreshSession()
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    private func executeSQL(
        _ sql: String,
        transaction: [String: Any]?,
        queryMode: String?,
        seqno: Int?
    ) async throws -> SpannerExecuteResult {
        try await ensureSession()
        var body: [String: Any] = ["sql": sql]
        if let transaction {
            body["transaction"] = transaction
        }
        if let queryMode {
            body["queryMode"] = queryMode
        }
        if let seqno {
            body["seqno"] = String(seqno)
        }

        let data = try await postRaw(path: ":executeSql", relativeToSession: true, body: body)
        let decoded = try JSONDecoder().decode(SpannerResultSet.self, from: data)
        let fields = decoded.metadata?.rowType?.fields ?? []
        let rows = decoded.rows ?? []
        let affected = Int(decoded.stats?.rowCountExact ?? "0") ?? 0
        return SpannerExecuteResult(
            fields: fields,
            rows: rows,
            rowsAffected: affected,
            transactionId: decoded.metadata?.transaction?.id
        )
    }

    private func updateDDL(_ statements: [String]) async throws {
        let body: [String: Any] = ["statements": statements]
        let payload = try await patchJSON(path: "/v1/\(databasePath)/ddl", body: body)
        guard let name = payload["name"] as? String else {
            if payload["done"] as? Bool == true { return }
            throw SpannerError.invalidResponse("updateDdl returned no operation name")
        }
        try await pollOperation(name)
    }

    private func pollOperation(_ name: String) async throws {
        let timeoutSeconds = lock.withLock { _queryTimeoutSeconds }
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            let payload = try await getJSON(path: "/v1/\(name)", relativeToSession: false)
            if payload["done"] as? Bool == true {
                if let error = payload["error"] as? [String: Any],
                   let message = error["message"] as? String
                {
                    throw SpannerError.apiError(code: error["code"] as? Int ?? 400, message: message, status: error["status"] as? String)
                }
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw SpannerError.timeout("DDL did not finish within \(timeoutSeconds) seconds")
    }

    private func fetchDatabaseDialect() async throws -> String {
        let payload = try await getJSON(path: "/v1/\(databasePath)", relativeToSession: false)
        return payload["databaseDialect"] as? String ?? "GOOGLE_STANDARD_SQL"
    }

    private func createSession() async throws -> String {
        let body: [String: Any] = ["session": ["labels": ["app": "tablepro"]]]
        let payload = try await postJSON(path: "/v1/\(databasePath)/sessions", relativeToSession: false, body: body)
        guard let name = payload["name"] as? String else {
            throw SpannerError.invalidResponse("createSession returned no name")
        }
        return name
    }

    private func deleteSession(_ name: String, session: URLSession) async throws {
        var request = URLRequest(url: url(for: "/v1/\(name)"))
        request.httpMethod = "DELETE"
        try await applyAuth(&request)
        _ = try await performRequest(request, session: session)
    }

    private func refreshSession() async throws {
        let old = lock.withLock { _spannerSession }
        if let old {
            if let urlSession = lock.withLock({ _session }) {
                try? await deleteSession(old, session: urlSession)
            }
        }
        let name = try await createSession()
        lock.withLock {
            _spannerSession = name
            _transactionId = nil
            _seqno = 0
        }
    }

    private func ensureSession() async throws {
        if lock.withLock({ _spannerSession == nil }) {
            let name = try await createSession()
            lock.withLock { _spannerSession = name }
        }
    }

    private func readOnlySingleUse() -> [String: Any] {
        ["singleUse": ["readOnly": ["strong": true]]]
    }

    private func createAuthProvider() throws -> SpannerAuthProvider {
        if usesEmulator {
            return SpannerEmulatorAuthProvider(projectId: projectId)
        }

        let authMethod = config.additionalFields["spAuthMethod"] ?? "serviceAccount"
        let overrideProjectId = projectId

        switch authMethod {
        case "serviceAccount":
            let keyValue = config.additionalFields["spServiceAccountJson"] ?? config.password
            guard !keyValue.isEmpty else {
                throw SpannerError.authFailed("Service account key is required")
            }
            let jsonData: Data
            let trimmed = keyValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") {
                guard let data = trimmed.data(using: .utf8) else {
                    throw SpannerError.authFailed("Failed to encode service account JSON")
                }
                jsonData = data
            } else {
                let path = NSString(string: trimmed).expandingTildeInPath
                guard let data = FileManager.default.contents(atPath: path) else {
                    throw SpannerError.authFailed("Cannot read service account file: \(trimmed)")
                }
                jsonData = data
            }
            return try SpannerServiceAccountAuthProvider(jsonData: jsonData, overrideProjectId: overrideProjectId)

        case "adc":
            return try SpannerADCAuthProvider(overrideProjectId: overrideProjectId)

        case "oauth":
            let clientId = config.additionalFields["spOAuthClientId"] ?? ""
            let clientSecret = config.additionalFields["spOAuthClientSecret"] ?? ""
            let refreshToken = config.additionalFields["spOAuthRefreshToken"]
            guard !clientId.isEmpty else {
                throw SpannerError.authFailed("OAuth Client ID is required")
            }
            guard !clientSecret.isEmpty else {
                throw SpannerError.authFailed("OAuth Client Secret is required")
            }
            let refreshTokenValue = (refreshToken?.isEmpty == false) ? refreshToken : nil
            return SpannerOAuthBrowserAuthProvider(
                clientId: clientId,
                clientSecret: clientSecret,
                refreshToken: refreshTokenValue,
                projectId: overrideProjectId
            )

        default:
            throw SpannerError.authFailed("Unknown auth method: \(authMethod)")
        }
    }

    private func getJSON(path: String, relativeToSession: Bool) async throws -> [String: Any] {
        var request = URLRequest(url: try resolvedURL(path: path, relativeToSession: relativeToSession))
        request.httpMethod = "GET"
        try await applyAuth(&request)
        let data = try await send(request)
        return try jsonObject(data)
    }

    private func postJSON(path: String, relativeToSession: Bool, body: [String: Any]) async throws -> [String: Any] {
        let data = try await postRaw(path: path, relativeToSession: relativeToSession, body: body)
        return try jsonObject(data)
    }

    private func postRaw(path: String, relativeToSession: Bool, body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: try resolvedURL(path: path, relativeToSession: relativeToSession))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await applyAuth(&request)
        return try await send(request)
    }

    private func patchJSON(path: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await applyAuth(&request)
        return try jsonObject(try await send(request))
    }

    private func resolvedURL(path: String, relativeToSession: Bool) throws -> URL {
        if relativeToSession {
            guard let sessionName = lock.withLock({ _spannerSession }) else {
                throw SpannerError.notConnected
            }
            return url(for: "/v1/\(sessionName)\(path)")
        }
        return url(for: path)
    }

    private func url(for path: String) -> URL {
        let trimmedBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.hasPrefix("/") ? path : "/\(path)"
        if let url = URL(string: trimmedBase + trimmedPath) {
            return url
        }
        return baseURL
    }

    private func applyAuth(_ request: inout URLRequest) async throws {
        if usesEmulator { return }
        let auth = try lock.withLock { () -> SpannerAuthProvider in
            guard let auth = _authProvider else { throw SpannerError.notConnected }
            return auth
        }
        let token = try await auth.accessToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let session = try lock.withLock { () -> URLSession in
            guard let session = _session else { throw SpannerError.notConnected }
            return session
        }
        let (data, response) = try await performRequestWithRetry(request, session: session)
        try checkHTTPResponse(response, data: data)
        return data
    }

    private func performRequest(
        _ request: URLRequest,
        session: URLSession
    ) async throws -> (Data, URLResponse) {
        var timedRequest = request
        timedRequest.timeoutInterval = _queryTimeout.requestTimeoutInterval
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: timedRequest) { [weak self] data, response, error in
                self?.lock.withLock { self?._currentTask = nil }
                if let error {
                    if (error as? URLError)?.code == .cancelled {
                        continuation.resume(throwing: SpannerError.requestCancelled)
                    } else {
                        continuation.resume(throwing: SpannerError.invalidResponse(error.localizedDescription))
                    }
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: SpannerError.invalidResponse("Empty response"))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            lock.withLock { _currentTask = task }
            task.resume()
        }
    }

    private func performRequestWithRetry(
        _ request: URLRequest,
        session: URLSession,
        maxRetries: Int = 3
    ) async throws -> (Data, URLResponse) {
        for attempt in 0..<maxRetries {
            let (data, response) = try await performRequest(request, session: session)
            guard let http = response as? HTTPURLResponse, http.statusCode == 429 else {
                return (data, response)
            }
            let delay = UInt64(pow(2.0, Double(attempt) + 1)) * 500_000_000
            try await Task.sleep(nanoseconds: delay)
        }
        return try await performRequest(request, session: session)
    }

    private func checkHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpannerError.invalidResponse("Not an HTTP response")
        }
        if (200..<300).contains(httpResponse.statusCode) {
            return
        }
        if let body = try? JSONDecoder().decode(SpannerAPIErrorBody.self, from: data), let detail = body.error {
            let message = detail.message ?? "Unknown error"
            let status = detail.status
            if status == "ABORTED" {
                throw SpannerError.aborted(message)
            }
            if status == "NOT_FOUND", message.uppercased().contains("SESSION") {
                throw SpannerError.sessionExpired
            }
            if detail.code == 401 || httpResponse.statusCode == 401 {
                throw SpannerError.authFailed(message)
            }
            throw SpannerError.apiError(code: detail.code ?? httpResponse.statusCode, message: message, status: status)
        }
        throw SpannerError.apiError(
            code: httpResponse.statusCode,
            message: "HTTP \(httpResponse.statusCode) (response length: \(data.count))",
            status: nil
        )
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SpannerError.invalidResponse("Expected a JSON object")
        }
        return object
    }
}

internal enum SpannerSQLClassification: Equatable {
    case query
    case dml
    case ddl
    case begin
    case commit
    case rollback

    static func classify(_ sql: String) -> SpannerSQLClassification {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = firstKeyword(trimmed)
        switch first {
        case "BEGIN", "START":
            return .begin
        case "COMMIT":
            return .commit
        case "ROLLBACK":
            return .rollback
        case "INSERT", "UPDATE", "DELETE":
            return .dml
        case "CREATE", "DROP", "ALTER", "GRANT", "REVOKE":
            return .ddl
        default:
            return .query
        }
    }

    static func firstKeyword(_ sql: String) -> String {
        var index = sql.startIndex
        if sql.uppercased().hasPrefix("EXPLAIN") {
            let after = sql.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
            return firstKeyword(String(after))
        }
        while index < sql.endIndex, sql[index].isWhitespace {
            sql.formIndex(after: &index)
        }
        var end = index
        while end < sql.endIndex, sql[end].isLetter {
            sql.formIndex(after: &end)
        }
        return String(sql[index..<end]).uppercased()
    }

    static func stripExplainPrefix(_ sql: String) -> (sql: String, isExplain: Bool) {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().hasPrefix("EXPLAIN") {
            let rest = trimmed.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines)
            return (String(rest), true)
        }
        return (trimmed, false)
    }
}
