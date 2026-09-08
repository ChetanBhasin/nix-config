mod config;
mod controller;
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
    /// Open the current-host session and SSH target picker.
    Run,
    /// Print the current local tmux session snapshot as JSON.
    Snapshot,
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
        Command::AttachLatest => {
            let status = tmux::attach_latest_or_new(&config)?;
            std::process::exit(status.code().unwrap_or(128));
        }
    }
}
