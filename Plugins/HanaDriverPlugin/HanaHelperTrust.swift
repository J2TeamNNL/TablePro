import Darwin
import Foundation
import Security

enum HanaHelperTrust {
    static let executableName = "tablepro-hana-helper"

    private static let validationFlags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)

    static func verifiedExecutable(in bundle: Bundle) throws -> URL {
        guard let executable = bundle.url(forAuxiliaryExecutable: executableName) else {
            throw untrusted("\(executableName) is missing from \(bundle.bundleURL.lastPathComponent)")
        }
        try verifyLocation(of: executable, inBundleAt: bundle.bundleURL)
        try verifySignature(of: executable, bundleURL: bundle.bundleURL)
        return executable
    }

    static func verifyLocation(of executable: URL, inBundleAt bundleURL: URL) throws {
        var status = stat()
        guard lstat(executable.path, &status) == 0 else {
            throw untrusted("\(executableName) could not be read")
        }
        guard status.st_mode & S_IFMT == S_IFREG else {
            throw untrusted("\(executableName) is not a regular file")
        }
        guard access(executable.path, X_OK) == 0 else {
            throw untrusted("\(executableName) is not executable")
        }
        guard let resolvedExecutable = resolvedPath(executable.path),
              let resolvedBundle = resolvedPath(bundleURL.path),
              resolvedExecutable == resolvedBundle + "/Contents/MacOS/" + executableName
        else {
            throw untrusted("\(executableName) is not inside the plugin's Contents/MacOS folder")
        }
    }

    static func requirement(forTeam team: String) -> String? {
        let isTeamIdentifier = team.count == 10 && team.unicodeScalars.allSatisfy { scalar in
            ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
        }
        guard isTeamIdentifier else { return nil }
        return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
    }

    static func signingTeam(ofCodeAt url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
        guard status == errSecSuccess,
              let values = information as? [String: Any],
              let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty
        else { return nil }
        return team
    }

    private static func verifySignature(of executable: URL, bundleURL: URL) throws {
        guard let team = signingTeam(ofCodeAt: bundleURL) else { return }
        guard let requirementText = requirement(forTeam: team) else {
            throw untrusted("the plugin's signing team identifier is not valid")
        }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else {
            throw untrusted("the signing requirement for team \(team) could not be built")
        }
        var code: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(executable as CFURL, [], &code)
        guard createStatus == errSecSuccess, let code else {
            throw untrusted("\(executableName) could not be opened for signature checks (OSStatus \(createStatus))")
        }
        let status = SecStaticCodeCheckValidity(code, validationFlags, requirement)
        guard status == errSecSuccess else {
            throw untrusted("\(executableName) is not signed by team \(team) (OSStatus \(status))")
        }
    }

    private static func resolvedPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func untrusted(_ message: String) -> HanaBridgeFailure {
        HanaBridgeFailure(kind: .internalFailure, message: message)
    }
}
