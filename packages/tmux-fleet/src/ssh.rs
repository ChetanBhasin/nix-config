use std::process::Command;

use anyhow::Result;

use crate::config::{validate_ssh_target, Config};

pub const REMOTE_ATTACH_COMMAND: &str = "if [ -x \"$HOME/.local/libexec/tmux-fleet\" ]; then exec \"$HOME/.local/libexec/tmux-fleet\" attach-latest; else export TMUX_FLEET_MANAGED=1; exec tmux start-server \\; if-shell -F '#{>:#{server_sessions},0}' 'attach-session' 'new-session'; fi";

pub fn attach_command(config: &Config, target: &str) -> Result<Command> {
    validate_ssh_target(target)?;
    let mut command = Command::new(&config.ssh_command);
    command
        .arg("-tt")
        .arg("--")
        .arg(target)
        .arg(REMOTE_ATTACH_COMMAND);
    Ok(command)
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::path::PathBuf;
    use std::process::Command;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    use crate::config::Config;

    use super::{attach_command, REMOTE_ATTACH_COMMAND};

    static TEST_NONCE: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn interactive_attach_preserves_authentication_and_uses_separate_arguments() {
        let config = Config::default();
        let command = attach_command(&config, "chetan@192.168.1.170")
            .expect("valid SSH target should build a command");
        let arguments = arguments(&command);
        assert_eq!(
            arguments,
            ["-tt", "--", "chetan@192.168.1.170", REMOTE_ATTACH_COMMAND,]
        );
        assert!(!arguments
            .iter()
            .any(|argument| argument.starts_with("BatchMode=")));
        assert!(!arguments
            .iter()
            .any(|argument| argument.starts_with("PasswordAuthentication=")));
        assert!(!arguments
            .iter()
            .any(|argument| argument.starts_with("KbdInteractiveAuthentication=")));
        assert!(!arguments
            .iter()
            .any(|argument| argument.starts_with("ControlMaster=")));
    }

    #[test]
    fn remote_command_prefers_managed_helper_with_an_atomic_tmux_fallback() {
        assert!(REMOTE_ATTACH_COMMAND.contains("tmux-fleet\" attach-latest"));
        assert!(REMOTE_ATTACH_COMMAND.contains("TMUX_FLEET_MANAGED=1"));
        assert!(REMOTE_ATTACH_COMMAND.contains("exec tmux start-server \\; if-shell -F"));
        assert!(REMOTE_ATTACH_COMMAND.contains("'#{>:#{server_sessions},0}'"));
        assert!(!REMOTE_ATTACH_COMMAND.contains("has-session"));
    }

    #[test]
    fn unmanaged_fallback_uses_one_atomic_queue_and_preserves_switch_status() {
        let (directory, log) = fake_tmux();
        let status = Command::new("/bin/sh")
            .arg("-c")
            .arg(REMOTE_ATTACH_COMMAND)
            .env_clear()
            .env("HOME", &directory)
            .env("PATH", &directory)
            .env("TMUX_FAKE_LOG", &log)
            .env("TMUX_FAKE_STATUS", "42")
            .status()
            .expect("fake shell fallback should run without a tmux socket");
        assert_eq!(status.code(), Some(42));
        assert_eq!(
            fs::read_to_string(&log).expect("fake tmux should log arguments"),
            "start-server\n;\nif-shell\n-F\n#{>:#{server_sessions},0}\nattach-session\nnew-session\n"
        );
        fs::remove_dir_all(directory).expect("fake tmux directory should be removable");
    }

    #[test]
    fn invalid_targets_do_not_reach_the_ssh_command() {
        assert!(attach_command(&Config::default(), "-oProxyCommand=bad").is_err());
    }

    fn arguments(command: &Command) -> Vec<String> {
        command
            .get_args()
            .map(|argument| argument.to_string_lossy().into_owned())
            .collect()
    }

    fn fake_tmux() -> (PathBuf, PathBuf) {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock should be after Unix epoch")
            .as_nanos();
        let sequence = TEST_NONCE.fetch_add(1, Ordering::Relaxed);
        let test_root = std::env::current_exe()
            .expect("test executable path should be available")
            .parent()
            .expect("test executable should have a parent directory")
            .to_path_buf();
        let directory = test_root.join(format!(
            "tmux-fleet-ssh-test-{}-{nonce}-{sequence}",
            std::process::id()
        ));
        fs::create_dir(&directory).expect("fake tmux directory should be created");
        fs::set_permissions(&directory, fs::Permissions::from_mode(0o700))
            .expect("fake tmux directory should be private");
        let executable = directory.join("tmux");
        let log = directory.join("arguments");
        fs::write(
            &executable,
            "#!/bin/sh\nprintf '%s\\n' \"$@\" >> \"$TMUX_FAKE_LOG\"\nexit \"$TMUX_FAKE_STATUS\"\n",
        )
        .expect("fake tmux executable should be written");
        fs::set_permissions(&executable, fs::Permissions::from_mode(0o700))
            .expect("fake tmux executable should become executable");
        (directory, log)
    }
}
