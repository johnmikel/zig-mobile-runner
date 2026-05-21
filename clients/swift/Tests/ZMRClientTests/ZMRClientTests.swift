import XCTest
@testable import ZMRClient

final class ZMRClientTests: XCTestCase {
    func testDrivesFakeJsonRpcSession() throws {
        let root = repoRoot()
        let server = root.appendingPathComponent("tests/fake-json-rpc-server.mjs").path
        let client = ZMRClient(executable: "node", arguments: [server])
        try client.start()
        defer { client.close() }

        guard let capabilities = try client.call("runner.capabilities") as? [String: Any] else {
            return XCTFail("capabilities response was not an object")
        }
        XCTAssertEqual(capabilities["protocolVersion"] as? String, "2026-04-28")
        let methods = capabilities["methods"] as? [String]
        XCTAssertEqual(methods?.contains("assert.healthy"), true)

        XCTAssertEqual(try client.assertHealthy(timeoutMs: 1000), true)
        let snapshot = try client.snapshot()
        XCTAssertEqual(snapshot["activePackage"] as? String, "com.example.mobiletest")
    }

    private func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
        }
        return url
    }
}
