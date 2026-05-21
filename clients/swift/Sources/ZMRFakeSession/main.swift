import Foundation
import ZMRClient

struct Options {
    var zmr = "zig-out/bin/zmr"
    var adb = "tests/fake-adb.sh"
    var device = "fake-android-1"
    var appID = "com.example.mobiletest"
    var traceDir = "traces/demo-swift-client"
    var traceOut = "traces/demo-swift-client-redacted.zmrtrace"
}

func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        guard index + 1 < arguments.count else {
            throw NSError(domain: "ZMRFakeSession", code: 2, userInfo: [NSLocalizedDescriptionKey: "\(argument) requires a value"])
        }
        let value = arguments[index + 1]
        switch argument {
        case "--zmr": options.zmr = value
        case "--adb": options.adb = value
        case "--device": options.device = value
        case "--app-id": options.appID = value
        case "--trace-dir": options.traceDir = value
        case "--trace-out": options.traceOut = value
        default:
            throw NSError(domain: "ZMRFakeSession", code: 2, userInfo: [NSLocalizedDescriptionKey: "unknown argument: \(argument)"])
        }
        index += 2
    }
    return options
}

func object(_ value: Any) throws -> [String: Any] {
    guard let object = value as? [String: Any] else {
        throw ZMRError.invalidResponse
    }
    return object
}

do {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    let client = ZMRClient(
        executable: options.zmr,
        arguments: [
            "serve",
            "--transport", "stdio",
            "--device", options.device,
            "--app-id", options.appID,
            "--adb", options.adb,
            "--trace-dir", options.traceDir
        ]
    )
    try client.start()
    defer { client.close() }

    let capabilities = try object(try client.call("runner.capabilities"))
    try client.createSession()
    _ = try client.call("app.openLink", params: ["url": "exampleapp://swift-client"])
    _ = try client.call("wait.until", params: ["visible": ["text": "Dashboard"], "timeoutMs": 1000])
    _ = try client.call("ui.tap", params: ["selector": ["text": "Sign in"]])
    _ = try client.call("ui.type", params: ["text": "agent@example.com", "selector": ["resourceId": "email-login-email-input"]])
    _ = try client.call("assert.notVisible", params: ["selector": ["text": "Application has crashed"], "timeoutMs": 100])
    _ = try client.assertHealthy(timeoutMs: 100)
    let snapshot = try client.snapshot()
    let exported = try object(try client.call("trace.export", params: ["out": options.traceOut, "redact": true, "includeScreenshots": true]))
    let events = try object(try client.call("trace.events", params: ["afterSeq": 0, "limit": 10]))

    let nodes = snapshot["nodes"] as? [Any] ?? []
    let summary: [String: Any] = [
        "protocolVersion": capabilities["protocolVersion"] ?? "",
        "activePackage": snapshot["activePackage"] ?? "",
        "nodes": nodes.count,
        "events": events["nextSeq"] ?? 0,
        "traceDir": options.traceDir,
        "traceOut": exported["out"] ?? options.traceOut
    ]
    let data = try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8) ?? "{}")
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
