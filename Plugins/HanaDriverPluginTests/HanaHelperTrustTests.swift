import Foundation
import XCTest

final class HanaHelperTrustTests: XCTestCase {
    private var root: URL?

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("HanaHelperTrustTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
    }

    override func tearDownWithError() throws {
        guard let root else { return }
        try FileManager.default.removeItem(at: root)
    }

    func testARegularExecutableInsideContentsMacOSIsTrustedInAnUnsignedBundle() throws {
        let bundle = try makeBundle(named: "Regular")
        try writeHelper(at: helperURL(in: bundle), permissions: 0o755)

        let executable = try HanaHelperTrust.verifiedExecutable(in: XCTUnwrap(Bundle(url: bundle)))

        XCTAssertEqual(executable.lastPathComponent, HanaHelperTrust.executableName)
        XCTAssertEqual(executable.deletingLastPathComponent().lastPathComponent, "MacOS")
    }

    func testAMissingHelperIsRefused() throws {
        let bundle = try makeBundle(named: "Missing")

        assertRefused(bundle, mentioning: "missing")
    }

    func testASymlinkedHelperIsRefusedEvenWhenItPointsAtAnExecutable() throws {
        let bundle = try makeBundle(named: "Symlink")
        let outside = try XCTUnwrap(root).appendingPathComponent("outside-helper")
        try writeHelper(at: outside, permissions: 0o755)
        try FileManager.default.createSymbolicLink(at: helperURL(in: bundle), withDestinationURL: outside)

        assertRefused(bundle, mentioning: "regular file")
    }

    func testADirectoryNamedLikeTheHelperIsRefused() throws {
        let bundle = try makeBundle(named: "Directory")
        try FileManager.default.createDirectory(at: helperURL(in: bundle), withIntermediateDirectories: true)

        assertRefused(bundle, mentioning: "regular file")
    }

    func testAHelperThatIsNotExecutableIsRefused() throws {
        let bundle = try makeBundle(named: "NotExecutable")
        try writeHelper(at: helperURL(in: bundle), permissions: 0o644)

        assertRefused(bundle, mentioning: "not executable")
    }

    func testAHelperReachedThroughASymlinkedMacOSFolderIsRefused() throws {
        let bundle = try makeBundle(named: "LinkedFolder", withMacOSFolder: false)
        let outsideFolder = try XCTUnwrap(root).appendingPathComponent("outside-macos", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideFolder, withIntermediateDirectories: true)
        try writeHelper(at: outsideFolder.appendingPathComponent(HanaHelperTrust.executableName), permissions: 0o755)
        try FileManager.default.createSymbolicLink(
            at: bundle.appendingPathComponent("Contents/MacOS"),
            withDestinationURL: outsideFolder
        )

        assertRefused(bundle, mentioning: "Contents/MacOS")
    }

    func testTheLocationCheckRefusesAHelperFromAnotherBundle() throws {
        let first = try makeBundle(named: "First")
        let second = try makeBundle(named: "Second")
        try writeHelper(at: helperURL(in: second), permissions: 0o755)

        XCTAssertThrowsError(try HanaHelperTrust.verifyLocation(of: helperURL(in: second), inBundleAt: first)) { error in
            XCTAssertEqual((error as? HanaBridgeFailure)?.kind, .internalFailure)
        }
        XCTAssertNoThrow(try HanaHelperTrust.verifyLocation(of: helperURL(in: second), inBundleAt: second))
    }

    func testAnUnsignedBundleHasNoTeamToRequire() throws {
        let bundle = try makeBundle(named: "NoTeam")
        try writeHelper(at: helperURL(in: bundle), permissions: 0o755)

        XCTAssertNil(HanaHelperTrust.signingTeam(ofCodeAt: bundle))
    }

    func testTheTeamRequirementNamesTheLeafCertificateUnit() {
        XCTAssertEqual(
            HanaHelperTrust.requirement(forTeam: "D7HJ5TFYCU"),
            "anchor apple generic and certificate leaf[subject.OU] = \"D7HJ5TFYCU\""
        )
    }

    func testATeamIdentifierThatIsNotTenUppercaseLettersOrDigitsBuildsNoRequirement() {
        for team in ["", "D7HJ5TFYC", "D7HJ5TFYCUX", "d7hj5tfycu", "D7HJ5\"TFYC", "ABC\" or \"1", "D7HJ5TFYÇU"] {
            XCTAssertNil(HanaHelperTrust.requirement(forTeam: team), team)
        }
    }

    private func makeBundle(named name: String, withMacOSFolder: Bool = true) throws -> URL {
        let bundle = try XCTUnwrap(root).appendingPathComponent("\(name).tableplugin", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let folder = withMacOSFolder ? contents.appendingPathComponent("MacOS", isDirectory: true) : contents
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return bundle
    }

    private func helperURL(in bundle: URL) -> URL {
        bundle.appendingPathComponent("Contents/MacOS/\(HanaHelperTrust.executableName)")
    }

    private func writeHelper(at url: URL, permissions: Int) throws {
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
    }

    private func assertRefused(
        _ bundle: URL,
        mentioning fragment: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let loaded = Bundle(url: bundle) else {
            XCTFail("\(bundle.path) did not open as a bundle", file: file, line: line)
            return
        }
        XCTAssertThrowsError(try HanaHelperTrust.verifiedExecutable(in: loaded), file: file, line: line) { error in
            let failure = error as? HanaBridgeFailure
            XCTAssertEqual(failure?.kind, .internalFailure, "got \(error)", file: file, line: line)
            XCTAssertEqual(
                failure?.message.contains(fragment), true,
                "\(failure?.message ?? "") does not mention \(fragment)",
                file: file,
                line: line
            )
        }
    }
}
