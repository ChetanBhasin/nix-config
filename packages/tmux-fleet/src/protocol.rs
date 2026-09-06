use std::io::{self, Write};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

pub const WIRE_PREFIX: &str = "tmux-fleet/1\t";
pub const MAX_SESSION_NAME_BYTES: usize = 1024;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct SessionInfo {
    pub id: String,
    pub name: String,
    pub windows: u32,
    pub attached: u32,
    pub created_at: u64,
    pub activity_at: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct Snapshot {
    #[serde(default)]
    pub server_started_at: u64,
    pub hostname: String,
    pub generated_at: u64,
    pub sessions: Vec<SessionInfo>,
}

#[derive(Clone, Debug, Deserialize, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum WireMessage {
    Snapshot { snapshot: Snapshot },
    Heartbeat { sent_at: u64 },
    Error { message: String, sent_at: u64 },
}

pub fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

pub fn write_wire(message: &WireMessage) -> Result<bool> {
    let mut stdout = io::stdout().lock();
    let json = serde_json::to_string(message).context("failed to serialize watcher message")?;
    match writeln!(stdout, "{WIRE_PREFIX}{json}").and_then(|()| stdout.flush()) {
        Ok(()) => Ok(true),
        Err(error) if error.kind() == io::ErrorKind::BrokenPipe => Ok(false),
        Err(error) => Err(error).context("failed to write watcher message"),
    }
}

pub fn parse_wire(line: &str) -> Option<WireMessage> {
    line.strip_prefix(WIRE_PREFIX)
        .and_then(|json| serde_json::from_str(json).ok())
}

#[cfg(test)]
mod tests {
    use super::{parse_wire, Snapshot, WireMessage, WIRE_PREFIX};

    #[test]
    fn ignores_shell_startup_noise() {
        assert!(parse_wire("Welcome to this host").is_none());
    }

    #[test]
    fn parses_prefixed_messages() {
        let line = format!(
            "{WIRE_PREFIX}{}",
            serde_json::to_string(&WireMessage::Snapshot {
                snapshot: Snapshot {
                    hostname: "hugh".into(),
                    server_started_at: 7,
                    generated_at: 42,
                    sessions: Vec::new(),
                },
            })
            .expect("snapshot test fixture should serialize")
        );
        assert!(matches!(
            parse_wire(&line),
            Some(WireMessage::Snapshot { .. })
        ));
    }
}
