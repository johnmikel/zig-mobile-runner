# iOS Shim Protocol

The iOS shim protocol is internal and may change before `v1.0.0`.

Commands are newline-delimited JSON objects:

```json
{"cmd":"snapshot"}
{"cmd":"tap","selector":"text=Continue","x":20,"y":40}
{"cmd":"type","selector":"identifier=email","text":"hello"}
{"cmd":"eraseText","selector":"identifier=email","maxChars":20}
{"cmd":"hideKeyboard"}
{"cmd":"swipe","x1":300,"y1":900,"x2":300,"y2":300,"durationMs":250}
{"cmd":"pressBack"}
{"cmd":"settle","durationMs":1000}
{"cmd":"appState"}
```

Selector-addressed `tap`, `type`, and `eraseText` support these internal
selector strings:

- `text=<exact>` and `textContains=<substring>`
- `label=<exact>` and `labelContains=<substring>`
- `identifier=<exact>` and `identifierContains=<substring>`
- `resourceId=<exact>` and `resourceIdContains=<substring>`
- `id=<stable snapshot id>`
- `value=<exact>` and `valueContains=<substring>`
- `type=<XCUIElementType...>`

Snapshot responses return XCTest element data in a shape Zig can map into
`UiNode`:

```json
{
  "status": "ok",
  "nodes": [
    {
      "id": "button-continue",
      "type": "XCUIElementTypeButton",
      "label": "Continue",
      "identifier": "continue_button",
      "bounds": { "x": 10, "y": 20, "width": 100, "height": 44 },
      "enabled": true,
      "visible": true,
      "selected": false
    }
  ]
}
```

Errors use a stable envelope:

```json
{"status":"error","code":"selector.timeout","message":"selector did not match"}
```
