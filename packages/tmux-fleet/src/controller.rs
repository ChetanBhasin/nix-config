use std::ffi::OsString;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};

use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};

use crate::config::{validate_ssh_target, Config};
use crate::daemon;
use crate::protocol::{
    DaemonReply, DaemonRequest, RemoteHost, RemoteState, Snapshot, MAX_SESSION_NAME_BYTES,
};
use crate::ssh::{self, RemoteAttachMode};
use crate::tmux::{self, AttachMode, ExistingTarget, STALE_TARGET_EXIT_CODE, SWITCH_EXIT_CODE};

const SSH_FAILURE_EXIT_CODE: i32 = 255;

const PICKER_ARGUMENTS: &[&str] = &[
    "--delimiter=\t",
    "--with-nth=2..",
    "--no-height",
    "--padding=1,2",
    "--margin=12%,8%",
    "--layout=reverse",
    "--border=rounded",
    "--info=inline-right",
    "--no-multi",
    "--cycle",
    "--prompt=Sessions › ",
    "--header=Enter attach/connect · Esc quit · typing filters every displayed host/session",
    "--color=bg:#1d2021,bg+:#3c3836,fg:#d0c0a0,fg+:#ebdbb2,hl:#84a9b2,hl+:#c9a257,prompt:#c9a257,pointer:#c9a257,marker:#84a9b2,spinner:#84a9b2,border:#504945,header:#96918a,info:#7c6f64",
];
#[derive(Debug, Eq, PartialEq)]
enum RemoteExit {
    ManagedSwitch,
    Detached,
    StaleTarget,
    ConnectionFailure,
    Other(i32),
}

struct Model {
    local_name: String,
    local: Snapshot,
    remote_hosts: Vec<RemoteHost>,
    daemon_error: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "action", rename_all = "snake_case")]
enum Target {
    LocalSession {
        id: String,
        name: String,
        server_pid: u64,
        server_started_at: u64,
        created_at: u64,
    },
    NewLocal,
    RemoteSession {
        ssh_target: String,
        connection_id: String,
        epoch: u64,
        id: String,
        name: String,
        server_pid: u64,
        server_started_at: u64,
        created_at: u64,
    },
    NewRemote {
        ssh_target: String,
        connection_id: String,
        epoch: u64,
    },
    ReconnectSsh {
        target: String,
    },
    RemoteStatus {
        target: String,
        message: String,
    },
    ConnectSsh,
}

pub fn run(config: Config) -> Result<()> {
    if tmux_client_is_active(std::env::var_os("TMUX")) {
        bail!("tmux-fleet must start in a terminal outside tmux; use Prefix S from a tmux client");
    }

    let mut model = Model::load(&config)?;

    loop {
        model.refresh(&config)?;
        let Some(target) = run_picker(&config, &model)? else {
            break;
        };

        match target {
            Target::LocalSession {
                id,
                name: _,
                server_pid,
                server_started_at,
                created_at,
            } => match wait_local(
                &config,
                AttachMode::Existing(ExistingTarget {
                    id,
                    server_pid,
                    server_started_at,
                    created_at,
                }),
            )? {
                SWITCH_EXIT_CODE => {}
                STALE_TARGET_EXIT_CODE => {
                    eprintln!("That local session changed since it was listed; refreshing.");
                }
                0 => break,
                code => {
                    eprintln!("Local tmux exited with status {code}; returning to the picker.");
                }
            },
            Target::NewLocal => {
                let Some(name) = prompt_session_name("local")? else {
                    continue;
                };
                match wait_local(&config, AttachMode::New(name))? {
                    SWITCH_EXIT_CODE => {}
                    0 => break,
                    code => {
                        eprintln!("Local tmux exited with status {code}; returning to the picker.");
                    }
                }
            }
            Target::RemoteSession {
                ssh_target,
                connection_id,
                epoch,
                id,
                name,
                server_pid,
                server_started_at,
                created_at,
            } => {
                if let Err(error) = run_remote_target(
                    &config,
                    &ssh_target,
                    &connection_id,
                    epoch,
                    RemoteAttachMode::Existing(ExistingTarget {
                        id,
                        server_pid,
                        server_started_at,
                        created_at,
                    }),
                    &name,
                ) {
                    eprintln!("Could not attach remote session: {error:#}");
                }
            }
            Target::NewRemote {
                ssh_target,
                connection_id,
                epoch,
            } => {
                if let Err(error) = run_remote_target(
                    &config,
                    &ssh_target,
                    &connection_id,
                    epoch,
                    RemoteAttachMode::New,
                    &ssh_target,
                ) {
                    eprintln!("Could not create remote session: {error:#}");
                }
            }
            Target::ReconnectSsh { target } => {
                if let Err(error) = connect_remote(&config, &target) {
                    eprintln!("Could not connect to {target}: {error:#}");
                }
            }
            Target::RemoteStatus { message, .. } => {
                eprintln!("{message}");
            }
            Target::ConnectSsh => {
                let Some(target) = prompt_ssh_target()? else {
                    continue;
                };
                if let Err(error) = connect_remote(&config, &target) {
                    eprintln!("Could not connect to {target}: {error:#}");
                }
            }
        }
    }
    Ok(())
}

