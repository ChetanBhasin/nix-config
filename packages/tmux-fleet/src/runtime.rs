use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{bail, Context, Result};
use nix::fcntl::{Flock, FlockArg};
use nix::unistd::{geteuid, gethostname};
use serde::{Deserialize, Serialize};

use crate::config::validate_ssh_target;

pub const MAX_RECENT_SSH_TARGETS: usize = 16;
const MAX_RECENT_SSH_STATE_BYTES: u64 = 16 * 1024;
const RECENT_SSH_STATE_NAME: &str = "recent-ssh-targets.json";
const RECENT_SSH_LOCK_NAME: &str = "recent-ssh-targets.lock";
static UNIQUE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

pub fn runtime_root() -> Result<PathBuf> {
    let uid = effective_uid();
    let path = PathBuf::from(format!("/tmp/tmux-fleet-{uid}"));
    ensure_private_dir(&path)?;
    Ok(path)
}

fn state_root() -> Result<PathBuf> {
    let base = env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".local/state")))
        .ok_or_else(|| {
            anyhow::anyhow!("HOME or XDG_STATE_HOME is required for tmux-fleet state")
        })?;
    // HOME and XDG_STATE_HOME are trusted boundaries; create each missing child privately.
    ensure_private_dir_tree(&base)?;
    let path = base.join("tmux-fleet");
    ensure_private_dir(&path)?;
    Ok(path)
}

pub struct ControllerDir {
    path: PathBuf,
}

impl ControllerDir {
    pub fn create() -> Result<Self> {
        let root = runtime_root()?;
        Self::create_at(&root)
    }

    fn create_at(root: &Path) -> Result<Self> {
        // Verify the predictable root before walking into any child path.
        ensure_private_dir(root)?;
        let controllers = root.join("controllers");
        ensure_private_dir(&controllers)?;
        let path = create_unique_private_dir(&controllers, "controller")?;
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

#[derive(Deserialize, Serialize)]
struct RecentSshState {
    targets: Vec<String>,
}

pub fn recent_ssh_targets() -> Vec<String> {
    match state_root() {
        Ok(root) => load_recent_ssh_targets_or_empty(&root.join(RECENT_SSH_STATE_NAME)),
        Err(error) => warn_and_clear_recent_ssh_targets(error),
    }
}

pub fn remember_ssh_target(target: &str) -> Result<Vec<String>> {
    validate_ssh_target(target)?;
    let path = state_root()?.join(RECENT_SSH_STATE_NAME);
    remember_ssh_target_at(&path, target)
}

fn remember_ssh_target_at(path: &Path, target: &str) -> Result<Vec<String>> {
    validate_ssh_target(target)?;
    let _lock = recent_ssh_state_lock(path)?;
    let mut targets = vec![target.to_owned()];
    targets.extend(
        load_recent_ssh_targets_from(path)?
            .into_iter()
            .filter(|existing| existing != target),
    );
    targets.truncate(MAX_RECENT_SSH_TARGETS);
    let state = RecentSshState {
        targets: targets.clone(),
    };
    let encoded = serde_json::to_vec(&state).context("failed to serialize recent SSH targets")?;
    atomic_write(path, &encoded)?;
    Ok(targets)
}

fn load_recent_ssh_targets_or_empty(path: &Path) -> Vec<String> {
    match load_recent_ssh_targets_from(path) {
        Ok(targets) => targets,
        Err(error) => warn_and_clear_recent_ssh_targets(error),
    }
}

fn warn_and_clear_recent_ssh_targets(error: anyhow::Error) -> Vec<String> {
    eprintln!("Warning: ignoring recent SSH target state: {error:#}");
    Vec::new()
}

fn load_recent_ssh_targets_from(path: &Path) -> Result<Vec<String>> {
    let file = match OpenOptions::new()
        .read(true)
        .custom_flags(nix::libc::O_NOFOLLOW)
        .open(path)
    {
        Ok(file) => file,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => {
            return Err(error).with_context(|| format!("failed to open {}", path.display()))
        }
    };
    let metadata = file
        .metadata()
        .with_context(|| format!("failed to inspect {}", path.display()))?;
    if !metadata.file_type().is_file() || metadata.uid() != effective_uid() {
        bail!("{} is not a private regular state file", path.display());
    }
    if metadata.permissions().mode() & 0o077 != 0 {
        bail!("{} is not private", path.display());
    }

    let mut bytes = Vec::new();
    file.take(MAX_RECENT_SSH_STATE_BYTES + 1)
        .read_to_end(&mut bytes)
        .with_context(|| format!("failed to read {}", path.display()))?;
    if bytes.len() as u64 > MAX_RECENT_SSH_STATE_BYTES {
        bail!("recent SSH target state exceeds the {MAX_RECENT_SSH_STATE_BYTES}-byte safety limit");
    }
    let state: RecentSshState =
        serde_json::from_slice(&bytes).context("recent SSH target state is invalid")?;
    let mut targets = Vec::new();
    for target in state.targets {
        validate_ssh_target(&target)?;
        if !targets.contains(&target) {
            targets.push(target);
        }
    }
    targets.truncate(MAX_RECENT_SSH_TARGETS);
    Ok(targets)
}

fn recent_ssh_state_lock(path: &Path) -> Result<Flock<File>> {
    let parent = path
        .parent()
        .ok_or_else(|| anyhow::anyhow!("{} has no parent directory", path.display()))?;
    ensure_private_dir(parent)?;
    let lock_path = parent.join(RECENT_SSH_LOCK_NAME);
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .mode(0o600)
        .custom_flags(nix::libc::O_NOFOLLOW)
        .open(&lock_path)
        .with_context(|| format!("failed to open {}", lock_path.display()))?;
    let metadata = file
        .metadata()
        .with_context(|| format!("failed to inspect {}", lock_path.display()))?;
    if !metadata.file_type().is_file()
        || metadata.uid() != effective_uid()
        || metadata.permissions().mode() & 0o077 != 0
    {
        bail!("{} is not a private regular lock file", lock_path.display());
    }
    Flock::lock(file, FlockArg::LockExclusive)
        .map_err(|(_, error)| anyhow::anyhow!("failed to lock {}: {error}", lock_path.display()))
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

enum DirectoryCreation {
    Created,
    Existing,
}

fn ensure_private_dir(path: &Path) -> Result<()> {
    let creation = create_private_dir(path)?;
    let metadata = verify_owned_directory(path)?;
    if matches!(creation, DirectoryCreation::Existing) && metadata.permissions().mode() & 0o077 != 0
    {
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))
            .with_context(|| format!("failed to secure {}", path.display()))?;
        verify_owned_directory(path)?;
    }
    Ok(())
}

fn ensure_private_dir_tree(path: &Path) -> Result<()> {
    let mut missing = Vec::new();
    let mut cursor = path;
    loop {
        match fs::symlink_metadata(cursor) {
            Ok(_) => {
                verify_owned_directory(cursor)?;
                break;
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                missing.push(cursor.to_path_buf());
                cursor = cursor.parent().ok_or_else(|| {
                    anyhow::anyhow!("{} has no trusted directory boundary", path.display())
                })?;
            }
            Err(error) => {
                return Err(error)
                    .with_context(|| format!("failed to inspect {}", cursor.display()))
            }
        }
    }
    for directory in missing.into_iter().rev() {
        ensure_private_dir(&directory)?;
    }
    Ok(())
}

fn create_private_dir(path: &Path) -> Result<DirectoryCreation> {
    let mut builder = fs::DirBuilder::new();
    builder.mode(0o700);
    match builder.create(path) {
        Ok(()) => {
            verify_owned_directory(path)?;
            Ok(DirectoryCreation::Created)
        }
        Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
            verify_owned_directory(path)?;
            Ok(DirectoryCreation::Existing)
        }
        Err(error) => Err(error).with_context(|| format!("failed to create {}", path.display())),
    }
}

