//
//  KeyboardShortcutModelsTests.swift
//  TableProTests
//

import AppKit
import SwiftUI
@testable import TablePro
import Testing

@Suite("KeyboardShortcutModels function keys")
struct KeyboardShortcutModelsTests {
    @Test("Function-key combo reports isFunctionKey and displays as F5")
    func functionKeyComboBasics() {
        let f5 = KeyCombo(key: "f5", isSpecialKey: true)
        #expect(f5.isFunctionKey)
        #expect(!f5.hasModifier)
        #expect(f5.displayString == "F5")
    }

    @Test("Non-function special and letter keys are not function keys")
    func nonFunctionKeys() {
        #expect(!KeyCombo(key: "escape", isSpecialKey: true).isFunctionKey)
        #expect(!KeyCombo(key: "f", command: true).isFunctionKey)
        #expect(!KeyCombo(key: "f13", isSpecialKey: true).isFunctionKey)
    }

    @Test("Function-key keyEquivalent maps to the AppKit function-key scalar")
    func functionKeyEquivalent() throws {
        let f5 = KeyCombo(key: "f5", isSpecialKey: true)
        let expected = try #require(UnicodeScalar(UInt32(NSF1FunctionKey + 4)))
        #expect(f5.keyEquivalent.character == Character(expected))
    }

    @Test("Function-key combo round-trips through Codable")
    func functionKeyCodable() throws {
        let f9 = KeyCombo(key: "f9", isSpecialKey: true)
        let data = try JSONEncoder().encode(f9)
        let decoded = try JSONDecoder().decode(KeyCombo.self, from: data)
        #expect(decoded == f9)
    }

    @Test("Default alternates bind F5 to refresh and F9 to execute query")
    func defaultAlternates() {
        let settings = KeyboardSettings.default
        #expect(settings.alternateShortcut(for: .refresh) == KeyCombo(key: "f5", isSpecialKey: true))
        #expect(settings.alternateShortcut(for: .executeQuery) == KeyCombo(key: "f9", isSpecialKey: true))
        #expect(settings.alternateShortcut(for: .formatQuery) == nil)
    }

    @Test("Open Documentation defaults to F1 with no menu shortcut")
    func openDocumentationDefault() {
        let settings = KeyboardSettings.default
        #expect(settings.shortcut(for: .openDocumentation) == KeyCombo(key: "f1", isSpecialKey: true))
        #expect(settings.keyboardShortcut(for: .openDocumentation) == nil)
    }

    @Test("Menu shortcut still resolves for non-function primary bindings")
    func menuShortcutForRefresh() {
        #expect(KeyboardSettings.default.keyboardShortcut(for: .refresh) != nil)
    }

    @Test("Only documentation accepts a function key as its primary shortcut")
    func functionKeyPrimarySupport() {
        #expect(ShortcutAction.openDocumentation.supportsFunctionKeyPrimary)
        #expect(!ShortcutAction.formatQuery.supportsFunctionKeyPrimary)
        #expect(!ShortcutAction.refresh.supportsFunctionKeyPrimary)
    }

    @Test("Sanitize keeps function-key overrides without a modifier")
    func sanitizeKeepsFunctionKeys() {
        var settings = KeyboardSettings.default
        settings.setShortcut(KeyCombo(key: "f2", isSpecialKey: true), for: .openDocumentation)
        let cleaned = settings.sanitized()
        #expect(cleaned.shortcut(for: .openDocumentation) == KeyCombo(key: "f2", isSpecialKey: true))
    }

    @Test("Conflict detection spots an alternate binding")
    func conflictWithAlternate() {
        let f5 = KeyCombo(key: "f5", isSpecialKey: true)
        #expect(KeyboardSettings.default.findConflict(for: f5, excluding: .openDocumentation) == .refresh)
    }

    @Test("Cleared alternate resolves to nil")
    func clearedAlternate() {
        var settings = KeyboardSettings.default
        settings.clearAlternate(for: .refresh)
        #expect(settings.alternateShortcut(for: .refresh) == nil)
    }

    @Test("Alternates persist through Codable")
    func settingsAlternatesCodable() throws {
        var settings = KeyboardSettings.default
        settings.setAlternate(KeyCombo(key: "f7", isSpecialKey: true), for: .executeQuery)
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: data)
        #expect(decoded.alternateShortcut(for: .executeQuery) == KeyCombo(key: "f7", isSpecialKey: true))
    }
}
