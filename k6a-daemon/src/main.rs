/*!
 * k6a-daemon — Real-time WebSocket backend for BadazZ89 k6a Optimizer
 *
 * Architecture:
 *   service.sh  ──Unix socket──▶  Daemon  ──WebSocket──▶  WebUI (browser)
 *                                   │
 *                                   └──HTTP──▶ static WebUI files
 *
 * Ports (localhost only — not exposed to network):
 *   7070  WebSocket  — real-time data push to WebUI
 *   7071  HTTP       — serves webroot/ static files
 *
 * Unix socket:
 *   /data/adb/modules/Bad4zz89_k6a_tweaks/run/daemon.sock
 *   service.sh writes newline-delimited JSON to this socket
 *
 * Kernel: 4.14 CAF (spoofed as 6.12) — no TLS, no fancy syscalls needed
 */

use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use futures_util::{SinkExt, StreamExt};
use http_body_util::Full;
use hyper::body::Bytes;
use hyper::{Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::net::{TcpListener, UnixListener};
use tokio::sync::{broadcast, RwLock};
use tokio_tungstenite::tungstenite::Message;
use tracing::{error, info, warn};

// ── Constants ────────────────────────────────────────────────────────────────

const MOD_PATH: &str = "/data/adb/modules/Bad4zz89_k6a_tweaks";
const SOCK_PATH: &str = "/data/adb/modules/Bad4zz89_k6a_tweaks/run/daemon.sock";
const WS_ADDR: &str = "127.0.0.1:7070";
const HTTP_ADDR: &str = "127.0.0.1:7071";
const BROADCAST_CAP: usize = 32;

// ── Data types ───────────────────────────────────────────────────────────────

/// Full state snapshot — mirrors what service.sh previously wrote to data.txt
/// All fields are Option<String> so partial updates work
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DeviceState {
    // System info
    pub kernel: Option<String>,
    pub kernel_real: Option<String>,
    pub android: Option<String>,
    pub bat: Option<String>,
    pub uptime: Option<String>,
    pub pid: Option<String>,

    // Networking
    pub ping: Option<String>,

    // Profile
    pub profile: Option<String>,
    pub manual_profile: Option<String>,

    // Memory
    pub ram_used: Option<String>,
    pub ram_total: Option<String>,
    pub cache_kb: Option<String>,
    pub last_clean: Option<String>,

    // Config toggles
    pub conf_auto: Option<String>,
    pub conf_thermal: Option<String>,
    pub conf_boost: Option<String>,
    pub conf_autocache: Option<String>,
    pub conf_spoof_enable: Option<String>,
    pub conf_spoof_temp: Option<String>,
    pub conf_bypass_thresh: Option<String>,

    // Per-app and log
    pub perapp: Option<String>,
    pub log: Option<String>,

    // Daemon metadata
    pub daemon_version: Option<String>,
    pub daemon_uptime_s: Option<u64>,
}

impl DeviceState {
    /// Merge a key=value update into the state
    pub fn apply_kv(&mut self, key: &str, value: &str) {
        let v = Some(value.to_string());
        match key {
            "kernel"            => self.kernel = v,
            "kernel_real"       => self.kernel_real = v,
            "android"           => self.android = v,
            "bat"               => self.bat = v,
            "uptime"            => self.uptime = v,
            "pid"               => self.pid = v,
            "ping"              => self.ping = v,
            "profile"           => self.profile = v,
            "manual_profile"    => self.manual_profile = v,
            "ram_used"          => self.ram_used = v,
            "ram_total"         => self.ram_total = v,
            "cache_kb"          => self.cache_kb = v,
            "last_clean"        => self.last_clean = v,
            "conf_auto"         => self.conf_auto = v,
            "conf_thermal"      => self.conf_thermal = v,
            "conf_boost"        => self.conf_boost = v,
            "conf_autocache"    => self.conf_autocache = v,
            "conf_spoof_enable" => self.conf_spoof_enable = v,
            "conf_spoof_temp"   => self.conf_spoof_temp = v,
            "conf_bypass_thresh"=> self.conf_bypass_thresh = v,
            "perapp"            => self.perapp = v,
            "log"               => self.log = v,
            _ => {} // unknown keys are silently ignored
        }
    }
}

/// Message types the WebSocket sends to clients
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum WsMessage {
    /// Full state snapshot — sent on connect and after each update
    StateSnapshot { data: DeviceState },
    /// Single field update — sent for low-latency partial updates
    FieldUpdate { key: String, value: String },
    /// Pong response to client ping
    Pong,
    /// Error message
    Error { message: String },
}

/// Messages the WebUI can send to the daemon
#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMessage {
    Ping,
    /// Request a full state refresh
    Refresh,
}

