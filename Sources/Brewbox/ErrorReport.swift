import Foundation

/// An error shown in the panel, with enough context to paste into an AI agent
/// or a bug report.
struct ErrorReport: Identifiable, Sendable {
    let id = UUID()
    /// What failed, e.g. "Installing ripgrep failed".
    let title: String
    let message: String
    var hint: String?
    var command: String?
    var exitCode: Int32?
    var output: String?
    let date = Date.now

    init(title: String, message: String, hint: String? = nil) {
        self.title = title
        self.message = message
        self.hint = hint
    }

    init(title: String, error: Error) {
        self.title = title
        message = error.localizedDescription
        if let brewError = error as? BrewError {
            command = brewError.command
            exitCode = brewError.exitCode
            output = brewError.output?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let text = [message, output ?? ""].joined(separator: "\n").lowercased()
        if text.contains("sudo") || text.contains("password") {
            hint = "This package needs an administrator password, so run the command in Terminal."
        }
    }

    /// The error as plain text, for a bug report or a chat.
    func plainText(environment: SystemInfo) -> String {
        var lines = [title, "", message]
        if let hint { lines += ["", hint] }
        if let command {
            lines += ["", "Command: \(command)" + (exitCode.map { " (exit \($0))" } ?? "")]
        }
        if let output, !output.isEmpty {
            lines += ["", "Output:", output]
        }
        lines += ["", environment.summary]
        return lines.joined(separator: "\n")
    }

    /// A ready-to-paste prompt asking an AI coding agent to diagnose the failure.
    func agentPrompt(environment: SystemInfo) -> String {
        var sections = [
            """
            A Homebrew command failed on my Mac. Find the cause and help me fix it.
            Explain what went wrong in a sentence or two, then give the exact commands to run, \
            in order. Prefer the least invasive fix. Before suggesting anything destructive \
            (uninstalling, deleting files, `--force`, `sudo`), say what it does and why it's needed.
            """,
            "## What failed\n\(title)",
        ]
        if let command {
            sections.append("## Command\n```\n\(command)\n```" + (exitCode.map { "\nExit code: \($0)" } ?? ""))
        }
        sections.append("## Error\n```\n\(message)\n```")
        if let output, !output.isEmpty, output != message {
            sections.append("## Full output\n```\n\(output)\n```")
        }
        sections.append("## Environment\n\(environment.bulletList)\n- Time: \(date.formatted(date: .abbreviated, time: .standard))")
        return sections.joined(separator: "\n\n")
    }
}

struct SystemInfo: Sendable {
    var brewVersion: String?
    var brewPath: String?

    private var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var architecture: String {
        #if arch(arm64)
        "arm64 (Apple silicon)"
        #else
        "x86_64 (Intel)"
        #endif
    }

    var bulletList: String {
        [
            "- macOS \(macOSVersion), \(architecture)",
            "- \(brewVersion ?? "Homebrew (version unknown)") at \(brewPath ?? "unknown path")",
        ].joined(separator: "\n")
    }

    var summary: String {
        "macOS \(macOSVersion), \(architecture); \(brewVersion ?? "Homebrew") at \(brewPath ?? "?")"
    }
}