fn tmux_client_is_active(value: Option<OsString>) -> bool {
    value.is_some_and(|value| !value.is_empty())
}

impl Model {
    fn load(config: &Config) -> Result<Self> {
        Ok(Self {
            local_name: crate::runtime::short_hostname(),
            local: tmux::snapshot(config)?,
            remote_hosts: Vec::new(),
            daemon_error: None,
        })
    }

    fn refresh(&mut self, config: &Config) -> Result<()> {
        self.local = tmux::snapshot(config)?;
        match daemon::request(DaemonRequest::List) {
            Ok(DaemonReply::Hosts { hosts }) => {
                self.remote_hosts = hosts;
                self.daemon_error = None;
            }
            Ok(DaemonReply::Error { message, .. }) => {
                self.remote_hosts.clear();
                self.daemon_error = Some(message);
            }
            Ok(_) => {
                self.remote_hosts.clear();
                self.daemon_error = Some("daemon returned an unexpected response".into());
            }
            Err(error) => {
                self.remote_hosts.clear();
                self.daemon_error = Some(format!("tmux-fleet daemon unavailable: {error:#}"));
            }
        }
        Ok(())
    }

    fn rows(&self) -> Result<String> {
        let mut rows = Vec::new();
        for session in &self.local.sessions {
            rows.push(candidate_line(
                &Target::LocalSession {
                    id: session.id.clone(),
                    name: session.name.clone(),
                    server_pid: self.local.server_pid,
                    server_started_at: self.local.server_started_at,
                    created_at: session.created_at,
                },
                &format!(
                    "●  LOCAL  {:<18}  {:<24}  {}{}",
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
                "＋ LOCAL  {:<18}  new session",
                clean_field(&self.local_name)
            ),
        )?);

        for host in &self.remote_hosts {
            match host.state {
                RemoteState::Ready => {
                    let host_label = host
                        .hostname
                        .as_deref()
                        .filter(|hostname| *hostname != host.target)
                        .map_or_else(
                            || clean_field(&host.target),
                            |hostname| {
                                format!("{} ({})", clean_field(&host.target), clean_field(hostname))
                            },
                        );
                    let Some(connection_id) = host.connection_id.as_deref() else {
                        rows.push(remote_status_row(
                            &host.target,
                            "Connected host has no connection identity",
                        )?);
                        continue;
                    };
                    for session in &host.sessions {
                        rows.push(candidate_line(
                            &Target::RemoteSession {
                                ssh_target: host.target.clone(),
                                connection_id: connection_id.to_owned(),
                                epoch: host.epoch,
                                id: session.id.clone(),
                                name: session.name.clone(),
                                server_pid: host.server_pid,
                                server_started_at: host.server_started_at,
                                created_at: session.created_at,
                            },
                            &format!(
                                "●  SSH    {:<18}  {:<24}  {}{}",
                                host_label,
                                clean_field(&session.name),
                                window_label(session.windows),
                                attached_label(session.attached)
                            ),
                        )?);
                    }
                    rows.push(candidate_line(
                        &Target::NewRemote {
                            ssh_target: host.target.clone(),
                            connection_id: connection_id.to_owned(),
                            epoch: host.epoch,
                        },
                        &format!("＋ SSH    {:<18}  new remote session", host_label),
                    )?);
                }
                RemoteState::Disconnected => {
                    rows.push(candidate_line(
                        &Target::ReconnectSsh {
                            target: host.target.clone(),
                        },
                        &format!(
                            "↻  SSH    {:<18}  connect{}",
                            clean_field(&host.target),
                            optional_message(host.message.as_deref())
                        ),
                    )?);
                }
                RemoteState::Connecting => {
                    rows.push(remote_status_row(
                        &host.target,
                        host.message
                            .as_deref()
                            .unwrap_or("SSH authentication is already in progress"),
                    )?);
                }
                RemoteState::Degraded | RemoteState::Unsupported => {
                    rows.push(remote_status_row(
                        &host.target,
                        host.message
                            .as_deref()
                            .unwrap_or("remote session inventory is unavailable"),
                    )?);
                }
            }
        }

        if let Some(error) = &self.daemon_error {
            rows.push(remote_status_row("", error)?);
        }
        rows.push(candidate_line(
            &Target::ConnectSsh,
            "＋ SSH                       connect another [user@]host or address…",
        )?);
        Ok(format!("{}\n", rows.join("\n")))
    }
}

fn remote_status_row(target: &str, message: &str) -> Result<String> {
    candidate_line(
        &Target::RemoteStatus {
            target: target.to_owned(),
            message: clean_field(message),
        },
        &format!(
            "!  SSH    {:<18}  {}",
            clean_field(target),
            clean_field(message)
        ),
    )
}

fn optional_message(message: Option<&str>) -> String {
    message
        .map(|message| format!(" · {}", clean_field(message)))
        .unwrap_or_default()
}

fn connect_remote(config: &Config, target: &str) -> Result<()> {
    eprintln!("Connecting to {target}…");
    let reply = daemon::request(DaemonRequest::BeginConnect {
        target: target.to_owned(),
    })?;
    let (connection_id, control_path) = match reply {
        DaemonReply::ConnectPlan {
            target: returned_target,
            connection_id,
            control_path,
        } if returned_target == target => (connection_id, PathBuf::from(control_path)),
        DaemonReply::Error { message, .. } => bail!("{message}"),
        _ => bail!("daemon returned an invalid SSH connection plan"),
    };

    let status =
        match ssh::bootstrap_command(config, target, &control_path).and_then(|mut command| {
            command
                .status()
                .with_context(|| format!("failed to run {}", config.ssh_command.display()))
        }) {
            Ok(status) => status,
            Err(error) => {
                let _ = daemon::request(DaemonRequest::AbortConnect {
                    target: target.to_owned(),
                    connection_id: connection_id.clone(),
                });
                return Err(error);
            }
        };
    if !status.success() {
        let _ = daemon::request(DaemonRequest::AbortConnect {
            target: target.to_owned(),
            connection_id,
        });
        bail!(
            "interactive SSH authentication exited with status {}",
            exit_code(status.code())
        );
    }

    let commit = daemon::request(DaemonRequest::CommitConnect {
        target: target.to_owned(),
        connection_id: connection_id.clone(),
    });
    match commit {
        Ok(DaemonReply::Ack) => {
            eprintln!("Connected to {target}; loading its tmux sessions.");
            Ok(())
        }
        Ok(DaemonReply::Error { message, .. }) => {
            let _ = ssh::close_master(config, target, &control_path);
            let _ = daemon::request(DaemonRequest::AbortConnect {
                target: target.to_owned(),
                connection_id,
            });
            bail!("{message}")
        }
        Ok(_) => {
            let _ = ssh::close_master(config, target, &control_path);
            let _ = daemon::request(DaemonRequest::AbortConnect {
                target: target.to_owned(),
                connection_id,
            });
            bail!("daemon returned an invalid SSH commit response")
        }
        Err(error) => {
            let _ = ssh::close_master(config, target, &control_path);
            let _ = daemon::request(DaemonRequest::AbortConnect {
                target: target.to_owned(),
                connection_id,
            });
            bail!("could not commit SSH connection: {error:#}")
        }
    }
}

fn run_remote_target(
    config: &Config,
    target: &str,
    connection_id: &str,
    epoch: u64,
    mode: RemoteAttachMode,
    selection_name: &str,
) -> Result<()> {
    let reply = daemon::request(DaemonRequest::PrepareAttach {
        target: target.to_owned(),
        connection_id: connection_id.to_owned(),
        epoch,
    })?;
    let control_path = match reply {
        DaemonReply::AttachPlan {
            target: returned_target,
            connection_id: returned_id,
            epoch: returned_epoch,
            control_path,
        } if returned_target == target
            && returned_id == connection_id
            && returned_epoch == epoch =>
        {
            PathBuf::from(control_path)
        }
        DaemonReply::Error { message, .. } => bail!("{message}"),
        _ => bail!("daemon returned an invalid remote attachment plan"),
    };

    let status = ssh::attach_command(config, target, &control_path, mode)?
        .status()
        .with_context(|| format!("failed to run {}", config.ssh_command.display()))?;
    let code = exit_code(status.code());
    match classify_remote_exit(code) {
        RemoteExit::ManagedSwitch => {}
        RemoteExit::Detached => eprintln!("Detached from {target}; returning to the picker."),
        RemoteExit::StaleTarget => {
            eprintln!("Remote session {selection_name:?} changed since it was listed; refreshing.")
        }
        RemoteExit::ConnectionFailure => {
            eprintln!("SSH connection to {target} was lost; reconnect from the picker.");
        }
        RemoteExit::Other(code) => {
            eprintln!(
                "Remote tmux on {target} exited with status {code}; returning to the picker."
            );
        }
    }
    Ok(())
}

fn classify_remote_exit(code: i32) -> RemoteExit {
    match code {
        SWITCH_EXIT_CODE => RemoteExit::ManagedSwitch,
        0 => RemoteExit::Detached,
        STALE_TARGET_EXIT_CODE => RemoteExit::StaleTarget,
        SSH_FAILURE_EXIT_CODE => RemoteExit::ConnectionFailure,
        code => RemoteExit::Other(code),
    }
}

fn run_picker(config: &Config, model: &Model) -> Result<Option<Target>> {
    let rows = model.rows()?;

    let mut command = Command::new(&config.fzf_command);
    command
        .args(PICKER_ARGUMENTS)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .env_remove("FZF_DEFAULT_COMMAND")
        .env_remove("FZF_DEFAULT_OPTS")
        .env_remove("FZF_DEFAULT_OPTS_FILE");
    let mut child = command
        .spawn()
        .with_context(|| format!("failed to run {}", config.fzf_command.display()))?;
    let write_result = child
        .stdin
        .take()
        .context("fzf stdin was not available")
        .and_then(|mut input| {
            input
                .write_all(rows.as_bytes())
                .context("failed to send picker candidates to fzf")
        });
    if let Err(error) = write_result {
        let _ = child.kill();
        let _ = child.wait();
        return Err(error);
    }
    let output = child.wait_with_output().context("failed to wait for fzf")?;
    parse_picker_output(output)
}

fn parse_picker_output(output: Output) -> Result<Option<Target>> {
    match output.status.code() {
        Some(0) => {}
        Some(1 | 130) => return Ok(None),
        Some(code) => bail!("fzf exited with status {code}"),
        None => bail!("fzf terminated by signal"),
    }

    let stdout = String::from_utf8(output.stdout).context("fzf emitted non-UTF-8 output")?;
    let selected = stdout.trim_end_matches(['\r', '\n']);
    if selected.is_empty() {
        return Ok(None);
    }
    let (json, _) = selected
        .split_once('\t')
        .context("fzf selection did not include a target payload")?;
    serde_json::from_str(json)
        .map(Some)
        .context("fzf selection contained an invalid target payload")
}

fn wait_local(config: &Config, mode: AttachMode) -> Result<i32> {
    let child = tmux::spawn_managed(config, mode)?;
    Ok(exit_code(child.wait()?.code()))
}

fn prompt_session_name(host: &str) -> Result<Option<Option<String>>> {
    eprint!("New session name on {host} (blank for tmux default): ");
    io::stderr().flush()?;
    let mut name = String::new();
    if io::stdin().read_line(&mut name)? == 0 {
        return Ok(None);
    }
    let name = name.trim_end_matches(['\r', '\n']);
    if name.len() > MAX_SESSION_NAME_BYTES {
        bail!("session name exceeds the {MAX_SESSION_NAME_BYTES}-byte safety limit");
    }
    Ok(Some((!name.is_empty()).then(|| name.to_owned())))
}

fn prompt_ssh_target() -> Result<Option<String>> {
    loop {
        eprint!("SSH target ([user@]host or address): ");
        io::stderr().flush()?;
        let mut target = String::new();
        if io::stdin().read_line(&mut target)? == 0 {
            return Ok(None);
        }
        let target = target.trim_end_matches(['\r', '\n']);
        match validate_ssh_target(target) {
            Ok(()) => return Ok(Some(target.to_owned())),
            Err(error) => eprintln!("{error:#}"),
        }
    }
}

fn candidate_line(target: &Target, display: &str) -> Result<String> {
    Ok(format!("{}\t{display}", serde_json::to_string(target)?))
}

fn clean_field(value: &str) -> String {
    value
        .chars()
        .map(|character| {
            if character.is_control() {
                ' '
            } else {
                character
            }
        })
        .collect()
}

fn window_label(windows: u32) -> String {
    format!(
        "{windows} {}",
        if windows == 1 { "window" } else { "windows" }
    )
}

fn attached_label(attached: u32) -> String {
    if attached == 0 {
        String::new()
    } else {
        format!(" · {attached} attached")
    }
}

fn exit_code(code: Option<i32>) -> i32 {
    code.unwrap_or(128)
}

#[cfg(test)]
mod tests {
    use crate::protocol::{RemoteHost, RemoteState, SessionInfo, Snapshot, PROTOCOL_VERSION};

