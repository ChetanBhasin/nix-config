use std::io::Read;
use std::process::{Child, Command, ExitStatus, Output, Stdio};
use std::thread;

use anyhow::{bail, Context, Result};

use crate::config::Config;
use crate::protocol::{
    unix_timestamp, valid_session_id, SessionInfo, Snapshot, MAX_SESSION_NAME_BYTES,
    PROTOCOL_VERSION,
};
use crate::runtime;

const FIELD_SEPARATOR: char = '\u{1f}';
const SNAPSHOT_FORMAT: &str = "#{session_id}\u{1f}#{session_name}\u{1f}#{session_windows}\u{1f}#{session_attached}\u{1f}#{session_created}\u{1f}#{session_activity}\u{1f}#{pid}\u{1f}#{start_time}";
const MAX_SNAPSHOT_OUTPUT_BYTES: usize = 8 * 1024 * 1024;
const MAX_ERROR_OUTPUT_BYTES: usize = 64 * 1024;
pub const SWITCH_EXIT_CODE: i32 = 42;
pub const STALE_TARGET_EXIT_CODE: i32 = 75;

#[derive(Clone, Debug)]
pub struct ExistingTarget {
    pub id: String,
    pub server_pid: u64,
    pub server_started_at: u64,
    pub created_at: u64,
}

pub enum AttachMode {
    Existing(ExistingTarget),
    LatestOrNew,
    New(Option<String>),
}

pub struct ManagedChild {
    child: Child,
}

impl ManagedChild {
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
    let (server_pid, server_started_at) = records
        .first()
        .map(|(_, server_pid, server_started_at)| (*server_pid, *server_started_at))
        .unwrap_or_default();
    if records
        .iter()
        .any(|(_, pid, started_at)| *pid != server_pid || *started_at != server_started_at)
    {
        bail!("tmux server identity changed while collecting sessions");
    }
    let mut sessions = records
        .into_iter()
        .map(|(session, _, _)| session)
        .collect::<Vec<_>>();
    sessions.sort_by(|left, right| {
        right
            .activity_at
            .cmp(&left.activity_at)
            .then_with(|| left.name.cmp(&right.name))
    });

    Ok(Snapshot {
        protocol_version: PROTOCOL_VERSION,
        server_pid,
        server_started_at,
        hostname: runtime::short_hostname(),
        generated_at: unix_timestamp(),
        sessions,
    })
}

