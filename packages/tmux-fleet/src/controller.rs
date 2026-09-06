use std::collections::{HashMap, HashSet, VecDeque};
use std::fs::{self, File};
use std::io::{self, BufRead, BufReader, Read, Write};
use std::os::unix::net::UnixStream;
use std::process::{Command, ExitStatus, Output, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;
use serde::{Deserialize, Serialize};

use crate::config::Config;
use crate::protocol::{parse_wire, Snapshot, WireMessage, MAX_SESSION_NAME_BYTES};
use crate::runtime::{self, ControllerDir};
use crate::ssh;
use crate::tmux::{self, AttachMode, ExistingTarget, STALE_TARGET_EXIT_CODE};

const SWITCH_EXIT_CODE: i32 = 42;
const SSH_FAILURE_EXIT_CODE: i32 = 255;
const WATCHER_LIVENESS_TIMEOUT: Duration = Duration::from_secs(35);
const MAX_STREAM_LINE_BYTES: usize = 8 * 1024 * 1024;
const MAX_CACHE_FILE_BYTES: u64 = 8 * 1024 * 1024;
const MAX_SNAPSHOT_SESSIONS: usize = 4096;
const MAX_HOSTNAME_BYTES: usize = 255;
const MAX_SESSION_ID_BYTES: usize = 64;
const MAX_ERROR_MESSAGE_BYTES: usize = 16 * 1024;

#[derive(Clone, Debug)]
enum RemoteStatus {
    Cached,
    Connecting,
    Online,
    Offline(String),
}

#[derive(Clone, Debug)]
struct RemoteState {
    snapshot: Option<Snapshot>,
    status: RemoteStatus,
}

struct Model {
    local_name: String,
    local: Snapshot,
    host_order: Vec<String>,
    remotes: HashMap<String, RemoteState>,
}

#[derive(Debug)]
enum StateEvent {
    Connecting {
        host: String,
    },
    Snapshot {
        host: Option<String>,
        snapshot: Snapshot,
    },
    Problem {
        host: Option<String>,
        message: String,
    },
    Offline {
        host: String,
        message: String,
    },
}

#[derive(Clone, Debug, Eq, Hash, PartialEq)]
enum EventHost {
    Local,
    Remote(String),
}

#[derive(Default)]
struct PendingStateEvents {
    sequence: u64,
    snapshots: HashMap<EventHost, (u64, StateEvent)>,
    statuses: HashMap<EventHost, (u64, StateEvent)>,
}

#[derive(Clone)]
struct StateEventSender {
    pending: Arc<Mutex<PendingStateEvents>>,
    wake: mpsc::SyncSender<()>,
}

struct StateEventReceiver {
    pending: Arc<Mutex<PendingStateEvents>>,
    wake: mpsc::Receiver<()>,
}

fn state_event_channel() -> (StateEventSender, StateEventReceiver) {
    let pending = Arc::new(Mutex::new(PendingStateEvents::default()));
    let (wake_tx, wake_rx) = mpsc::sync_channel(1);
    (
        StateEventSender {
            pending: Arc::clone(&pending),
            wake: wake_tx,
        },
        StateEventReceiver {
            pending,
            wake: wake_rx,
        },
    )
}

fn lock_unpoisoned<T>(mutex: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    match mutex.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

impl StateEventSender {
    fn send(&self, event: StateEvent) -> std::result::Result<(), ()> {
        let (host, snapshot) = match &event {
            StateEvent::Snapshot { host: None, .. } => (EventHost::Local, true),
            StateEvent::Problem { host: None, .. } => (EventHost::Local, false),
            StateEvent::Snapshot {
                host: Some(host), ..
            } => (EventHost::Remote(host.clone()), true),
            StateEvent::Problem {
                host: Some(host), ..
            }
            | StateEvent::Connecting { host }
            | StateEvent::Offline { host, .. } => (EventHost::Remote(host.clone()), false),
        };
        let mut pending = lock_unpoisoned(&self.pending);
        pending.sequence = pending.sequence.wrapping_add(1);
        let sequence = pending.sequence;
        let slot = if snapshot {
            &mut pending.snapshots
        } else {
            &mut pending.statuses
        };
        slot.insert(host, (sequence, event));
        drop(pending);
        match self.wake.try_send(()) {
            Ok(()) | Err(mpsc::TrySendError::Full(())) => Ok(()),
            Err(mpsc::TrySendError::Disconnected(())) => Err(()),
        }
    }
}

impl StateEventReceiver {
    fn recv_timeout(
        &self,
        timeout: Duration,
    ) -> std::result::Result<Vec<StateEvent>, mpsc::RecvTimeoutError> {
        self.wake.recv_timeout(timeout)?;
        Ok(self.drain())
    }

    fn drain(&self) -> Vec<StateEvent> {
        let mut pending = lock_unpoisoned(&self.pending);
        let mut events = pending
            .snapshots
            .drain()
            .map(|(_, queued)| queued)
            .collect::<Vec<_>>();
        events.extend(pending.statuses.drain().map(|(_, queued)| queued));
        events.sort_unstable_by_key(|(sequence, _)| *sequence);
        events.into_iter().map(|(_, event)| event).collect()
    }
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "action", rename_all = "snake_case")]
enum Target {
    LocalSession {
        id: String,
        name: String,
        server_started_at: u64,
        created_at: u64,
    },
    RemoteSession {
        host: String,
        id: String,
        name: String,
        server_started_at: u64,
        created_at: u64,
    },
    NewLocal,
    NewRemote {
        host: String,
    },
    Reconnect {
        host: String,
    },
}

#[derive(Clone, Copy, Debug)]
enum WorkerCommand {
    Wake,
    Stop,
}

struct WorkerHandle {
    commands: mpsc::Sender<WorkerCommand>,
    thread: JoinHandle<()>,
}

#[derive(Default)]
struct ProcessRegistry {
    state: Mutex<ProcessState>,
}

#[derive(Default)]
struct ProcessState {
    shutdown: bool,
    pids: HashSet<u32>,
}

impl ProcessRegistry {
    fn insert(&self, pid: u32) -> bool {
        let mut state = lock_unpoisoned(&self.state);
        if state.shutdown {
            terminate_pid(pid);
            false
        } else {
            state.pids.insert(pid);
            true
        }
    }

    fn remove(&self, pid: u32) {
        lock_unpoisoned(&self.state).pids.remove(&pid);
    }

    fn terminate_all(&self) {
        let mut state = lock_unpoisoned(&self.state);
        state.shutdown = true;
        for pid in state.pids.iter().copied() {
            terminate_pid(pid);
        }
    }
}

fn terminate_pid(pid: u32) {
    if let Ok(pid) = i32::try_from(pid) {
        let _ = kill(Pid::from_raw(pid), Signal::SIGTERM);
    }
}

pub fn run(config: Config) -> Result<()> {
    if std::env::var_os("TMUX").is_some() {
        bail!(
            "tmux-fleet must start in a terminal outside tmux; use Prefix s from a managed client"
        );
    }

    let shutdown = Arc::new(AtomicBool::new(false));
    let processes = Arc::new(ProcessRegistry::default());
    install_signal_handler(Arc::clone(&shutdown), Arc::clone(&processes))?;

    let local_name = runtime::short_hostname();
    let mut model = Model::load(&config, local_name)?;
    let controller_dir = ControllerDir::create()?;
    let (events_tx, events_rx) = state_event_channel();
    let mut workers = Vec::new();
    workers.push(spawn_stream_worker(
        None,
        config.clone(),
        events_tx.clone(),
        Arc::clone(&shutdown),
        Arc::clone(&processes),
    ));
    let mut remote_commands = HashMap::new();
    for host in model.host_order.clone() {
        let worker = spawn_stream_worker(
            Some(host.clone()),
            config.clone(),
            events_tx.clone(),
            Arc::clone(&shutdown),
            Arc::clone(&processes),
        );
        remote_commands.insert(host, worker.commands.clone());
        workers.push(worker);
    }
    drop(events_tx);

    let mut resume_query = None;
    let result = (|| -> Result<()> {
        'controller: loop {
            if shutdown.load(Ordering::SeqCst) {
                break;
            }
            drain_events(&mut model, &events_rx);
            let Some(target) = run_picker(
                &config,
                &mut model,
                &events_rx,
                &controller_dir,
                &processes,
                resume_query.take(),
            )?
            else {
                break;
            };
            if shutdown.load(Ordering::SeqCst) {
                break;
            }

            let outcome = match target.clone() {
                Target::LocalSession {
                    id,
                    server_started_at,
                    created_at,
                    ..
                } => wait_local(
                    &config,
                    AttachMode::Existing(ExistingTarget {
                        id,
                        server_started_at,
                        created_at,
                    }),
                    &processes,
                    &mut model,
                    &events_rx,
                )?,
                Target::RemoteSession {
                    ref host,
                    ref id,
                    server_started_at,
                    created_at,
                    ..
                } => {
                    let code = wait_remote(
                        &config,
                        host,
                        AttachMode::Existing(ExistingTarget {
                            id: id.clone(),
                            server_started_at,
                            created_at,
                        }),
                        &processes,
                        &mut model,
                        &events_rx,
                    )?;
                    wake_worker(&remote_commands, host);
                    code
                }
                Target::NewLocal => {
                    let Some(name) =
                        prompt_session_name("local", &shutdown, &mut model, &events_rx)?
                    else {
                        break 'controller;
                    };
                    wait_local(
                        &config,
                        AttachMode::New(name),
                        &processes,
                        &mut model,
                        &events_rx,
                    )?
                }
                Target::NewRemote { ref host } => {
                    let Some(name) = prompt_session_name(host, &shutdown, &mut model, &events_rx)?
                    else {
                        break 'controller;
                    };
                    let code = wait_remote(
                        &config,
                        host,
                        AttachMode::New(name),
                        &processes,
                        &mut model,
                        &events_rx,
                    )?;
                    wake_worker(&remote_commands, host);
                    code
                }
                Target::Reconnect { ref host } => {
                    eprintln!("Authenticating {host} with your configured SSH key…");
                    let code = wait_command(
                        ssh::reconnect_command(&config, host)?,
                        &processes,
                        &mut model,
                        &events_rx,
                    )?;
                    wake_worker(&remote_commands, host);
                    if code != 0 {
                        eprintln!("SSH reconnect to {host} failed (exit {code}).");
                    }
                    continue;
                }
            };

            if shutdown.load(Ordering::SeqCst) {
                break;
            }

            match outcome {
                SWITCH_EXIT_CODE => {}
                STALE_TARGET_EXIT_CODE => {
                    eprintln!(
                        "That session changed since it was listed; refreshing before attach."
                    );
                    resume_query = target_query(&target);
                }
                0 => break,
                SSH_FAILURE_EXIT_CODE => {
                    if let Target::RemoteSession {
                        ref host, ref name, ..
                    } = target
                    {
                        eprintln!("SSH connection to {host} dropped; returning to the cached session list.");
                        resume_query = Some(format!("{host} {name}"));
                    }
                }
                code => {
                    eprintln!(
                        "Session command exited with status {code}; returning to the picker."
                    );
                    resume_query = target_query(&target);
                }
            }
        }
        Ok(())
    })();

    shutdown.store(true, Ordering::SeqCst);
    for worker in &workers {
        let _ = worker.commands.send(WorkerCommand::Stop);
    }
    processes.terminate_all();
    for worker in workers {
        let _ = worker.thread.join();
    }
    result
}

