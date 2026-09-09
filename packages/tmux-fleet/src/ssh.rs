use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use anyhow::{bail, Context, Result};

use crate::config::{validate_ssh_target, Config};
use crate::protocol::{validate_snapshot, Snapshot};
use crate::runtime;
use crate::tmux::ExistingTarget;

const REMOTE_SNAPSHOT_COMMAND: &str = "if [ ! -x \"$HOME/.local/libexec/tmux-fleet\" ]; then printf '%s\\n' 'tmux-fleet helper is not installed' >&2; exit 127; fi; exec \"$HOME/.local/libexec/tmux-fleet\" snapshot";
const REMOTE_NEW_COMMAND: &str = "exec \"$HOME/.local/libexec/tmux-fleet\" attach-new";
const MAX_REMOTE_SNAPSHOT_BYTES: usize = 2 * 1024 * 1024;
const MAX_REMOTE_ERROR_BYTES: usize = 64 * 1024;
const MASTER_CHECK_TIMEOUT: Duration = Duration::from_millis(500);
const INVENTORY_TIMEOUT: Duration = Duration::from_secs(2);
const MASTER_CLOSE_TIMEOUT: Duration = Duration::from_millis(750);

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum InventoryOutcome {
    Ready(Snapshot),
    Unsupported(String),
    Failed(String),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum MasterHealth {
    Alive,
    Missing,
    TimedOut,
}

#[derive(Clone, Debug)]
pub enum RemoteAttachMode {
    Existing(ExistingTarget),
    New,
}

pub fn bootstrap_command(config: &Config, target: &str, control_path: &Path) -> Result<Command> {
    validate_ssh_target(target)?;
    validate_control_path(control_path)?;
    let mut command = Command::new(&config.ssh_command);
    command.args([
        "-M",
        "-S",
        control_path
            .to_str()
            .context("SSH control path is not valid UTF-8")?,
        "-o",
        "ControlMaster=yes",
        "-o",
        "ControlPersist=yes",
        "-o",
        "ClearAllForwardings=yes",
        "-o",
        "ExitOnForwardFailure=yes",
        "-o",
        "ServerAliveInterval=15",
        "-o",
        "ServerAliveCountMax=2",
        "-o",
        "ConnectTimeout=10",
        "-o",
        "RemoteCommand=none",
        "-T",
        "--",
        target,
        "true",
    ]);
    Ok(command)
}

pub fn master_health(config: &Config, target: &str, control_path: &Path) -> Result<MasterHealth> {
    let mut command = mux_command(config, target, control_path)?;
    command.args(["-O", "check", "--", target]);
    let output = capture_with_timeout(
        command,
        MASTER_CHECK_TIMEOUT,
        MAX_REMOTE_ERROR_BYTES,
        MAX_REMOTE_ERROR_BYTES,
    )?;
    if output.timed_out {
        Ok(MasterHealth::TimedOut)
    } else if output.output.status.success() {
        Ok(MasterHealth::Alive)
    } else {
        Ok(MasterHealth::Missing)
    }
}

pub fn inventory(config: &Config, target: &str, control_path: &Path) -> InventoryOutcome {
    match inventory_inner(config, target, control_path) {
        Ok(outcome) => outcome,
        Err(error) => InventoryOutcome::Failed(format!("{error:#}")),
    }
}

fn inventory_inner(config: &Config, target: &str, control_path: &Path) -> Result<InventoryOutcome> {
    let mut command = mux_command(config, target, control_path)?;
    command.args(["-T", "--", target, REMOTE_SNAPSHOT_COMMAND]);
    let output = capture_with_timeout(
        command,
        INVENTORY_TIMEOUT,
        MAX_REMOTE_SNAPSHOT_BYTES,
        MAX_REMOTE_ERROR_BYTES,
    )?;
    if output.timed_out {
        return Ok(InventoryOutcome::Failed(
            "remote session inventory timed out".into(),
        ));
    }
    let stderr = String::from_utf8_lossy(&output.output.stderr)
        .trim()
        .to_owned();
    if output.output.status.code() == Some(127) {
        return Ok(InventoryOutcome::Unsupported(if stderr.is_empty() {
            "tmux-fleet helper is not installed on the remote host".into()
        } else {
            stderr
        }));
    }
    if !output.output.status.success() {
        return Ok(InventoryOutcome::Failed(if stderr.is_empty() {
            format!(
                "remote session inventory exited with status {}",
                output.output.status.code().unwrap_or(128)
            )
        } else {
            stderr
        }));
    }
    let snapshot: Snapshot = serde_json::from_slice(&output.output.stdout)
        .context("remote helper returned invalid JSON")?;
    validate_snapshot(&snapshot)?;
    Ok(InventoryOutcome::Ready(snapshot))
}

pub fn attach_command(
    config: &Config,
    target: &str,
    control_path: &Path,
    mode: RemoteAttachMode,
) -> Result<Command> {
    let remote_command = match mode {
        RemoteAttachMode::Existing(existing) => remote_existing_command(&existing)?,
        RemoteAttachMode::New => REMOTE_NEW_COMMAND.to_owned(),
    };
    let mut command = mux_command(config, target, control_path)?;
    command.args(["-tt", "--", target, &remote_command]);
    Ok(command)
}

pub fn close_master(config: &Config, target: &str, control_path: &Path) -> Result<()> {
    let mut command = mux_command(config, target, control_path)?;
    command.args(["-O", "exit", "--", target]);
    let output = capture_with_timeout(
        command,
        MASTER_CLOSE_TIMEOUT,
        MAX_REMOTE_ERROR_BYTES,
        MAX_REMOTE_ERROR_BYTES,
    )?;
    if output.timed_out {
        bail!("timed out while closing SSH master for {target}");
    }
    if !output.output.status.success() {
        let stderr = String::from_utf8_lossy(&output.output.stderr);
        bail!("failed to close SSH master for {target}: {}", stderr.trim());
    }
    Ok(())
}

fn mux_command(config: &Config, target: &str, control_path: &Path) -> Result<Command> {
    validate_ssh_target(target)?;
    validate_control_path(control_path)?;
    let path = control_path
        .to_str()
        .context("SSH control path is not valid UTF-8")?;
    let false_command = config
        .false_command
        .to_str()
        .context("false command path is not valid UTF-8")?;
    let mut command = Command::new(&config.ssh_command);
    command.args([
        "-S",
        path,
        "-o",
        "ControlMaster=no",
        "-o",
        "ControlPersist=no",
        "-o",
        "BatchMode=yes",
        "-o",
        "NumberOfPasswordPrompts=0",
        "-o",
        "ClearAllForwardings=yes",
        "-o",
        &format!("ProxyCommand={false_command}"),
        "-o",
        "ConnectionAttempts=1",
    ]);
    Ok(command)
}

fn remote_existing_command(existing: &ExistingTarget) -> Result<String> {
    if !crate::protocol::valid_session_id(&existing.id) {
        bail!("invalid tmux session ID");
    }
    Ok(format!(
        "exec \"$HOME/.local/libexec/tmux-fleet\" attach-existing --id '{}' --server-pid {} --server-started-at {} --created-at {}",
        existing.id,
        existing.server_pid,
        existing.server_started_at,
        existing.created_at
    ))
}

fn validate_control_path(control_path: &Path) -> Result<()> {
    let root = runtime::runtime_root()?.join("masters");
    let parent = control_path
        .parent()
        .context("SSH control path has no parent")?;
    if parent != root {
        bail!("SSH control path is outside tmux-fleet's private master directory");
    }
    let name = control_path
        .file_name()
        .and_then(|name| name.to_str())
        .context("SSH control path has an invalid file name")?;
    let token = name
        .strip_prefix("cm-")
        .context("SSH control path has an invalid prefix")?;
    if token.len() != 32 || !token.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("SSH control path has an invalid connection token");
    }
    Ok(())
}

