import Foundation
import StriderKit

/// Installs "strider watch" as a per-user launchd agent.
enum Agent {
    static let label = "local.strider-chroma.watch"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/strider-chroma.log")
    }

    private static var domain: String { "gui/\(getuid())" }

    static func run(_ action: AgentAction) throws {
        switch action {
        case .install: try install()
        case .uninstall: try uninstall()
        case .status: status()
        }
    }

    private static func install() throws {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path else {
            throw DeviceError(description: "could not work out where this program is installed")
        }
        if executable.contains("/.build/") {
            throw DeviceError(
                description: """
                    this copy of strider is inside a build directory (\(executable)), which a rebuild or \
                    clean would replace. Run "make install" and then "strider agent install" from the installed copy
                    """
            )
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable, "watch"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ThrottleInterval": 30,
            "ProcessType": "Background",
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)

        // Replace a copy that is already loaded, so that a changed path takes effect.
        _ = launchctl(["bootout", "\(domain)/\(label)"])
        let result = launchctl(["bootstrap", domain, plistURL.path])
        guard result.status == 0 else {
            throw DeviceError(
                description: "wrote \(plistURL.path), but launchctl could not load it: \(result.output)")
        }
        print("Installed. \"\(executable) watch\" will now run in the background and start at login.")
        print("Log: \(logURL.path)")
    }

    private static func uninstall() throws {
        let wasLoaded = launchctl(["bootout", "\(domain)/\(label)"]).status == 0
        let hadPlist = FileManager.default.fileExists(atPath: plistURL.path)
        if hadPlist { try FileManager.default.removeItem(at: plistURL) }
        print(wasLoaded || hadPlist ? "Uninstalled." : "The agent was not installed.")
    }

    private static func status() {
        let installed = FileManager.default.fileExists(atPath: plistURL.path)
        let result = launchctl(["print", "\(domain)/\(label)"])
        guard result.status == 0 else {
            print(installed ? "Installed but not loaded. Run \"strider agent install\" to load it." : "Not installed.")
            return
        }
        let pid = result.output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("pid = ") }?
            .dropFirst("pid = ".count)
        print(pid.map { "Running, pid \($0)." } ?? "Loaded but not running at the moment.")
        print("Log: \(logURL.path)")
    }

    private static func launchctl(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "\(error)")
        }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
