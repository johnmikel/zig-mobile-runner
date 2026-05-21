use serde_json::json;
use std::env;
use zmr_client::Client;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut zmr = String::from("zig-out/bin/zmr");
    let mut adb = String::from("tests/fake-adb.sh");
    let mut device = String::from("fake-android-1");
    let mut app_id = String::from("com.example.mobiletest");
    let mut trace_dir = String::from("traces/demo-rust-client");
    let mut trace_out = String::from("traces/demo-rust-client-redacted.zmrtrace");

    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--zmr" => zmr = args.next().ok_or("--zmr requires a value")?,
            "--adb" => adb = args.next().ok_or("--adb requires a value")?,
            "--device" => device = args.next().ok_or("--device requires a value")?,
            "--app-id" => app_id = args.next().ok_or("--app-id requires a value")?,
            "--trace-dir" => trace_dir = args.next().ok_or("--trace-dir requires a value")?,
            "--trace-out" => trace_out = args.next().ok_or("--trace-out requires a value")?,
            _ => return Err(format!("unknown argument: {arg}").into()),
        }
    }

    let mut client = Client::start(
        &zmr,
        [
            "serve",
            "--transport",
            "stdio",
            "--device",
            &device,
            "--app-id",
            &app_id,
            "--adb",
            &adb,
            "--trace-dir",
            &trace_dir,
        ],
    )?;
    let capabilities = client.capabilities()?;
    client.create_session()?;
    client.open_link("exampleapp://rust-client")?;
    client.wait_until(json!({ "text": "Dashboard" }), Some(1000))?;
    client.tap(json!({ "text": "Sign in" }))?;
    client.type_text(
        "agent@example.com",
        Some(json!({ "resourceId": "email-login-email-input" })),
    )?;
    client.assert_not_visible(json!({ "text": "Application has crashed" }), Some(100))?;
    client.assert_healthy(Some(100))?;
    let snapshot = client.snapshot()?;
    let exported = client.export_trace(&trace_out, true, true)?;
    let events = client.trace_events(0, Some(10))?;

    println!(
        "{}",
        json!({
            "protocolVersion": capabilities.protocol_version,
            "activePackage": snapshot.active_package,
            "nodes": snapshot.nodes.len(),
            "events": events.next_seq,
            "traceDir": trace_dir,
            "traceOut": exported.out,
        })
    );

    Ok(())
}