struct TimedOutput {
    output: Output,
    timed_out: bool,
}

fn capture_with_timeout(
    mut command: Command,
    timeout: Duration,
    stdout_limit: usize,
    stderr_limit: usize,
) -> Result<TimedOutput> {
    let program = PathBuf::from(command.get_program());
    let mut child = command
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("failed to run {}", program.display()))?;
    let stdout = child
        .stdout
        .take()
        .context("failed to capture SSH stdout")?;
    let stderr = child
        .stderr
        .take()
        .context("failed to capture SSH stderr")?;
    let stdout_thread = thread::spawn(move || read_capped(stdout, stdout_limit, "stdout"));
    let stderr_thread = thread::spawn(move || read_capped(stderr, stderr_limit, "stderr"));
    let started = Instant::now();
    let (status, timed_out) = loop {
        if let Some(status) = child.try_wait().context("failed to wait for SSH")? {
            break (status, false);
        }
        if started.elapsed() >= timeout {
            let _ = child.kill();
            break (
                child
                    .wait()
                    .context("failed to reap timed-out SSH process")?,
                true,
            );
        }
        thread::sleep(Duration::from_millis(20));
    };
    let stdout = stdout_thread
        .join()
        .map_err(|_| anyhow::anyhow!("SSH stdout reader panicked"))??;
    let stderr = stderr_thread
        .join()
        .map_err(|_| anyhow::anyhow!("SSH stderr reader panicked"))??;
    Ok(TimedOutput {
        output: Output {
            status,
            stdout,
            stderr,
        },
        timed_out,
    })
}

