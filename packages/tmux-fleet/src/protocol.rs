use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{bail, Result};
use serde::{Deserialize, Serialize};

pub const PROTOCOL_VERSION: u16 = 1;
pub const MAX_SESSION_NAME_BYTES: usize = 1024;
pub const MAX_HOSTNAME_BYTES: usize = 255;
pub const MAX_REMOTE_SESSIONS: usize = 4096;
pub const MAX_IPC_REQUEST_BYTES: usize = 64 * 1024;
pub const MAX_IPC_RESPONSE_BYTES: usize = 8 * 1024 * 1024;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct SessionInfo {
    pub id: String,
    pub name: String,
    pub windows: u32,
    pub attached: u32,
    pub created_at: u64,
    pub activity_at: u64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Snapshot {
    pub protocol_version: u16,
    pub server_pid: u64,
    pub server_started_at: u64,
    pub hostname: String,
    pub generated_at: u64,
    pub sessions: Vec<SessionInfo>,
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum RemoteState {
    Disconnected,
    Connecting,
    Ready,
    Degraded,
    Unsupported,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RemoteHost {
    pub target: String,
    pub state: RemoteState,
    pub connection_id: Option<String>,
    pub epoch: u64,
    pub hostname: Option<String>,
    pub server_pid: u64,
    pub server_started_at: u64,
    pub sessions: Vec<SessionInfo>,
    pub message: Option<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
pub enum DaemonRequest {
    List,
    BeginConnect {
        target: String,
    },
    CommitConnect {
        target: String,
        connection_id: String,
    },
    AbortConnect {
        target: String,
        connection_id: String,
    },
    PrepareAttach {
        target: String,
        connection_id: String,
        epoch: u64,
    },
    Disconnect {
        target: String,
        connection_id: String,
    },
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RpcRequest {
    pub version: u16,
    pub request_id: String,
    pub request: DaemonRequest,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DaemonErrorCode {
    UnsupportedVersion,
    InvalidRequest,
    Busy,
    NotConnected,
    StaleConnection,
    MasterFailed,
    Internal,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(tag = "result", rename_all = "snake_case", deny_unknown_fields)]
pub enum DaemonReply {
    Hosts {
        hosts: Vec<RemoteHost>,
    },
    ConnectPlan {
        target: String,
        connection_id: String,
        control_path: String,
    },
    AttachPlan {
        target: String,
        connection_id: String,
        epoch: u64,
        control_path: String,
    },
    Ack,
    Error {
        code: DaemonErrorCode,
        retryable: bool,
        message: String,
    },
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
pub struct RpcResponse {
    pub version: u16,
    pub request_id: String,
    pub reply: DaemonReply,
}

pub fn valid_session_id(value: &str) -> bool {
    value.strip_prefix('$').is_some_and(|digits| {
        !digits.is_empty()
            && digits.len() <= 20
            && digits.bytes().all(|byte| byte.is_ascii_digit())
            && digits.parse::<u64>().is_ok()
    })
}

pub fn validate_snapshot(snapshot: &Snapshot) -> Result<()> {
    if snapshot.protocol_version != PROTOCOL_VERSION {
        bail!(
            "remote tmux-fleet protocol {} is unsupported; expected {}",
            snapshot.protocol_version,
            PROTOCOL_VERSION
        );
    }
    if snapshot.hostname.len() > MAX_HOSTNAME_BYTES {
        bail!("remote hostname exceeds {MAX_HOSTNAME_BYTES} bytes");
    }
    if snapshot.sessions.len() > MAX_REMOTE_SESSIONS {
        bail!("remote snapshot exceeds {MAX_REMOTE_SESSIONS} sessions");
    }
    if !snapshot.sessions.is_empty()
        && (snapshot.server_pid == 0 || snapshot.server_started_at == 0)
    {
        bail!("remote snapshot has sessions without a server identity");
    }
    for session in &snapshot.sessions {
        if !valid_session_id(&session.id) {
            bail!("remote snapshot contains an invalid session ID");
        }
        if session.name.len() > MAX_SESSION_NAME_BYTES {
            bail!("remote session name exceeds {MAX_SESSION_NAME_BYTES} bytes");
        }
    }
    Ok(())
}

pub fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::{valid_session_id, validate_snapshot, SessionInfo, Snapshot, PROTOCOL_VERSION};

    #[test]
    fn session_ids_are_canonical_and_bounded() {
        assert!(valid_session_id("$0"));
        assert!(valid_session_id("$18446744073709551615"));
        assert!(!valid_session_id("$"));
        assert!(!valid_session_id("$18446744073709551616"));
        assert!(!valid_session_id("$123456789012345678901"));
        assert!(!valid_session_id("work"));
    }

    #[test]
    fn remote_snapshot_requires_matching_protocol_and_identity() {
        let mut snapshot = Snapshot {
            protocol_version: PROTOCOL_VERSION,
            server_pid: 7,
            server_started_at: 11,
            hostname: "remote".into(),
            generated_at: 12,
            sessions: vec![SessionInfo {
                id: "$1".into(),
                name: "work".into(),
                windows: 1,
                attached: 0,
                created_at: 13,
                activity_at: 14,
            }],
        };
        validate_snapshot(&snapshot).expect("valid snapshot should pass");
        snapshot.protocol_version += 1;
        assert!(validate_snapshot(&snapshot).is_err());
        snapshot.protocol_version = PROTOCOL_VERSION;
        snapshot.server_pid = 0;
        assert!(validate_snapshot(&snapshot).is_err());
    }
}
