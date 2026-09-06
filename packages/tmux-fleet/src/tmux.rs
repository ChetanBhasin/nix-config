use std::fs;
use std::io::{self, Read};
use std::os::unix::net::UnixDatagram;
use std::path::PathBuf;
use std::process::{Child, Command, ExitStatus, Output, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context, Result};

use crate::config::Config;
use crate::protocol::{
    unix_timestamp, write_wire, SessionInfo, Snapshot, WireMessage, MAX_SESSION_NAME_BYTES,
};
use crate::runtime;

const FIELD_SEPARATOR: char = '\u{1f}';
const SNAPSHOT_FORMAT: &str = "#{session_id}\u{1f}#{session_name}\u{1f}#{session_windows}\u{1f}#{session_attached}\u{1f}#{session_created}\u{1f}#{session_activity}\u{1f}#{start_time}";
const MAX_SNAPSHOT_OUTPUT_BYTES: usize = 8 * 1024 * 1024;
const MAX_ERROR_OUTPUT_BYTES: usize = 64 * 1024;
const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(10);
pub const STALE_TARGET_EXIT_CODE: i32 = 75;

#[derive(Clone, Debug)]
pub struct ExistingTarget {
    pub id: String,
    pub server_started_at: u64,
    pub created_at: u64,
}
pub enum AttachMode {
    Existing(ExistingTarget),
    New(Option<String>),
}

pub struct ManagedChild {
    child: Child,
}

impl ManagedChild {
    pub fn id(&self) -> u32 {
        self.child.id()
    }

    pub fn try_wait(&mut self) -> Result<Option<ExitStatus>> {
        self.child
            .try_wait()
            .context("failed to query tmux client status")
    }

    pub fn wait(mut self) -> Result<ExitStatus> {
        self.child.wait().context("failed to wait for tmux client")
    }
}

fn read_capped(mut reader: impl Read, limit: usize, stream: &'static str) -> Result<Vec<u8>> {
    let mut output = Vec::with_capacity(limit.min(8 * 1024));
    let mut buffer = [0_u8; 8 * 1024];
    loop {
        let count = reader
            .read(&mut buffer)
            .with_context(|| format!("failed to read tmux {stream}"))?;
        if count == 0 {
            return Ok(output);
        }
        if output.len().saturating_add(count) > limit {
            bail!("tmux {stream} exceeded the {limit}-byte safety limit");
        }
        output.extend_from_slice(&buffer[..count]);
    }
}

fn capture_tmux(config: &Config, args: &[&str]) -> Result<Output> {
    let mut child = Command::new(&config.tmux_command)
        .args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("failed to run {}", config.tmux_command.display()))?;
    let stdout = child
        .stdout
        .take()
        .context("failed to capture tmux stdout")?;
    let stderr = child
        .stderr
        .take()
        .context("failed to capture tmux stderr")?;
    let stdout_thread =
        thread::spawn(move || read_capped(stdout, MAX_SNAPSHOT_OUTPUT_BYTES, "stdout"));
    let stderr_thread =
        thread::spawn(move || read_capped(stderr, MAX_ERROR_OUTPUT_BYTES, "stderr"));
    let status = child.wait().context("failed to wait for tmux")?;
    let stdout = stdout_thread
        .join()
        .map_err(|_| anyhow::anyhow!("tmux stdout reader panicked"))??;
    let stderr = stderr_thread
        .join()
        .map_err(|_| anyhow::anyhow!("tmux stderr reader panicked"))??;
    Ok(Output {
        status,
        stdout,
        stderr,
    })
}

pub fn snapshot(config: &Config) -> Result<Snapshot> {
    let output = capture_tmux(config, &["list-sessions", "-F", SNAPSHOT_FORMAT])?;

    let stdout = String::from_utf8(output.stdout).context("tmux emitted non-UTF-8 session data")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        if stdout.trim().is_empty()
            && (stderr.contains("no server running")
                || stderr.contains("error connecting")
                || stderr.contains("failed to connect"))
        {
            return Ok(empty_snapshot());
        }
        bail!("tmux list-sessions failed: {}", stderr.trim());
    }

    let records = stdout
        .lines()
        .filter(|line| !line.is_empty())
        .map(parse_session)
        .collect::<Result<Vec<_>>>()?;
    let server_started_at = records
        .first()
        .map(|(_, server_started_at)| *server_started_at)
        .unwrap_or_default();
    if records
        .iter()
        .any(|(_, started_at)| *started_at != server_started_at)
    {
        bail!("tmux server generation changed while collecting sessions");
    }
    let mut sessions = records
        .into_iter()
        .map(|(session, _)| session)
        .collect::<Vec<_>>();
    sessions.sort_by(|left, right| {
        right
            .activity_at
            .cmp(&left.activity_at)
            .then_with(|| left.name.cmp(&right.name))
    });

    Ok(Snapshot {
        server_started_at,
        hostname: runtime::short_hostname(),
        generated_at: unix_timestamp(),
        sessions,
    })
}

