package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/johnmikel/zig-mobile-runner/clients/go/zmr"
)

func main() {
	node := flag.String("node", "node", "node executable")
	server := flag.String("server", "tests/fake-json-rpc-server.mjs", "fake JSON-RPC server path")
	traceOut := flag.String("trace-out", "traces/demo-go-client-redacted.zmrtrace", "trace export path")
	flag.Parse()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	client, err := zmr.Start(ctx, *node, *server)
	if err != nil {
		fail(err)
	}
	defer client.Close()

	capabilities, err := client.Capabilities(ctx)
	if err != nil {
		fail(err)
	}
	if _, err := client.CreateSession(ctx); err != nil {
		fail(err)
	}
	if _, err := client.OpenLink(ctx, "exampleapp://go-client"); err != nil {
		fail(err)
	}
	if _, err := client.WaitUntil(ctx, map[string]interface{}{"text": "Home"}, 1000); err != nil {
		fail(err)
	}
	snapshot, err := client.Snapshot(ctx)
	if err != nil {
		fail(err)
	}
	exported, err := client.ExportTrace(ctx, *traceOut, true, true)
	if err != nil {
		fail(err)
	}
	events, err := client.TraceEvents(ctx, 0, 10)
	if err != nil {
		fail(err)
	}

	summary := map[string]interface{}{
		"protocolVersion": capabilities.ProtocolVersion,
		"activePackage":   snapshot.ActivePackage,
		"nodes":           len(snapshot.Nodes),
		"events":          events.NextSeq,
		"traceOut":        exported.Out,
	}
	encoded, _ := json.Marshal(summary)
	fmt.Println(string(encoded))
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
