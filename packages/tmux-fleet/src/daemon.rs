use std::collections::{HashMap, HashSet};
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::net::Shutdown;
use std::os::unix::fs::{FileTypeExt, MetadataExt, OpenOptionsExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use nix::fcntl::{Flock, FlockArg};
use nix::unistd::geteuid;
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use signal_hook::consts::signal::{SIGINT, SIGTERM};

use crate::config::{validate_ssh_target, Config};
use crate::protocol::{
    unix_timestamp, DaemonErrorCode, DaemonReply, DaemonRequest, RemoteHost, RemoteState,
    RpcRequest, RpcResponse, SessionInfo, MAX_IPC_REQUEST_BYTES, MAX_IPC_RESPONSE_BYTES,
    PROTOCOL_VERSION,
};
use crate::{runtime, ssh};

const REGISTRY_VERSION: u16 = 1;
const MAX_CONNECTIONS: usize = 64;
const MAX_EXPIRED_CLEANUPS_PER_TICK: usize = 1;
const HOSTS_REPLY_BUDGET: usize = MAX_IPC_RESPONSE_BYTES - MAX_IPC_REQUEST_BYTES;
const CONNECT_RESERVATION_SECONDS: u64 = 10 * 60;
const REFRESH_INTERVAL: Duration = Duration::from_secs(2);
const REGISTRY_MAX_BYTES: u64 = 128 * 1024;
const IPC_TIMEOUT: Duration = Duration::from_secs(4);
const CLIENT_STARTUP_RETRIES: usize = 20;
const CLIENT_STARTUP_DELAY: Duration = Duration::from_millis(50);
static REQUEST_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Debug)]
struct DaemonPaths {
    masters: PathBuf,
    socket: PathBuf,
    lock: PathBuf,
    registry: PathBuf,
}

impl DaemonPaths {
    fn create() -> Result<Self> {
        let root = runtime::runtime_root()?;
        let masters = root.join("masters");
        runtime::ensure_private_dir(&masters)?;
        Ok(Self {
            socket: root.join("daemon.sock"),
            lock: root.join("daemon.lock"),
            registry: root.join("connections.json"),
            masters,
        })
    }