impl Model {
    fn load(config: &Config, local_name: String) -> Result<Self> {
        let local = tmux::snapshot(config)?;
        validate_snapshot(&local).map_err(anyhow::Error::msg)?;
        let mut host_order = Vec::new();
        let mut remotes = HashMap::new();
        for host in &config.hosts {
            let snapshot = load_cached_snapshot(host).ok().flatten();
            let status = if snapshot.is_some() {
                RemoteStatus::Cached
            } else {
                RemoteStatus::Connecting
            };
            host_order.push(host.clone());
            remotes.insert(host.clone(), RemoteState { snapshot, status });
        }
        Ok(Self {
            local_name,
            local,
            host_order,
            remotes,
        })
    }

    fn apply(&mut self, event: StateEvent) -> bool {
        match event {
            StateEvent::Connecting { host } => {
                let Some(remote) = self.remotes.get_mut(&host) else {
                    return false;
                };
                if matches!(remote.status, RemoteStatus::Connecting) {
                    return false;
                }
                remote.status = RemoteStatus::Connecting;
                true
            }
            StateEvent::Snapshot {
                host: None,
                snapshot,
            } => {
                let changed = self.local.server_started_at != snapshot.server_started_at
                    || self.local.sessions != snapshot.sessions;
                self.local = snapshot;
                changed
            }
            StateEvent::Snapshot {
                host: Some(host),
                snapshot,
            } => {
                let Some(remote) = self.remotes.get_mut(&host) else {
                    return false;
                };
                let changed = !matches!(remote.status, RemoteStatus::Online)
                    || remote.snapshot.as_ref().map(|old| {
                        old.server_started_at == snapshot.server_started_at
                            && old.sessions == snapshot.sessions
                    }) != Some(true);
                remote.snapshot = Some(snapshot.clone());
                remote.status = RemoteStatus::Online;
                if let Err(error) = save_cached_snapshot(&host, &snapshot) {
                    eprintln!("tmux-fleet: could not cache {host}: {error:#}");
                }
                changed
            }
            StateEvent::Problem {
                host: None,
                message,
            } => {
                eprintln!("tmux-fleet: local watcher: {message}");
                false
            }
            StateEvent::Problem {
                host: Some(host),
                message,
            }
            | StateEvent::Offline { host, message } => {
                let Some(remote) = self.remotes.get_mut(&host) else {
                    return false;
                };
                let changed = match &remote.status {
                    RemoteStatus::Offline(old) => old != &message,
                    _ => true,
                };
                remote.status = RemoteStatus::Offline(message);
                changed
            }
        }
    }

