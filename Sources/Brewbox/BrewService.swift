import Foundation

struct BrewError: LocalizedError {
    /// The last few stderr lines, short enough for the panel.
    let message: String
    /// The full command line, when the error came from running brew.
    var command: String?
    var exitCode: Int32?
    /// Everything brew printed, stdout and stderr in arrival order (capped).
    var output: String?

    var errorDescription: String? { message }
}

/// Thin wrapper around the `brew` executable. GUI apps don't inherit the shell's
/// PATH, so brew is located by absolute path and gets a minimal environment.
struct BrewService: Sendable {
    let brewURL: URL

    static func locate() -> BrewService? {
        let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return BrewService(brewURL: URL(fileURLWithPath: path))
        }
        return nil
    }

    private var environment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        let brewBin = brewURL.deletingLastPathComponent().path
        env["PATH"] = "\(brewBin):/usr/bin:/bin:/usr/sbin:/sbin"
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_NO_COLOR"] = "1"
        env["HOMEBREW_NO_EMOJI"] = "1"
        return env
    }

    /// Runs brew and returns its stdout. `onOutput` receives stdout and stderr
    /// chunks as they arrive, for live progress.
    @discardableResult
    func run(_ arguments: [String], onOutput: (@Sendable (String) -> Void)? = nil) async throws -> String {
        let process = Process()
        process.executableURL = brewURL
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdout = DataBuffer()
        let stderr = DataBuffer()
        let combined = DataBuffer()
        let group = DispatchGroup()

        for (pipe, buffer) in [(stdoutPipe, stdout), (stderrPipe, stderr)] {
            group.enter()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    group.leave()
                    return
                }
                buffer.append(data)
                combined.append(data)
                if let onOutput, let text = String(data: data, encoding: .utf8) {
                    onOutput(text)
                }
            }
        }

        group.enter()
        process.terminationHandler = { _ in group.leave() }

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
                return
            }
            group.notify(queue: .global()) {
                let output = String(decoding: stdout.data, as: UTF8.self)
                guard process.terminationStatus == 0 else {
                    let errorText = String(decoding: stderr.data, as: UTF8.self)
                        .split(separator: "\n")
                        .suffix(6)
                        .joined(separator: "\n")
                    let summary = errorText.isEmpty
                        ? "brew \(arguments.joined(separator: " ")) failed (exit \(process.terminationStatus))"
                        : errorText
                    let fullOutput = String(decoding: combined.data, as: UTF8.self)
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .suffix(150)
                        .joined(separator: "\n")
                    continuation.resume(throwing: BrewError(
                        message: summary,
                        command: (["brew"] + arguments).joined(separator: " "),
                        exitCode: process.terminationStatus,
                        output: fullOutput
                    ))
                    return
                }
                continuation.resume(returning: output)
            }
        }
    }
}

private final class DataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        lock.withLock { storage.append(data) }
    }

    var data: Data {
        lock.withLock { storage }
    }
}
