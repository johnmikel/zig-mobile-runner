use serde_json::json;
use std::path::PathBuf;
use zmr_client::{Client, Error};

fn fake_server_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("tests")
        .join("fake-json-rpc-server.mjs")
}

#[test]
fn client_drives_fake_session() {
    let server = fake_server_path();
    let mut client = Client::start("node", [server.to_string_lossy().to_string()]).unwrap();

    let capabilities = client.capabilities().unwrap();
    assert_eq!(capabilities.protocol_version, "2026-04-28");
    assert!(capabilities
        .methods
        .iter()
        .any(|method| method == "observe.snapshot"));
    assert!(!capabilities.ios_preview);
    let ios_support = capabilities.platform_support.get("ios").unwrap();
    assert_eq!(ios_support.status, "supported");
    assert_eq!(ios_support.device_types, vec!["simulator"]);
    assert!(!ios_support.physical_devices);

    let session = client.create_session().unwrap();
    assert_eq!(session.session_id, "default");

    assert!(client.open_link("exampleapp://rust-client").unwrap());
    assert!(client
        .wait_until(json!({ "text": "Home" }), Some(1000))
        .unwrap());

    let snapshot = client.snapshot().unwrap();
    assert_eq!(snapshot.active_package, "com.example.mobiletest");
    assert_eq!(snapshot.nodes[0].text.as_deref(), Some("Home"));

    let exported = client
        .export_trace("traces/rust-client.zmrtrace", true, true)
        .unwrap();
    assert!(exported.redacted);
    assert!(exported.omit_screenshots);

    let events = client.trace_events(0, Some(10)).unwrap();
    assert_eq!(events.next_seq, 2);
    assert_eq!(events.events[0]["kind"], "rpc.request");
}

#[test]
fn client_returns_rpc_errors() {
    let server = fake_server_path();
    let mut client = Client::start("node", [server.to_string_lossy().to_string()]).unwrap();

    let err = client
        .request::<serde_json::Value>("missing.method", json!({}))
        .unwrap_err();
    match err {
        Error::Rpc(rpc) => {
            assert_eq!(rpc.code, -32601);
            assert_eq!(rpc.message, "method not found");
        }
        other => panic!("expected rpc error, got {other:?}"),
    }
}
