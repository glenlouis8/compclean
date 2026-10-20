import Foundation
import Security

public enum CodeSignature {
    /// True when the bundle is signed by Apple itself (not just any Apple-issued developer cert).
    public static func isAppleSigned(_ url: URL) -> Bool {
        guard let code = staticCode(url) else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        let flags = SecCSFlags(rawValue: kSecCSBasicValidateOnly)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    public static func teamID(_ url: URL) -> String? {
        guard let code = staticCode(url) else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func staticCode(_ url: URL) -> SecStaticCode? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess else { return nil }
        return code
    }
}
