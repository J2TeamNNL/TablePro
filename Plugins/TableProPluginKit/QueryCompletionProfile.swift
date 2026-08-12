import Foundation

public enum QueryCompletionTokenCasingPolicy: String, Sendable {
    case preserveTypedToken
    case uppercaseKeywordsAndFunctions
    case lowercaseKeywordsAndFunctions
    case canonicalGrammarCasing
}

public struct QueryCompletionProfile: Sendable {
    public let resolvedDialect: SQLDialectDescriptor?
    public let statementCompletions: [CompletionEntry]
    public let tokenCasingPolicy: QueryCompletionTokenCasingPolicy
    public let revision: String

    public static let defaultRevision = "base"

    @_disfavoredOverload
    public init(
        resolvedDialect: SQLDialectDescriptor?,
        statementCompletions: [CompletionEntry]
    ) {
        self.init(
            resolvedDialect: resolvedDialect,
            statementCompletions: statementCompletions,
            tokenCasingPolicy: .preserveTypedToken,
            revision: Self.defaultRevision
        )
    }

    public init(
        resolvedDialect: SQLDialectDescriptor?,
        statementCompletions: [CompletionEntry],
        tokenCasingPolicy: QueryCompletionTokenCasingPolicy = .preserveTypedToken,
        revision: String = QueryCompletionProfile.defaultRevision
    ) {
        self.resolvedDialect = resolvedDialect
        self.statementCompletions = statementCompletions
        self.tokenCasingPolicy = tokenCasingPolicy
        self.revision = revision
    }
}
