mod config;
mod controller;
mod protocol;
mod runtime;
mod ssh;
mod tmux;

use anyhow::Result;
use clap::{Parser, Subcommand};

use config::Config;
use tmux::{AttachMode, ExistingTarget};

#[derive(Debug, Parser)]
#[command(version, about)]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Open the cached local/SSH session picker and supervise attachments.
    Run,
    /// Stream an initial snapshot and hook-driven updates as JSON lines.
    #[command(hide = true)]
    Watch {
        #[arg(long)]
        reconcile_seconds: Option<u64>,
    },
    /// Notify every watcher on this host that tmux state changed.
    #[command(hide = true)]
    Notify,
    /// Print the current local tmux session snapshot as JSON.
    Snapshot,
    /// Attach a managed tmux client whose Prefix s may return exit 42.
    #[command(hide = true)]
    Attach {
        #[arg(long)]
        new: bool,
        #[arg(long)]
        session_hex: Option<String>,
        #[arg(long)]
        server_started_at: Option<u64>,
        #[arg(long)]
        created_at: Option<u64>,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let config = Config::load()?;
    match cli.command.unwrap_or(Command::Run) {
        Command::Run => controller::run(config),
        Command::Watch { reconcile_seconds } => tmux::run_watch(
            &config,
            reconcile_seconds.unwrap_or(config.reconcile_seconds),
        ),
        Command::Notify => tmux::notify_watchers(),
        Command::Snapshot => {
            println!(
                "{}",
                serde_json::to_string_pretty(&tmux::snapshot(&config)?)?
            );
            Ok(())
        }
        Command::Attach {
            new,
            session_hex,
            server_started_at,
            created_at,
        } => {
            let target = session_hex
                .as_deref()
                .map(runtime::hex_decode)
                .transpose()?;
            let mode = if new {
                AttachMode::New(target)
            } else {
                let id = target
                    .ok_or_else(|| anyhow::anyhow!("--session-hex is required without --new"))?;
                let server_started_at = server_started_at.ok_or_else(|| {
                    anyhow::anyhow!("--server-started-at is required without --new")
                })?;
                let created_at = created_at
                    .ok_or_else(|| anyhow::anyhow!("--created-at is required without --new"))?;
                AttachMode::Existing(ExistingTarget {
                    id,
                    server_started_at,
                    created_at,
                })
            };
            let child = tmux::spawn_managed(&config, mode)?;
            let status = child.wait()?;
            std::process::exit(status.code().unwrap_or(128));
        }
    }
}