    fn rows(&self) -> Result<String> {
        let mut rows = Vec::new();
        for session in &self.local.sessions {
            rows.push(candidate_line(
                &Target::LocalSession {
                    id: session.id.clone(),
                    name: session.name.clone(),
                    server_started_at: self.local.server_started_at,
                    created_at: session.created_at,
                },
                &format!(
                    "●  LOCAL  {:<14}  {:<24}  {}{}",
                    clean_field(&self.local_name),
                    clean_field(&session.name),
                    window_label(session.windows),
                    attached_label(session.attached)
                ),
            )?);
        }
        rows.push(candidate_line(
            &Target::NewLocal,
            &format!(
                "＋ LOCAL  {:<14}  new session",
                clean_field(&self.local_name)
            ),
        )?);

        for host in &self.host_order {
            let Some(remote) = self.remotes.get(host) else {
                continue;
            };
            let stale = !matches!(remote.status, RemoteStatus::Online);
            if let Some(snapshot) = &remote.snapshot {
                for session in &snapshot.sessions {
                    rows.push(candidate_line(
                        &Target::RemoteSession {
                            host: host.clone(),
                            id: session.id.clone(),
                            name: session.name.clone(),
                            server_started_at: snapshot.server_started_at,
                            created_at: session.created_at,
                        },
                        &format!(
                            "{}  SSH    {:<14}  {:<24}  {}{}{}",
                            if stale { "◌" } else { "●" },
                            clean_field(host),
                            clean_field(&session.name),
                            window_label(session.windows),
                            attached_label(session.attached),
                            if stale { " · cached" } else { "" }
                        ),
                    )?);
                }
            }
            if matches!(remote.status, RemoteStatus::Online) {
                rows.push(candidate_line(
                    &Target::NewRemote { host: host.clone() },
                    &format!("＋ SSH    {:<14}  new session", clean_field(host)),
                )?);
            } else {
                let detail = match &remote.status {
                    RemoteStatus::Cached => "cached · connecting".to_owned(),
                    RemoteStatus::Connecting => "connecting".to_owned(),
                    RemoteStatus::Offline(message) => {
                        format!("offline · {}", shorten(&clean_field(message), 72))
                    }
                    RemoteStatus::Online => unreachable!(),
                };
                rows.push(candidate_line(
                    &Target::Reconnect { host: host.clone() },
                    &format!(
                        "↻  SSH    {:<14}  authenticate / reconnect  {detail}",
                        clean_field(host)
                    ),
                )?);
            }
        }
        Ok(format!("{}\n", rows.join("\n")))
    }
}

