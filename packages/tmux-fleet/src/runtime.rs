use std::env;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process;
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context, Result};
use nix::unistd::{geteuid, gethostname};
use sha2::{Digest, Sha256};

pub fn runtime_root() -> Result<PathBuf> {
    let uid = effective_uid();
    // Keep AF_UNIX paths below Darwin's short sockaddr_un limit. XDG_RUNTIME_DIR
    // and macOS TMPDIR can both be long enough to break watcher or FZF sockets.
    let path = PathBuf::from(format!("/tmp/tmux-fleet-{uid}"));
    ensure_private_dir(&path)?;
    Ok(path)
}

pub fn cache_root() -> Result<PathBuf> {
    let base = env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))
        .ok_or_else(|| {
            anyhow::anyhow!("HOME or XDG_CACHE_HOME is required for the session cache")
        })?;
    let path = base.join("tmux-fleet");
    ensure_private_dir(&path)?;
    Ok(path)
}

pub fn watcher_dir() -> Result<PathBuf> {
    let path = runtime_root()?.join("watchers");
    ensure_private_dir(&path)?;
    Ok(path)
}

pub fn ssh_control_path(host: &str) -> Result<PathBuf> {
    let path = runtime_root()?.join("ssh");
    ensure_private_dir(&path)?;
    Ok(path.join(format!("cm-{}-%C", alias_digest(host))))
}

pub struct ControllerDir {
    path: PathBuf,
}

impl ControllerDir {
    pub fn create() -> Result<Self> {
        let path = runtime_root()?
            .join("controllers")
            .join(unique_name("controller"));
        ensure_private_dir(&path)?;
        Ok(Self { path })
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl Drop for ControllerDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

pub fn cache_file(host: &str) -> Result<PathBuf> {
    let mut readable = String::with_capacity(host.len());
    for character in host.chars() {
        if character.is_ascii_alphanumeric() || matches!(character, '-' | '_') {
            readable.push(character);
        } else {
            readable.push('_');
        }
    }
    readable.truncate(32);
    Ok(cache_root()?.join(format!("{readable}-{:016x}.json", fnv1a(host.as_bytes()))))
}

pub fn atomic_write(path: &Path, contents: &[u8]) -> Result<()> {
    let parent = path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("{} has no parent directory", path.display()))?;
    ensure_private_dir(parent)?;
    let temporary = parent.join(unique_name("write"));
    let result = (|| -> Result<()> {
        let mut file = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&temporary)
            .with_context(|| format!("failed to create {}", temporary.display()))?;
        file.write_all(contents)
            .with_context(|| format!("failed to write {}", temporary.display()))?;
        file.sync_all()
            .with_context(|| format!("failed to sync {}", temporary.display()))?;
        fs::rename(&temporary, path).with_context(|| {
            format!(
                "failed to replace {} with {}",
                path.display(),
                temporary.display()
            )
        })?;
        Ok(())
    })();
    if result.is_err() {
        let _ = fs::remove_file(temporary);
    }
    result
}

pub fn short_hostname() -> String {
    if let Ok(hostname) = gethostname() {
        let hostname = hostname.to_string_lossy();
        let short = hostname.split('.').next().unwrap_or_default().trim();
        if !short.is_empty() {
            return short.to_owned();
        }
    }
    env::var("HOSTNAME").unwrap_or_else(|_| "local".to_owned())
}

pub fn hex_encode(value: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut encoded = String::with_capacity(value.len() * 2);
    for byte in value.bytes() {
        encoded.push(char::from(HEX[usize::from(byte >> 4)]));
        encoded.push(char::from(HEX[usize::from(byte & 0x0f)]));
    }
    encoded
}

pub fn hex_decode(value: &str) -> Result<String> {
    if value.len() & 1 == 1 {
        bail!("hex value has an odd length");
    }
    let bytes = value.as_bytes();
    let mut decoded = Vec::with_capacity(value.len() / 2);
    for index in (0..bytes.len()).step_by(2) {
        let high = hex_digit(bytes[index])?;
        let low = hex_digit(bytes[index + 1])?;
        decoded.push((high << 4) | low);
    }
    String::from_utf8(decoded).context("hex value is not valid UTF-8")
}

pub fn shell_quote(path: &Path) -> String {
    let text = path.as_os_str().to_string_lossy();
    format!("'{}'", text.replace('\'', "'\\''"))
}

fn ensure_private_dir(path: &Path) -> Result<()> {
    fs::create_dir_all(path).with_context(|| format!("failed to create {}", path.display()))?;
    let metadata = fs::symlink_metadata(path)
        .with_context(|| format!("failed to inspect {}", path.display()))?;
    if !metadata.file_type().is_dir() || metadata.file_type().is_symlink() {
        bail!("{} is not a safe directory", path.display());
    }
    if metadata.uid() != effective_uid() {
        bail!("{} is owned by another user", path.display());
    }
    if metadata.permissions().mode() & 0o077 != 0 {
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))
            .with_context(|| format!("failed to secure {}", path.display()))?;
    }
    Ok(())
}

fn effective_uid() -> u32 {
    geteuid().as_raw()
}

fn unique_name(prefix: &str) -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    format!("{prefix}-{}-{nanos}", process::id())
}

fn alias_digest(host: &str) -> String {
    let digest = format!("{:x}", Sha256::digest(host.as_bytes()));
    digest[..20].to_owned()
}

fn fnv1a(bytes: &[u8]) -> u64 {
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

fn hex_digit(value: u8) -> Result<u8> {
    match value {
        b'0'..=b'9' => Ok(value - b'0'),
        b'a'..=b'f' => Ok(value - b'a' + 10),
        b'A'..=b'F' => Ok(value - b'A' + 10),
        _ => bail!("invalid hex digit {:?}", char::from(value)),
    }
}

#[cfg(test)]
mod tests {
    use super::{hex_decode, hex_encode};

    #[test]
    fn hex_round_trip_preserves_punctuation_and_unicode() {
        let original = "work ! @ café";
        assert_eq!(
            hex_decode(&hex_encode(original)).expect("encoded UTF-8 should decode"),
            original
        );
    }

    #[test]
    fn rejects_invalid_hex() {
        assert!(hex_decode("xyz").is_err());
        assert!(hex_decode("gg").is_err());
    }
}