// ── Shared state ─────────────────────────────────────────────────────────────

type SharedState = Arc<RwLock<DeviceState>>;
type Broadcaster = broadcast::Sender<WsMessage>;

// ── Unix socket listener ─────────────────────────────────────────────────────

/// Listens on the Unix socket for newline-delimited key=value lines from service.sh
/// Each line is "key=value" — same format as data.txt but streamed in real time
async fn unix_socket_listener(
    state: SharedState,
    tx: Broadcaster,
    start_time: std::time::Instant,
) {
    // Remove stale socket if present
    let _ = std::fs::remove_file(SOCK_PATH);

    // Ensure run/ directory exists
    let sock_dir = PathBuf::from(SOCK_PATH).parent().unwrap().to_path_buf();
    if let Err(e) = tokio::fs::create_dir_all(&sock_dir).await {
        error!("Failed to create socket dir {:?}: {}", sock_dir, e);
        return;
    }

    let listener = match UnixListener::bind(SOCK_PATH) {
        Ok(l) => {
            info!("Unix socket listening at {}", SOCK_PATH);
            l
        }
        Err(e) => {
            error!("Failed to bind Unix socket {}: {}", SOCK_PATH, e);
            return;
        }
    };

    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                let state = Arc::clone(&state);
                let tx = tx.clone();
                let start_time = start_time;
                tokio::spawn(async move {
                    handle_unix_connection(stream, state, tx, start_time).await;
                });
            }
            Err(e) => {
                error!("Unix socket accept error: {}", e);
                tokio::time::sleep(Duration::from_millis(100)).await;
            }
        }
    }
}

async fn handle_unix_connection(
    stream: tokio::net::UnixStream,
    state: SharedState,
    tx: Broadcaster,
    start_time: std::time::Instant,
) {
    let reader = BufReader::new(stream);
    let mut lines = reader.lines();

    // Accumulate a batch of updates then broadcast once
    let mut updated_keys: Vec<(String, String)> = Vec::new();

    while let Ok(Some(line)) = lines.next_line().await {
        let line = line.trim().to_string();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }

        // Parse "key=value" — value may contain '=' so split at first '=' only
        if let Some(eq_pos) = line.find('=') {
            let key = &line[..eq_pos];
            let value = &line[eq_pos + 1..];
            updated_keys.push((key.to_string(), value.to_string()));
        }
    }

    if updated_keys.is_empty() {
        return;
    }

    // Apply all updates to shared state
    {
        let mut s = state.write().await;
        for (k, v) in &updated_keys {
            s.apply_kv(k, v);
        }
        s.daemon_uptime_s = Some(start_time.elapsed().as_secs());
        s.daemon_version = Some(env!("CARGO_PKG_VERSION").to_string());
    }

    // Broadcast full snapshot — simpler than tracking which fields changed
    let snapshot = {
        let s = state.read().await;
        WsMessage::StateSnapshot { data: s.clone() }
    };

    // Ignore send errors — clients may have disconnected
    let _ = tx.send(snapshot);

    info!("State updated ({} fields)", updated_keys.len());
}

// ── WebSocket server ─────────────────────────────────────────────────────────