fn read_capped(mut reader: impl Read, limit: usize, stream: &'static str) -> Result<Vec<u8>> {
    let mut output = Vec::with_capacity(limit.min(8 * 1024));
    let mut buffer = [0_u8; 8 * 1024];
    loop {
        let count = reader
            .read(&mut buffer)
            .with_context(|| format!("failed to read SSH {stream}"))?;
        if count == 0 {
            return Ok(output);
        }
        if output.len().saturating_add(count) > limit {
            bail!("SSH {stream} exceeded the {limit}-byte safety limit");
        }
        output.extend_from_slice(&buffer[..count]);
    }
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;
    use std::process::Command;

    use crate::config::Config;
    use crate::tmux::ExistingTarget;

    use super::{attach_command, bootstrap_command, remote_existing_command, RemoteAttachMode};

    #[test]
    fn bootstrap_preserves_interactive_auth_and_clears_forwards() {
        let config = Config::default();
        let path = control_path();
        let command = bootstrap_command(&config, "chetan@example.internal", &path)
            .expect("valid bootstrap command should build");
        let arguments = arguments(&command);
        assert!(arguments
            .windows(2)
            .any(|pair| pair == ["-o", "ControlMaster=yes"]));
        assert!(arguments
            .windows(2)
            .any(|pair| pair == ["-o", "ControlPersist=yes"]));
        assert!(arguments
            .windows(2)
            .any(|pair| pair == ["-o", "ClearAllForwardings=yes"]));
        assert!(!arguments.iter().any(|argument| argument == "BatchMode=yes"));
        assert!(arguments.ends_with(&[
            "-T".into(),
            "--".into(),
            "chetan@example.internal".into(),
            "true".into(),
        ]));
    }

    #[test]
    fn mux_attach_is_fail_closed_and_keeps_target_out_of_shell_text() {
        let config = Config::default();
        let path = control_path();
        let existing = ExistingTarget {
            id: "$17".into(),
            server_pid: 7,
            server_started_at: 11,
            created_at: 13,
        };
        let command = attach_command(&config, "hugh", &path, RemoteAttachMode::Existing(existing))
            .expect("valid attach command should build");
        let arguments = arguments(&command);
        assert!(arguments
            .windows(2)
            .any(|pair| pair[0] == "-o" && pair[1].starts_with("ProxyCommand=")));
        assert!(arguments
            .windows(2)
            .any(|pair| pair == ["-o", "BatchMode=yes"]));
        assert_eq!(arguments[arguments.len() - 2], "hugh");
        assert!(!arguments
            .last()
            .expect("remote command should exist")
            .contains("hugh"));
    }

    #[test]
    fn remote_existing_command_accepts_only_bounded_canonical_id() {
        let valid = ExistingTarget {
            id: "$1".into(),
            server_pid: 2,
            server_started_at: 3,
            created_at: 4,
        };
        assert!(remote_existing_command(&valid)
            .expect("valid identity should build")
            .contains("--id '$1'"));
        let invalid = ExistingTarget {
            id: "$999999999999999999999".into(),
            ..valid
        };
        assert!(remote_existing_command(&invalid).is_err());
    }

    #[test]
    fn invalid_target_and_control_path_are_rejected() {
        assert!(
            bootstrap_command(&Config::default(), "-oProxyCommand=bad", &control_path()).is_err()
        );
        assert!(bootstrap_command(
            &Config::default(),
            "hugh",
            PathBuf::from("/tmp/outside/cm-00000000000000000000000000000000").as_path(),
        )
        .is_err());
    }

    fn control_path() -> PathBuf {
        crate::runtime::runtime_root()
            .expect("runtime root should be available")
            .join("masters/cm-0123456789abcdef0123456789abcdef")
    }

    fn arguments(command: &Command) -> Vec<String> {
        command
            .get_args()
            .map(|argument| argument.to_string_lossy().into_owned())
            .collect()
    }
}