fn new_session_name_argument(name: &str) -> Result<String> {
    if name.len() > MAX_SESSION_NAME_BYTES {
        bail!("tmux session name exceeds {MAX_SESSION_NAME_BYTES} bytes");
    }
    if name.chars().any(char::is_control) {
        bail!("tmux session name cannot contain control characters");
    }
    // tmux expands #() and #{} even in direct argv; ## is the literal # escape.
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
                "#{&&:#{==:#{pid},",
                &target.server_pid.to_string(),
                "},#{&&:#{==:#{start_time},",
                &target.server_started_at.to_string(),
                "},#{==:#{session_created},",
                &target.created_at.to_string(),
                "}}}",
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
        AttachMode::LatestOrNew => {
            command.args([
                "start-server",
                ";",
                "if-shell",
                "-F",
                "#{>:#{server_sessions},0}",
                "attach-session",
                "new-session",
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
    spawn_managed_command(command, &config.tmux_command)
}

pub fn attach_latest_or_new(config: &Config) -> Result<ExitStatus> {
    spawn_managed(config, AttachMode::LatestOrNew)?.wait()
}

fn spawn_managed_command(
    mut command: Command,
    tmux_command: &std::path::Path,
) -> Result<ManagedChild> {
    command.env("TMUX_FLEET_MANAGED", "1");
    let child = command
        .spawn()
        .with_context(|| format!("failed to run {}", tmux_command.display()))?;
    Ok(ManagedChild { child })
}

fn parse_session(line: &str) -> Result<(SessionInfo, u64, u64)> {
    let (id, fields) = line
        .split_once(FIELD_SEPARATOR)
        .context("unexpected tmux session record without a session ID")?;
    if !valid_session_id(id) {
        bail!("invalid tmux session ID in snapshot");
    }
    let mut fields = fields.rsplitn(7, FIELD_SEPARATOR);
    let server_started_at = fields
        .next()
        .context("tmux session record is missing the server start time")?
        .parse()
        .context("invalid tmux server start time")?;
    let server_pid = fields
        .next()
        .context("tmux session record is missing the server PID")?
        .parse()
        .context("invalid tmux server PID")?;
    let activity_at = fields
        .next()
        .context("tmux session record is missing the activity time")?
        .parse()
        .context("invalid tmux activity time")?;
    let created_at = fields
        .next()
        .context("tmux session record is missing the creation time")?
        .parse()
        .context("invalid tmux creation time")?;
    let attached = fields
        .next()
        .context("tmux session record is missing the attached count")?
        .parse()
        .context("invalid tmux attached count")?;
    let windows = fields
        .next()
        .context("tmux session record is missing the window count")?
        .parse()
        .context("invalid tmux window count")?;
    let name = fields
        .next()
        .context("tmux session record is missing the session name")?;

    Ok((
        SessionInfo {
            id: id.to_owned(),
            name: name.to_owned(),
            windows,
            attached,
            created_at,
            activity_at,
        },
        server_pid,
        server_started_at,
    ))
}

fn empty_snapshot() -> Snapshot {
    Snapshot {
        protocol_version: PROTOCOL_VERSION,
        server_pid: 0,
        server_started_at: 0,
        hostname: runtime::short_hostname(),
        generated_at: unix_timestamp(),
        sessions: Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::os::unix::process::ExitStatusExt;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{Duration, SystemTime, UNIX_EPOCH};

    use crate::config::Config;
    use crate::protocol::MAX_SESSION_NAME_BYTES;

    use super::{
        attach_latest_or_new, new_session_name_argument, parse_session, snapshot, spawn_managed,
        AttachMode, ExistingTarget, SNAPSHOT_FORMAT, STALE_TARGET_EXIT_CODE, SWITCH_EXIT_CODE,
    };

    static TEST_NONCE: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn parses_tmux_record_when_name_contains_the_field_separator() {
        let record = "$3\u{1f}work ! \u{1f} now\u{1f}4\u{1f}1\u{1f}10\u{1f}20\u{1f}321\u{1f}5";
        let (session, server_pid, server_started_at) =
            parse_session(record).expect("valid tmux record should parse");
        assert_eq!(server_pid, 321);
        assert_eq!(server_started_at, 5);
        assert_eq!(session.id, "$3");
        assert_eq!(session.name, "work ! \u{1f} now");
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
    fn new_session_name_limit_is_enforced_before_creation() {
        let boundary = "x".repeat(MAX_SESSION_NAME_BYTES);
        assert_eq!(
            new_session_name_argument(&boundary).expect("boundary name should be accepted"),
            boundary
        );
        let oversized = "x".repeat(MAX_SESSION_NAME_BYTES + 1);
        assert!(new_session_name_argument(&oversized).is_err());
        assert!(new_session_name_argument("line\nbreak").is_err());
        assert!(new_session_name_argument("field\u{1f}separator").is_err());
    }

    #[test]
    fn managed_attach_uses_one_atomic_identity_guard() {
        let (directory, executable, log) = fake_tmux("exit 0");
        let config = Config {
            tmux_command: executable,
            ..Config::default()
        };
        let child = retry_text_file_busy(|| {
            spawn_managed(
                &config,
                AttachMode::Existing(ExistingTarget {
                    id: "$3".into(),
                    server_pid: 321,
                    server_started_at: 5,
                    created_at: 10,
                }),
            )
        })
        .expect("fake tmux should spawn");
        assert!(
            child.wait().expect("fake tmux should exit").success(),
            "fake tmux should succeed"
        );
        assert_eq!(
            fs::read_to_string(&log).expect("fake tmux should log arguments"),
            "if-shell\n-F\n-t\n$3\n#{&&:#{==:#{pid},321},#{&&:#{==:#{start_time},5},#{==:#{session_created},10}}}\nattach-session -t '$3'\ndetach-client -E 'exit 75'\n"
        );
        fs::remove_dir_all(directory).expect("fake tmux directory should be removable");
    }

    #[test]
    fn managed_attach_propagates_the_atomic_stale_exit() {
        let (directory, executable, _) = fake_tmux("exit 75");
        let config = Config {
            tmux_command: executable,
            ..Config::default()
        };
        let child = retry_text_file_busy(|| {
            spawn_managed(
                &config,
                AttachMode::Existing(ExistingTarget {
                    id: "$3".into(),
                    server_pid: 321,
                    server_started_at: 4,
                    created_at: 10,
                }),
            )
        })
        .expect("fake stale tmux should spawn");
        assert_eq!(
            child.wait().expect("fake stale tmux should exit").code(),
            Some(STALE_TARGET_EXIT_CODE)
        );
        fs::remove_dir_all(directory).expect("fake tmux directory should be removable");
    }

    #[test]
    fn latest_or_new_runs_one_atomic_queue_and_preserves_switch_status() {
        let (directory, executable, log) = fake_tmux("exit 42");
        let config = Config {
            tmux_command: executable,
            ..Config::default()
        };

        assert_eq!(
            retry_text_file_busy(|| attach_latest_or_new(&config))
                .expect("atomic attach-or-create should run")
                .code(),
            Some(SWITCH_EXIT_CODE)
        );
        assert_eq!(
            fs::read_to_string(&log).expect("fake tmux should log arguments"),
            "start-server\n;\nif-shell\n-F\n#{>:#{server_sessions},0}\nattach-session\nnew-session\n"
        );
        fs::remove_dir_all(directory).expect("fake tmux directory should be removable");
    }

    #[test]
    fn latest_or_new_propagates_nonzero_status() {
        let (directory, executable, log) = fake_tmux("exit 75");
        let config = Config {
            tmux_command: executable,
            ..Config::default()
        };

        let status = retry_text_file_busy(|| attach_latest_or_new(&config))
            .expect("atomic attach-or-create should return its child status");
        assert_eq!(status.code(), Some(STALE_TARGET_EXIT_CODE));
        assert_eq!(status.signal(), None);
        assert_eq!(
            fs::read_to_string(&log).expect("fake tmux should log arguments"),
            "start-server\n;\nif-shell\n-F\n#{>:#{server_sessions},0}\nattach-session\nnew-session\n"
        );
        fs::remove_dir_all(directory).expect("fake tmux directory should be removable");
    }

    #[test]
    fn latest_or_new_propagates_signal_status() {
        let (directory, executable, log) = fake_tmux("kill -TERM $$");
        let config = Config {
            tmux_command: executable,
            ..Config::default()
        };

        let status = retry_text_file_busy(|| attach_latest_or_new(&config))
            .expect("atomic attach-or-create should return its child status");
        assert_eq!(status.code(), None);
        assert_eq!(status.signal(), Some(15));
        assert_eq!(
            fs::read_to_string(&log).expect("fake tmux should log arguments"),
            "start-server\n;\nif-shell\n-F\n#{>:#{server_sessions},0}\nattach-session\nnew-session\n"
        );
        fs::remove_dir_all(directory).expect("fake tmux directory should be removable");
    }

    #[test]
    fn explicit_new_session_always_uses_new_session() {
        let (directory, executable, log) = fake_tmux("exit 0");
        let config = Config {
            tmux_command: executable,
            ..Config::default()
        };

        assert!(retry_text_file_busy(|| spawn_managed(
            &config,
            AttachMode::New(Some("fresh".into()))
        ))
        .expect("explicit new session should spawn")
        .wait()
        .expect("fake tmux should exit")
        .success());
        assert_eq!(
            fs::read_to_string(&log).expect("fake tmux should log arguments"),
            "new-session\n-s\nfresh\n"
        );
        fs::remove_dir_all(directory).expect("fake tmux directory should be removable");
    }

    #[test]
    fn snapshot_rejects_inconsistent_server_identity() {
        let (directory, executable, _) = fake_tmux(
            "printf '%s\\n' '$3\u{1f}first\u{1f}1\u{1f}0\u{1f}10\u{1f}20\u{1f}321\u{1f}5' '$4\u{1f}second\u{1f}1\u{1f}0\u{1f}11\u{1f}21\u{1f}322\u{1f}5'",
        );
        let config = Config {
            tmux_command: executable,
            ..Config::default()
        };

        let error = retry_text_file_busy(|| snapshot(&config))
            .expect_err("inconsistent tmux server identity must be rejected");
        assert!(
            error
                .to_string()
                .contains("tmux server identity changed while collecting sessions"),
            "unexpected error: {error:#}"
        );
        fs::remove_dir_all(directory).expect("fake tmux directory should be removable");
    }

    #[test]
    fn snapshot_recognizes_no_server_from_status_one_and_stderr() {
        let (directory, executable, log) =
            fake_tmux("printf '%s\\n' 'no server running on /tmp/tmux-1000/default' >&2\nexit 1");
        let config = Config {
            tmux_command: executable,
            ..Config::default()
        };

        let snapshot = retry_text_file_busy(|| snapshot(&config))
            .expect("no-server response should be an empty snapshot");
        assert_eq!(snapshot.server_pid, 0);
        assert_eq!(snapshot.server_started_at, 0);
        assert!(snapshot.sessions.is_empty());
        assert_eq!(
            fs::read_to_string(&log).expect("fake tmux should log arguments"),
            format!("list-sessions\n-F\n{SNAPSHOT_FORMAT}\n")
        );
        fs::remove_dir_all(directory).expect("fake tmux directory should be removable");
    }

    #[test]
    fn snapshot_reports_unrelated_list_failure() {
        let (directory, executable, log) =
            fake_tmux("printf '%s\\n' 'permission denied' >&2\nexit 1");
        let config = Config {
            tmux_command: executable,
            ..Config::default()
        };

        let error = retry_text_file_busy(|| snapshot(&config))
            .expect_err("unrelated list failure must propagate");
        assert!(
            error
                .to_string()
                .contains("tmux list-sessions failed: permission denied"),
            "unexpected error: {error:#}"
        );
        assert_eq!(
            fs::read_to_string(&log).expect("fake tmux should log arguments"),
            format!("list-sessions\n-F\n{SNAPSHOT_FORMAT}\n")
        );
        fs::remove_dir_all(directory).expect("fake tmux directory should be removable");
    }

    fn retry_text_file_busy<T>(
        mut operation: impl FnMut() -> anyhow::Result<T>,
    ) -> anyhow::Result<T> {
        for attempt in 0..20 {
            match operation() {
                Err(error) if text_file_busy(&error) && attempt < 19 => {
                    std::thread::sleep(Duration::from_millis(5));
                }
                result => return result,
            }
        }
        unreachable!("the bounded retry loop always returns");
    }

    fn text_file_busy(error: &anyhow::Error) -> bool {
        error.chain().any(|cause| {
            cause
                .downcast_ref::<std::io::Error>()
                .is_some_and(|io_error| io_error.raw_os_error() == Some(nix::libc::ETXTBSY))
        })
    }

    fn fake_tmux(body: &str) -> (PathBuf, PathBuf, PathBuf) {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should be after the Unix epoch")
            .as_nanos();
        let sequence = TEST_NONCE.fetch_add(1, Ordering::Relaxed);
        let test_root = std::env::current_exe()
            .expect("test executable path should be available")
            .parent()
            .expect("test executable should have a parent directory")
            .to_path_buf();
        let directory = test_root.join(format!(
            "tmux-fleet-test-{}-{nonce}-{sequence}",
            std::process::id()
        ));
        fs::create_dir(&directory).expect("fake tmux directory should be created");
        fs::set_permissions(&directory, fs::Permissions::from_mode(0o700))
            .expect("fake tmux directory should be private");
        let executable = directory.join("tmux");
        let log = directory.join("arguments");
        fs::write(
            &executable,
            format!(
                "#!/bin/sh\nprintf '%s\\n' \"$@\" >> {}\n{body}\n",
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
