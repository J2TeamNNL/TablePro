//
//  ChatToolRegistry.swift
//  TablePro
//

import Foundation
import os

@MainActor
final class ChatToolRegistry {
    static let shared = ChatToolRegistry()

    nonisolated private static let logger = Logger(subsystem: "com.TablePro", category: "ChatToolRegistry")

    private var tools: [String: any ChatTool] = [:]
    private var builtInNames: Set<String> = []

    init() {}

    /// Claims a name for a tool the app ships. A later `register` cannot take that name.
    func registerBuiltIn(_ tool: any ChatTool) {
        tools[tool.name] = tool
        builtInNames.insert(tool.name)
    }

    /// Registers a tool that did not ship with the app, refusing any name a built-in already holds.
    ///
    /// This used to overwrite the built-in and log a warning, so anything that could reach the
    /// registry could replace `execute_query` with its own implementation and keep the name the
    /// approval rules are written against.
    @discardableResult
    func register(_ tool: any ChatTool) -> Bool {
        guard !builtInNames.contains(tool.name) else {
            Self.logger.error("Refused ChatTool '\(tool.name, privacy: .public)': the name belongs to a built-in")
            return false
        }
        if tools[tool.name] != nil {
            Self.logger.warning("Replaced ChatTool '\(tool.name, privacy: .public)' in registry; second registration won")
        }
        tools[tool.name] = tool
        return true
    }

    func unregister(name: String) {
        guard !builtInNames.contains(name) else {
            Self.logger.error("Refused to unregister built-in ChatTool '\(name, privacy: .public)'")
            return
        }
        tools.removeValue(forKey: name)
    }

    func tool(named name: String) -> (any ChatTool)? {
        tools[name]
    }

    func tool(named name: String, in mode: AIChatMode) -> (any ChatTool)? {
        guard let tool = tools[name] else { return nil }
        guard tool.mode.isAllowed(in: mode) else { return nil }
        return tool
    }

    var allTools: [any ChatTool] {
        tools.values
            .sorted { $0.name < $1.name }
    }

    var allSpecs: [ChatToolSpec] {
        allTools.map(\.spec)
    }

    func allTools(for mode: AIChatMode) -> [any ChatTool] {
        allTools.filter { $0.mode.isAllowed(in: mode) }
    }

    func allSpecs(for mode: AIChatMode) -> [ChatToolSpec] {
        allTools(for: mode).map(\.spec)
    }

    func requiresApproval(toolName: String) -> Bool {
        guard let tool = tools[toolName] else { return true }
        return tool.mode.requiresApproval
    }

    func isToolAllowed(name: String, in mode: AIChatMode) -> Bool {
        guard let tool = tools[name] else {
            return mode == .agent
        }
        return tool.mode.isAllowed(in: mode)
    }

    // MARK: - Scoped resolution

    /// Built-in tools are offered to every session on every connection, so these delegate to the
    /// mode filter today. The scope is what a per-connection allowlist for an outside server will
    /// be applied on, which a mode alone cannot express.

    func tools(in scope: ChatToolScope) -> [any ChatTool] {
        allTools(for: scope.mode)
    }

    func specs(in scope: ChatToolScope) -> [ChatToolSpec] {
        tools(in: scope).map(\.spec)
    }

    func tool(named name: String, in scope: ChatToolScope) -> (any ChatTool)? {
        tool(named: name, in: scope.mode)
    }

    func isToolAllowed(name: String, in scope: ChatToolScope) -> Bool {
        isToolAllowed(name: name, in: scope.mode)
    }
}