    use super::{
        classify_remote_exit, parse_picker_output, tmux_client_is_active, Model, RemoteExit,
        Target, PICKER_ARGUMENTS,
    };

    #[test]
    fn detached_tmux_client_environment_can_start_the_picker() {
        assert!(!tmux_client_is_active(Some(std::ffi::OsString::new())));
        assert!(tmux_client_is_active(Some(std::ffi::OsString::from(
            "/tmp/tmux",
        ))));
    }

    #[test]
    fn picker_is_centered_unfiltered_and_matches_visible_columns() {
        assert!(PICKER_ARGUMENTS.contains(&"--no-height"));
        assert!(PICKER_ARGUMENTS.contains(&"--margin=12%,8%"));
        assert!(PICKER_ARGUMENTS.contains(&"--with-nth=2.."));
        assert!(!PICKER_ARGUMENTS.contains(&"--disabled"));
        assert!(!PICKER_ARGUMENTS
            .iter()
            .any(|argument| argument.starts_with("--nth=")));
        assert!(!PICKER_ARGUMENTS
            .iter()
            .any(|argument| argument.starts_with("--query")));
    }

    #[test]
    fn picker_rows_include_local_all_connected_remotes_and_one_disconnected_reconnect() {
        let model = Model {
            local_name: "local".into(),
            local: snapshot("local", 7, 11, vec![session("$1", "local-work", 12)]),
            remote_hosts: vec![
                RemoteHost {
                    target: "hugh".into(),
                    state: RemoteState::Ready,
                    connection_id: Some("0123456789abcdef0123456789abcdef".into()),
                    epoch: 3,
                    hostname: Some("hugh-mini".into()),
                    server_pid: 17,
                    server_started_at: 19,
                    sessions: vec![session("$2", "remote-work", 20)],
                    message: None,
                },
                RemoteHost {
                    target: "markus".into(),
                    state: RemoteState::Ready,
                    connection_id: Some("fedcba9876543210fedcba9876543210".into()),
                    epoch: 5,
                    hostname: Some("markus-mini".into()),
                    server_pid: 23,
                    server_started_at: 29,
                    sessions: vec![session("$3", "second-remote-work", 30)],
                    message: None,
                },
                RemoteHost {
                    target: "boris".into(),
                    state: RemoteState::Disconnected,
                    connection_id: None,
                    epoch: 0,
                    hostname: None,
                    server_pid: 0,
                    server_started_at: 0,
                    sessions: Vec::new(),
                    message: Some("not connected".into()),
                },
            ],
            daemon_error: None,
        };
        let rows = model.rows().expect("test model should render rows");
        assert!(rows.contains("local-work"));
        assert!(rows.contains("remote-work"));
        assert!(rows.contains("hugh-mini"));
        assert!(rows.contains("second-remote-work"));
        assert!(rows.contains("markus-mini"));
        assert_eq!(rows.matches("\"action\":\"reconnect_ssh\"").count(), 1);
        assert_eq!(rows.matches("\"action\":\"remote_session\"").count(), 2);
    }

