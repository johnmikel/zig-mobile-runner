package dev.zmr

import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue
import kotlin.test.assertFailsWith

class ZmrClientTest {
    @Test
    fun drivesFakeJsonRpcSession() {
        val server = fakeServerPath()
        ZmrClient(listOf("node", server.absolutePath)).use { client ->
            val capabilities = client.call("runner.capabilities")
            assertTrue(capabilities.contains("\"protocolVersion\":\"2026-04-28\""))
            assertTrue(capabilities.contains("\"assert.healthy\""))

            val healthy = client.assertHealthy(timeoutMs = 1000)
            assertTrue(healthy.contains("\"result\":true"))

            val snapshot = client.snapshot()
            assertTrue(snapshot.contains("\"activePackage\":\"com.example.mobiletest\""))
        }
    }

    @Test
    fun rejectsJsonRpcErrors() {
        val server = fakeServerPath()
        ZmrClient(listOf("node", server.absolutePath)).use { client ->
            val error = assertFailsWith<ZmrRpcException> {
                client.call("missing.method")
            }
            assertTrue(error.message.orEmpty().contains("method not found"))
            assertTrue(error.code == -32601)
        }
    }

    private fun fakeServerPath(): File {
        val candidates = listOf(
            File("tests/fake-json-rpc-server.mjs"),
            File("../../tests/fake-json-rpc-server.mjs")
        )
        return candidates.firstOrNull { it.isFile }?.absoluteFile
            ?: error("could not find tests/fake-json-rpc-server.mjs from ${File(".").absolutePath}")
    }
}
