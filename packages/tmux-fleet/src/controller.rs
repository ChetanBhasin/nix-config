use std::ffi::OsString;
use std::fs::File;
use std::io::{self, Write};
use std::process::{Command, Output, Stdio};

use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};

use crate::config::{validate_ssh_target, Config};
use crate::protocol::{Snapshot, MAX_SESSION_NAME_BYTES};
use crate::runtime::{self, ControllerDir};
use crate::ssh;
use crate::tmux::{self, AttachMode, ExistingTarget, STALE_TARGET_EXIT_CODE, SWITCH_EXIT_CODE};

const SSH_FAILURE_EXIT_CODE: i32 = 255;

#[derive(Debug, Eq, PartialEq)]
enum RemoteExit {
    ManagedSwitch,
    Detached,
    ConnectionFailure,
    Other(i32),
}

struct Model {
    local_name: String,
    local: Snapshot,
    ssh_targets: Vec<String>,
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
    Ssh {
        target: String,
    },
    ConnectSsh,
}

pub fn run(config: Config) -> Result<()> {
    if tmux_client_is_active(std::env::var_os("TMUX")) {
        bail!(
            "tmux-fleet must start in a terminal outside tmux; use Prefix s then s from a tmux client"
        );
    }

    let controller_dir = ControllerDir::create()?;
    let mut model = Model::load(&config)?;
    let mut resume_query = None;

    loop {
        model.refresh(&config)?;
        let Some(target) = run_picker(&config, &model, &controller_dir, resume_query.take())?
        else {
            break;
        };

        match target {
            Target::LocalSession {
                id,
                name,
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
                    resume_query = Some(name);
                }
                0 => break,
                code => {
                    eprintln!("Local tmux exited with status {code}; returning to the picker.");
                    resume_query = Some(name);
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
            Target::Ssh { target } => {
                resume_query = Some(run_ssh_target(&config, &target)?);
            }
            Target::ConnectSsh => {
                let Some(target) = prompt_ssh_target()? else {
                    continue;
                };
                if let Err(error) = runtime::remember_ssh_target(&target) {
                    eprintln!("Could not remember SSH target {target:?}: {error:#}");
                }
                model.add_ssh_target(target.clone());
                resume_query = Some(run_ssh_target(&config, &target)?);
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
        let mut model = Self {
            local_name: runtime::short_hostname(),
            local: tmux::snapshot(config)?,
            ssh_targets: config.ssh_targets.clone(),
        };
        for target in runtime::recent_ssh_targets() {
            model.add_ssh_target(target);
        }
        Ok(model)
    }

    fn refresh(&mut self, config: &Config) -> Result<()> {
        self.local = tmux::snapshot(config)?;
        Ok(())
    }

    fn add_ssh_target(&mut self, target: String) {
        if !self.ssh_targets.contains(&target) {
            self.ssh_targets.push(target);
        }
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

        for target in &self.ssh_targets {
            rows.push(candidate_line(
                &Target::Ssh {
                    target: target.clone(),
                },
                &format!(
                    "→  SSH    {:<14}  attach most-recent remote tmux session",
                    clean_field(target)
                ),
            )?);
        }
        rows.push(candidate_line(
            &Target::ConnectSsh,
            "＋ SSH                 connect to [user@]host or address…",
        )?);
        Ok(format!("{}\n", rows.join("\n")))
    }
}

fn run_ssh_target(config: &Config, target: &str) -> Result<String> {
    eprintln!("Connecting to {target}…");
    let status = ssh::attach_command(config, target)?
        .status()
        .with_context(|| format!("failed to run {}", config.ssh_command.display()))?;
    let code = exit_code(status.code());
    match classify_remote_exit(code) {
        RemoteExit::ManagedSwitch => {}
        RemoteExit::Detached => eprintln!("Detached from {target}; returning to the picker."),
        RemoteExit::ConnectionFailure => {
            eprintln!("SSH connection to {target} failed or disconnected; retry from the picker.");
        }
        RemoteExit::Other(code) => {
            eprintln!("Remote tmux on {target} exited with status {code}; retry from the picker.");
        }
    }
    Ok(remote_retry_query(target))
}

fn remote_retry_query(target: &str) -> String {
    target.to_owned()
}

fn classify_remote_exit(code: i32) -> RemoteExit {
    match code {
        SWITCH_EXIT_CODE => RemoteExit::ManagedSwitch,
        0 => RemoteExit::Detached,
        SSH_FAILURE_EXIT_CODE => RemoteExit::ConnectionFailure,
        code => RemoteExit::Other(code),
    }
}

fn run_picker(
    config: &Config,
    model: &Model,
    controller_dir: &ControllerDir,
    query: Option<String>,
) -> Result<Option<Target>> {
    let candidates_path = controller_dir.path().join("candidates");
    runtime::atomic_write(&candidates_path, model.rows()?.as_bytes())?;
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
            "--header=Enter attach · Esc quit · SSH targets open foreground authentication",
            "--color=bg:#1d2021,bg+:#3c3836,fg:#d0c0a0,fg+:#ebdbb2,hl:#84a9b2,hl+:#c9a257,prompt:#c9a257,pointer:#c9a257,marker:#84a9b2,spinner:#84a9b2,border:#504945,header:#96918a,info:#7c6f64",
        ])
        .stdin(Stdio::from(input))
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .env_remove("FZF_DEFAULT_COMMAND");
    if let Some(query) = query {
        command.arg("--query").arg(query);
    }
    let output = command
        .output()
        .with_context(|| format!("failed to run {}", config.fzf_command.display()))?;
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
    use crate::protocol::{SessionInfo, Snapshot};

    use super::{
        classify_remote_exit, parse_picker_output, remote_retry_query, tmux_client_is_active,
        Model, RemoteExit, Target,
    };

    #[test]
    fn detached_tmux_client_environment_can_start_the_picker() {
        assert!(!tmux_client_is_active(Some(std::ffi::OsString::new())));
        assert!(tmux_client_is_active(Some(std::ffi::OsString::from(
            "/tmp/tmux"
        ))));
    }
    #[test]
    fn picker_rows_preserve_target_identity_and_sanitize_display() {
        let model = Model {
            local_name: "local".into(),
            local: Snapshot {
                server_pid: 7,
                server_started_at: 11,
                hostname: "local".into(),
                generated_at: 100,
                sessions: vec![session("$1", "work\tline\nname", 12)],
            },
            ssh_targets: vec!["chetan@192.168.1.170".into()],
        };
        let rows = model.rows().expect("test model should render rows");
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
            Target::LocalSession { id, name, server_pid: 7, server_started_at: 11, created_at: 12 }
                if id == "$1" && name == "work\tline\nname"
        )));
        assert!(targets.iter().any(|target| matches!(
            target,
            Target::Ssh { target } if target == "chetan@192.168.1.170"
        )));
        assert!(targets
            .iter()
            .any(|target| matches!(target, Target::ConnectSsh)));
    }

    #[test]
    fn picker_output_round_trips_local_session_target() {
        let target = Target::LocalSession {
            id: "$1".into(),
            name: "work".into(),
            server_pid: 7,
            server_started_at: 11,
            created_at: 12,
        };
        let output = std::process::Output {
            status: success_status(),
            stdout: format!(
                "{}\tLOCAL row\n",
                serde_json::to_string(&target).expect("target should serialize")
            )
            .into_bytes(),
            stderr: Vec::new(),
        };
        assert!(matches!(
            parse_picker_output(output).expect("picker output should parse"),
            Some(Target::LocalSession {
                id,
                name,
                server_pid: 7,
                server_started_at: 11,
                created_at: 12,
            }) if id == "$1" && name == "work"
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
            let error = parse_picker_output(output).expect_err("operational errors must propagate");
            assert!(error.to_string().contains(&format!("status {code}")));
        }

        let output = std::process::Output {
            status: signalled_status(),
            stdout: Vec::new(),
            stderr: Vec::new(),
        };
        let error = parse_picker_output(output).expect_err("signals must propagate");
        assert!(error.to_string().contains("signal"));
    }

    #[test]
    fn remote_exit_handling_returns_to_the_origin_picker() {
        assert_eq!(classify_remote_exit(42), RemoteExit::ManagedSwitch);
        assert_eq!(classify_remote_exit(0), RemoteExit::Detached);
        assert_eq!(classify_remote_exit(255), RemoteExit::ConnectionFailure);
        assert_eq!(classify_remote_exit(1), RemoteExit::Other(1));
        assert_eq!(
            remote_retry_query("chetan@192.168.1.170"),
            "chetan@192.168.1.170"
        );
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

    fn signalled_status() -> std::process::ExitStatus {
        std::os::unix::process::ExitStatusExt::from_raw(9)
    }
}
