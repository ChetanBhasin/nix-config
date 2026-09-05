# Pi Settings Hub

A live Pi extension that turns `/settings` into a unified control center while preserving access to Pi's native settings screen.

## What it manages

- Core Pi settings through the native `/settings` UI
- Models, scoped models, accounts, Codex configuration, and usage
- Active/default tools
- Global package resources: extensions, skills, prompts, and themes
- Extension-provided settings and runtime controls
- Advanced JSON/JSONC configuration with validation and atomic writes

## Commands

- `/settings` — open the unified hub (intercepted in interactive TUI mode)
- `/settings-hub` — explicit fallback command

The extension wraps the active editor factory rather than replacing editor behavior. Selecting **Core Pi settings** delegates directly to Pi's original `/settings` handler.

Package/resource and raw configuration changes prompt for `/reload` because extension state is initialized at session startup.

## Safety

- Advanced editors reject invalid JSON/JSONC.
- Saves use a same-directory temporary file and atomic rename.
- Existing file permissions are preserved.
- Symbolic-link targets are refused rather than replaced.
- Credential files are intentionally excluded from raw editing.
