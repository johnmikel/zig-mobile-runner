package dev.zmr

import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.Closeable
import java.io.InputStreamReader
import java.io.OutputStreamWriter

class ZmrClient(
    private val command: List<String> = listOf("zmr", "serve", "--transport", "stdio")
) : Closeable {
    private var nextId = 1
    private val process = ProcessBuilder(command).redirectError(ProcessBuilder.Redirect.INHERIT).start()
    private val input = BufferedWriter(OutputStreamWriter(process.outputStream))
    private val output = BufferedReader(InputStreamReader(process.inputStream))

    fun createSession(): String = call("session.create")

    fun snapshot(): String = call("observe.snapshot")

    fun semanticSnapshot(): String = call("observe.semanticSnapshot")

    @Synchronized
    fun call(method: String, paramsJson: String? = null): String {
        val id = nextId++
        val params = paramsJson?.let { "," + "\"params\":" + it } ?: ""
        input.write("{\"jsonrpc\":\"2.0\",\"id\":$id,\"method\":\"$method\"$params}")
        input.newLine()
        input.flush()
        return output.readLine() ?: error("zmr closed stdout")
    }

    override fun close() {
        runCatching { call("session.close") }
        runCatching { input.close() }
        process.destroy()
    }
}
