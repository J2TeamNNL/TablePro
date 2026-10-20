//
//  MainEditorContentView+StatusBar.swift
//  TablePro
//

import SwiftUI
import TableProPluginKit

extension MainEditorContentView {
    func statusBar(tab: QueryTab) -> some View {
        let resolvedRows = resolvedTableRows(for: tab)
        let structureFooter = coordinator.structureSessions[tab.id]?.footer ?? StructureFooterCapability()
        let isExecuting = coordinator.tabExecution.isBusy(tab.id)
        let snapshot = StatusBarSnapshot(
            tab: tab,
            tableRows: resolvedRows,
            displayRowCount: coordinator.displayIDs(forTab: tab.id)?.count,
            isFetching: isExecuting,
            hasStructureActions: structureFooter.isActive,
            isQueryPlan: tab.display.activeExplainResult != nil,
            paginationCapability: coordinator.paginationCapability,
            hasServerOutput: !(tab.display.activeResultSet?.serverOutput.isEmpty ?? true),
            activeResultStatusMessage: tab.display.activeResultSet?.statusMessage
        )
        return ResultStatusBar(
            model: ResultStatusModel(
                snapshot: snapshot,
                viewMode: tab.display.resultsViewMode,
                selectedRowCount: selectionState.indices.count
            ),
            snapshot: snapshot,
            filterState: tab.filterState,
            columnState: StatusBarColumnState(
                hidden: tab.columnLayout.hiddenColumns,
                columns: coordinator.columnCatalog(for: tab, resultRows: resolvedRows),
                onToggle: { coordinator.toggleColumnVisibility($0) },
                onShowAll: { coordinator.showAllColumns() },
                onHideAll: { coordinator.hideAllColumns($0) },
                onReset: { coordinator.resetColumns() },
                onJumpToColumn: !tab.display.isResultsCollapsed
                    && showsGrid(tab: tab, rows: resolvedRows)
                    ? { coordinator.showColumnJump(seededWith: $0) }
                    : nil
            ),
            highlightState: StatusBarHighlightState(
                rules: coordinator.highlightRules(for: tab),
                columns: resolvedRows.columns,
                isPersisted: coordinator.highlightRuleScope(for: tab) != nil,
                presentationRequest: tab.display.highlightRulesPresentationRequest,
                onChange: { [coordinator, tabId = tab.id] rules in
                    coordinator.setHighlightRules(rules, forTab: tabId)
                },
                onDismiss: { [coordinator] tabId in
                    coordinator.discardIncompleteHighlightRules(forTab: tabId)
                }
            ),
            paginationCallbacks: PaginationCallbacks(
                onFirst: onFirstPage,
                onPrevious: onPreviousPage,
                onNext: onNextPage,
                onLast: onLastPage,
                onPageSizeChange: onPageSizeChange,
                onShowAll: onShowAll,
                onGoToPage: onGoToPage,
                onRequestExactCount: { coordinator.paginationCoordinator.requestExactRowCount() }
            ),
            structureFooter: structureFooter,
            execution: ExecutionReadout(
                tabId: tab.id,
                execution: coordinator.tabExecution,
                lastTiming: coordinator.toolbarState.queryTiming(forTab: tab.id),
                onCancel: { coordinator.stopExecution(for: tab.id) }
            ),
            selectionSummary: coordinator.selectionSummary,
            isRefreshingSchema: schemaService.isRefreshing(connectionId: connectionId),
            viewMode: resultsViewModeBinding(for: tab),
            resultSetMenu: resultSetMenuModel(for: tab),
            onActivateResultSet: { coordinator.switchActiveResultSet(to: $0, in: tab.id) },
            onToggleResultSetPin: { coordinator.togglePinResultSet(id: $0) },
            onCloseResultSet: { coordinator.closeResultSet(id: $0) },
            onCloseOtherResultSets: { keptId in
                for other in tab.display.resultSets where other.id != keptId && !other.isPinned {
                    coordinator.closeResultSet(id: other.id)
                }
            },
            onToggleFilters: { coordinator.toggleFilterPanel() },
            onFetchAll: { coordinator.fetchAllRows() },
            onStructureAdd: { coordinator.structureActions?.addRow?() },
            onStructureRemove: { coordinator.structureActions?.removeRow?() }
        )
    }

    // Three fields, not a full `resultPresentation`, which would pull the tab's row buffer for nothing.
    private func resultSetMenuModel(for tab: QueryTab) -> ResultSetMenuModel {
        var selectorInputs = QueryResultInputs()
        selectorInputs.tabType = tab.tabType
        selectorInputs.viewMode = tab.display.resultsViewMode
        selectorInputs.resultSetCount = tab.display.resultSets.count
        guard QueryResultPresentation(inputs: selectorInputs).showsResultSetSelector else {
            return ResultSetMenuModel(entries: [], activeOrdinal: 0, total: 0)
        }
        let activeId = tab.display.activeResultSet?.id
        let entries = tab.display.resultSets.enumerated().map { index, resultSet in
            ResultSetMenuEntry(
                id: resultSet.id,
                label: resultSet.label,
                isPinned: resultSet.isPinned,
                isActive: resultSet.id == activeId,
                ordinal: index + 1
            )
        }
        return ResultSetMenuModel(
            entries: entries,
            activeOrdinal: entries.first(where: \.isActive)?.ordinal ?? entries.count,
            total: entries.count
        )
    }

    private func resultsViewModeBinding(for tab: QueryTab) -> Binding<ResultsViewMode> {
        Binding(
            get: { tab.display.resultsViewMode },
            set: { newValue in
                Task { @MainActor in
                    if let index = tabManager.selectedTabIndex {
                        tabManager.mutate(at: index) { $0.display.resultsViewMode = newValue }
                    }
                }
            }
        )
    }
}
