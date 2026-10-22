import AppKit
import Combine
import SwiftUI

private struct CoreCommandResult {
    let success: Bool
    let output: String
    let message: String
}

@MainActor
final class JitterBreakModel: ObservableObject {
    @Published var isOn = false
    @Published var isBusy = false
    @Published var statusMessage = "Checking status..."
    @Published var errorMessage = ""

    func refreshStatus() {
        guard !isBusy else {
            return
        }

        let result = runDirectCommand(arg: "status")
        if result.success {
            isOn = result.output == "on"
            statusMessage = isOn ? "JitterBreak is active" : "JitterBreak is inactive"
            errorMessage = ""
            return
        }

        statusMessage = "Status unavailable"
        errorMessage = result.message
    }

    func setEnabled(_ enabled: Bool) {
        guard !isBusy else {
            return
        }

        isBusy = true
        errorMessage = ""
        statusMessage = "Waiting for administrator authorization..."

        // nohup can't detach under `do shell script` as admin, so a background core never starts
        let result = runPrivilegedCommand(arg: enabled ? "on" : "off")

        isBusy = false

        if result.success {
            refreshStatus()
            return
        }

        refreshStatus()
        errorMessage = result.message
    }

    private func enginePath() -> String? {
        Bundle.main.path(forResource: "jitterbreak-core", ofType: nil)
    }

    private func runDirectCommand(arg: String) -> CoreCommandResult {
        guard let route = enginePath() else {
            return CoreCommandResult(success: false, output: "", message: "Internal engine not found")
        }

        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()

        process.executableURL = URL(fileURLWithPath: route)
        process.arguments = [arg]
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CoreCommandResult(success: false, output: "", message: error.localizedDescription)
        }

        let output = read(pipe: stdout)
        let failureOutput = read(pipe: stderr)

        if process.terminationStatus == 0 {
            return CoreCommandResult(success: true, output: output, message: "")
        }

        let message = failureOutput.isEmpty ? output : failureOutput
        return CoreCommandResult(success: false, output: output, message: message.isEmpty ? "Command failed" : message)
    }

    private func runPrivilegedCommand(arg: String) -> CoreCommandResult {
        guard let route = enginePath() else {
            return CoreCommandResult(success: false, output: "", message: "Internal engine not found")
        }

        let command = "\(shellQuote(route)) \(shellQuote(arg))"
        return runPrivilegedShellCommand(command)
    }

    private func runPrivilegedShellCommand(_ command: String) -> CoreCommandResult {
        let scriptSource = "do shell script \(appleScriptQuote(command)) with administrator privileges"
        var error: NSDictionary?

        guard let script = NSAppleScript(source: scriptSource) else {
            return CoreCommandResult(success: false, output: "", message: "Could not prepare administrator request")
        }

        let result = script.executeAndReturnError(&error)

        if let error {
            return CoreCommandResult(success: false, output: "", message: formatAppleScriptError(error))
        }

        return CoreCommandResult(
            success: true,
            output: result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            message: ""
        )
    }

    private func read(pipe: Pipe) -> String {
        String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func appleScriptQuote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return "\"\(escaped)\""
    }

    private func formatAppleScriptError(_ error: NSDictionary) -> String {
        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"

        if code == -128 {
            return "Administrator authorization was canceled"
        }

        return message
    }
}

@main
struct JitterBreakApp: App {
    @StateObject private var model = JitterBreakModel()

    var body: some Scene {
        MenuBarExtra("JitterBreak", systemImage: model.isOn ? "house.badge.wifi.fill" : "house.badge.wifi") {
            Text(model.statusMessage)
                .onAppear {
                    model.refreshStatus()
                }

            Text("Uses administrator authorization to change AWDL and LLW")

            if !model.errorMessage.isEmpty {
                Divider()
                Text(model.errorMessage)
            }

            Divider()
            Button(model.isOn ? "Stop JitterBreak" : "Start JitterBreak") {
                model.setEnabled(!model.isOn)
            }
            .disabled(model.isBusy)

            Button("Refresh Status") {
                model.refreshStatus()
            }
            .disabled(model.isBusy)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
