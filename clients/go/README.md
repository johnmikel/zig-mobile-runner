# ZMR Go Client

Small standard-library JSON-RPC client for driving `zmr serve --transport stdio`
from Go agents and test harnesses.

```go
client, err := zmr.Start(ctx, "zmr", "serve", "--transport", "stdio")
if err != nil {
    panic(err)
}
defer client.Close()

snapshot, err := client.Snapshot(ctx)
```

Run the fake-session example from the repository root:

```sh
go run ./clients/go/examples/fake-session --server tests/fake-json-rpc-server.mjs
```
