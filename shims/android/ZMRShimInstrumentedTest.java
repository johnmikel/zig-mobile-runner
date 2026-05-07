package dev.zmr.shim;

import android.graphics.Rect;
import android.os.Bundle;
import android.view.KeyEvent;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;
import androidx.test.uiautomator.Until;

import org.json.JSONArray;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.File;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.List;

@RunWith(AndroidJUnit4.class)
public final class ZMRShimInstrumentedTest {
    @Test
    public void testRunZMRCommand() throws Exception {
        Bundle args = InstrumentationRegistry.getArguments();
        String requestFile = args.getString("zmrRequestFile");
        String responseFile = args.getString("zmrResponseFile");
        if (requestFile == null || responseFile == null) {
            throw new IllegalArgumentException("zmrRequestFile and zmrResponseFile are required");
        }

        String request = new String(Files.readAllBytes(new File(requestFile).toPath()), StandardCharsets.UTF_8);
        JSONObject command = new JSONObject(request);
        JSONObject response = run(command, UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()));
        Files.write(new File(responseFile).toPath(), response.toString().getBytes(StandardCharsets.UTF_8));
    }

    private JSONObject run(JSONObject command, UiDevice device) throws Exception {
        String cmd = command.optString("cmd", "");
        switch (cmd) {
            case "snapshot":
                return ok().put("nodes", snapshot(device));
            case "tap":
                device.click(command.getInt("x"), command.getInt("y"));
                return ok();
            case "type":
                device.executeShellCommand("input text " + escapeInputText(command.optString("text", "")));
                return ok();
            case "eraseText":
                int count = command.optInt("maxChars", 0);
                for (int i = 0; i < count; i += 1) {
                    device.pressKeyCode(KeyEvent.KEYCODE_DEL);
                }
                return ok();
            case "hideKeyboard":
            case "pressBack":
                device.pressBack();
                return ok();
            case "swipe":
                device.swipe(
                    command.getInt("x1"),
                    command.getInt("y1"),
                    command.getInt("x2"),
                    command.getInt("y2"),
                    Math.max(1, command.optInt("durationMs", 250) / 5)
                );
                return ok();
            case "settle":
                device.waitForIdle(command.optLong("durationMs", 1000));
                return ok();
            case "appState":
                return ok().put("state", "ready");
            default:
                return error("unknown.command", "unsupported command: " + cmd);
        }
    }

    private JSONArray snapshot(UiDevice device) throws Exception {
        device.waitForIdle();
        List<UiObject2> objects = device.wait(Until.findObjects(By.depth(0)), 1000);
        JSONArray nodes = new JSONArray();
        appendChildren(nodes, device.findObject(By.depth(0)), "root");
        if (nodes.length() == 0 && objects != null) {
            for (int i = 0; i < objects.size(); i += 1) {
                appendNode(nodes, objects.get(i), "node:" + i);
            }
        }
        return nodes;
    }

    private void appendChildren(JSONArray nodes, UiObject2 object, String prefix) throws Exception {
        if (object == null) return;
        appendNode(nodes, object, prefix);
        List<UiObject2> children = object.getChildren();
        for (int i = 0; i < children.size(); i += 1) {
            appendChildren(nodes, children.get(i), prefix + ":" + i);
        }
    }

    private void appendNode(JSONArray nodes, UiObject2 object, String fallbackId) throws Exception {
        Rect bounds = object.getVisibleBounds();
        String resourceName = object.getResourceName();
        String text = object.getText();
        String description = object.getContentDescription();
        String id = resourceName != null && !resourceName.isEmpty() ? "id:" + resourceName : fallbackId;

        JSONObject node = new JSONObject();
        node.put("id", id);
        node.put("type", object.getClassName());
        node.put("label", text == null ? "" : text);
        node.put("identifier", resourceName == null ? "" : resourceName);
        node.put("contentDescription", description == null ? "" : description);
        node.put("enabled", object.isEnabled());
        node.put("visible", bounds.width() > 0 && bounds.height() > 0);
        node.put("selected", object.isSelected());
        node.put("bounds", new JSONObject()
            .put("x", bounds.left)
            .put("y", bounds.top)
            .put("width", bounds.width())
            .put("height", bounds.height()));
        nodes.put(node);
    }

    private JSONObject ok() throws Exception {
        return new JSONObject().put("status", "ok");
    }

    private JSONObject error(String code, String message) throws Exception {
        return new JSONObject()
            .put("status", "error")
            .put("code", code)
            .put("message", message);
    }

    private String escapeInputText(String value) {
        return value
            .replace("\\", "\\\\")
            .replace(" ", "%s")
            .replace("&", "\\&")
            .replace("<", "\\<")
            .replace(">", "\\>")
            .replace(";", "\\;")
            .replace("|", "\\|")
            .replace("*", "\\*")
            .replace("~", "\\~")
            .replace("\"", "\\\"")
            .replace("'", "\\'");
    }
}
