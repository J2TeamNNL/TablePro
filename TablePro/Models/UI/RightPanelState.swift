//
//  RightPanelState.swift
//  TablePro
//
//  Per-window state for the right panel: active tab, edit state, AI chat.
//

import Foundation
import os

@MainActor @Observable final class RightPanelState {
    @ObservationIgnored private let _didTeardown = OSAllocatedUnfairLock(initialState: false)
    @ObservationIgnored private let connectionId: UUID?
    /// The connection this panel's session talks to, held so the view model has it from creation.
    /// It used to arrive from `AIChatPanelView.onAppear`, which meant a send before the panel's
    /// first layout ran with no connection and skipped every policy and Safe Mode check.
    @ObservationIgnored private var connection: DatabaseConnection?
    @ObservationIgnored private let defaults: UserDefaults

    var activeTab: RightPanelTab {
        didSet {
            guard let connectionId else { return }
            defaults.set(activeTab.rawValue, forKey: Self.activeTabKey(connectionId))
        }
    }

    var inspectorContext: InspectorContext = .empty

    // Save closure — set by MainContentCommandActions, called by UnifiedRightPanelView
    var onSave: (() -> Void)?

    // Owned objects — lifted from MainContentView @StateObject
    let editState = MultiRowEditState()
    private var _aiViewModel: AIChatViewModel?
    var aiViewModel: AIChatViewModel {
        if _aiViewModel == nil {
            _aiViewModel = AIChatViewModel(connection: connection)
        }
        return _aiViewModel! // swiftlint:disable:this force_unwrapping
    }

    init(
        connectionId: UUID? = nil,
        connection: DatabaseConnection? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.connectionId = connectionId
        self.connection = connection
        self.defaults = defaults
        if let connectionId,
           let raw = defaults.string(forKey: Self.activeTabKey(connectionId)),
           let tab = RightPanelTab(rawValue: raw) {
            self.activeTab = tab
        } else {
            self.activeTab = .details
        }
    }

    /// Pushed in when the stored connection record changes, so the session's copy does not go stale.
    /// Only the record for this panel's own connection is taken: a bulk update names every record,
    /// and adopting another connection's would repoint the session's authorization checks at it.
    ///
    /// The view model is refreshed only if it already exists. Reading `aiViewModel` here would
    /// create a session for a connection nobody has opened a chat on.
    internal func refreshConnectionRecord(_ record: DatabaseConnection) {
        guard record.id == connectionId else { return }
        connection = record
        _aiViewModel?.connection = record
    }

    private static func activeTabKey(_ connectionId: UUID) -> String {
        "com.TablePro.rightPanel.activeTab.\(connectionId.uuidString)"
    }

    /// Release all heavy data on disconnect so memory drops
    /// even if AppKit keeps the window alive.
    func teardown() {
        guard !_didTeardown.withLock({ $0 }) else { return }
        _didTeardown.withLock { $0 = true }
        onSave = nil
        _aiViewModel?.clearSessionData()
        editState.releaseData()
    }
}