fn spawn_stream_worker(
    host: Option<String>,
    config: Config,
    events: StateEventSender,
    shutdown: Arc<AtomicBool>,
    processes: Arc<ProcessRegistry>,
) -> WorkerHandle {
    let (commands_tx, commands_rx) = mpsc::channel();
    let thread = thread::spawn(move || {
        let mut backoff_seconds = 1_u64;
        while !shutdown.load(Ordering::SeqCst) {
            if let Some(host) = &host {
                let _ = events.send(StateEvent::Connecting { host: host.clone() });
            }
            let command = match &host {
                Some(host) => ssh::watch_command(&config, host),
                None => local_watch_command(&config),
            };
            let outcome = match command {
                Ok(command) => run_stream_process(
                    command,
                    host.as_deref(),
                    &events,
                    &commands_rx,
                    &shutdown,
                    &processes,
                ),
                Err(error) => StreamOutcome::Exited {
                    got_snapshot: false,
                    message: format!("{error:#}"),
                },
            };
            match outcome {
                StreamOutcome::Stopped => break,
                StreamOutcome::Exited {
                    got_snapshot,
                    message,
                } => {
                    if let Some(host) = &host {
                        let _ = events.send(StateEvent::Offline {
                            host: host.clone(),
                            message,
                        });
                    } else if !message.is_empty() {
                        let _ = events.send(StateEvent::Problem {
                            host: None,
                            message,
                        });
                    }
                    if got_snapshot {
                        backoff_seconds = 1;
                    }
                }
            }

            let wait = if host.is_some() {
                Duration::from_secs(backoff_seconds)
            } else {
                Duration::from_secs(1)
            };
            backoff_seconds = (backoff_seconds * 2).min(30);
            match commands_rx.recv_timeout(wait) {
                Ok(WorkerCommand::Stop) => break,
                Ok(WorkerCommand::Wake) | Err(mpsc::RecvTimeoutError::Timeout) => continue,
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
        }
    });
    WorkerHandle {
        commands: commands_tx,
        thread,
    }
}

enum StreamOutcome {
    Stopped,
    Exited { got_snapshot: bool, message: String },
}

enum StreamLine {
    Stdout(String),
    Stderr(String),
    Failure(String),
}

enum StreamActivity {
    Noise,
    Message,
    Fatal(String),
}

fn run_stream_process(
    mut command: Command,
    host: Option<&str>,
    events: &StateEventSender,
    commands: &mpsc::Receiver<WorkerCommand>,
    shutdown: &AtomicBool,
    processes: &ProcessRegistry,
) -> StreamOutcome {
    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            return StreamOutcome::Exited {
                got_snapshot: false,
                message: format!("failed to start watcher: {error}"),
            }
        }
    };
    let pid = child.id();
    let registered = processes.insert(pid);
    let stdout = child.stdout.take();
    let stderr = child.stderr.take();
    let (lines_tx, lines_rx) = mpsc::sync_channel(256);
    let stdout_thread = stdout.map(|stdout| spawn_reader(stdout, lines_tx.clone(), false));
    let stderr_thread = stderr.map(|stderr| spawn_reader(stderr, lines_tx, true));
    let mut got_snapshot = false;
    let mut errors = VecDeque::with_capacity(4);
    let mut stopped = !registered;
    let mut failure = None;
    let mut last_message = Instant::now();

    if !registered {
        let _ = child.kill();
    }
    loop {
        while let Ok(line) = lines_rx.try_recv() {
            observe_stream_line(
                line,
                host,
                events,
                &mut got_snapshot,
                &mut errors,
                &mut last_message,
                &mut failure,
            );
        }
        if shutdown.load(Ordering::SeqCst) {
            stopped = true;
            let _ = child.kill();
        }
        match commands.try_recv() {
            Ok(WorkerCommand::Stop) | Err(mpsc::TryRecvError::Disconnected) => {
                stopped = true;
                let _ = child.kill();
            }
            Ok(WorkerCommand::Wake) | Err(mpsc::TryRecvError::Empty) => {}
        }
        if failure.is_none() && watcher_timed_out(last_message, Instant::now()) {
            let message = format!(
                "watcher sent no protocol message for {} seconds",
                WATCHER_LIVENESS_TIMEOUT.as_secs()
            );
            push_error(&mut errors, message.clone());
            failure = Some(message);
        }
        if failure.is_some() {
            let _ = child.kill();
        }
        match child.try_wait() {
            Ok(Some(status)) => {
                processes.remove(pid);
                if let Some(thread) = stdout_thread {
                    let _ = thread.join();
                }
                if let Some(thread) = stderr_thread {
                    let _ = thread.join();
                }
                while let Ok(line) = lines_rx.try_recv() {
                    observe_stream_line(
                        line,
                        host,
                        events,
                        &mut got_snapshot,
                        &mut errors,
                        &mut last_message,
                        &mut failure,
                    );
                }
                if stopped {
                    return StreamOutcome::Stopped;
                }
                let detail = failure.unwrap_or_else(|| {
                    if errors.is_empty() {
                        format!("watcher exited with status {}", exit_code(status.code()))
                    } else {
                        errors.into_iter().collect::<Vec<_>>().join(" · ")
                    }
                });
                return StreamOutcome::Exited {
                    got_snapshot,
                    message: detail,
                };
            }
            Ok(None) => {}
            Err(error) => {
                processes.remove(pid);
                let _ = child.kill();
                let _ = child.wait();
                return StreamOutcome::Exited {
                    got_snapshot,
                    message: format!("failed to wait for watcher: {error}"),
                };
            }
        }
        thread::sleep(Duration::from_millis(20));
    }
}

