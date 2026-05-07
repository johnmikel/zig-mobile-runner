use serde_json::json;
use std::env;
use zmr_client::Client;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut node = String::from("node");
    let mut server = String::from("tests/fake-json-rpc-server.mjs");
    let mut trace_out = String::from("traces/demo-rust-client-redacted.zmrtrace");

    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--node" => node = args.next().ok_or("--node requires a value")?,
            "--server" => server = args.next().ok_or("--server requires a value")?,
            "--trace-out" => trace_out = args.next().ok_or("--trace-out requires a value")?,
            _ => return Err(format!("unknown argument: {arg}").into()),
        }
    }

    let mut client = Client::start(&node, [server])?;
    let capabilities = client.capabilities()?;
    client.create_session()?;
    client.open_link("exampleapp://rust-client")?;
    client.wait_until(json!({ "text": "Home" }), Some(1000))?;
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
            "traceOut": exported.out,
        })
    );

    Ok(())
}