    #[test]
    fn picker_output_round_trips_remote_session_identity() {
        let target = Target::RemoteSession {
            ssh_target: "hugh".into(),
            connection_id: "0123456789abcdef0123456789abcdef".into(),
            epoch: 4,
            id: "$1".into(),
            name: "work".into(),
            server_pid: 7,
            server_started_at: 11,
            created_at: 12,
        };
        let output = std::process::Output {
            status: success_status(),
            stdout: format!(
                "{}\tSSH row\n",
                serde_json::to_string(&target).expect("target should serialize")
            )
            .into_bytes(),
            stderr: Vec::new(),
        };
        assert!(matches!(
            parse_picker_output(output).expect("picker output should parse"),
            Some(Target::RemoteSession {
                ssh_target, connection_id, epoch: 4, id, name, server_pid: 7,
                server_started_at: 11, created_at: 12,
            }) if ssh_target == "hugh"
                && connection_id == "0123456789abcdef0123456789abcdef"
                && id == "$1"
                && name == "work"
        ));
    }

    #[test]
    fn picker_only_treats_expected_cancel_statuses_as_cancellation() {
        for code in [1, 130] {
            let output = std::process::Output {
                status: exit_status(code),
                stdout: Vec::new(),
                stderr: Vec::new(),
            };
            assert!(parse_picker_output(output)
                .expect("expected cancellation should not be an error")
                .is_none());
        }
        for code in [2, 42] {
            let output = std::process::Output {
                status: exit_status(code),
                stdout: Vec::new(),
                stderr: Vec::new(),
            };
            assert!(parse_picker_output(output).is_err());
        }
    }

