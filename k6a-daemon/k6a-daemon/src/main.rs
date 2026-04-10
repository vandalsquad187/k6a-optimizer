/*!
 * k6a-daemon — Real-time WebSocket backend for BadazZ89 k6a Optimizer v5.6
 */

// ── Imports ──────────────────────────────────────────────────────────────────
use futures_util::{SinkExt, StreamExt};
use http_body_util::Full;
use hyper::body::Bytes;
use hyper::{Request, Response, StatusCode};
use hyper_util::rt::TokioIo;
use inotify::{Inotify, WatchMask};
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;
use serde::{Deserialize, Serialize};
use std::fs;
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
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

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct DeviceState {
    pub kernel: Option<String>,
    pub kernel_real: Option<String>,
    pub android: Option<String>,
    pub bat: Option<String>,
    pub uptime: Option<String>,
    pub pid: Option<String>,
    pub ping: Option<String>,
    pub profile: Option<String>,
    pub manual_profile: Option<String>,
    pub ram_used: Option<String>,
    pub ram_total: Option<String>,
    pub cache_kb: Option<String>,
    pub last_clean: Option<String>,
    pub conf_auto: Option<String>,
    pub conf_thermal: Option<String>,
    pub conf_boost: Option<String>,
    pub conf_autocache: Option<String>,
    pub conf_spoof_enable: Option<String>,
    pub conf_spoof_temp: Option<String>,
    pub conf_bypass_thresh: Option<String>,
    pub perapp: Option<String>,
    pub log: Option<String>,
    pub daemon_version: Option<String>,
    pub daemon_uptime_s: Option<u64>,
}

