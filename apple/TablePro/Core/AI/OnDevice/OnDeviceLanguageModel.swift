//
//  OnDeviceLanguageModel.swift
//  TablePro
//

import Foundation

struct OnDeviceRequest: Equatable, Sendable {
    let instructions: String
    let prompt: String
}

struct OnDeviceUnavailableError: LocalizedError {
    let availability: AppleIntelligenceAvailability

    var errorDescription: String? {
        availability.unavailableExplanation
    }
}

enum OnDeviceFit: Equatable, Sendable {
    case fits(index: Int, maximumResponseTokens: Int)
    case tooLarge
}

protocol OnDeviceLanguageModel: Sendable {
    var availability: AppleIntelligenceAvailability { get }
    var contextSize: Int { get }
    func tokenCount(for request: OnDeviceRequest) async -> Int
    func streamResponse(to request: OnDeviceRequest, maximumResponseTokens: Int) -> AsyncThrowingStream<String, Error>
}

extension OnDeviceLanguageModel {
    func fit(_ candidates: [OnDeviceRequest], reservingForReply reserve: Int) async -> OnDeviceFit {
        let limit = contextSize - OnDeviceTokenBudget.transcriptMargin
        for (index, candidate) in candidates.enumerated() {
            guard !Task.isCancelled else { return .tooLarge }
            let tokens = await tokenCount(for: candidate)
            if tokens + reserve <= limit {
                return .fits(index: index, maximumResponseTokens: limit - tokens)
            }
        }
        return .tooLarge
    }
}

enum OnDeviceTokenBudget {
    // The session wraps instructions and prompt in role markers that two separate counts miss.
    static let transcriptMargin = 64

    // Measured on the macOS 27 model: SQL ~2.9 characters a token, a Markdown table ~2.6, CJK ~2.
    // Two keeps the estimate on the high side where tokenCount(for:) is missing (macOS 26.0 to 26.3).
    static let charactersPerToken = 2
    static let estimateOverhead = 64

    static func estimatedTokens(in request: OnDeviceRequest) -> Int {
        let characters = (request.instructions as NSString).length + (request.prompt as NSString).length
        return (characters + charactersPerToken - 1) / charactersPerToken + estimateOverhead
    }
}
