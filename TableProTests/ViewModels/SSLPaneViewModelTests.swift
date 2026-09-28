//
//  SSLPaneViewModelTests.swift
//  TableProTests
//

import Foundation
@testable import TablePro
import TableProPluginKit
import Testing

@MainActor
struct SSLPaneViewModelTests {
    @Test("resetForType applies engine's native default for PostgreSQL")
    func testResetForPostgreSQL() {
        let viewModel = SSLPaneViewModel()
        viewModel.mode = .disabled
        viewModel.resetForType(.postgresql)
        #expect(viewModel.mode == .preferred)
    }

    @Test("resetForType applies engine's native default for SQL Server")
    func testResetForMSSQL() {
        let viewModel = SSLPaneViewModel()
        viewModel.mode = .disabled
        viewModel.resetForType(.mssql)
        #expect(viewModel.mode == .preferred)
    }

    @Test("resetForType keeps disabled for binary-TLS engines")
    func testResetForRedis() {
        let viewModel = SSLPaneViewModel()
        viewModel.mode = .required
        viewModel.resetForType(.redis)
        #expect(viewModel.mode == .disabled)
    }

    @Test("resetForType clears certificate paths")
    func testResetClearsPaths() {
        let viewModel = SSLPaneViewModel()
        viewModel.caCertPath = "/tmp/ca.pem"
        viewModel.clientCertPath = "/tmp/client.crt"
        viewModel.clientKeyPath = "/tmp/client.key"
        viewModel.resetForType(.postgresql)
        #expect(viewModel.caCertPath.isEmpty)
        #expect(viewModel.clientCertPath.isEmpty)
        #expect(viewModel.clientKeyPath.isEmpty)
    }

    @Test("resetForType for unknown future engine falls back to disabled")
    func testResetForUnknownType() {
        let viewModel = SSLPaneViewModel()
        viewModel.mode = .required
        viewModel.resetForType(DatabaseType(rawValue: "FutureDB"))
        #expect(viewModel.mode == .disabled)
    }

    private func verifyIdentityIssues(for type: DatabaseType, caCertPath: String = "") -> [String] {
        let coordinator = ConnectionFormCoordinator(connectionId: nil)
        coordinator.network.type = type
        coordinator.ssl.mode = .verifyIdentity
        coordinator.ssl.caCertPath = caCertPath
        return coordinator.ssl.validationIssues
    }

    @Test("Verify Identity without a CA file saves for engines that trust the system roots")
    func systemTrustStoreEnginesNeedNoCAFile() {
        for type in [DatabaseType.sapHana, .kafka, .mssql] {
            #expect(type.verifiesTLSWithSystemTrustStore)
            #expect(verifyIdentityIssues(for: type).isEmpty)
        }
    }

    @Test("Verify Identity without a CA file is refused for engines that need one")
    func fileTrustEnginesStillRequireACAFile() {
        #expect(!DatabaseType.postgresql.verifiesTLSWithSystemTrustStore)
        #expect(verifyIdentityIssues(for: .postgresql).count == 1)
        #expect(verifyIdentityIssues(for: .postgresql, caCertPath: "/tmp/ca.pem").isEmpty)
    }
}