async fn websocket_server(state: SharedState, tx: Broadcaster) {
    let listener = match TcpListener::bind(WS_ADDR).await {
        Ok(l) => {
            info!("WebSocket server listening on ws://{}", WS_ADDR);
            l
        }
        Err(e) => {
            error!("Failed to bind WebSocket on {}: {}", WS_ADDR, e);
            return;
        }
    };

    loop {
        match listener.accept().await {
            Ok((stream, addr)) => {
                let state = Arc::clone(&state);
                let rx = tx.subscribe();
                tokio::spawn(async move {
                    handle_ws_connection(stream, addr, state, rx).await;
                });
            }
            Err(e) => {
                error!("WebSocket accept error: {}", e);
            }
        }
    }
}

async fn handle_ws_connection(
    stream: tokio::net::TcpStream,
    addr: SocketAddr,
    state: SharedState,
    mut rx: broadcast::Receiver<WsMessage>,
) {
    info!("WebSocket connection from {}", addr);

    let ws_stream = match tokio_tungstenite::accept_async(stream).await {
        Ok(ws) => ws,
        Err(e) => {
            warn!("WebSocket handshake failed from {}: {}", addr, e);
            return;
        }
    };

    let (mut ws_tx, mut ws_rx) = ws_stream.split();

    // Send current state snapshot immediately on connect
    {
        let s = state.read().await;
        let snapshot = WsMessage::StateSnapshot { data: s.clone() };
        if let Ok(json) = serde_json::to_string(&snapshot) {
            let _ = ws_tx.send(Message::Text(json)).await;
        }
    }

    // Spawn task to forward broadcasts to this client
    let send_task = tokio::spawn(async move {
        loop {
            match rx.recv().await {
                Ok(msg) => {
                    match serde_json::to_string(&msg) {
                        Ok(json) => {
                            if ws_tx.send(Message::Text(json)).await.is_err() {
                                break; // client disconnected
                            }
                        }
                        Err(e) => error!("JSON serialization error: {}", e),
                    }
                }
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    warn!("WebSocket client {} lagged {} messages", addr, n);
                }
                Err(broadcast::error::RecvError::Closed) => break,
            }
        }
    });

    // Handle incoming client messages
    while let Some(msg) = ws_rx.next().await {
        match msg {
            Ok(Message::Text(text)) => {
                match serde_json::from_str::<ClientMessage>(&text) {
                    Ok(ClientMessage::Ping) => {
                        // Pong is handled by tungstenite automatically for binary ping frames
                        // but we also handle JSON pings from the JS client
                        let _ = rx; // suppress unused warning
                    }
                    Ok(ClientMessage::Refresh) => {
                        info!("Client {} requested refresh", addr);
                        // Will be handled by next state update from service.sh
                    }
                    Err(_) => {} // ignore unknown messages
                }
            }
            Ok(Message::Close(_)) => break,
            Err(e) => {
                warn!("WebSocket error from {}: {}", addr, e);
                break;
            }
            _ => {}
        }
    }

    send_task.abort();
    info!("WebSocket client {} disconnected", addr);
}

// ── HTTP static file server ──────────────────────────────────────────────────

async fn http_server() {
    let webroot = PathBuf::from(MOD_PATH).join("webroot");

    let listener = match TcpListener::bind(HTTP_ADDR).await {
        Ok(l) => {
            info!("HTTP server listening on http://{}", HTTP_ADDR);
            l
        }
        Err(e) => {
            error!("Failed to bind HTTP on {}: {}", HTTP_ADDR, e);
            return;
        }
    };

    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                let webroot = webroot.clone();
                let io = TokioIo::new(stream);
                tokio::spawn(async move {
                    let service = hyper::service::service_fn(move |req| {
                        serve_file(req, webroot.clone())
                    });
                    if let Err(e) = hyper::server::conn::http1::Builder::new()
                        .serve_connection(io, service)
                        .await
                    {
                        // Connection errors are normal (client closed early)
                        let _ = e;
                    }
                });
            }
            Err(e) => error!("HTTP accept error: {}", e),
        }
    }
}

