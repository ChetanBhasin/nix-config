mod config;
mod controller;
mod daemon;
mod protocol;
mod runtime;
mod ssh;
mod tmux;

use anyhow::Result;
use clap::{Parser, Subcommand};

use config::Config;

#[derive(Debug, Parser)]
#[command(version, about)]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Open the current-host and connected-host session picker.
    Run,
    /// Print the current local tmux session snapshot as JSON.
    Snapshot,
    /// Run the per-user SSH connection and inventory daemon.
    Daemon,
    /// Attach one exact tmux session after validating its server identity.
    #[command(hide = true)]
    AttachExisting {
        #[arg(long)]
        id: String,
        #[arg(long)]
        server_pid: u64,
        #[arg(long)]
        server_started_at: u64,
        #[arg(long)]
        created_at: u64,
    },
    /// Create and attach a new managed tmux session.
    #[command(hide = true)]
    AttachNew,
    /// Attach tmux's most-recent session, or create one when no server exists.
    #[command(hide = true)]
    AttachLatest,
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    let config = Config::load()?;
    match cli.command.unwrap_or(Command::Run) {
        Command::Run => controller::run(config),
        Command::Snapshot => {
            println!(
                "{}",
                serde_json::to_string_pretty(&tmux::snapshot(&config)?)?
            );
            Ok(())
        }
        Command::Daemon => daemon::serve(config),
        Command::AttachExisting {
            id,
            server_pid,
            server_started_at,
            created_at,
        } => {
            let status = tmux::spawn_managed(
                &config,
                tmux::AttachMode::Existing(tmux::ExistingTarget {
                    id,
                    server_pid,
                    server_started_at,
                    created_at,
                }),
            )?
            .wait()?;
            std::process::exit(status.code().unwrap_or(128));
        }
        Command::AttachNew => {
            let status = tmux::spawn_managed(&config, tmux::AttachMode::New(None))?.wait()?;
            std::process::exit(status.code().unwrap_or(128));
        }
        Command::AttachLatest => {
            let status = tmux::attach_latest_or_new(&config)?;
            std::process::exit(status.code().unwrap_or(128));
        }
    }
}
