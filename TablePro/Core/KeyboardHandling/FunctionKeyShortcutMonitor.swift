//
//  FunctionKeyShortcutMonitor.swift
//  TablePro
//
//  Dispatches function-key shortcuts (F1–F12) that can't ride on SwiftUI menu
//  key equivalents: secondary bindings whose primary already owns a menu
//  shortcut (e.g. F5 alongside ⌘R), and Help actions with no menu shortcut.
//

import AppKit
import Combine
import Foundation

@MainActor
final class FunctionKeyShortcutMonitor {
    static let shared = FunctionKeyShortcutMonitor()

    private var eventMonitor: Any?

    private init() {}

    func start() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let action = matchedAction(for: event) else { return event }
        if NSApp.keyWindow?.firstResponder is ShortcutRecorderNSView {
            return event
        }
        return perform(action) ? nil : event
    }

    private func matchedAction(for event: NSEvent) -> ShortcutAction? {
        let keyboard = AppSettingsManager.shared.keyboard
        for action in ShortcutAction.allCases where action.supportsFunctionKeyPrimary {
            if let combo = keyboard.shortcut(for: action), combo.isFunctionKey, combo.matches(event) {
                return action
            }
        }
        for action in ShortcutAction.allCases where action.supportsFunctionKeyAlternate {
            if let combo = keyboard.alternateShortcut(for: action), combo.isFunctionKey, combo.matches(event) {
                return action
            }
        }
        return nil
    }

    private func perform(_ action: ShortcutAction) -> Bool {
        switch action {
        case .refresh:
            AppCommands.shared.refreshData.send(nil)
            return true
        case .executeQuery:
            guard let actions = CommandActionsRegistry.shared.current else { return false }
            actions.runQuery()
            return true
        case .openDocumentation:
            guard let url = URL(string: "https://docs.tablepro.app") else { return false }
            NSWorkspace.shared.open(url)
            return true
        default:
            return false
        }
    }
}
