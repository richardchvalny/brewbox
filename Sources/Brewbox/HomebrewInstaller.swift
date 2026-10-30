import AppKit

/// Helps users without Homebrew install it the official ways. The installer asks
/// for an administrator password, so it runs in Terminal rather than inside the app.
enum HomebrewInstaller {
    /// The command from brew.sh.
    static let command = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    /// Homebrew's signed .pkg installer, for people who'd rather not use Terminal.
    static let packageURL = URL(string: "https://github.com/Homebrew/brew/releases/latest")!
    static let websiteURL = URL(string: "https://brew.sh")!

    /// Opens Terminal running the official install command. A .command file opens
    /// in Terminal without needing Automation permission.
    static func installInTerminal() throws {
        let script = """
            #!/bin/bash
            clear
            echo "Installing Homebrew for Brewbox."
            echo "You'll be asked for your Mac password. Nothing shows while you type it."
            echo
            \(command)
            echo
            echo "All set. You can close this window and go back to Brewbox."
            """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Install Homebrew.command")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }

    static func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