pub fn run_watch(config: &Config, reconcile_seconds: u64) -> Result<()> {
    let watcher = WatcherSocket::bind()?;
    if !send_snapshot(config)? {
        return Ok(());
    }

    let reconcile_interval = Duration::from_secs(reconcile_seconds.max(1));
    let mut next_reconcile = Instant::now() + reconcile_interval;
    let mut next_heartbeat = Instant::now() + HEARTBEAT_INTERVAL;
    let mut buffer = [0_u8; 32];

    loop {
        let mut changed = false;
        match watcher.socket.recv(&mut buffer) {
            Ok(_) => changed = true,
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                ) => {}
            Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
            Err(error) => return Err(error).context("failed to receive tmux notification"),
        }

        if changed {
            thread::sleep(Duration::from_millis(25));
            watcher.socket.set_nonblocking(true)?;
            while watcher.socket.recv(&mut buffer).is_ok() {}
            watcher.socket.set_nonblocking(false)?;
            watcher
                .socket
                .set_read_timeout(Some(Duration::from_secs(1)))?;
        }

        let now = Instant::now();
        if changed || now >= next_reconcile {
            if !send_snapshot(config)? {
                return Ok(());
            }
            next_reconcile = now + reconcile_interval;
            next_heartbeat = now + HEARTBEAT_INTERVAL;
        } else if now >= next_heartbeat {
            if !write_wire(&WireMessage::Heartbeat {
                sent_at: unix_timestamp(),
            })? {
                return Ok(());
            }
            next_heartbeat = now + HEARTBEAT_INTERVAL;
        }
    }
}

pub fn notify_watchers() -> Result<()> {
    let directory = runtime::watcher_dir()?;
    let sender = UnixDatagram::unbound().context("failed to create notification socket")?;
    sender
        .set_nonblocking(true)
        .context("failed to make notification socket nonblocking")?;
    for entry in fs::read_dir(&directory)
        .with_context(|| format!("failed to read {}", directory.display()))?
    {
        let entry = match entry {
            Ok(entry) => entry,
            Err(_) => continue,
        };
        let path = entry.path();
        if path.extension().and_then(|extension| extension.to_str()) != Some("sock") {
            continue;
        }
        match sender.send_to(&[1], &path) {
            Err(error)
                if matches!(
                    error.kind(),
                    io::ErrorKind::NotFound | io::ErrorKind::ConnectionRefused
                ) =>
            {
                let _ = fs::remove_file(path);
            }
            _ => {}
        }
    }
    Ok(())
}

fn new_session_name_argument(name: &str) -> Result<String> {
    if name.len() > MAX_SESSION_NAME_BYTES {
        bail!("tmux session name exceeds {MAX_SESSION_NAME_BYTES} bytes");
    }
    Ok(name.replace('#', "##"))
}

pub fn spawn_managed(config: &Config, mode: AttachMode) -> Result<ManagedChild> {
    let mut command = Command::new(&config.tmux_command);
    match mode {
        AttachMode::Existing(target) => {
            if !valid_session_id(&target.id) {
                bail!("invalid tmux session ID");
            }
            let condition = [
                "#{&&:#{==:#{start_time},",
                &target.server_started_at.to_string(),
                "},#{==:#{session_created},",
                &target.created_at.to_string(),
                "}}",
            ]
            .concat();
            let attach = format!("attach-session -t '{}'", target.id);
            command.args([
                "if-shell",
                "-F",
                "-t",
                &target.id,
                &condition,
                &attach,
                "detach-client -E 'exit 75'",
            ]);
        }
        AttachMode::New(name) => {
            command.arg("new-session");
            if let Some(name) = name {
                let name = new_session_name_argument(&name)?;
                command.args(["-s", &name]);
            }
        }
    }
    command.env("TMUX_FLEET_MANAGED", "1");
    let child = command
        .spawn()
        .with_context(|| format!("failed to run {}", config.tmux_command.display()))?;
    Ok(ManagedChild { child })
}

fn send_snapshot(config: &Config) -> Result<bool> {
    match snapshot(config) {
        Ok(snapshot) => write_wire(&WireMessage::Snapshot { snapshot }),
        Err(error) => write_wire(&WireMessage::Error {
            message: format!("{error:#}"),
            sent_at: unix_timestamp(),
        }),
    }
}

fn valid_session_id(value: &str) -> bool {
    value.strip_prefix('$').is_some_and(|digits| {
        !digits.is_empty() && digits.bytes().all(|byte| byte.is_ascii_digit())
    })
}

fn parse_session(line: &str) -> Result<(SessionInfo, u64)> {
    let fields = line.split(FIELD_SEPARATOR).collect::<Vec<_>>();
    if fields.len() != 7 {
        bail!(
            "unexpected tmux session record with {} fields",
            fields.len()
        );
    }
    if !valid_session_id(fields[0]) {
        bail!("invalid tmux session ID in snapshot");
    }
    Ok((
        SessionInfo {
            id: fields[0].to_owned(),
            name: fields[1].to_owned(),
            windows: fields[2].parse().context("invalid tmux window count")?,
            attached: fields[3].parse().context("invalid tmux attached count")?,
            created_at: fields[4].parse().context("invalid tmux creation time")?,
            activity_at: fields[5].parse().context("invalid tmux activity time")?,
        },
        fields[6]
            .parse()
            .context("invalid tmux server start time")?,
    ))
}