fn create_unique_private_dir(parent: &Path, prefix: &str) -> Result<PathBuf> {
    for _ in 0..128 {
        let path = parent.join(unique_name(prefix));
        match create_private_dir(&path)? {
            DirectoryCreation::Created => return Ok(path),
            DirectoryCreation::Existing => continue,
        }
    }
    bail!(
        "failed to create a unique directory under {}",
        parent.display()
    );
}

fn verify_owned_directory(path: &Path) -> Result<fs::Metadata> {
    let metadata = fs::symlink_metadata(path)
        .with_context(|| format!("failed to inspect {}", path.display()))?;
    if !metadata.file_type().is_dir() || metadata.file_type().is_symlink() {
        bail!("{} is not a safe directory", path.display());
    }
    if metadata.uid() != effective_uid() {
        bail!("{} is owned by another user", path.display());
    }
    Ok(metadata)
}

fn effective_uid() -> u32 {
    geteuid().as_raw()
}

fn unique_name(prefix: &str) -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let sequence = UNIQUE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    format!("{prefix}-{}-{nanos}-{sequence}", process::id())
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::os::unix::fs::{symlink, MetadataExt, PermissionsExt};
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::{Arc, Barrier};
    use std::thread;
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::{
        load_recent_ssh_targets_from, load_recent_ssh_targets_or_empty, remember_ssh_target_at,
        ControllerDir, MAX_RECENT_SSH_TARGETS,
    };

    static TEST_NONCE: AtomicU64 = AtomicU64::new(0);

    #[test]
    fn controller_directories_are_created_privately_without_using_runtime_root() {
        let base = temporary_directory();
        let root = base.join("runtime");
        let controller =
            ControllerDir::create_at(&root).expect("controller directories should be created");
        let controllers = root.join("controllers");

        assert_private_directory(&root);
        assert_private_directory(&controllers);
        assert_private_directory(controller.path());
        drop(controller);
        fs::remove_dir_all(base).expect("temporary runtime directory should be removable");
    }

    #[test]
    fn controller_creation_rejects_a_symlinked_intermediate_directory() {
        let base = temporary_directory();
        let root = base.join("runtime");
        fs::create_dir(&root).expect("runtime fixture should be created");
        fs::set_permissions(&root, fs::Permissions::from_mode(0o700))
            .expect("runtime fixture should be private");
        let outside = base.join("outside");
        fs::create_dir(&outside).expect("outside fixture should be created");
        fs::set_permissions(&outside, fs::Permissions::from_mode(0o700))
            .expect("outside fixture should be private");
        symlink(&outside, root.join("controllers")).expect("hostile symlink should be created");

        assert!(ControllerDir::create_at(&root).is_err());
        assert!(
            fs::read_dir(&outside)
                .expect("outside fixture should remain readable")
                .next()
                .is_none(),
            "controller creation must not follow the hostile intermediate symlink"
        );
        fs::remove_dir_all(base).expect("temporary runtime directory should be removable");
    }

    #[test]
    fn recent_ssh_targets_are_deduplicated_and_bounded() {
        let directory = temporary_directory();
        let path = directory.join("recent-ssh-targets.json");
        for index in 0..(MAX_RECENT_SSH_TARGETS + 3) {
            remember_ssh_target_at(&path, &format!("chetan@192.0.2.{index}"))
                .expect("valid target should be remembered");
        }
        let targets = remember_ssh_target_at(&path, "chetan@192.0.2.2")
            .expect("existing target should move to the front");
        assert_eq!(targets.len(), MAX_RECENT_SSH_TARGETS);
        assert_eq!(
            targets.first().map(String::as_str),
            Some("chetan@192.0.2.2")
        );
        assert_eq!(
            targets
                .iter()
                .filter(|target| *target == "chetan@192.0.2.2")
                .count(),
            1
        );
        assert_eq!(
            load_recent_ssh_targets_from(&path).expect("saved target state should load"),
            targets
        );
        fs::remove_dir_all(directory).expect("temporary state directory should be removable");
    }

    #[test]
    fn concurrent_writers_preserve_every_target() {
        const WRITERS: usize = 8;

        let directory = temporary_directory();
        let path = directory.join("recent-ssh-targets.json");
        let barrier = Arc::new(Barrier::new(WRITERS));
        let writers = (0..WRITERS)
            .map(|index| {
                let barrier = Arc::clone(&barrier);
                let path = path.clone();
                thread::spawn(move || {
                    barrier.wait();
                    remember_ssh_target_at(&path, &format!("writer-{index}"))
                })
            })
            .collect::<Vec<_>>();

        for writer in writers {
            writer
                .join()
                .expect("writer should not panic")
                .expect("writer should preserve valid state");
        }
        let targets = load_recent_ssh_targets_from(&path).expect("saved target state should load");
        assert_eq!(targets.len(), WRITERS);
        for index in 0..WRITERS {
            assert!(targets.contains(&format!("writer-{index}")));
        }
        fs::remove_dir_all(directory).expect("temporary state directory should be removable");
    }

    #[test]
    fn malformed_or_insecure_recent_state_is_ignored_but_writes_stay_strict() {
        let directory = temporary_directory();
        let path = directory.join("recent-ssh-targets.json");

        fs::write(&path, b"not JSON").expect("malformed fixture should be written");
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600))
            .expect("fixture should be private");
        assert!(load_recent_ssh_targets_or_empty(&path).is_empty());
        assert!(remember_ssh_target_at(&path, "host").is_err());

        fs::write(&path, br#"{"targets":["host"]}"#).expect("insecure fixture should be written");
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644))
            .expect("fixture should become insecure");
        assert!(load_recent_ssh_targets_or_empty(&path).is_empty());
        assert!(remember_ssh_target_at(&path, "host").is_err());

        fs::remove_dir_all(directory).expect("temporary state directory should be removable");
    }

    #[test]
    fn recent_state_rejects_oversized_files_before_parsing() {
        let directory = temporary_directory();
        let path = directory.join("recent-ssh-targets.json");
        fs::write(&path, vec![b'x'; 16 * 1024 + 1]).expect("oversized fixture should be written");
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600))
            .expect("fixture should be private");
        assert!(load_recent_ssh_targets_from(&path).is_err());
        fs::remove_dir_all(directory).expect("temporary state directory should be removable");
    }

    fn assert_private_directory(path: &std::path::Path) {
        let metadata = fs::symlink_metadata(path).expect("private directory should exist");
        assert!(metadata.file_type().is_dir());
        assert!(!metadata.file_type().is_symlink());
        assert_eq!(metadata.uid(), super::effective_uid());
        assert_eq!(metadata.permissions().mode() & 0o777, 0o700);
    }
    fn temporary_directory() -> std::path::PathBuf {
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
            "tmux-fleet-runtime-{}-{nonce}-{sequence}",
            std::process::id()
        ));
        fs::create_dir(&directory).expect("temporary state directory should be created");
        fs::set_permissions(&directory, fs::Permissions::from_mode(0o700))
            .expect("temporary state directory should be private");
        directory
    }
}
