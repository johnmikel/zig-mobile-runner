import Foundation
import XCTest

final class ZMRShimUITestCase: XCTestCase {
    func testRunZMRCommand() throws {
        let environment = ProcessInfo.processInfo.environment
        let app = makeApplication(bundleIdentifier: shimRuntimeValue("ZMR_APP_BUNDLE_ID", environment: environment))

        if shimRuntimeValue("ZMR_SHIM_MODE", environment: environment) == "server" {
            guard let serverDir = shimRuntimeValue("ZMR_SHIM_SERVER_DIR", environment: environment) else {
                throw ZMRShimError.missingEnvironment
            }
            try runServer(serverDir: serverDir, app: app)
            return
        }

        guard let requestFile = shimRuntimeValue("ZMR_SHIM_REQUEST_FILE", environment: environment),
              let responseFile = shimRuntimeValue("ZMR_SHIM_RESPONSE_FILE", environment: environment) else {
            throw ZMRShimError.missingEnvironment
        }

        try process(requestAt: requestFile, responseAt: responseFile, app: app)
    }

    private func runServer(serverDir: String, app: XCUIApplication) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(atPath: serverDir, withIntermediateDirectories: true)

        let readyFile = path(in: serverDir, named: "ready")
        let stopFile = path(in: serverDir, named: "stop")
        _ = fileManager.createFile(atPath: readyFile, contents: Data(), attributes: nil)

        var idleDeadline = Date().addingTimeInterval(900)
        while Date() < idleDeadline {
            if fileManager.fileExists(atPath: stopFile) {
                break
            }

            let requestNames = try fileManager.contentsOfDirectory(atPath: serverDir)
                .filter { $0.hasPrefix("request-") && $0.hasSuffix(".json") }
                .sorted()

            if requestNames.isEmpty {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }

            for requestName in requestNames {
                let requestID = requestName
                    .dropFirst("request-".count)
                    .dropLast(".json".count)
                let requestFile = path(in: serverDir, named: requestName)
                let responseFile = path(in: serverDir, named: "response-\(requestID).json")

                try process(requestAt: requestFile, responseAt: responseFile, app: app)
                try? fileManager.removeItem(atPath: requestFile)
                idleDeadline = Date().addingTimeInterval(900)
            }
        }
    }

    private func process(requestAt requestFile: String, responseAt responseFile: String, app: XCUIApplication) throws {
        let response = responseFor(requestAt: requestFile, app: app)
        let responseData = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
        let responseURL = URL(fileURLWithPath: responseFile)
        let temporaryURL = URL(fileURLWithPath: "\(responseFile).tmp")
        try responseData.write(to: temporaryURL, options: [.atomic])
        if FileManager.default.fileExists(atPath: responseFile) {
            try FileManager.default.removeItem(at: responseURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: responseURL)
    }

    private func responseFor(requestAt requestFile: String, app: XCUIApplication) -> [String: Any] {
        do {
            let requestData = try Data(contentsOf: URL(fileURLWithPath: requestFile))
            let command = try JSONDecoder().decode(ZMRShimCommand.self, from: requestData)
            return run(command: command, app: app)
        } catch {
            return self.error("invalid.request", "\(error)")
        }
    }

    private func path(in directory: String, named name: String) -> String {
        (directory as NSString).appendingPathComponent(name)
    }

    private func shimRuntimeValue(_ key: String, environment: [String: String]) -> String? {
        if let value = environment[key], !value.isEmpty, !value.hasPrefix("$(") {
            return value
        }
        if let value = Bundle(for: Self.self).object(forInfoDictionaryKey: key) as? String,
           !value.isEmpty,
           !value.hasPrefix("$(") {
            return value
        }
        return nil
    }

    private func makeApplication(bundleIdentifier: String?) -> XCUIApplication {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return XCUIApplication(bundleIdentifier: bundleIdentifier)
        }
        return XCUIApplication()
    }

    private func run(command: ZMRShimCommand, app: XCUIApplication) -> [String: Any] {
        switch command.cmd {
        case "snapshot":
            return [
                "status": "ok",
                "nodes": ZMRShim.snapshot(app: app).map { $0.json }
            ]
        case "tap":
            guard let x = command.x, let y = command.y else {
                return error("invalid.tap", "tap requires x and y")
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: x, dy: y))
                .tap()
            return ok()
        case "type":
            app.typeText(command.text ?? "")
            return ok()
        case "eraseText":
            let count = Int(command.maxChars ?? 0)
            if count > 0 {
                app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
            }
            return ok()
        case "hideKeyboard":
            if app.keyboards.firstMatch.exists {
                app.keyboards.buttons["Return"].tap()
            }
            return ok()
        case "swipe":
            guard let x1 = command.x1, let y1 = command.y1, let x2 = command.x2, let y2 = command.y2 else {
                return error("invalid.swipe", "swipe requires x1, y1, x2, and y2")
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: x1, dy: y1))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
                .withOffset(CGVector(dx: x2, dy: y2))
            start.press(forDuration: 0.01, thenDragTo: end)
            return ok()
        case "pressBack":
            XCUIDevice.shared.press(.home)
            return ok()
        case "settle":
            let timeout = TimeInterval(command.durationMs ?? 1000) / 1000.0
            _ = app.wait(for: app.state, timeout: timeout)
            return ok()
        case "appState":
            return ["status": "ok", "state": app.state.rawValue]
        default:
            return error("unknown.command", "unsupported command: \(command.cmd)")
        }
    }

    private func ok() -> [String: Any] {
        ["status": "ok"]
    }

    private func error(_ code: String, _ message: String) -> [String: Any] {
        ["status": "error", "code": code, "message": message]
    }
}

enum ZMRShimError: Error {
    case missingEnvironment
}

private extension ZMRShimBounds {
    var json: [String: Any] {
        [
            "x": x,
            "y": y,
            "width": width,
            "height": height
        ]
    }
}

private extension ZMRShimNode {
    var json: [String: Any] {
        [
            "id": id,
            "type": type,
            "label": label,
            "identifier": identifier,
            "bounds": bounds.json,
            "enabled": enabled,
            "visible": visible,
            "selected": selected
        ]
    }
}