fn spawn_reader<R: Read + Send + 'static>(
    reader: R,
    sender: mpsc::SyncSender<StreamLine>,
    stderr: bool,
) -> JoinHandle<()> {
    thread::spawn(move || {
        let mut reader = BufReader::new(reader);
        loop {
            let mut bytes = match read_bounded_line(&mut reader, MAX_STREAM_LINE_BYTES) {
                Ok(Some(bytes)) => bytes,
                Ok(None) => break,
                Err(error) => {
                    let stream = if stderr { "stderr" } else { "stdout" };
                    let _ = sender.try_send(StreamLine::Failure(format!(
                        "watcher {stream} reader failed: {error}"
                    )));
                    break;
                }
            };
            if bytes.last() == Some(&b'\n') {
                bytes.pop();
            }
            if bytes.last() == Some(&b'\r') {
                bytes.pop();
            }
            let line = if stderr {
                String::from_utf8_lossy(&bytes).into_owned()
            } else {
                match String::from_utf8(bytes) {
                    Ok(line) => line,
                    Err(_) => {
                        let _ = sender.try_send(StreamLine::Failure(
                            "watcher stdout contained non-UTF-8 data".into(),
                        ));
                        break;
                    }
                }
            };
            let event = if stderr {
                StreamLine::Stderr(line)
            } else {
                StreamLine::Stdout(line)
            };
            if sender.try_send(event).is_err() {
                break;
            }
        }
    })
}

fn read_bounded_line(reader: &mut impl BufRead, maximum: usize) -> io::Result<Option<Vec<u8>>> {
    let mut output = Vec::new();
    loop {
        let available = reader.fill_buf()?;
        if available.is_empty() {
            return Ok((!output.is_empty()).then_some(output));
        }
        let newline = available.iter().position(|byte| *byte == b'\n');
        let consumed = newline.map_or(available.len(), |position| position + 1);
        if output.len().saturating_add(consumed) > maximum {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!("line exceeded {maximum} bytes"),
            ));
        }
        output.extend_from_slice(&available[..consumed]);
        reader.consume(consumed);
        if newline.is_some() {
            return Ok(Some(output));
        }
    }
}

fn observe_stream_line(
    line: StreamLine,
    host: Option<&str>,
    events: &StateEventSender,
    got_snapshot: &mut bool,
    errors: &mut VecDeque<String>,
    last_message: &mut Instant,
    failure: &mut Option<String>,
) {
    match process_stream_line(line, host, events, got_snapshot, errors) {
        StreamActivity::Noise => {}
        StreamActivity::Message => *last_message = Instant::now(),
        StreamActivity::Fatal(message) => {
            if failure.is_none() {
                push_error(errors, message.clone());
                *failure = Some(message);
            }
        }
    }
}

fn process_stream_line(
    line: StreamLine,
    host: Option<&str>,
    events: &StateEventSender,
    got_snapshot: &mut bool,
    errors: &mut VecDeque<String>,
) -> StreamActivity {
    match line {
        StreamLine::Stdout(line) => match parse_wire(&line) {
            Some(WireMessage::Snapshot { snapshot }) => {
                if let Err(message) = validate_snapshot(&snapshot) {
                    return StreamActivity::Fatal(message);
                }
                *got_snapshot = true;
                let _ = events.send(StateEvent::Snapshot {
                    host: host.map(ToOwned::to_owned),
                    snapshot,
                });
                StreamActivity::Message
            }
            Some(WireMessage::Error { message, .. }) => {
                if message.len() > MAX_ERROR_MESSAGE_BYTES {
                    return StreamActivity::Fatal("watcher error message exceeded limit".into());
                }
                push_error(errors, message.clone());
                let _ = events.send(StateEvent::Problem {
                    host: host.map(ToOwned::to_owned),
                    message,
                });
                StreamActivity::Message
            }
            Some(WireMessage::Heartbeat { .. }) => StreamActivity::Message,
            None if line.starts_with(crate::protocol::WIRE_PREFIX) => {
                StreamActivity::Fatal("watcher sent malformed protocol data".into())
            }
            None => StreamActivity::Noise,
        },
        StreamLine::Stderr(line) if !line.trim().is_empty() => {
            push_error(errors, line);
            StreamActivity::Noise
        }
        StreamLine::Stderr(_) => StreamActivity::Noise,
        StreamLine::Failure(message) => StreamActivity::Fatal(message),
    }
}

fn validate_snapshot(snapshot: &Snapshot) -> std::result::Result<(), String> {
    if snapshot.hostname.len() > MAX_HOSTNAME_BYTES {
        return Err("watcher hostname exceeded limit".into());
    }
    if snapshot.sessions.len() > MAX_SNAPSHOT_SESSIONS {
        return Err("watcher session count exceeded limit".into());
    }
    let mut ids = HashSet::with_capacity(snapshot.sessions.len());
    for session in &snapshot.sessions {
        let valid_id = session.id.strip_prefix('$').is_some_and(|digits| {
            !digits.is_empty() && digits.bytes().all(|byte| byte.is_ascii_digit())
        });
        if !valid_id || session.id.len() > MAX_SESSION_ID_BYTES {
            return Err("watcher sent an invalid tmux session ID".into());
        }
        if session.name.len() > MAX_SESSION_NAME_BYTES {
            return Err("watcher session name exceeded limit".into());
        }
        if !ids.insert(session.id.as_str()) {
            return Err("watcher sent duplicate tmux session IDs".into());
        }
    }
    Ok(())
}