async fn serve_file(
    req: Request<hyper::body::Incoming>,
    webroot: PathBuf,
) -> Result<Response<Full<Bytes>>, hyper::Error> {
    let path = req.uri().path().trim_start_matches('/');

    // Default to index.html
    let file_path = if path.is_empty() || path == "/" {
        webroot.join("index.html")
    } else {
        // Security: prevent path traversal
        let sanitized = path.replace("..", "").replace('\\', "");
        webroot.join(sanitized)
    };

    match tokio::fs::read(&file_path).await {
        Ok(bytes) => {
            let mime = mime_for_path(&file_path);
            let resp = Response::builder()
                .status(StatusCode::OK)
                .header("Content-Type", mime)
                .header("Cache-Control", "no-cache")
                .header("Access-Control-Allow-Origin", "*")
                .body(Full::new(Bytes::from(bytes)))
                .unwrap();
            Ok(resp)
        }
        Err(_) => {
            let resp = Response::builder()
                .status(StatusCode::NOT_FOUND)
                .body(Full::new(Bytes::from("404 Not Found")))
                .unwrap();
            Ok(resp)
        }
    }
}

fn mime_for_path(path: &PathBuf) -> &'static str {
    match path.extension().and_then(|e| e.to_str()) {
        Some("html") => "text/html; charset=utf-8",
        Some("js")   => "application/javascript",
        Some("css")  => "text/css",
        Some("json") => "application/json",
        Some("png")  => "image/png",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("ico")  => "image/x-icon",
        _            => "application/octet-stream",
    }
}

// ── Watchdog — fallback data.txt reader ─────────────────────────────────────
// If service.sh hasn't been updated to use the socket yet,
// fall back to reading data.txt so the WebUI still works

async fn data_txt_watchdog(state: SharedState, tx: Broadcaster) {
    let data_path = PathBuf::from(MOD_PATH).join("webroot/data.txt");
    let mut last_modified = std::time::SystemTime::UNIX_EPOCH;

    loop {
        tokio::time::sleep(Duration::from_secs(5)).await;

        let meta = match tokio::fs::metadata(&data_path).await {
            Ok(m) => m,
            Err(_) => continue,
        };

        let modified = meta.modified().unwrap_or(std::time::SystemTime::UNIX_EPOCH);
        if modified <= last_modified {
            continue; // no change
        }
        last_modified = modified;

        let content = match tokio::fs::read_to_string(&data_path).await {
            Ok(c) => c,
            Err(_) => continue,
        };

        {
            let mut s = state.write().await;
            for line in content.lines() {
                let line = line.trim();
                if line.is_empty() || line.starts_with('#') {
                    continue;
                }
                if let Some(eq_pos) = line.find('=') {
                    s.apply_kv(&line[..eq_pos], &line[eq_pos + 1..]);
                }
            }
        }

        let snapshot = {
            let s = state.read().await;
            WsMessage::StateSnapshot { data: s.clone() }
        };
        let _ = tx.send(snapshot);
    }
}

// ── Main ─────────────────────────────────────────────────────────────────────

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() {
    // Init logging — on Android this goes to logcat via stderr
    tracing_subscriber::fmt()
        .with_target(false)
        .with_thread_ids(false)
        .with_level(true)
        .init();

    info!(
        "k6a-daemon v{} starting (SD730/sweet2, kernel 4.14 CAF)",
        env!("CARGO_PKG_VERSION")
    );

    let state: SharedState = Arc::new(RwLock::new(DeviceState {
        daemon_version: Some(env!("CARGO_PKG_VERSION").to_string()),
        ..Default::default()
    }));

    let (tx, _) = broadcast::channel::<WsMessage>(BROADCAST_CAP);
    let start_time = std::time::Instant::now();

    // Spawn all services concurrently
    tokio::join!(
        unix_socket_listener(Arc::clone(&state), tx.clone(), start_time),
        websocket_server(Arc::clone(&state), tx.clone()),
        http_server(),
        data_txt_watchdog(Arc::clone(&state), tx.clone()),
    );
}