    fn control_path(&self, connection_id: &str) -> Result<PathBuf> {
        validate_connection_id(connection_id)?;
        Ok(self.masters.join(format!("cm-{connection_id}")))
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Phase {
    Connecting,
    Ready,
    Degraded,
    Unsupported,
}

#[derive(Clone, Debug)]
struct Connection {
    target: String,
    connection_id: String,
    control_path: PathBuf,
    epoch: u64,
    started_at: u64,
    phase: Phase,
    hostname: Option<String>,
    server_pid: u64,
    server_started_at: u64,
    sessions: Vec<SessionInfo>,
    message: Option<String>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct PersistedRegistry {
    version: u16,
    next_epoch: u64,
    connections: Vec<PersistedConnection>,
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct PersistedConnection {
    target: String,
    connection_id: String,
    epoch: u64,
}

struct State {
    paths: DaemonPaths,
    known_targets: Vec<String>,
    connections: HashMap<String, Connection>,
    last_errors: HashMap<String, String>,
    next_epoch: u64,
    refresh_tx: Sender<RefreshResult>,
    refresh_rx: Receiver<RefreshResult>,
    refresh_in_flight: HashSet<String>,
    last_refresh_started: Instant,
}

impl State {
    fn load(config: &Config, paths: DaemonPaths) -> Result<Self> {
        let mut known_targets = config.ssh_targets.clone();
        for target in runtime::recent_ssh_targets() {
            push_unique(&mut known_targets, target);
        }
        let registry = load_registry(&paths)?;
        let (refresh_tx, refresh_rx) = mpsc::channel();
        let mut state = Self {
            paths,
            known_targets,
            connections: HashMap::new(),
            last_errors: HashMap::new(),
            next_epoch: registry.as_ref().map_or(0, |value| value.next_epoch),
            refresh_tx,
            refresh_rx,
            refresh_in_flight: HashSet::new(),
            last_refresh_started: Instant::now() - REFRESH_INTERVAL,
        };
        if let Some(registry) = registry {
            if registry.connections.len() > MAX_CONNECTIONS {
                bail!("tmux-fleet connection registry exceeds {MAX_CONNECTIONS} entries");
            }
            for persisted in registry.connections {
                validate_ssh_target(&persisted.target)?;
                if persisted.epoch == 0 {
                    bail!("tmux-fleet connection registry contains a zero epoch");
                }
                let control_path = state.paths.control_path(&persisted.connection_id)?;
                push_unique(&mut state.known_targets, persisted.target.clone());
                state.next_epoch = state.next_epoch.max(persisted.epoch);
                state.connections.insert(
                    persisted.target.clone(),
                    Connection {
                        target: persisted.target,
                        connection_id: persisted.connection_id,
                        control_path,
                        epoch: persisted.epoch,
                        started_at: unix_timestamp(),
                        phase: Phase::Degraded,
                        hostname: None,
                        server_pid: 0,
                        server_started_at: 0,
                        sessions: Vec::new(),
                        message: Some("Refreshing remote sessions…".into()),
                    },
                );
            }
            state.persist()?;
        }
        Ok(state)
    }

    fn begin_connect(&mut self, config: &Config, target: String) -> DaemonReply {
        if let Err(error) = validate_ssh_target(&target) {
            return daemon_error(DaemonErrorCode::InvalidRequest, false, format!("{error:#}"));
        }
        self.expire_connecting(config);
        if self.connections.contains_key(&target) {
            return daemon_error(
                DaemonErrorCode::Busy,
                true,
                format!("{target} is already connected or being authenticated"),
            );
        }
        if self.connections.len() >= MAX_CONNECTIONS {
            return daemon_error(
                DaemonErrorCode::Busy,
                false,
                format!("tmux-fleet supports at most {MAX_CONNECTIONS} simultaneous hosts"),
            );
        }
        let connection_id = match random_connection_id() {
            Ok(value) => value,
            Err(error) => {
                return daemon_error(DaemonErrorCode::Internal, true, format!("{error:#}"))
            }
        };
        let control_path = match self.paths.control_path(&connection_id) {
            Ok(value) => value,
            Err(error) => {
                return daemon_error(DaemonErrorCode::Internal, false, format!("{error:#}"))
            }
        };
        if control_path.exists() {
            return daemon_error(
                DaemonErrorCode::Internal,
                true,
                "generated SSH control path already exists".into(),
            );
        }

        self.next_epoch = self.next_epoch.saturating_add(1).max(1);
        let epoch = self.next_epoch;
        push_unique(&mut self.known_targets, target.clone());
        self.last_errors.remove(&target);
        self.connections.insert(
            target.clone(),
            Connection {
                target: target.clone(),
                connection_id: connection_id.clone(),
                control_path: control_path.clone(),
                epoch,
                started_at: unix_timestamp(),
                phase: Phase::Connecting,
                hostname: None,
                server_pid: 0,
                server_started_at: 0,
                sessions: Vec::new(),
                message: Some("Waiting for SSH authentication…".into()),
            },
        );
        if let Err(error) = self.persist() {
            self.connections.remove(&target);
            return daemon_error(
                DaemonErrorCode::Internal,
                true,
                format!("could not persist SSH reservation: {error:#}"),
            );
        }
        DaemonReply::ConnectPlan {
            target,
            connection_id,
            control_path: control_path.to_string_lossy().into_owned(),
        }
    }

    fn commit_connect(
        &mut self,
        config: &Config,
        target: &str,
        connection_id: &str,
    ) -> DaemonReply {
        let Some(connection) = self.connections.get(target).cloned() else {
            return daemon_error(
                DaemonErrorCode::NotConnected,
                true,
                "SSH connection reservation no longer exists".into(),
            );
        };
        if connection.phase != Phase::Connecting || connection.connection_id != connection_id {
            return daemon_error(
                DaemonErrorCode::StaleConnection,
                true,
                "SSH connection reservation was replaced".into(),
            );
        }
        match ssh::master_health(config, target, &connection.control_path) {
            Ok(ssh::MasterHealth::Alive) => {}
            Ok(ssh::MasterHealth::Missing) => {
                self.connections.remove(target);
                let _ = remove_stale_control_socket(&connection.control_path);
                if let Err(error) = self.persist() {
                    eprintln!("tmux-fleet daemon could not update its registry: {error:#}");
                }
                return daemon_error(
                    DaemonErrorCode::MasterFailed,
                    true,
                    "OpenSSH did not leave a usable control master".into(),
                );
            }
            Ok(ssh::MasterHealth::TimedOut) => {
                return daemon_error(
                    DaemonErrorCode::MasterFailed,
                    true,
                    "timed out while verifying the new OpenSSH control master".into(),
                )
            }
            Err(error) => {
                return daemon_error(
                    DaemonErrorCode::MasterFailed,
                    true,
                    format!("failed to verify OpenSSH control master: {error:#}"),
                )
            }
        }
        if let Some(connection) = self.connections.get_mut(target) {
            connection.phase = Phase::Degraded;
            connection.message = Some("Refreshing remote sessions…".into());
        }
        self.refresh_targets(config, &[target.to_owned()]);
        DaemonReply::Ack
    }

    fn abort_connect(&mut self, config: &Config, target: &str, connection_id: &str) -> DaemonReply {
        let Some(connection) = self.connections.get(target).cloned() else {
            return DaemonReply::Ack;
        };
        if connection.phase != Phase::Connecting || connection.connection_id != connection_id {
            return DaemonReply::Ack;
        }
        if let Err(error) = close_master_or_confirm_missing(config, &connection) {
            if let Some(connection) = self.connections.get_mut(target) {
                connection.phase = Phase::Degraded;
                connection.message = Some(
                    "Could not close the SSH control master; checking whether it is usable…".into(),
                );
            }
            self.refresh_targets(config, &[target.to_owned()]);
            return daemon_error(
                DaemonErrorCode::MasterFailed,
                true,
                format!("could not close SSH master; connection retained for recovery: {error:#}"),
            );
        }
        self.connections.remove(target);
        let _ = remove_stale_control_socket(&connection.control_path);
        if let Err(error) = self.persist() {
            eprintln!("tmux-fleet daemon could not update its registry: {error:#}");
        }
        DaemonReply::Ack
    }

    fn prepare_attach(
        &mut self,
        config: &Config,
        target: &str,
        connection_id: &str,
        epoch: u64,
    ) -> DaemonReply {
        let Some(connection) = self.connections.get(target).cloned() else {
            return daemon_error(
                DaemonErrorCode::NotConnected,
                true,
                format!("{target} is no longer connected"),
            );
        };
        if connection.phase == Phase::Connecting
            || connection.connection_id != connection_id
            || connection.epoch != epoch
        {
            return daemon_error(
                DaemonErrorCode::StaleConnection,
                true,
                format!("the connection to {target} changed; refresh the picker"),
            );
        }
        match ssh::master_health(config, target, &connection.control_path) {
            Ok(ssh::MasterHealth::Alive) => DaemonReply::AttachPlan {
                target: target.to_owned(),
                connection_id: connection_id.to_owned(),
                epoch,
                control_path: connection.control_path.to_string_lossy().into_owned(),
            },
            Ok(ssh::MasterHealth::Missing) => {
                self.disconnect_dead(target, &connection, "SSH control master disconnected");
                daemon_error(
                    DaemonErrorCode::NotConnected,
                    true,
                    format!("SSH connection to {target} was lost"),
                )
            }
            Ok(ssh::MasterHealth::TimedOut) => daemon_error(
                DaemonErrorCode::MasterFailed,
                true,
                format!("timed out while checking SSH connection to {target}"),
            ),
            Err(error) => daemon_error(
                DaemonErrorCode::MasterFailed,
                true,
                format!("failed to check SSH connection to {target}: {error:#}"),
            ),
        }
    }

    fn disconnect(&mut self, config: &Config, target: &str, connection_id: &str) -> DaemonReply {
        let Some(connection) = self.connections.get(target).cloned() else {
            return DaemonReply::Ack;
        };
        if connection.connection_id != connection_id {
            return daemon_error(
                DaemonErrorCode::StaleConnection,
                true,
                "the SSH connection was already replaced".into(),
            );
        }
        if let Err(error) = close_master_or_confirm_missing(config, &connection) {
            if let Some(connection) = self.connections.get_mut(target) {
                connection.phase = Phase::Degraded;
                connection.message =
                    Some("Could not close the SSH control master; retry disconnect later".into());
            }
            return daemon_error(
                DaemonErrorCode::MasterFailed,
                true,
                format!("could not close SSH master; connection retained for recovery: {error:#}"),
            );
        }
        self.connections.remove(target);
        let _ = remove_stale_control_socket(&connection.control_path);
        self.last_errors
            .insert(target.to_owned(), "Disconnected".into());
        match self.persist() {
            Ok(()) => DaemonReply::Ack,
            Err(error) => daemon_error(DaemonErrorCode::Internal, true, format!("{error:#}")),
        }
    }

    fn list(&mut self, config: &Config) -> DaemonReply {
        self.maintain(config);
        DaemonReply::Hosts {
            hosts: self.hosts_for_reply(),
        }
    }

    fn refresh_targets(&mut self, config: &Config, targets: &[String]) {
        let jobs = targets
            .iter()
            .filter_map(|target| self.connections.get(target))
            .filter(|connection| connection.phase != Phase::Connecting)
            .cloned()
            .collect::<Vec<_>>();
        let results = thread::scope(|scope| {
            jobs.into_iter()
                .map(|connection| {
                    let config = config.clone();
                    scope.spawn(move || refresh_one(&config, connection))
                })
                .collect::<Vec<_>>()
                .into_iter()
                .map(|handle| {
                    handle.join().unwrap_or_else(|_| RefreshResult {
                        target: String::new(),
                        connection_id: String::new(),
                        epoch: 0,
                        outcome: RefreshOutcome::Degraded("remote refresh worker panicked".into()),
                    })
                })
                .collect::<Vec<_>>()
        });
        self.apply_refresh_results(results);
    }

    fn maintain(&mut self, config: &Config) {
        self.expire_connecting(config);
        self.poll_refresh_results();
        if self.last_refresh_started.elapsed() < REFRESH_INTERVAL {
            return;
        }
        self.last_refresh_started = Instant::now();

        let jobs = self
            .connections
            .values()
            .filter(|connection| {
                connection.phase != Phase::Connecting
                    && !self.refresh_in_flight.contains(&connection.target)
            })
            .cloned()
            .collect::<Vec<_>>();
        for connection in jobs {
            self.refresh_in_flight.insert(connection.target.clone());
            let sender = self.refresh_tx.clone();
            let config = config.clone();
            thread::spawn(move || {
                let target = connection.target.clone();
                let connection_id = connection.connection_id.clone();
                let epoch = connection.epoch;
                let result = catch_unwind(AssertUnwindSafe(|| refresh_one(&config, connection)))
                    .unwrap_or_else(|_| RefreshResult {
                        target,
                        connection_id,
                        epoch,
                        outcome: RefreshOutcome::Degraded("remote refresh worker panicked".into()),
                    });
                let _ = sender.send(result);
            });
        }
    }

    fn poll_refresh_results(&mut self) {
        let mut results = Vec::new();
        while let Ok(result) = self.refresh_rx.try_recv() {
            self.refresh_in_flight.remove(&result.target);
            results.push(result);
        }
        self.apply_refresh_results(results);
    }

    fn apply_refresh_results(&mut self, results: Vec<RefreshResult>) {
        let mut registry_changed = false;
        for result in results {
            let Some(current) = self.connections.get(&result.target) else {
                continue;
            };
            if current.connection_id != result.connection_id || current.epoch != result.epoch {
                continue;
            }
            match result.outcome {
                RefreshOutcome::Ready(snapshot) => {
                    if let Some(connection) = self.connections.get_mut(&result.target) {
                        connection.phase = Phase::Ready;
                        connection.hostname = Some(snapshot.hostname);
                        connection.server_pid = snapshot.server_pid;
                        connection.server_started_at = snapshot.server_started_at;
                        connection.sessions = snapshot.sessions;
                        connection.message = None;
                    }
                    self.last_errors.remove(&result.target);
                }
                RefreshOutcome::Unsupported(message) => {
                    if let Some(connection) = self.connections.get_mut(&result.target) {
                        connection.phase = Phase::Unsupported;
                        connection.hostname = None;
                        connection.server_pid = 0;
                        connection.server_started_at = 0;
                        connection.sessions.clear();
                        connection.message = Some(bounded_message(message));
                    }
                }
                RefreshOutcome::Degraded(message) => {
                    if let Some(connection) = self.connections.get_mut(&result.target) {
                        connection.phase = Phase::Degraded;
                        connection.hostname = None;
                        connection.server_pid = 0;
                        connection.server_started_at = 0;
                        connection.sessions.clear();
                        connection.message = Some(bounded_message(message));
                    }
                }
                RefreshOutcome::Disconnected(message) => {
                    if let Some(connection) = self.connections.remove(&result.target) {
                        let _ = remove_stale_control_socket(&connection.control_path);
                    }
                    self.last_errors
                        .insert(result.target, bounded_message(message));
                    registry_changed = true;
                }
            }
        }
        if registry_changed {
            if let Err(error) = self.persist() {
                eprintln!("tmux-fleet daemon could not update its registry: {error:#}");
            }
        }
    }

    fn disconnect_dead(&mut self, target: &str, connection: &Connection, message: &str) {
        self.connections.remove(target);
        let _ = remove_stale_control_socket(&connection.control_path);
        self.last_errors
            .insert(target.to_owned(), bounded_message(message.to_owned()));
        if let Err(error) = self.persist() {
            eprintln!("tmux-fleet daemon could not update its registry: {error:#}");
        }
    }

    fn expire_connecting(&mut self, config: &Config) {
        let now = unix_timestamp();
        let expired = self
            .connections
            .values()
            .filter(|connection| {
                connection.phase == Phase::Connecting
                    && now.saturating_sub(connection.started_at) > CONNECT_RESERVATION_SECONDS
            })
            .take(MAX_EXPIRED_CLEANUPS_PER_TICK)
            .cloned()
            .collect::<Vec<_>>();
        let mut registry_changed = false;
        let mut refresh = Vec::new();
        for connection in expired {
            let target = connection.target.clone();
            match close_master_or_confirm_missing(config, &connection) {
                Ok(()) => {
                    self.connections.remove(&target);
                    let _ = remove_stale_control_socket(&connection.control_path);
                    self.last_errors
                        .insert(target, "SSH authentication reservation expired".into());
                    registry_changed = true;
                }
                Err(error) => {
                    if let Some(current) = self.connections.get_mut(&target) {
                        current.phase = Phase::Degraded;
                        current.message = Some(bounded_message(format!(
                            "SSH authentication expired, but its control master could not be closed: {error:#}"
                        )));
                    }
                    refresh.push(target);
                }
            }
        }
        if registry_changed {
            if let Err(error) = self.persist() {
                eprintln!("tmux-fleet daemon could not update its registry: {error:#}");
            }
        }
        if !refresh.is_empty() {
            self.refresh_targets(config, &refresh);
        }
    }

    fn hosts(&self) -> Vec<RemoteHost> {
        let mut targets = self.known_targets.clone();
        for target in self.connections.keys() {
            push_unique(&mut targets, target.clone());
        }
        targets
            .into_iter()
            .map(|target| {
                if let Some(connection) = self.connections.get(&target) {
                    RemoteHost {
                        target,
                        state: match connection.phase {
                            Phase::Connecting => RemoteState::Connecting,
                            Phase::Ready => RemoteState::Ready,
                            Phase::Degraded => RemoteState::Degraded,
                            Phase::Unsupported => RemoteState::Unsupported,
                        },
                        connection_id: Some(connection.connection_id.clone()),
                        epoch: connection.epoch,
                        hostname: connection.hostname.clone(),
                        server_pid: connection.server_pid,
                        server_started_at: connection.server_started_at,
                        sessions: connection.sessions.clone(),
                        message: connection.message.clone(),
                    }
                } else {
                    RemoteHost {
                        message: self.last_errors.get(&target).cloned(),
                        target,
                        state: RemoteState::Disconnected,
                        connection_id: None,
                        epoch: 0,
                        hostname: None,
                        server_pid: 0,
                        server_started_at: 0,
                        sessions: Vec::new(),
                    }
                }
            })
            .collect()
    }

    fn hosts_for_reply(&self) -> Vec<RemoteHost> {
        let mut hosts = self.hosts();
        let serialized_len = |host: &RemoteHost| {
            serde_json::to_vec(host)
                .map(|bytes| bytes.len())
                .unwrap_or(HOSTS_REPLY_BUDGET.saturating_add(1))
        };
        let sizes = hosts.iter().map(serialized_len).collect::<Vec<_>>();
        let mut total_size = sizes
            .iter()
            .fold(2_u128, |total, size| total + *size as u128)
            + hosts.len().saturating_sub(1) as u128;
        if total_size <= HOSTS_REPLY_BUDGET as u128 {
            return hosts;
        }

        let mut candidates = hosts
            .iter()
            .enumerate()
            .filter(|(_, host)| !host.sessions.is_empty())
            .map(|(index, _)| (index, sizes[index]))
            .collect::<Vec<_>>();
        candidates.sort_unstable_by_key(|candidate| std::cmp::Reverse(candidate.1));

        for (index, previous_size) in candidates {
            let session_count = hosts[index].sessions.len();
            hosts[index].state = RemoteState::Degraded;
            hosts[index].server_pid = 0;
            hosts[index].server_started_at = 0;
            hosts[index].sessions.clear();
            hosts[index].message = Some(format!(
                "Remote inventory with {session_count} sessions was omitted because the combined picker response exceeded its safety limit"
            ));
            let replacement_size = serialized_len(&hosts[index]);
            total_size = total_size
                .saturating_sub(previous_size as u128)
                .saturating_add(replacement_size as u128);
            if total_size <= HOSTS_REPLY_BUDGET as u128 {
                break;
            }
        }
        hosts
    }

    fn persist(&self) -> Result<()> {
        let registry = PersistedRegistry {
            version: REGISTRY_VERSION,
            next_epoch: self.next_epoch,
            connections: self
                .connections
                .values()
                .map(|connection| PersistedConnection {
                    target: connection.target.clone(),
                    connection_id: connection.connection_id.clone(),
                    epoch: connection.epoch,
                })
                .collect(),
        };
        runtime::atomic_write(&self.paths.registry, &serde_json::to_vec(&registry)?)
    }

    fn shutdown(&mut self, config: &Config) {
        let connections = self.connections.values().cloned().collect::<Vec<_>>();
        let closed = thread::scope(|scope| {
            connections
                .into_iter()
                .map(|connection| {
                    let config = config.clone();
                    scope.spawn(move || {
                        let result = close_master_or_confirm_missing(&config, &connection);
                        (connection, result)
                    })
                })
                .collect::<Vec<_>>()
                .into_iter()
                .filter_map(|handle| handle.join().ok())
                .collect::<Vec<_>>()
        });
        for (connection, result) in closed {
            match result {
                Ok(()) => {
                    self.connections.remove(&connection.target);
                    let _ = remove_stale_control_socket(&connection.control_path);
                }
                Err(error) => eprintln!(
                    "tmux-fleet daemon retained the SSH master for {} after cleanup failed: {error:#}",
                    connection.target
                ),
            }
        }
        if let Err(error) = self.persist() {
            eprintln!("tmux-fleet daemon could not persist shutdown state: {error:#}");
        }
    }
}

fn close_master_or_confirm_missing(config: &Config, connection: &Connection) -> Result<()> {
    if !owned_control_socket_exists(&connection.control_path)? {
        return Ok(());
    }
    match ssh::close_master(config, &connection.target, &connection.control_path) {
        Ok(()) => Ok(()),
        Err(close_error) => {
            match ssh::master_health(config, &connection.target, &connection.control_path) {
                Ok(ssh::MasterHealth::Missing) => Ok(()),
                Ok(ssh::MasterHealth::Alive) => {
                    bail!("{close_error:#}; health check confirms the SSH master is still alive")
                }
                Ok(ssh::MasterHealth::TimedOut) => {
                    bail!("{close_error:#}; SSH master health check also timed out")
                }
                Err(health_error) => bail!(
                    "{close_error:#}; could not confirm that the SSH master exited: {health_error:#}"
                ),
            }
        }
    }
}

#[derive(Debug)]
struct RefreshResult {
    target: String,
    connection_id: String,
    epoch: u64,
    outcome: RefreshOutcome,
}

#[derive(Debug)]
enum RefreshOutcome {
    Ready(crate::protocol::Snapshot),
    Unsupported(String),
    Degraded(String),
    Disconnected(String),
}

fn refresh_one(config: &Config, connection: Connection) -> RefreshResult {
    let outcome = match ssh::master_health(config, &connection.target, &connection.control_path) {
        Ok(ssh::MasterHealth::Alive) => {
            match ssh::inventory(config, &connection.target, &connection.control_path) {
                ssh::InventoryOutcome::Ready(snapshot) => RefreshOutcome::Ready(snapshot),
                ssh::InventoryOutcome::Unsupported(message) => RefreshOutcome::Unsupported(message),
                ssh::InventoryOutcome::Failed(message) => {
                    match ssh::master_health(config, &connection.target, &connection.control_path) {
                        Ok(ssh::MasterHealth::Missing) => {
                            RefreshOutcome::Disconnected("SSH control master disconnected".into())
                        }
                        _ => RefreshOutcome::Degraded(message),
                    }
                }
            }
        }
        Ok(ssh::MasterHealth::Missing) => {
            RefreshOutcome::Disconnected("SSH control master disconnected".into())
        }
        Ok(ssh::MasterHealth::TimedOut) => {
            RefreshOutcome::Degraded("SSH control master health check timed out".into())
        }
        Err(error) => RefreshOutcome::Degraded(format!("SSH health check failed: {error:#}")),
    };
    RefreshResult {
        target: connection.target,
        connection_id: connection.connection_id,
        epoch: connection.epoch,
        outcome,
    }
}

pub fn serve(config: Config) -> Result<()> {
    let paths = DaemonPaths::create()?;
    let _lock = daemon_lock(&paths.lock)?;
    let listener = bind_listener(&paths)?;
    let mut state = State::load(&config, paths.clone())?;
    let stopping = Arc::new(AtomicBool::new(false));
    signal_hook::flag::register(SIGTERM, Arc::clone(&stopping))?;
    signal_hook::flag::register(SIGINT, Arc::clone(&stopping))?;
    listener.set_nonblocking(true)?;
    while !stopping.load(Ordering::Relaxed) {
        state.maintain(&config);
        match listener.accept() {
            Ok((stream, _)) => {
                if let Err(error) = handle_stream(stream, &config, &mut state) {
                    eprintln!("tmux-fleet daemon rejected a request: {error:#}");
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                thread::sleep(Duration::from_millis(50));
            }
            Err(error) => return Err(error).context("failed to accept tmux-fleet client"),
        }
    }
    state.shutdown(&config);
    drop(listener);
    remove_daemon_socket(&paths.socket)?;
    Ok(())
}

pub fn request(request: DaemonRequest) -> Result<DaemonReply> {
    let paths = DaemonPaths::create()?;
    verify_daemon_socket(&paths.socket)?;
    let mut stream = connect_with_retry(&paths.socket)?;
    stream.set_read_timeout(Some(IPC_TIMEOUT))?;
    stream.set_write_timeout(Some(IPC_TIMEOUT))?;
    let request_id = format!(
        "{}-{}",
        std::process::id(),
        REQUEST_SEQUENCE.fetch_add(1, Ordering::Relaxed)
    );
    let envelope = RpcRequest {
        version: PROTOCOL_VERSION,
        request_id: request_id.clone(),
        request,
    };
    write_json_frame(&mut stream, &envelope, MAX_IPC_REQUEST_BYTES)?;
    stream.shutdown(Shutdown::Write)?;
    let response: RpcResponse = read_json_frame(&mut stream, MAX_IPC_RESPONSE_BYTES)?;
    if response.version != PROTOCOL_VERSION {
        bail!(
            "tmux-fleet daemon protocol {} is unsupported; expected {}",
            response.version,
            PROTOCOL_VERSION
        );
    }
    if response.request_id != request_id {
        bail!("tmux-fleet daemon returned a mismatched request ID");
    }
    Ok(response.reply)
}

fn handle_stream(mut stream: UnixStream, config: &Config, state: &mut State) -> Result<()> {
    verify_peer(&stream)?;
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    stream.set_write_timeout(Some(IPC_TIMEOUT))?;
    let request: RpcRequest = read_json_frame(&mut stream, MAX_IPC_REQUEST_BYTES)?;
    if request.request_id.is_empty()
        || request.request_id.len() > 128
        || request.request_id.chars().any(char::is_control)
    {
        bail!("invalid tmux-fleet request ID");
    }
    let reply = if request.version != PROTOCOL_VERSION {
        daemon_error(
            DaemonErrorCode::UnsupportedVersion,
            false,
            format!(
                "client protocol {} is unsupported; expected {}",
                request.version, PROTOCOL_VERSION
            ),
        )
    } else {
        dispatch(config, state, request.request)
    };
    let response = RpcResponse {
        version: PROTOCOL_VERSION,
        request_id: request.request_id,
        reply,
    };
    write_json_frame(&mut stream, &response, MAX_IPC_RESPONSE_BYTES)?;
    stream.shutdown(Shutdown::Write)?;
    Ok(())
}

fn dispatch(config: &Config, state: &mut State, request: DaemonRequest) -> DaemonReply {
    match request {
        DaemonRequest::List => state.list(config),
        DaemonRequest::BeginConnect { target } => {
            if let Err(error) = runtime::remember_ssh_target(&target) {
                return daemon_error(
                    DaemonErrorCode::Internal,
                    true,
                    format!("could not remember SSH target: {error:#}"),
                );
            }
            state.begin_connect(config, target)
        }
        DaemonRequest::CommitConnect {
            target,
            connection_id,
        } => state.commit_connect(config, &target, &connection_id),
        DaemonRequest::AbortConnect {
            target,
            connection_id,
        } => state.abort_connect(config, &target, &connection_id),
        DaemonRequest::PrepareAttach {
            target,
            connection_id,
            epoch,
        } => state.prepare_attach(config, &target, &connection_id, epoch),
        DaemonRequest::Disconnect {
            target,
            connection_id,
        } => state.disconnect(config, &target, &connection_id),
    }
}

fn load_registry(paths: &DaemonPaths) -> Result<Option<PersistedRegistry>> {
    let metadata = match fs::symlink_metadata(&paths.registry) {
        Ok(value) => value,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(error)
                .with_context(|| format!("failed to inspect {}", paths.registry.display()))
        }
    };
    if !metadata.file_type().is_file()
        || metadata.uid() != geteuid().as_raw()
        || metadata.permissions().mode() & 0o077 != 0
    {
        bail!("{} is not a private regular file", paths.registry.display());
    }
    if metadata.len() > REGISTRY_MAX_BYTES {
        bail!(
            "{} exceeds the registry size limit",
            paths.registry.display()
        );
    }
    let bytes = fs::read(&paths.registry)
        .with_context(|| format!("failed to read {}", paths.registry.display()))?;
    let registry: PersistedRegistry = serde_json::from_slice(&bytes)
        .with_context(|| format!("failed to parse {}", paths.registry.display()))?;
    if registry.version != REGISTRY_VERSION {
        bail!(
            "connection registry version {} is unsupported",
            registry.version
        );
    }
    let mut targets = HashSet::new();
    let mut identifiers = HashSet::new();
    for connection in &registry.connections {
        if !targets.insert(connection.target.clone())
            || !identifiers.insert(connection.connection_id.clone())
        {
            bail!("connection registry contains duplicate entries");
        }
    }
    Ok(Some(registry))
}

fn daemon_lock(path: &Path) -> Result<Flock<File>> {
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .mode(0o600)
        .custom_flags(nix::libc::O_NOFOLLOW)
        .open(path)
        .with_context(|| format!("failed to open {}", path.display()))?;
    let metadata = file
        .metadata()
        .with_context(|| format!("failed to inspect {}", path.display()))?;
    if !metadata.file_type().is_file()
        || metadata.uid() != geteuid().as_raw()
        || metadata.permissions().mode() & 0o077 != 0
    {
        bail!("{} is not a private regular lock file", path.display());
    }
    Flock::lock(file, FlockArg::LockExclusiveNonblock).map_err(|(_, error)| {
        anyhow::anyhow!("another tmux-fleet daemon is already running: {error}")
    })
}

fn bind_listener(paths: &DaemonPaths) -> Result<UnixListener> {
    match fs::symlink_metadata(&paths.socket) {
        Ok(metadata) => {
            if !metadata.file_type().is_socket() || metadata.uid() != geteuid().as_raw() {
                bail!("{} is not an owned Unix socket", paths.socket.display());
            }
            fs::remove_file(&paths.socket)
                .with_context(|| format!("failed to remove stale {}", paths.socket.display()))?;
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => {
            return Err(error)
                .with_context(|| format!("failed to inspect {}", paths.socket.display()))
        }
    }
    let listener = UnixListener::bind(&paths.socket)
        .with_context(|| format!("failed to bind {}", paths.socket.display()))?;
    fs::set_permissions(&paths.socket, fs::Permissions::from_mode(0o600))?;
    Ok(listener)
}

fn verify_daemon_socket(path: &Path) -> Result<()> {
    let metadata = fs::symlink_metadata(path)
        .with_context(|| format!("tmux-fleet daemon is unavailable at {}", path.display()))?;
    if !metadata.file_type().is_socket()
        || metadata.uid() != geteuid().as_raw()
        || metadata.permissions().mode() & 0o077 != 0
    {
        bail!("{} is not a private owned Unix socket", path.display());
    }
    Ok(())
}

fn connect_with_retry(path: &Path) -> Result<UnixStream> {
    let mut last_error = None;
    for attempt in 0..CLIENT_STARTUP_RETRIES {
        match UnixStream::connect(path) {
            Ok(stream) => return Ok(stream),
            Err(error)
                if matches!(
                    error.kind(),
                    std::io::ErrorKind::NotFound | std::io::ErrorKind::ConnectionRefused
                ) =>
            {
                last_error = Some(error);
                if attempt + 1 < CLIENT_STARTUP_RETRIES {
                    thread::sleep(CLIENT_STARTUP_DELAY);
                }
            }
            Err(error) => {
                return Err(error)
                    .with_context(|| format!("failed to connect to {}", path.display()))
            }
        }
    }
    Err(last_error.unwrap_or_else(|| std::io::Error::from(std::io::ErrorKind::ConnectionRefused)))
        .with_context(|| format!("tmux-fleet daemon is unavailable at {}", path.display()))
}

#[cfg(target_os = "linux")]
fn verify_peer(stream: &UnixStream) -> Result<()> {
    use nix::sys::socket::{getsockopt, sockopt::PeerCredentials};

    let credentials = getsockopt(stream, PeerCredentials)?;
    if credentials.uid() != geteuid().as_raw() {
        bail!("tmux-fleet client belongs to a different user");
    }
    Ok(())
}

#[cfg(target_os = "macos")]
fn verify_peer(stream: &UnixStream) -> Result<()> {
    let (uid, _) = nix::unistd::getpeereid(stream)?;
    if uid != geteuid() {
        bail!("tmux-fleet client belongs to a different user");
    }
    Ok(())
}

fn write_json_frame<T: Serialize>(writer: &mut impl Write, value: &T, limit: usize) -> Result<()> {
    let bytes = serde_json::to_vec(value)?;
    if bytes.len().saturating_add(1) > limit {
        bail!("tmux-fleet IPC frame exceeds {limit} bytes");
    }
    writer.write_all(&bytes)?;
    writer.write_all(b"\n")?;
    writer.flush()?;
    Ok(())
}

fn read_json_frame<T: DeserializeOwned>(reader: &mut impl Read, limit: usize) -> Result<T> {
    let mut bytes = Vec::new();
    reader
        .take((limit + 1) as u64)
        .read_to_end(&mut bytes)
        .context("failed to read tmux-fleet IPC frame")?;
    if bytes.len() > limit {
        bail!("tmux-fleet IPC frame exceeds {limit} bytes");
    }
    if bytes.last() != Some(&b'\n') || bytes[..bytes.len().saturating_sub(1)].contains(&b'\n') {
        bail!("tmux-fleet IPC requires exactly one newline-terminated JSON value");
    }
    serde_json::from_slice(&bytes[..bytes.len() - 1]).context("invalid tmux-fleet IPC JSON")
}

fn random_connection_id() -> Result<String> {
    let mut random = [0_u8; 16];
    File::open("/dev/urandom")
        .context("failed to open /dev/urandom")?
        .read_exact(&mut random)
        .context("failed to read /dev/urandom")?;
    let mut encoded = String::with_capacity(32);
    for byte in random {
        use std::fmt::Write as _;
        write!(&mut encoded, "{byte:02x}").expect("writing to a String cannot fail");
    }
    Ok(encoded)
}

fn validate_connection_id(value: &str) -> Result<()> {
    if value.len() != 32 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("invalid tmux-fleet connection ID");
    }
    Ok(())
}

fn owned_control_socket_exists(path: &Path) -> Result<bool> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => {
            if !metadata.file_type().is_socket() || metadata.uid() != geteuid().as_raw() {
                bail!("{} is not an owned SSH control socket", path.display());
            }
            Ok(true)
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error).with_context(|| format!("failed to inspect {}", path.display())),
    }
}

fn remove_stale_control_socket(path: &Path) -> Result<()> {
    if owned_control_socket_exists(path)? {
        fs::remove_file(path)
            .with_context(|| format!("failed to remove stale {}", path.display()))?;
    }
    Ok(())
}

fn remove_daemon_socket(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata)
            if metadata.file_type().is_socket() && metadata.uid() == geteuid().as_raw() =>
        {
            fs::remove_file(path)
                .with_context(|| format!("failed to remove {}", path.display()))?;
        }
        Ok(_) => bail!("refusing to remove non-socket path {}", path.display()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
    Ok(())
}

fn daemon_error(code: DaemonErrorCode, retryable: bool, message: String) -> DaemonReply {
    DaemonReply::Error {
        code,
        retryable,
        message: bounded_message(message),
    }
}

fn bounded_message(message: String) -> String {
    message.chars().take(512).collect()
}

fn push_unique(values: &mut Vec<String>, value: String) {
    if !values.contains(&value) {
        values.push(value);
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::io::Cursor;
    use std::os::unix::fs::PermissionsExt;
    use std::os::unix::net::UnixListener;

    use crate::config::Config;
    use crate::protocol::{
        DaemonErrorCode, DaemonReply, RemoteState, RpcRequest, RpcResponse, SessionInfo,
        PROTOCOL_VERSION,
    };

    use super::{
        load_registry, random_connection_id, read_json_frame, validate_connection_id,
        write_json_frame, Connection, DaemonPaths, Phase, State, MAX_CONNECTIONS,
        MAX_IPC_REQUEST_BYTES, MAX_IPC_RESPONSE_BYTES,
    };

    #[test]
    fn ipc_frame_round_trips_and_requires_one_record() {
        let request = RpcRequest {
            version: PROTOCOL_VERSION,
            request_id: "test-1".into(),
            request: crate::protocol::DaemonRequest::List,
        };
        let mut bytes = Vec::new();
        write_json_frame(&mut bytes, &request, MAX_IPC_REQUEST_BYTES)
            .expect("frame should serialize");
        let decoded: RpcRequest = read_json_frame(&mut Cursor::new(bytes), MAX_IPC_REQUEST_BYTES)
            .expect("frame should parse");
        assert_eq!(decoded, request);
        assert!(read_json_frame::<RpcRequest>(
            &mut Cursor::new(b"{}\n{}\n"),
            MAX_IPC_REQUEST_BYTES
        )
        .is_err());
    }

    #[test]
    fn connection_ids_are_fixed_hex_tokens() {
        assert!(validate_connection_id("0123456789abcdef0123456789abcdef").is_ok());
        assert!(validate_connection_id("../daemon.sock").is_err());
        assert!(validate_connection_id("abc").is_err());
    }

    #[test]
    fn known_hosts_render_one_disconnected_row_and_duplicate_connects_are_busy() {
        let root = crate::runtime::runtime_root().expect("runtime root should exist");
        let token = random_connection_id().expect("test token should be generated");
        let registry = root.join(format!("test-connections-{token}.json"));
        let masters = root.join("masters");
        crate::runtime::ensure_private_dir(&masters).expect("master root should be private");
        let paths = DaemonPaths {
            socket: root.join(format!("test-daemon-{token}.sock")),
            lock: root.join(format!("test-daemon-{token}.lock")),
            registry: registry.clone(),
            masters,
        };
        let config = Config {
            ssh_targets: vec!["hugh".into()],
            ..Config::default()
        };
        let (refresh_tx, refresh_rx) = std::sync::mpsc::channel();
        let mut state = State {
            paths,
            known_targets: config.ssh_targets.clone(),
            connections: Default::default(),
            last_errors: Default::default(),
            next_epoch: 0,
            refresh_tx,
            refresh_rx,
            refresh_in_flight: Default::default(),
            last_refresh_started: std::time::Instant::now(),
        };
        let hosts = state.hosts();
        assert_eq!(hosts.len(), 1);
        assert_eq!(hosts[0].state, RemoteState::Disconnected);
        let DaemonReply::ConnectPlan { connection_id, .. } =
            state.begin_connect(&config, "hugh".into())
        else {
            panic!("connection should be reserved");
        };
        assert!(matches!(
            state.begin_connect(&config, "hugh".into()),
            DaemonReply::Error { .. }
        ));
        assert_eq!(
            state.abort_connect(&config, "hugh", &connection_id),
            DaemonReply::Ack
        );
        assert!(!state.connections.contains_key("hugh"));
        assert!(matches!(
            state.begin_connect(&config, "hugh".into()),
            DaemonReply::ConnectPlan { .. }
        ));
        let _ = fs::remove_file(registry);
    }

    #[test]
    fn failed_master_cleanup_keeps_recoverable_ownership() {
        let root = crate::runtime::runtime_root().expect("runtime root should exist");
        let masters = root.join("masters");
        crate::runtime::ensure_private_dir(&masters).expect("master root should be private");
        let token = random_connection_id().expect("test token should be generated");
        let script = root.join(format!("fake-stubborn-ssh-{token}"));
        let registry = root.join(format!("test-stubborn-connections-{token}.json"));
        fs::write(
            &script,
            "#!/bin/sh\ncase \" $* \" in\n  *\" -O check \"*) exit 0 ;;\n  *\" -O exit \"*) exit 1 ;;\n  *) exit 1 ;;\nesac\n",
        )
        .expect("fake SSH should be written");
        let mut permissions = fs::metadata(&script)
            .expect("fake SSH metadata should exist")
            .permissions();
        permissions.set_mode(0o700);
        fs::set_permissions(&script, permissions).expect("fake SSH should be executable");

        let paths = DaemonPaths {
            socket: root.join(format!("test-stubborn-daemon-{token}.sock")),
            lock: root.join(format!("test-stubborn-daemon-{token}.lock")),
            registry: registry.clone(),
            masters,
        };
        let config = Config {
            ssh_targets: vec!["hugh".into()],
            ssh_command: script.clone(),
            ..Config::default()
        };
        let (refresh_tx, refresh_rx) = std::sync::mpsc::channel();
        let mut state = State {
            paths,
            known_targets: config.ssh_targets.clone(),
            connections: Default::default(),
            last_errors: Default::default(),
            next_epoch: 0,
            refresh_tx,
            refresh_rx,
            refresh_in_flight: Default::default(),
            last_refresh_started: std::time::Instant::now(),
        };
        let DaemonReply::ConnectPlan {
            connection_id,
            control_path,
            ..
        } = state.begin_connect(&config, "hugh".into())
        else {
            panic!("connection should be reserved");
        };
        let control_path = std::path::PathBuf::from(control_path);
        let listener = UnixListener::bind(&control_path).expect("fake master socket should bind");

        assert!(matches!(
            state.abort_connect(&config, "hugh", &connection_id),
            DaemonReply::Error {
                code: DaemonErrorCode::MasterFailed,
                ..
            }
        ));
        let retained = state
            .connections
            .get("hugh")
            .expect("failed cleanup must retain ownership");
        assert_eq!(retained.connection_id, connection_id);
        assert_eq!(retained.phase, Phase::Degraded);
        assert!(control_path.exists());
        let persisted = load_registry(&state.paths)
            .expect("registry should remain readable")
            .expect("failed cleanup should stay persisted");
        assert_eq!(persisted.connections.len(), 1);

        state.shutdown(&config);
        assert!(state.connections.contains_key("hugh"));
        assert!(control_path.exists());

        drop(listener);
        let _ = fs::remove_file(control_path);
        let _ = fs::remove_file(script);
        let _ = fs::remove_file(registry);
    }

    #[test]
    fn expired_reservations_are_cleaned_in_bounded_batches() {
        let root = crate::runtime::runtime_root().expect("runtime root should exist");
        let masters = root.join("masters");
        crate::runtime::ensure_private_dir(&masters).expect("master root should be private");
        let token = random_connection_id().expect("test token should be generated");
        let registry = root.join(format!("test-expired-connections-{token}.json"));
        let paths = DaemonPaths {
            socket: root.join(format!("test-expired-daemon-{token}.sock")),
            lock: root.join(format!("test-expired-daemon-{token}.lock")),
            registry: registry.clone(),
            masters: masters.clone(),
        };
        let (refresh_tx, refresh_rx) = std::sync::mpsc::channel();
        let mut state = State {
            paths,
            known_targets: Vec::new(),
            connections: Default::default(),
            last_errors: Default::default(),
            next_epoch: 3,
            refresh_tx,
            refresh_rx,
            refresh_in_flight: Default::default(),
            last_refresh_started: std::time::Instant::now(),
        };

        for index in 0_u64..3 {
            let target = format!("expired-{index}");
            state.known_targets.push(target.clone());
            state.connections.insert(
                target.clone(),
                Connection {
                    target,
                    connection_id: format!("{index:032x}"),
                    control_path: masters.join(format!("missing-expired-{token}-{index}")),
                    epoch: index + 1,
                    started_at: 0,
                    phase: Phase::Connecting,
                    hostname: None,
                    server_pid: 0,
                    server_started_at: 0,
                    sessions: Vec::new(),
                    message: None,
                },
            );
        }

        let config = Config::default();
        state.expire_connecting(&config);
        assert_eq!(state.connections.len(), 2);
        assert_eq!(state.last_errors.len(), 1);

        state.expire_connecting(&config);
        assert_eq!(state.connections.len(), 1);
        state.expire_connecting(&config);
        assert!(state.connections.is_empty());

        let _ = fs::remove_file(registry);
    }

    #[test]
    fn oversized_inventory_is_bounded_without_dropping_hosts() {
        let root = crate::runtime::runtime_root().expect("runtime root should exist");
        let masters = root.join("masters");
        crate::runtime::ensure_private_dir(&masters).expect("master root should be private");
        let token = random_connection_id().expect("test token should be generated");
        let paths = DaemonPaths {
            socket: root.join(format!("test-large-daemon-{token}.sock")),
            lock: root.join(format!("test-large-daemon-{token}.lock")),
            registry: root.join(format!("test-large-connections-{token}.json")),
            masters: masters.clone(),
        };
        let (refresh_tx, refresh_rx) = std::sync::mpsc::channel();
        let mut state = State {
            paths,
            known_targets: Vec::new(),
            connections: Default::default(),
            last_errors: Default::default(),
            next_epoch: 0,
            refresh_tx,
            refresh_rx,
            refresh_in_flight: Default::default(),
            last_refresh_started: std::time::Instant::now(),
        };

        for host_index in 0_u64..MAX_CONNECTIONS as u64 {
            let target = format!("large-host-{host_index}");
            let sessions = (0..150)
                .map(|session_index| SessionInfo {
                    id: format!("${session_index}"),
                    name: format!("{host_index}-{session_index:04}-{}", "x".repeat(880)),
                    windows: 1,
                    attached: 0,
                    created_at: session_index,
                    activity_at: session_index,
                })
                .collect();
            state.known_targets.push(target.clone());
            state.connections.insert(
                target.clone(),
                Connection {
                    target,
                    connection_id: format!("{host_index:032x}"),
                    control_path: masters.join(format!("large-master-{host_index}")),
                    epoch: host_index + 1,
                    started_at: 1,
                    phase: Phase::Ready,
                    hostname: Some(format!("large-hostname-{host_index}")),
                    server_pid: host_index + 100,
                    server_started_at: host_index + 200,
                    sessions,
                    message: None,
                },
            );
        }

        let full_hosts = state.hosts();
        let full_response = RpcResponse {
            version: PROTOCOL_VERSION,
            request_id: "large-inventory".into(),
            reply: DaemonReply::Hosts {
                hosts: full_hosts.clone(),
            },
        };
        assert!(
            serde_json::to_vec(&full_response)
                .expect("full response should serialize")
                .len()
                + 1
                > MAX_IPC_RESPONSE_BYTES,
            "fixture must exceed the aggregate response limit"
        );

        let hosts = state.hosts_for_reply();
        assert_eq!(hosts.len(), full_hosts.len());
        assert!(hosts.iter().any(|host| host.state == RemoteState::Ready));
        assert!(hosts
            .iter()
            .any(|host| host.state == RemoteState::Degraded && host.sessions.is_empty()));
        let response = RpcResponse {
            version: PROTOCOL_VERSION,
            request_id: "bounded-inventory".into(),
            reply: DaemonReply::Hosts { hosts },
        };
        let mut bytes = Vec::new();
        write_json_frame(&mut bytes, &response, MAX_IPC_RESPONSE_BYTES)
            .expect("bounded inventory must fit the IPC frame");
        assert!(bytes.len() <= MAX_IPC_RESPONSE_BYTES);
    }
}