fn watcher_timed_out(last_message: Instant, now: Instant) -> bool {
    now.saturating_duration_since(last_message) >= WATCHER_LIVENESS_TIMEOUT
}

fn push_error(errors: &mut VecDeque<String>, message: String) {
    if errors.len() == 4 {
        errors.pop_front();
    }
    errors.push_back(shorten(&clean_field(&message), 120));
}

fn local_watch_command(config: &Config) -> Result<Command> {
    let executable = std::env::current_exe().context("failed to locate tmux-fleet executable")?;
    let mut command = Command::new(executable);
    command
        .arg("watch")
        .arg("--reconcile-seconds")
        .arg(config.reconcile_seconds.to_string())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    Ok(command)
}

fn run_picker(
    config: &Config,
    model: &mut Model,
    events: &StateEventReceiver,
    controller_dir: &ControllerDir,
    processes: &ProcessRegistry,
    query: Option<String>,
) -> Result<Option<Target>> {
    let candidates_path = controller_dir.path().join("candidates");
    let socket_path = controller_dir.path().join("fzf.sock");
    runtime::atomic_write(&candidates_path, model.rows()?.as_bytes())?;
    let reload_action = format!("reload(cat -- {})", runtime::shell_quote(&candidates_path));

    let input = File::open(&candidates_path)
        .with_context(|| format!("failed to open {}", candidates_path.display()))?;
    let mut command = Command::new(&config.fzf_command);
    command
        .args([
            "--delimiter=\t",
            "--with-nth=2..",
            "--nth=2..",
            "--layout=reverse",
            "--border=rounded",
            "--info=inline-right",
            "--no-multi",
            "--cycle",
            "--prompt=Sessions › ",
            "--header=Enter attach · Esc quit · Ctrl-R refresh",
            "--color=bg:#1d2021,bg+:#3c3836,fg:#d0c0a0,fg+:#ebdbb2,hl:#84a9b2,hl+:#d58a54,prompt:#d58a54,pointer:#d58a54,marker:#84a9b2,spinner:#84a9b2,border:#504945,header:#9c8d7d,info:#7c6f64",
        ])
        .arg(format!("--listen-unsafe={}", socket_path.display()))
        .arg(format!("--bind=ctrl-r:{reload_action}"))
        .stdin(Stdio::from(input))
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .env_remove("FZF_DEFAULT_COMMAND");
    if let Some(query) = query {
        command.arg("--query").arg(query);
    }

    let child = command
        .spawn()
        .with_context(|| format!("failed to run {}", config.fzf_command.display()))?;
    let pid = child.id();
    processes.insert(pid);
    let (done_tx, done_rx) = mpsc::channel();
    thread::spawn(move || {
        let _ = done_tx.send(child.wait_with_output());
    });

    let mut reload_pending = false;
    let output = loop {
        match done_rx.try_recv() {
            Ok(output) => break output.context("failed to wait for fzf")?,
            Err(mpsc::TryRecvError::Disconnected) => bail!("fzf result channel closed"),
            Err(mpsc::TryRecvError::Empty) => {}
        }
        let mut changed = false;
        match events.recv_timeout(Duration::from_millis(40)) {
            Ok(pending) => {
                for event in pending {
                    changed |= model.apply(event);
                }
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => {}
        }
        if changed {
            runtime::atomic_write(&candidates_path, model.rows()?.as_bytes())?;
            reload_pending = true;
        }
        if reload_pending && post_fzf_action(&socket_path, &reload_action) {
            reload_pending = false;
        }
    };
    processes.remove(pid);
    let _ = fs::remove_file(socket_path);
    parse_picker_output(output)
}

fn post_fzf_action(socket_path: &std::path::Path, action: &str) -> bool {
    let Ok(mut stream) = UnixStream::connect(socket_path) else {
        return false;
    };
    let request = format!(
        "POST / HTTP/1.1\r\nHost: localhost\r\nContent-Type: text/plain\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{action}",
        action.len()
    );
    stream.write_all(request.as_bytes()).is_ok()
}

fn parse_picker_output(output: Output) -> Result<Option<Target>> {
    if !output.status.success() {
        return Ok(None);
    }
    let text = String::from_utf8(output.stdout).context("fzf emitted non-UTF-8 output")?;
    let Some(line) = text.lines().next() else {
        return Ok(None);
    };
    let json = line.split_once('\t').map_or(line, |(json, _)| json);
    serde_json::from_str(json)
        .map(Some)
        .context("fzf returned an invalid session target")
}

fn wait_local(
    config: &Config,
    mode: AttachMode,
    processes: &ProcessRegistry,
    model: &mut Model,
    events: &StateEventReceiver,
) -> Result<i32> {
    let mut child = tmux::spawn_managed(config, mode)?;
    wait_for_exit(child.id(), processes, model, events, || child.try_wait())
}

fn wait_remote(
    config: &Config,
    host: &str,
    mode: AttachMode,
    processes: &ProcessRegistry,
    model: &mut Model,
    events: &StateEventReceiver,
) -> Result<i32> {
    wait_command(
        ssh::attach_command(config, host, &mode)?,
        processes,
        model,
        events,
    )
}

fn wait_command(
    mut command: Command,
    processes: &ProcessRegistry,
    model: &mut Model,
    events: &StateEventReceiver,
) -> Result<i32> {
    let mut child = command.spawn().context("failed to start session command")?;
    wait_for_exit(child.id(), processes, model, events, || {
        child
            .try_wait()
            .context("failed to query session command status")
    })
}

fn wait_for_exit(
    pid: u32,
    processes: &ProcessRegistry,
    model: &mut Model,
    events: &StateEventReceiver,
    mut try_wait: impl FnMut() -> Result<Option<ExitStatus>>,
) -> Result<i32> {
    processes.insert(pid);
    let result = (|| loop {
        if let Some(status) = try_wait()? {
            return Ok(exit_code(status.code()));
        }
        drain_events(model, events);
        thread::sleep(Duration::from_millis(20));
    })();
    processes.remove(pid);
    result
}

fn install_signal_handler(
    shutdown: Arc<AtomicBool>,
    processes: Arc<ProcessRegistry>,
) -> Result<()> {
    ctrlc::set_handler(move || {
        shutdown.store(true, Ordering::SeqCst);
        processes.terminate_all();
    })
    .context("failed to install signal handler")
}

fn drain_events(model: &mut Model, events: &StateEventReceiver) {
    for event in events.drain() {
        model.apply(event);
    }
}

fn wake_worker(workers: &HashMap<String, mpsc::Sender<WorkerCommand>>, host: &str) {
    if let Some(worker) = workers.get(host) {
        let _ = worker.send(WorkerCommand::Wake);
    }
}

fn load_cached_snapshot(host: &str) -> Result<Option<Snapshot>> {
    let path = runtime::cache_file(host)?;
    let file = match File::open(&path) {
        Ok(file) => file,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(error).with_context(|| format!("failed to open {}", path.display()));
        }
    };
    let mut bytes = Vec::new();
    file.take(MAX_CACHE_FILE_BYTES + 1)
        .read_to_end(&mut bytes)
        .with_context(|| format!("failed to read {}", path.display()))?;
    if bytes.len() as u64 > MAX_CACHE_FILE_BYTES {
        bail!("cached snapshot for {host} exceeds the {MAX_CACHE_FILE_BYTES}-byte safety limit");
    }
    let snapshot: Snapshot = serde_json::from_slice(&bytes)
        .with_context(|| format!("cached snapshot for {host} is invalid"))?;
    validate_snapshot(&snapshot)
        .map_err(|message| anyhow::anyhow!("cached snapshot for {host} is invalid: {message}"))?;
    Ok(Some(snapshot))
}