    #[test]
    fn remote_exit_handling_returns_to_the_origin_picker() {
        assert_eq!(classify_remote_exit(42), RemoteExit::ManagedSwitch);
        assert_eq!(classify_remote_exit(0), RemoteExit::Detached);
        assert_eq!(classify_remote_exit(75), RemoteExit::StaleTarget);
        assert_eq!(classify_remote_exit(255), RemoteExit::ConnectionFailure);
        assert_eq!(classify_remote_exit(1), RemoteExit::Other(1));
    }

    fn snapshot(
        hostname: &str,
        server_pid: u64,
        started_at: u64,
        sessions: Vec<SessionInfo>,
    ) -> Snapshot {
        Snapshot {
            protocol_version: PROTOCOL_VERSION,
            server_pid,
            server_started_at: started_at,
            hostname: hostname.into(),
            generated_at: 100,
            sessions,
        }
    }

    fn session(id: &str, name: &str, created_at: u64) -> SessionInfo {
        SessionInfo {
            id: id.into(),
            name: name.into(),
            windows: 1,
            attached: 0,
            created_at,
            activity_at: created_at,
        }
    }

    fn success_status() -> std::process::ExitStatus {
        exit_status(0)
    }

    fn exit_status(code: i32) -> std::process::ExitStatus {
        std::os::unix::process::ExitStatusExt::from_raw(code << 8)
    }
}
