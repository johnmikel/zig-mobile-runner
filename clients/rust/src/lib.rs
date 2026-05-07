use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::fmt;
use std::io::{BufRead, BufReader, Write};
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};

#[derive(Debug)]
pub enum Error {
    Io(std::io::Error),
    Json(serde_json::Error),
    Rpc(RpcError),
    UnexpectedResponseId(i64),
    MissingPipe(&'static str),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Io(err) => write!(f, "{err}"),
            Error::Json(err) => write!(f, "{err}"),
            Error::Rpc(err) => write!(f, "{err}"),
            Error::UnexpectedResponseId(id) => write!(f, "unexpected JSON-RPC response id {id}"),
            Error::MissingPipe(name) => write!(f, "missing child process {name} pipe"),
        }
    }
}

impl std::error::Error for Error {}

impl From<std::io::Error> for Error {
    fn from(value: std::io::Error) -> Self {
        Error::Io(value)
    }
}

impl From<serde_json::Error> for Error {
    fn from(value: serde_json::Error) -> Self {
        Error::Json(value)
    }
}

#[derive(Debug, Deserialize)]
pub struct RpcError {
    pub code: i64,
    pub message: String,
    #[serde(rename = "publicCode")]
    pub public_code: Option<String>,
    pub data: Option<Value>,
}

impl fmt::Display for RpcError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for RpcError {}

#[derive(Debug, Deserialize)]
struct RpcResponse {
    id: i64,
    result: Option<Value>,
    error: Option<RpcError>,
}

pub struct Client {
    child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
    next_id: i64,
}

#[derive(Debug, Deserialize)]
pub struct Capabilities {
    pub name: String,
    pub version: String,
    #[serde(rename = "protocolVersion")]
    pub protocol_version: String,
    pub platforms: Vec<String>,
    pub transports: Vec<String>,
    pub methods: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct Session {
    #[serde(rename = "sessionId")]
    pub session_id: String,
}

#[derive(Debug, Deserialize)]
pub struct Snapshot {
    pub id: String,
    #[serde(rename = "timestampMs")]
    pub timestamp_ms: i64,
    pub viewport: Value,
    #[serde(rename = "activePackage")]
    pub active_package: String,
    #[serde(rename = "activeActivity")]
    pub active_activity: Option<String>,
    pub nodes: Vec<Node>,
}

#[derive(Debug, Deserialize)]
pub struct Node {
    #[serde(rename = "stableId")]
    pub stable_id: String,
    #[serde(rename = "className")]
    pub class_name: String,
    #[serde(default, rename = "resourceId")]
    pub resource_id: Option<String>,
    pub text: Option<String>,
    #[serde(rename = "contentDesc")]
    pub content_desc: Option<String>,
    pub bounds: Value,
    pub enabled: bool,
    pub visible: bool,
    pub selected: bool,
}

#[derive(Debug, Deserialize)]
pub struct TraceExport {
    #[serde(rename = "traceDir")]
    pub trace_dir: String,
    pub out: String,
    pub redacted: bool,
    #[serde(rename = "omitScreenshots")]
    pub omit_screenshots: bool,
}

#[derive(Debug, Deserialize)]
pub struct TraceEvents {
    #[serde(rename = "traceDir")]
    pub trace_dir: String,
    #[serde(rename = "afterSeq")]
    pub after_seq: i64,
    #[serde(rename = "nextSeq")]
    pub next_seq: i64,
    #[serde(rename = "latestSeq")]
    pub latest_seq: i64,
    pub events: Vec<Value>,
}

impl Client {
    pub fn start<I, S>(command: &str, args: I) -> Result<Self, Error>
    where
        I: IntoIterator<Item = S>,
        S: AsRef<std::ffi::OsStr>,
    {
        let mut child = Command::new(command)
            .args(args)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()?;
        let stdin = child.stdin.take().ok_or(Error::MissingPipe("stdin"))?;
        let stdout = child.stdout.take().ok_or(Error::MissingPipe("stdout"))?;
        Ok(Self {
            child,
            stdin,
            stdout: BufReader::new(stdout),
            next_id: 1,
        })
    }

    pub fn request<T: for<'de> Deserialize<'de>>(&mut self, method: &str, params: Value) -> Result<T, Error> {
        let id = self.next_id;
        self.next_id += 1;
        let request = json!({
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        });
        writeln!(self.stdin, "{}", serde_json::to_string(&request)?)?;
        self.stdin.flush()?;

        let mut line = String::new();
        self.stdout.read_line(&mut line)?;
        let response: RpcResponse = serde_json::from_str(&line)?;
        if response.id != id {
            return Err(Error::UnexpectedResponseId(response.id));
        }
        if let Some(error) = response.error {
            return Err(Error::Rpc(error));
        }
        let result = response.result.unwrap_or(Value::Null);
        Ok(serde_json::from_value(result)?)
    }

    pub fn capabilities(&mut self) -> Result<Capabilities, Error> {
        self.request("runner.capabilities", json!({}))
    }

    pub fn create_session(&mut self) -> Result<Session, Error> {
        self.request("session.create", json!({}))
    }

    pub fn open_link(&mut self, url: &str) -> Result<bool, Error> {
        self.request("app.openLink", json!({ "url": url }))
    }

    pub fn snapshot(&mut self) -> Result<Snapshot, Error> {
        self.request("observe.snapshot", json!({}))
    }

    pub fn wait_until(&mut self, selector: Value, timeout_ms: Option<i64>) -> Result<bool, Error> {
        let mut params = json!({ "visible": selector });
        if let Some(timeout_ms) = timeout_ms {
            params["timeoutMs"] = json!(timeout_ms);
        }
        self.request("wait.until", params)
    }

    pub fn export_trace(&mut self, out: &str, redact: bool, omit_screenshots: bool) -> Result<TraceExport, Error> {
        self.request("trace.export", json!({ "out": out, "redact": redact, "omitScreenshots": omit_screenshots }))
    }

    pub fn trace_events(&mut self, after_seq: i64, limit: Option<i64>) -> Result<TraceEvents, Error> {
        let mut params = json!({ "afterSeq": after_seq });
        if let Some(limit) = limit {
            params["limit"] = json!(limit);
        }
        self.request("trace.events", params)
    }
}

impl Drop for Client {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

#[derive(Debug, Serialize)]
pub struct Selector {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", rename = "resourceId")]
    pub resource_id: Option<String>,
}
