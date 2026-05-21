import Foundation

public enum ZMRError: Error {
    case processNotStarted
    case invalidResponse
    case rpcError([String: Any])
}

public final class ZMRClient {
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private var nextID = 1

    public init(executable: String = "zmr", arguments: [String] = ["serve", "--transport", "stdio"]) {
        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.standardError

        self.process = process
        self.input = stdinPipe.fileHandleForWriting
        self.output = stdoutPipe.fileHandleForReading
    }

    public func start() throws {
        try process.run()
    }

    public func close() {
        _ = try? call("session.close")
        input.closeFile()
        if process.isRunning {
            process.terminate()
        }
    }

    @discardableResult
    public func call(_ method: String, params: [String: Any]? = nil) throws -> Any {
        guard process.isRunning else { throw ZMRError.processNotStarted }
        let id = nextID
        nextID += 1

        var request: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params {
            request["params"] = params
        }
        let data = try JSONSerialization.data(withJSONObject: request, options: [])
        input.write(data)
        input.write(Data([0x0a]))

        let line = try readLineData()
        let object = try JSONSerialization.jsonObject(with: line, options: [])
        guard let response = object as? [String: Any] else { throw ZMRError.invalidResponse }
        if let error = response["error"] as? [String: Any] {
            throw ZMRError.rpcError(error)
        }
        guard let result = response["result"] else { throw ZMRError.invalidResponse }
        return result
    }

    public func createSession() throws {
        _ = try call("session.create")
    }

    public func snapshot() throws -> [String: Any] {
        guard let result = try call("observe.snapshot") as? [String: Any] else {
            throw ZMRError.invalidResponse
        }
        return result
    }

    public func semanticSnapshot() throws -> [String: Any] {
        guard let result = try call("observe.semanticSnapshot") as? [String: Any] else {
            throw ZMRError.invalidResponse
        }
        return result
    }

    public func assertHealthy(timeoutMs: Int? = nil) throws -> Bool {
        var params: [String: Any] = [:]
        if let timeoutMs {
            params["timeoutMs"] = timeoutMs
        }
        guard let result = try call("assert.healthy", params: params) as? Bool else {
            throw ZMRError.invalidResponse
        }
        return result
    }

    private func readLineData() throws -> Data {
        var data = Data()
        while true {
            let byte = output.readData(ofLength: 1)
            if byte.isEmpty {
                throw ZMRError.invalidResponse
            }
            if byte[0] == 0x0a {
                return data
            }
            data.append(byte)
        }
    }
}
