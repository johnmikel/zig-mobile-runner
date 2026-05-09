package zmr

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func fakeServerPath(t *testing.T) string {
	t.Helper()
	root := filepath.Clean(filepath.Join("..", "..", ".."))
	return filepath.Join(root, "tests", "fake-json-rpc-server.mjs")
}

func TestClientDrivesFakeSession(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client, err := Start(ctx, "node", fakeServerPath(t))
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	capabilities, err := client.Capabilities(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if capabilities.ProtocolVersion != "2026-04-28" {
		t.Fatalf("protocol version = %q", capabilities.ProtocolVersion)
	}
	if capabilities.IosPreview {
		t.Fatal("iOS should be reported as supported, not preview")
	}
	iosSupport := capabilities.PlatformSupport["ios"]
	if iosSupport.Status != "supported" || len(iosSupport.DeviceTypes) != 2 || iosSupport.DeviceTypes[0] != "simulator" || iosSupport.DeviceTypes[1] != "physical" || !iosSupport.PhysicalDevices {
		t.Fatalf("unexpected iOS platform support: %+v", iosSupport)
	}

	session, err := client.CreateSession(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if session.SessionID != "default" {
		t.Fatalf("session id = %q", session.SessionID)
	}

	ok, err := client.OpenLink(ctx, "exampleapp://go-client")
	if err != nil || !ok {
		t.Fatalf("open link ok=%v err=%v", ok, err)
	}

	ok, err = client.WaitUntil(ctx, map[string]interface{}{"text": "Home"}, 1000)
	if err != nil || !ok {
		t.Fatalf("wait ok=%v err=%v", ok, err)
	}

	snapshot, err := client.Snapshot(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if snapshot.ActivePackage != "com.example.mobiletest" {
		t.Fatalf("active package = %q", snapshot.ActivePackage)
	}
	if len(snapshot.Nodes) == 0 || snapshot.Nodes[0].Text == nil || *snapshot.Nodes[0].Text != "Home" {
		t.Fatalf("unexpected first node: %+v", snapshot.Nodes)
	}

	semanticSnapshot, err := client.SemanticSnapshot(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(semanticSnapshot.Nodes) == 0 || semanticSnapshot.Nodes[0].Role != "button" || semanticSnapshot.Nodes[0].RecommendedAction == nil || *semanticSnapshot.Nodes[0].RecommendedAction != "tap" {
		t.Fatalf("unexpected semantic first node: %+v", semanticSnapshot.Nodes)
	}

	exported, err := client.ExportTrace(ctx, filepath.Join(os.TempDir(), "go-client.zmrtrace"), true, true)
	if err != nil {
		t.Fatal(err)
	}
	if !exported.Redacted || !exported.OmitScreenshots {
		t.Fatalf("unexpected export: %+v", exported)
	}

	events, err := client.TraceEvents(ctx, 0, 10)
	if err != nil {
		t.Fatal(err)
	}
	if events.NextSeq != 2 || len(events.Events) == 0 || events.Events[0]["kind"] != "rpc.request" {
		t.Fatalf("unexpected events: %+v", events)
	}
}

func TestClientReturnsRPCError(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	client, err := Start(ctx, "node", fakeServerPath(t))
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	var rpcErr *RPCError
	err = client.Request(ctx, "missing.method", map[string]interface{}{}, nil)
	if !errors.As(err, &rpcErr) {
		t.Fatalf("expected RPCError, got %T %v", err, err)
	}
	if rpcErr.Code != -32601 || rpcErr.Message != "method not found" {
		t.Fatalf("unexpected rpc error: %+v", rpcErr)
	}
}