fn save_cached_snapshot(host: &str, snapshot: &Snapshot) -> Result<()> {
    let path = runtime::cache_file(host)?;
    let text = serde_json::to_vec(snapshot)?;
    runtime::atomic_write(&path, &text)
}

fn candidate_line(target: &Target, display: &str) -> Result<String> {
    Ok(format!("{}\t{display}", serde_json::to_string(target)?))
}

fn prompt_session_name(
    host: &str,
    shutdown: &AtomicBool,
    model: &mut Model,
    events: &StateEventReceiver,
) -> Result<Option<Option<String>>> {
    eprint!("New session name on {host} (blank for tmux default): ");
    std::io::stderr().flush()?;

    let (result_tx, result_rx) = mpsc::sync_channel(1);
    drop(thread::spawn(move || {
        let mut name = String::new();
        let result = std::io::stdin()
            .read_line(&mut name)
            .map(|bytes_read| (bytes_read, name));
        let _ = result_tx.send(result);
    }));

    loop {
        if shutdown.load(Ordering::SeqCst) {
            return Ok(None);
        }
        drain_events(model, events);
        match result_rx.recv_timeout(Duration::from_millis(50)) {
            Ok(Ok((0, _))) => return Ok(None),
            Ok(Ok((_, name))) => {
                let name = name.trim_end_matches(['\r', '\n']);
                if name.len() > MAX_SESSION_NAME_BYTES {
                    bail!("session name exceeds the {MAX_SESSION_NAME_BYTES}-byte safety limit");
                }
                return Ok(Some((!name.is_empty()).then(|| name.to_owned())));
            }
            Ok(Err(error)) => return Err(error.into()),
            Err(mpsc::RecvTimeoutError::Timeout) => {}
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                bail!("session-name prompt stopped unexpectedly");
            }
        }
    }
}

fn clean_field(value: &str) -> String {
    value
        .chars()
        .map(|character| match character {
            '\t' | '\r' | '\n' => ' ',
            character if character.is_control() => ' ',
            character => character,
        })
        .collect()
}

fn shorten(value: &str, maximum: usize) -> String {
    if value.chars().count() <= maximum {
        return value.to_owned();
    }
    let mut shortened = value
        .chars()
        .take(maximum.saturating_sub(1))
        .collect::<String>();
    shortened.push('…');
    shortened
}

fn window_label(windows: u32) -> String {
    format!("{windows} window{}", if windows == 1 { "" } else { "s" })
}

fn attached_label(attached: u32) -> String {
    if attached == 0 {
        String::new()
    } else {
        format!(" · {attached} attached")
    }
}

fn target_query(target: &Target) -> Option<String> {
    match target {
        Target::LocalSession { name, .. } => Some(name.clone()),
        Target::RemoteSession { host, name, .. } => Some(format!("{host} {name}")),
        Target::NewLocal => None,
        Target::NewRemote { host } | Target::Reconnect { host } => Some(host.clone()),
    }
}

