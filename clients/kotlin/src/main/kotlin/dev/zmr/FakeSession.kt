package dev.zmr

private data class Options(
    var zmr: String = "zig-out/bin/zmr",
    var adb: String = "tests/fake-adb.sh",
    var device: String = "fake-android-1",
    var appId: String = "com.example.mobiletest",
    var traceDir: String = "traces/demo-kotlin-client",
    var traceOut: String = "traces/demo-kotlin-client-redacted.zmrtrace"
)

fun main(args: Array<String>) {
    val options = parseOptions(args)
    ZmrClient(
        listOf(
            options.zmr,
            "serve",
            "--transport", "stdio",
            "--device", options.device,
            "--app-id", options.appId,
            "--adb", options.adb,
            "--trace-dir", options.traceDir
        )
    ).use { client ->
        val capabilities = client.call("runner.capabilities")
        client.createSession()
        client.call("app.openLink", """{"url":"exampleapp://kotlin-client"}""")
        client.call("wait.until", """{"visible":{"text":"Dashboard"},"timeoutMs":1000}""")
        client.call("ui.tap", """{"selector":{"text":"Sign in"}}""")
        client.call("ui.type", """{"text":"agent@example.com","selector":{"resourceId":"email-login-email-input"}}""")
        client.call("assert.notVisible", """{"selector":{"text":"Application has crashed"},"timeoutMs":100}""")
        client.assertHealthy(timeoutMs = 100)
        val snapshot = client.snapshot()
        val exported = client.call(
            "trace.export",
            """{"out":"${escapeJson(options.traceOut)}","redact":true,"includeScreenshots":true}"""
        )
        val events = client.call("trace.events", """{"afterSeq":0,"limit":10}""")

        println(
            "{" +
                "\"protocolVersion\":\"${extractString(capabilities, "protocolVersion")}\"," +
                "\"activePackage\":\"${extractString(snapshot, "activePackage")}\"," +
                "\"nodes\":${countOccurrences(snapshot, "\"stableId\"")}," +
                "\"events\":${extractNumber(events, "nextSeq")}," +
                "\"traceDir\":\"${escapeJson(options.traceDir)}\"," +
                "\"traceOut\":\"${escapeJson(extractString(exported, "out"))}\"" +
                "}"
        )
    }
}

private fun parseOptions(args: Array<String>): Options {
    val options = Options()
    var index = 0
    while (index < args.size) {
        val value = args.getOrNull(index + 1) ?: error("${args[index]} requires a value")
        when (args[index]) {
            "--zmr" -> options.zmr = value
            "--adb" -> options.adb = value
            "--device" -> options.device = value
            "--app-id" -> options.appId = value
            "--trace-dir" -> options.traceDir = value
            "--trace-out" -> options.traceOut = value
            else -> error("unknown argument: ${args[index]}")
        }
        index += 2
    }
    return options
}

private fun extractString(json: String, key: String): String {
    val match = Regex(""""$key"\s*:\s*"([^"]*)"""").find(json)
    return match?.groupValues?.get(1) ?: ""
}

private fun extractNumber(json: String, key: String): String {
    val match = Regex(""""$key"\s*:\s*([0-9]+)""").find(json)
    return match?.groupValues?.get(1) ?: "0"
}

private fun countOccurrences(value: String, needle: String): Int =
    Regex.escape(needle).toRegex().findAll(value).count()

private fun escapeJson(value: String): String =
    value.replace("\\", "\\\\").replace("\"", "\\\"")
