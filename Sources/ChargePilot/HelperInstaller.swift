import Foundation
import KurrenchiShared

enum HelperInstallError: LocalizedError {
    case scriptUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .scriptUnavailable: "无法创建管理员安装脚本。"
        case .failed(let message): message
        }
    }
}

enum HelperInstaller {
    static let label = "com.kurrenchi.helper"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    static let helperPath = "/Library/PrivilegedHelperTools/\(label)"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: helperPath)
            && FileManager.default.fileExists(atPath: plistPath)
    }

    static func install() throws {
        let source = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/kurrenchi-helper").path
        guard FileManager.default.fileExists(atPath: source) else {
            throw HelperInstallError.failed("应用包中缺少 Helper。")
        }
        let plist = try temporaryFile(contents: launchDaemonPlist, extension: "plist")
        defer { try? FileManager.default.removeItem(atPath: plist) }
        let uid = getuid()
        let script = """
        set -e
        mkdir -p \(quote(KurrenchiStore.directory.path))
        chown \(uid):staff \(quote(KurrenchiStore.directory.path))
        chmod 775 \(quote(KurrenchiStore.directory.path))
        mkdir -p /Library/PrivilegedHelperTools
        cp \(quote(source)) \(quote(helperPath))
        chown root:wheel \(quote(helperPath))
        chmod 755 \(quote(helperPath))
        cp \(quote(plist)) \(quote(plistPath))
        chown root:wheel \(quote(plistPath))
        chmod 644 \(quote(plistPath))
        launchctl bootout system/\(label) 2>/dev/null || true
        launchctl bootstrap system \(quote(plistPath))
        """
        try runPrivileged(script)
    }

    static func uninstall() throws {
        let script = """
        launchctl kill TERM system/\(label) 2>/dev/null || true
        sleep 1
        launchctl bootout system/\(label) 2>/dev/null || true
        rm -f \(quote(plistPath)) \(quote(helperPath))
        rm -f \(quote(KurrenchiStore.statusURL.path)) \(quote(KurrenchiStore.configURL.path))
        """
        try runPrivileged(script)
    }

    private static var launchDaemonPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
          <key>Label</key><string>\(label)</string>
          <key>ProgramArguments</key><array><string>\(helperPath)</string></array>
          <key>RunAtLoad</key><true/>
          <key>KeepAlive</key><true/>
          <key>StandardOutPath</key><string>/var/log/\(label).log</string>
          <key>StandardErrorPath</key><string>/var/log/\(label).log</string>
        </dict></plist>
        """
    }

    private static func runPrivileged(_ script: String) throws {
        let path = try temporaryFile(contents: script, extension: "sh")
        defer { try? FileManager.default.removeItem(atPath: path) }
        let command = "/bin/sh \(quote(path))"
        let source = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        guard let appleScript = NSAppleScript(source: source) else { throw HelperInstallError.scriptUnavailable }
        var details: NSDictionary?
        appleScript.executeAndReturnError(&details)
        if let details {
            throw HelperInstallError.failed(details[NSAppleScript.errorMessage] as? String ?? "Helper 安装失败。")
        }
    }

    private static func temporaryFile(contents: String, extension suffix: String) throws -> String {
        let path = "/tmp/\(label).\(UUID().uuidString).\(suffix)"
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