fn exit_code(code: Option<i32>) -> i32 {
    code.unwrap_or(128)
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::io::Cursor;
    use std::time::{Duration, Instant};

    use crate::protocol::{SessionInfo, Snapshot};

    use super::{
        read_bounded_line, state_event_channel, validate_snapshot, watcher_timed_out, Model,
        RemoteState, RemoteStatus, StateEvent, Target, WATCHER_LIVENESS_TIMEOUT,
    };

    #[test]
    fn rows_preserve_identity_and_sanitize_only_the_display() {
        let remote_host = "remote".to_owned();
        let model = Model {
            local_name: "local".into(),
            local: Snapshot {
                server_started_at: 11,
                hostname: "local".into(),
                generated_at: 100,
                sessions: vec![session("$1", "work\tline\nname", 12)],
            },
            host_order: vec![remote_host.clone()],
            remotes: HashMap::from([(
                remote_host,
                RemoteState {
                    snapshot: Some(Snapshot {
                        server_started_at: 21,
                        hostname: "remote".into(),
                        generated_at: 101,
                        sessions: vec![session("$2", "ops", 22)],
                    }),
                    status: RemoteStatus::Cached,
                },
            )]),
        };

        let rows = model.rows().expect("test model should render rows");
        assert_eq!(rows.lines().count(), 4);
        let targets = rows
            .lines()
            .map(|line| {
                let (json, display) = line
                    .split_once('\t')
                    .expect("rendered row should contain a display separator");
                assert!(!display.contains(['\t', '\r', '\n']));
                serde_json::from_str::<Target>(json)
                    .expect("rendered target should remain valid JSON")
            })
            .collect::<Vec<_>>();

        assert!(targets.iter().any(|target| matches!(
            target,
            Target::LocalSession {
                id,
                name,
                server_started_at: 11,
                created_at: 12,
            } if id == "$1" && name == "work\tline\nname"
        )));
        assert!(targets.iter().any(|target| matches!(
            target,
            Target::RemoteSession {
                host,
                id,
                name,
                server_started_at: 21,
                created_at: 22,
            } if host == "remote" && id == "$2" && name == "ops"
        )));
        assert!(targets
            .iter()
            .any(|target| matches!(target, Target::Reconnect { host } if host == "remote")));
        assert!(!targets
            .iter()
            .any(|target| matches!(target, Target::NewRemote { .. })));
    }

    #[test]
    fn watcher_liveness_timeout_has_a_deterministic_boundary() {
        let now = Instant::now();
        assert!(!watcher_timed_out(
            now - (WATCHER_LIVENESS_TIMEOUT - Duration::from_millis(1)),
            now
        ));
        assert!(watcher_timed_out(now - WATCHER_LIVENESS_TIMEOUT, now));
    }

    #[test]
    fn bounded_reader_rejects_an_unterminated_oversized_line() {
        let mut reader = Cursor::new(vec![b'x'; 9]);
        let error = read_bounded_line(&mut reader, 8).unwrap_err();
        assert_eq!(error.kind(), std::io::ErrorKind::InvalidData);
    }

    #[test]
    fn state_events_coalesce_to_the_latest_snapshot_and_status_per_host() {
        let (sender, receiver) = state_event_channel();
        sender
            .send(StateEvent::Connecting {
                host: "remote".into(),
            })
            .expect("state channel should accept connecting event");
        for generated_at in [1, 2] {
            sender
                .send(StateEvent::Snapshot {
                    host: Some("remote".into()),
                    snapshot: Snapshot {
                        server_started_at: 1,
                        hostname: "remote".into(),
                        generated_at,
                        sessions: vec![session("$1", "work", 1)],
                    },
                })
                .expect("state channel should accept snapshot event");
        }
        sender
            .send(StateEvent::Offline {
                host: "remote".into(),
                message: "gone".into(),
            })
            .expect("state channel should accept offline event");
        sender
            .send(StateEvent::Connecting {
                host: "remote".into(),
            })
            .expect("state channel should replace pending status");

        let pending = receiver
            .recv_timeout(Duration::ZERO)
            .expect("state channel should contain pending events");
        assert_eq!(pending.len(), 2);
        assert!(matches!(
            &pending[0],
            StateEvent::Snapshot { snapshot, .. } if snapshot.generated_at == 2
        ));
        assert!(matches!(&pending[1], StateEvent::Connecting { .. }));

        let mut model = Model {
            local_name: "local".into(),
            local: Snapshot {
                server_started_at: 0,
                hostname: "local".into(),
                generated_at: 0,
                sessions: Vec::new(),
            },
            host_order: vec!["remote".into()],
            remotes: HashMap::from([(
                "remote".into(),
                RemoteState {
                    snapshot: None,
                    status: RemoteStatus::Online,
                },
            )]),
        };
        for event in pending {
            model.apply(event);
        }
        let remote = model
            .remotes
            .get("remote")
            .expect("remote state should exist");
        assert!(matches!(remote.status, RemoteStatus::Connecting));
        assert_eq!(
            remote
                .snapshot
                .as_ref()
                .map(|snapshot| snapshot.generated_at),
            Some(2)
        );
    }

    #[test]
    fn snapshot_validation_rejects_duplicate_ids() {
        let snapshot = Snapshot {
            server_started_at: 1,
            hostname: "remote".into(),
            generated_at: 2,
            sessions: vec![session("$1", "one", 3), session("$1", "two", 4)],
        };
        assert!(validate_snapshot(&snapshot).is_err());
    }

    fn session(id: &str, name: &str, created_at: u64) -> SessionInfo {
        SessionInfo {
            id: id.into(),
            name: name.into(),
            windows: 2,
            attached: 0,
            created_at,
            activity_at: created_at,
        }
    }
}
