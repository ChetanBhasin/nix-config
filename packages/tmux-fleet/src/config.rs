use std::collections::HashSet;
use std::env;
use std::fs;
use std::path::PathBuf;

use anyhow::{bail, Context, Result};
use serde::Deserialize;

pub const MAX_SSH_TARGET_BYTES: usize = 512;
#[derive(Clone, Debug, Deserialize)]
#[serde(default)]
pub struct Config {
    pub ssh_targets: Vec<String>,
    pub tmux_command: PathBuf,
    pub fzf_command: PathBuf,
    pub ssh_command: PathBuf,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            ssh_targets: Vec::new(),
            tmux_command: PathBuf::from("tmux"),
            fzf_command: PathBuf::from("fzf"),
            ssh_command: PathBuf::from("ssh"),
        }
    }
}

impl Config {
    pub fn load() -> Result<Self> {
        let path = config_path();
        let mut config = match path {
            Some(ref path) if path.exists() => {
                let text = fs::read_to_string(path)
                    .with_context(|| format!("failed to read {}", path.display()))?;
                serde_json::from_str(&text)
                    .with_context(|| format!("failed to parse {}", path.display()))?
            }
            _ => Self::default(),
        };
        config.validate()?;
        Ok(config)
    }

    fn validate(&mut self) -> Result<()> {
        let mut seen = HashSet::new();
        self.ssh_targets
            .retain(|target| seen.insert(target.clone()));
        for target in &self.ssh_targets {
            validate_ssh_target(target)?;
        }

        for (name, command) in [
            ("tmux_command", &self.tmux_command),
            ("fzf_command", &self.fzf_command),
            ("ssh_command", &self.ssh_command),
        ] {
            if command.as_os_str().is_empty() {
                bail!("{name} cannot be empty");
            }
        }
        Ok(())
    }
}

pub fn validate_ssh_target(target: &str) -> Result<()> {
    if target.is_empty()
        || target.len() > MAX_SSH_TARGET_BYTES
        || target.starts_with('-')
        || target.chars().any(char::is_whitespace)
        || target.chars().any(char::is_control)
    {
        bail!(
            "invalid SSH target {target:?}; use a non-empty [user@]host, address, or ssh_config alias without whitespace or a leading '-'"
        );
    }
    Ok(())
}

fn config_path() -> Option<PathBuf> {
    if let Some(path) = env::var_os("TMUX_FLEET_CONFIG") {
        return Some(PathBuf::from(path));
    }
    if let Some(path) = env::var_os("XDG_CONFIG_HOME") {
        return Some(PathBuf::from(path).join("tmux-fleet/config.json"));
    }
    env::var_os("HOME").map(|home| {
        PathBuf::from(home)
            .join(".config")
            .join("tmux-fleet/config.json")
    })
}

#[cfg(test)]
mod tests {
    use super::{validate_ssh_target, Config};

    #[test]
    fn accepts_safe_open_ssh_destinations() {
        for target in [
            "hugh",
            "chetan@192.168.1.170",
            "chetan@example.internal",
            "chetan@2001:db8::1",
            "[2001:db8::1]",
        ] {
            validate_ssh_target(target).expect("valid SSH destination should be accepted");
        }
    }

    #[test]
    fn rejects_unsafe_ssh_destinations() {
        for target in ["", "-oProxyCommand=bad", "name with spaces", "name\nnext"] {
            assert!(
                validate_ssh_target(target).is_err(),
                "{target:?} should fail"
            );
        }
    }

    #[test]
    fn deduplicates_configured_targets_in_order() {
        let mut config = Config {
            ssh_targets: vec!["hugh".into(), "chetan@192.168.1.170".into(), "hugh".into()],
            ..Config::default()
        };
        config
            .validate()
            .expect("valid SSH destinations should pass validation");
        assert_eq!(config.ssh_targets, ["hugh", "chetan@192.168.1.170"]);
    }
}