fn empty_snapshot() -> Snapshot {
    Snapshot {
        server_started_at: 0,
        hostname: runtime::short_hostname(),
        generated_at: unix_timestamp(),
        sessions: Vec::new(),
    }
}

struct WatcherSocket {
    socket: UnixDatagram,
    path: PathBuf,
}

impl WatcherSocket {
    fn bind() -> Result<Self> {
        let directory = runtime::watcher_dir()?;
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos();
        let path = directory.join(format!("watch-{}-{nonce}.sock", std::process::id()));
        let socket = UnixDatagram::bind(&path)
            .with_context(|| format!("failed to bind {}", path.display()))?;
        socket.set_read_timeout(Some(Duration::from_secs(1)))?;
        Ok(Self { socket, path })
    }
}

impl Drop for WatcherSocket {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    use crate::config::Config;
    use crate::protocol::MAX_SESSION_NAME_BYTES;

    use super::{
        new_session_name_argument, parse_session, spawn_managed, AttachMode, ExistingTarget,
    };

    #[test]
    fn parses_tmux_record_with_spaces_and_punctuation() {
        let record = "$3\u{1f}work ! now\u{1f}4\u{1f}1\u{1f}10\u{1f}20\u{1f}5";
        let (session, server_started_at) =
            parse_session(record).expect("valid tmux record should parse");
        assert_eq!(server_started_at, 5);
        assert_eq!(session.id, "$3");
        assert_eq!(session.name, "work ! now");
        assert_eq!(session.windows, 4);
        assert_eq!(session.attached, 1);
    }

    #[test]
    fn new_session_names_escape_tmux_format_sequences() {
        let name = "#(touch /tmp/pwned) #{session_name}";
        let argument = new_session_name_argument(name).expect("valid name should be escaped");
        assert_eq!(argument, "##(touch /tmp/pwned) ##{session_name}");
    }

    #[test]
    fn new_session_name_limit_matches_snapshot_validation() {
        let boundary = "x".repeat(MAX_SESSION_NAME_BYTES);
        assert_eq!(
            new_session_name_argument(&boundary).expect("boundary name should be accepted"),
            boundary
        );
        let oversized = "x".repeat(MAX_SESSION_NAME_BYTES + 1);
        assert!(new_session_name_argument(&oversized).is_err());
    }

    #[test]
    fn managed_attach_uses_one_atomic_identity_guard() {
        let (directory, executable, log) = fake_tmux(0);
        let config = Config {
            tmux_command: executable,
            ..Config::default()
        };

        let child = spawn_managed(
            &config,
            AttachMode::Existing(ExistingTarget {
                id: "$3".into(),
                server_started_at: 5,
                created_at: 10,
            }),
        )
        .expect("fake tmux should spawn");
        assert!(
            child.wait().expect("fake tmux should exit").success(),
            "fake tmux should succeed"
        );

        let arguments = fs::read_to_string(&log).expect("fake tmux should log arguments");
        assert_eq!(
            arguments,
            "if-shell\n-F\n-t\n$3\n#{&&:#{==:#{start_time},5},#{==:#{session_created},10}}\nattach-session -t '$3'\ndetach-client -E 'exit 75'\n"
        );
        fs::remove_dir_all(directory).expect("fake tmux directory should be removable");
    }

    #[test]
    fn managed_attach_propagates_the_atomic_stale_exit() {
        let (directory, executable, _) = fake_tmux(75);
        let config = Config {
            tmux_command: executable,
            ..Config::default()
        };
        let child = spawn_managed(
            &config,
            AttachMode::Existing(ExistingTarget {
                id: "$3".into(),
                server_started_at: 4,
                created_at: 10,
            }),
        )
        .expect("fake stale tmux should spawn");

        assert_eq!(
            child.wait().expect("fake stale tmux should exit").code(),
            Some(75)
        );
        fs::remove_dir_all(directory).expect("fake tmux directory should be removable");
    }

    fn fake_tmux(exit_status: i32) -> (PathBuf, PathBuf, PathBuf) {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should be after the Unix epoch")
            .as_nanos();
        let directory =
            std::env::temp_dir().join(format!("tmux-fleet-test-{}-{nonce}", std::process::id()));
        fs::create_dir(&directory).expect("fake tmux directory should be created");
        let executable = directory.join("tmux");
        let log = directory.join("arguments");
        fs::write(
            &executable,
            format!(
                "#!/bin/sh\nprintf '%s\\n' \"$@\" > {}\nexit {exit_status}\n",
                shell_single_quote(&log)
            ),
        )
        .expect("fake tmux executable should be written");
        fs::set_permissions(&executable, fs::Permissions::from_mode(0o700))
            .expect("fake tmux executable should become executable");
        (directory, executable, log)
    }

    fn shell_single_quote(path: &std::path::Path) -> String {
        format!("'{}'", path.to_string_lossy().replace('\'', "'\\''"))
    }
}
