use std::time::{SystemTime, UNIX_EPOCH};

use serde::Serialize;

pub const MAX_SESSION_NAME_BYTES: usize = 1024;

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct SessionInfo {
    pub id: String,
    pub name: String,
    pub windows: u32,
    pub attached: u32,
    pub created_at: u64,
    pub activity_at: u64,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct Snapshot {
    pub server_pid: u64,
    pub server_started_at: u64,
    pub hostname: String,
    pub generated_at: u64,
    pub sessions: Vec<SessionInfo>,
}

pub fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}
