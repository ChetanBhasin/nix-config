use std::ffi::OsString;
use std::process::{Command, Stdio};

use anyhow::Result;

use crate::config::Config;
use crate::runtime::{hex_encode, ssh_control_path};
use crate::tmux::AttachMode;

const REMOTE_BINARY: &str = "\"$HOME/.local/libexec/tmux-fleet\"";

pub fn watch_command(config: &Config, host: &str) -> Result<Command> {
    let mut command = base_command(config, host, true)?;
    command
        .arg("-T")
        .arg("--")
        .arg(host)
        .arg(format!(
            "exec {REMOTE_BINARY} watch --reconcile-seconds {}",
            config.reconcile_seconds
        ))
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    Ok(command)
}

pub fn attach_command(config: &Config, host: &str, mode: &AttachMode) -> Result<Command> {
    let mut command = base_command(config, host, false)?;
    let remote_command = match mode {
        AttachMode::Existing(target) => format!(
            "exec {REMOTE_BINARY} attach --session-hex {} --server-started-at {} --created-at {}",
            hex_encode(&target.id),
            target.server_started_at,
            target.created_at
        ),
        AttachMode::New(Some(name)) => format!(
            "exec {REMOTE_BINARY} attach --new --session-hex {}",
            hex_encode(name)
        ),
        AttachMode::New(None) => format!("exec {REMOTE_BINARY} attach --new"),
    };
    command.arg("-tt").arg("--").arg(host).arg(remote_command);
    Ok(command)
}

pub fn reconnect_command(config: &Config, host: &str) -> Result<Command> {
    let mut command = base_command(config, host, false)?;
    command.arg("-fN").arg("--").arg(host);
    Ok(command)
}

fn base_command(config: &Config, host: &str, batch: bool) -> Result<Command> {
    let mut command = Command::new(&config.ssh_command);
    let control_path = ssh_control_path(host)?;
    command
        .arg("-o")
        .arg(format!("BatchMode={}", if batch { "yes" } else { "no" }))
        .arg("-o")
        .arg("PreferredAuthentications=publickey")
        .arg("-o")
        .arg("PasswordAuthentication=no")
        .arg("-o")
        .arg("KbdInteractiveAuthentication=no")
        .arg("-o")
        .arg("ForwardAgent=no")
        .arg("-o")
        .arg("RemoteCommand=none")
        .arg("-o")
        .arg("ControlMaster=auto")
        .arg("-o")
        .arg(format!("ControlPersist={}", config.control_persist_seconds))
        .arg("-o")
        .arg(control_path_option(&control_path))
        .arg("-o")
        .arg(format!("ConnectTimeout={}", config.connect_timeout_seconds))
        .arg("-o")
        .arg(format!(
            "ServerAliveInterval={}",
            config.server_alive_interval_seconds
        ))
        .arg("-o")
        .arg(format!(
            "ServerAliveCountMax={}",
            config.server_alive_count_max
        ))
        .arg("-o")
        .arg("ConnectionAttempts=1");
    Ok(command)
}

fn control_path_option(path: &std::path::Path) -> OsString {
    let mut option = OsString::from("ControlPath=");
    option.push(path);
    option
}

#[cfg(test)]
mod tests {
    use std::process::Command;

    use crate::config::Config;
    use crate::tmux::{AttachMode, ExistingTarget};

    use super::{attach_command, watch_command};

    #[test]
    fn existing_attach_transports_only_encoded_identity_fields() {
        let config = Config::default();
        let mode = AttachMode::Existing(ExistingTarget {
            id: "$9".into(),
            server_started_at: 123,
            created_at: 456,
        });
        let command =
            attach_command(&config, "work", &mode).expect("valid attach command should build");
        let arguments = arguments(&command);

        assert_eq!(
            &arguments[arguments.len() - 4..],
            [
                "-tt",
                "--",
                "work",
                "exec \"$HOME/.local/libexec/tmux-fleet\" attach --session-hex 2439 --server-started-at 123 --created-at 456",
            ]
        );
        assert!(!arguments.iter().any(|argument| argument.contains("$9")));
        assert!(has_option(&arguments, "BatchMode=no"));
        assert!(has_option(&arguments, "ForwardAgent=no"));
    }

    #[test]
    fn watcher_is_noninteractive_and_uses_a_separate_host_argument() {
        let config = Config::default();
        let command = watch_command(&config, "work").expect("valid watch command should build");
        let arguments = arguments(&command);

        assert_eq!(
            &arguments[arguments.len() - 4..],
            [
                "-T",
                "--",
                "work",
                "exec \"$HOME/.local/libexec/tmux-fleet\" watch --reconcile-seconds 30",
            ]
        );
        assert!(has_option(&arguments, "BatchMode=yes"));
        assert!(has_option(&arguments, "PasswordAuthentication=no"));
        assert!(has_option(&arguments, "KbdInteractiveAuthentication=no"));
    }

    #[test]
    fn control_paths_are_scoped_to_the_configured_alias() {
        let config = Config::default();
        let work =
            arguments(&watch_command(&config, "work").expect("first watch command should build"));
        let work_via_jump = arguments(
            &watch_command(&config, "work-via-jump").expect("second watch command should build"),
        );

        assert_ne!(
            option_value(&work, "ControlPath="),
            option_value(&work_via_jump, "ControlPath=")
        );
    }

    fn arguments(command: &Command) -> Vec<String> {
        command
            .get_args()
            .map(|argument| argument.to_string_lossy().into_owned())
            .collect()
    }

    fn option_value<'a>(arguments: &'a [String], prefix: &str) -> Option<&'a str> {
        arguments
            .iter()
            .find_map(|argument| argument.strip_prefix(prefix))
    }

    fn has_option(arguments: &[String], option: &str) -> bool {
        arguments
            .windows(2)
            .any(|pair| pair[0] == "-o" && pair[1] == option)
    }
}
