use std::collections::HashSet;
use std::env;
use std::fs;
use std::path::PathBuf;

use anyhow::{bail, Context, Result};
use serde::Deserialize;

#[derive(Clone, Debug, Deserialize)]
#[serde(default)]
pub struct Config {
    pub hosts: Vec<String>,
    pub tmux_command: PathBuf,
    pub fzf_command: PathBuf,
    pub ssh_command: PathBuf,
    pub reconcile_seconds: u64,
    pub connect_timeout_seconds: u64,
    pub server_alive_interval_seconds: u64,
    pub server_alive_count_max: u64,
    pub control_persist_seconds: u64,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            hosts: Vec::new(),
            tmux_command: PathBuf::from("tmux"),
            fzf_command: PathBuf::from("fzf"),
            ssh_command: PathBuf::from("ssh"),
            reconcile_seconds: 30,
            connect_timeout_seconds: 5,
            server_alive_interval_seconds: 15,
            server_alive_count_max: 2,
            control_persist_seconds: 600,
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
        self.hosts.retain(|host| seen.insert(host.clone()));

        for host in &self.hosts {
            if host.is_empty()
                || host.starts_with('-')
                || host.chars().any(char::is_whitespace)
                || host.chars().any(char::is_control)
            {
                bail!(
                    "invalid SSH host {host:?}; use a whitespace-free ssh_config host alias that does not start with '-'"
                );
            }
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

        if !(1..=3600).contains(&self.reconcile_seconds) {
            bail!("reconcile_seconds must be between 1 and 3600");
        }
        if !(1..=300).contains(&self.connect_timeout_seconds) {
            bail!("connect_timeout_seconds must be between 1 and 300");
        }
        if !(1..=3600).contains(&self.server_alive_interval_seconds) {
            bail!("server_alive_interval_seconds must be between 1 and 3600");
        }
        if !(1..=100).contains(&self.server_alive_count_max) {
            bail!("server_alive_count_max must be between 1 and 100");
        }
        if !(1..=86400).contains(&self.control_persist_seconds) {
            bail!("control_persist_seconds must be between 1 and 86400");
        }

        Ok(())
    }
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
    use super::Config;

    #[test]
    fn rejects_option_shaped_host() {
        let mut config = Config {
            hosts: vec!["-oProxyCommand=bad".into()],
            ..Config::default()
        };
        assert!(config.validate().is_err());
    }

    #[test]
    fn deduplicates_hosts_in_order() {
        let mut config = Config {
            hosts: vec!["hugh".into(), "boris".into(), "hugh".into()],
            ..Config::default()
        };
        config
            .validate()
            .expect("valid host aliases should pass validation");
        assert_eq!(config.hosts, ["hugh", "boris"]);
    }
}