impl DeviceState {
    pub fn apply_kv(&mut self, key: &str, value: &str) {
        let v = Some(value.to_string());
        match key {
            "kernel"             => self.kernel = v,
            "kernel_real"        => self.kernel_real = v,
            "android"            => self.android = v,
            "bat"                => self.bat = v,
            "uptime"             => self.uptime = v,
            "pid"                => self.pid = v,
            "ping"               => self.ping = v,
            "profile"            => self.profile = v,
            "manual_profile"     => self.manual_profile = v,
            "ram_used"           => self.ram_used = v,
            "ram_total"          => self.ram_total = v,
            "cache_kb"           => self.cache_kb = v,
            "last_clean"         => self.last_clean = v,
            "conf_auto"          => self.conf_auto = v,
            "conf_thermal"       => self.conf_thermal = v,
            "conf_boost"         => self.conf_boost = v,
            "conf_autocache"     => self.conf_autocache = v,
            "conf_spoof_enable"  => self.conf_spoof_enable = v,
            "conf_spoof_temp"    => self.conf_spoof_temp = v,
            "conf_bypass_thresh" => self.conf_bypass_thresh = v,
            "perapp"             => self.perapp = v,
            "log"                => self.log = v,
            _ => {}
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum WsMessage {
    StateSnapshot { data: DeviceState },
    FieldUpdate { key: String, value: String },
    Pong,
    Error { message: String },
}

#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum ClientMessage {
    Ping,
    Refresh,
}

type SharedState = Arc<RwLock<DeviceState>>;
type Broadcaster = broadcast::Sender<WsMessage>;

// ── inotify Config-Watcher + SIGHUP ─────────────────────────────────────────

fn read_controller_pid(moddir: &PathBuf) -> Option<i32> {
    let raw = fs::read_to_string(moddir.join("run/controller.pid")).ok()?;
    raw.trim().parse::<i32>().ok()
}

fn signal_controller_reload(moddir: &PathBuf) {
    match read_controller_pid(moddir) {
        Some(pid) => match kill(Pid::from_raw(pid), Signal::SIGHUP) {
            Ok(_)  => eprintln!("[daemon] SIGHUP → controller PID {}", pid),
            Err(e) => eprintln!("[daemon] SIGHUP fehlgeschlagen PID {}: {}", pid, e),
        },
        None => eprintln!("[daemon] controller.pid nicht lesbar — kein SIGHUP"),
    }
}

/// Startet inotify-Watch in eigenem std::thread.
/// Blockierender Watch — unterbricht tokio-Runtime nicht.
fn spawn_config_watcher(moddir: PathBuf) {
    std::thread::spawn(move || {
        let conf_path = moddir.join("config/settings.conf");

        let mut inotify = match Inotify::init() {
            Ok(i)  => i,
            Err(e) => { eprintln!("[daemon] inotify init fehlgeschlagen: {}", e); return; }
        };

        if let Err(e) = inotify.watches().add(
            &conf_path,
            WatchMask::CLOSE_WRITE | WatchMask::MOVED_TO,
        ) {
            eprintln!("[daemon] inotify watch fehlgeschlagen: {}", e);
            return;
        }

        eprintln!("[daemon] Config-Watch aktiv: {:?}", conf_path);
        let mut buffer = [0u8; 1024];

        loop {
            match inotify.read_events_blocking(&mut buffer) {
                Ok(events) => {
                    let count = events.count();
                    if count > 0 {
                        eprintln!("[daemon] settings.conf geändert ({} events) → reload", count);
                        signal_controller_reload(&moddir);
                    }
                }
                Err(e) => {
                    eprintln!("[daemon] inotify read error: {}", e);
                    std::thread::sleep(Duration::from_secs(1));
                }
            }
        }
    });
}

// ── Unix socket listener ─────────────────────────────────────────────────────

async fn unix_socket_listener(
    state: SharedState,
    tx: Broadcaster,
    start_time: std::time::Instant,
) {
    let _ = std::fs::remove_file(SOCK_PATH);
    let sock_dir = PathBuf::from(SOCK_PATH).parent().unwrap().to_path_buf();
    if let Err(e) = tokio::fs::create_dir_all(&sock_dir).await {
        error!("Failed to create socket dir: {}", e);
        return;
    }

    let listener = match UnixListener::bind(SOCK_PATH) {
        Ok(l) => { info!("Unix socket listening at {}", SOCK_PATH); l }
        Err(e) => { error!("Failed to bind Unix socket: {}", e); return; }
    };

    loop {
        match listener.accept().await {
            Ok((stream, _)) => {
                let state = Arc::clone(&state);
                let tx = tx.clone();
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
    let mut updated_keys: Vec<(String, String)> = Vec::new();

    while let Ok(Some(line)) = lines.next_line().await {
        let line = line.trim().to_string();
        if line.is_empty() || line.starts_with('#') { continue; }
        if let Some(eq_pos) = line.find('=') {
            updated_keys.push((line[..eq_pos].to_string(), line[eq_pos + 1..].to_string()));
        }
    }

    if updated_keys.is_empty() { return; }

    {
        let mut s = state.write().await;
        for (k, v) in &updated_keys { s.apply_kv(k, v); }
        s.daemon_uptime_s = Some(start_time.elapsed().as_secs());
        s.daemon_version = Some(env!("CARGO_PKG_VERSION").to_string());
    }

    let snapshot = { let s = state.read().await; WsMessage::StateSnapshot { data: s.clone() } };
    let _ = tx.send(snapshot);
    info!("State updated ({} fields)", updated_keys.len());
}

// ── WebSocket server ─────────────────────────────────────────────────────────

async fn websocket_server(state: SharedState, tx: Broadcaster) {
    let listener = match TcpListener::bind(WS_ADDR).await {
        Ok(l) => { info!("WebSocket listening on ws://{}", WS_ADDR); l }
        Err(e) => { error!("Failed to bind WebSocket: {}", e); return; }
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
            Err(e) => error!("WebSocket accept error: {}", e),
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
        Err(e) => { warn!("WS handshake failed from {}: {}", addr, e); return; }
    };

    let (mut ws_tx, mut ws_rx) = ws_stream.split();

    {
        let s = state.read().await;
        let snapshot = WsMessage::StateSnapshot { data: s.clone() };
        if let Ok(json) = serde_json::to_string(&snapshot) {
            let _ = ws_tx.send(Message::Text(json)).await;
        }
    }

    let send_task = tokio::spawn(async move {
        loop {
            match rx.recv().await {
                Ok(msg) => {
                    if let Ok(json) = serde_json::to_string(&msg) {
                        if ws_tx.send(Message::Text(json)).await.is_err() { break; }
                    }
                }
                Err(broadcast::error::RecvError::Lagged(n)) => warn!("Client {} lagged {} msgs", addr, n),
                Err(broadcast::error::RecvError::Closed) => break,
            }
        }
    });

    while let Some(msg) = ws_rx.next().await {
        match msg {
            Ok(Message::Close(_)) => break,
            Err(e) => { warn!("WS error from {}: {}", addr, e); break; }
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
        Ok(l) => { info!("HTTP listening on http://{}", HTTP_ADDR); l }
        Err(e) => { error!("Failed to bind HTTP: {}", e); return; }
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
                    let _ = hyper::server::conn::http1::Builder::new()
                        .serve_connection(io, service)
                        .await;
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
    let file_path = if path.is_empty() || path == "/" {
        webroot.join("index.html")
    } else {
        webroot.join(path.replace("..", "").replace('\\', ""))
    };

    match tokio::fs::read(&file_path).await {
        Ok(bytes) => Ok(Response::builder()
            .status(StatusCode::OK)
            .header("Content-Type", mime_for_path(&file_path))
            .header("Cache-Control", "no-cache")
            .header("Access-Control-Allow-Origin", "*")
            .body(Full::new(Bytes::from(bytes)))
            .unwrap()),
        Err(_) => Ok(Response::builder()
            .status(StatusCode::NOT_FOUND)
            .body(Full::new(Bytes::from("404 Not Found")))
            .unwrap()),
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

// ── data.txt Fallback-Watchdog ────────────────────────────────────────────────

async fn data_txt_watchdog(state: SharedState, tx: Broadcaster) {
    let data_path = PathBuf::from(MOD_PATH).join("webroot/data.txt");
    let mut last_modified = std::time::SystemTime::UNIX_EPOCH;

    loop {
        tokio::time::sleep(Duration::from_secs(5)).await;
        let meta = match tokio::fs::metadata(&data_path).await { Ok(m) => m, Err(_) => continue };
        let modified = meta.modified().unwrap_or(std::time::SystemTime::UNIX_EPOCH);
        if modified <= last_modified { continue; }
        last_modified = modified;

        let content = match tokio::fs::read_to_string(&data_path).await { Ok(c) => c, Err(_) => continue };
        {
            let mut s = state.write().await;
            for line in content.lines() {
                let line = line.trim();
                if line.is_empty() || line.starts_with('#') { continue; }
                if let Some(eq_pos) = line.find('=') { s.apply_kv(&line[..eq_pos], &line[eq_pos + 1..]); }
            }
        }
        let snapshot = { let s = state.read().await; WsMessage::StateSnapshot { data: s.clone() } };
        let _ = tx.send(snapshot);
    }
}

// ── Main ─────────────────────────────────────────────────────────────────────

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() {
    tracing_subscriber::fmt()
        .with_target(false)
        .with_thread_ids(false)
        .with_level(true)
        .init();

    info!("k6a-daemon v{} starting (SD730/sweet2, kernel 4.14 CAF)", env!("CARGO_PKG_VERSION"));

    // MODDIR: erstes Argument ODER aus Binary-Pfad ableiten
    let moddir: PathBuf = std::env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            std::env::current_exe()
                .unwrap()
                .parent().unwrap()  // bin/
                .parent().unwrap()  // moddir/
                .to_path_buf()
        });

    // inotify Config-Watcher — eigener std::thread, blockiert tokio nicht
    spawn_config_watcher(moddir.clone());

    let state: SharedState = Arc::new(RwLock::new(DeviceState {
        daemon_version: Some(env!("CARGO_PKG_VERSION").to_string()),
        ..Default::default()
    }));

    let (tx, _) = broadcast::channel::<WsMessage>(BROADCAST_CAP);
    let start_time = std::time::Instant::now();

    tokio::join!(
        unix_socket_listener(Arc::clone(&state), tx.clone(), start_time),
        websocket_server(Arc::clone(&state), tx.clone()),
        http_server(),
        data_txt_watchdog(Arc::clone(&state), tx.clone()),
    );
}
