# Protocol Fixtures

These JSONL fixtures pin exact JSON-RPC request and response shapes for stable
core methods. The Zig unit suite feeds the request fixtures through the local
dispatcher and compares byte-for-byte response output.

When changing any response shape, update these fixtures deliberately and bump or
document protocol compatibility as needed.
