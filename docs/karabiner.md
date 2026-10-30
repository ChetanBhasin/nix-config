# macOS keyboard shortcuts

Karabiner-Elements replaces Hammerspoon on both Macs. Homebrew installs the
official signed app because the pinned nix-darwin service uses an obsolete
Karabiner service layout ([upstream issue](https://github.com/nix-darwin/nix-darwin/issues/1041)).
Rules live in `home/darwin/karabiner.nix`.

## Setup and updates

Run `make build-darwin host=hugh`, then `make apply-darwin host=hugh` (use
`host=markus` on Markus). Open Karabiner-Elements and complete its
[setup prompts](https://karabiner-elements.pqrs.org/docs/getting-started/installation/)
for background services, input access and its virtual keyboard driver. Select
the keyboard type that matches your hardware. macOS permissions require your
interaction; Hammerspoon is uninstalled on apply.

The first activation seeds a writable `~/.config/karabiner/karabiner.json` with
all six rule groups enabled. Existing profiles and UI changes are preserved.
To enable these rules in an existing profile, open **Complex Modifications →
Add predefined rule** and add the groups under **nix-config keyboard shortcuts**.

The importable asset is managed by Nix; Karabiner copies enabled rules into its
own config. After changing the Nix rules and applying, remove only the old
enabled groups from this repository and add them again from **Add predefined rule**.
Do not reset your entire config: activation never overwrites it.

## Ctrl shortcuts

In GUI apps, Ctrl plus **A, C, D, F, G, K, L, N, O, P, Q, R, S, T, V, W, X, Z**
sends the corresponding Command shortcut. Both Control keys work, and Shift
is preserved, including Ctrl+Shift+Z for redo, except Ctrl+Shift+Q (to avoid the
macOS logout shortcut). Slack accepts Ctrl+K; Ctrl+C/X/V
copy, cut and paste. Ctrl+plus/minus/0 controls zoom where the app supports it.
Original Command shortcuts keep working.

Alacritty, Terminal, iTerm2, kitty and WezTerm preserve ordinary Ctrl commands,
including Ctrl+C, Ctrl+Z, Ctrl+K and tmux's Ctrl+Space. Use **Ctrl+Shift+C/V**
for terminal copy/paste. Alacritty already sends the CSI-u Ctrl+Space sequence
that the old Hammerspoon handler injected. On other Macs, disable the macOS
**Keyboard → Keyboard Shortcuts → Input Sources → Select the previous input source**
Ctrl+Space binding if it intercepts tmux's prefix.

These are common aliases rather than a complete Linux keyboard layer. Other
Ctrl combinations retain their app behavior; Ctrl+H does not become Command+H
(Hide). To resolve an app-specific conflict, edit the GUI rule's application
condition. Boris is unchanged: its Linux config still swaps physical Ctrl and Super.

## Text navigation

Outside the five terminals above, these shortcuts send macOS's native editing
commands. Both Control keys work; hold Shift with movement keys to select text.

| Shortcut | Action while editing | macOS shortcut sent |
| --- | --- | --- |
| Ctrl+Left/Right | Move one word | Option+Left/Right |
| Ctrl+Backspace | Delete the previous word | Option+Backspace |
| Home/End | Move to the start/end of the line | Command+Left/Right |

Ctrl+Left/Right therefore replaces macOS desktop switching in these apps.
Home/End follow the focused app's Command-arrow behavior: outside a text field,
browsers may navigate back/forward instead of moving a cursor. See the
[Apple editing shortcuts](https://support.apple.com/en-us/102650) and
[Chrome shortcuts](https://support.google.com/chrome/answer/157179).
Ctrl+Shift+Backspace and Ctrl+Home/End retain their existing behavior.

## Application switching

**Alt+Tab** (Option+Tab on a Mac keyboard) opens the native macOS app switcher.
Keep Alt held and press Tab again to cycle; **Alt+Shift+Tab** cycles backwards.
Release Alt to select the app. Both Option keys work, including in terminals.
This switches applications, rather than individual windows, and Cmd+Tab still works.

The [held-modifier rule](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/to-if-other-key-pressed/)
requires Karabiner-Elements 16 or newer. Ordinary Option typing and the existing
Ctrl+Option window shortcuts and Cmd+Option launchers keep working.

## Window placement and app launchers

| Shortcut | Action |
| --- | --- |
| Ctrl+Option+Return | Fill desktop |
| Ctrl+Option+Left/Right/Up/Down | Corresponding screen half |
| Ctrl+Option+C | Center window |

These emit macOS's [native Fn+Ctrl window shortcuts](https://support.apple.com/en-au/guide/mac-help/mchl9674d0b0/26/mac/26)
and require macOS 15 or newer. Native tiling follows app size constraints,
app support and the **Desktop & Dock → Tiled windows have margins** setting,
so placement can differ slightly from Hammerspoon.

The existing **Command+Option+letter** app launchers are preserved:

| Key | App | Key | App | Key | App |
| --- | --- | --- | --- | --- | --- |
| B | Zen | T | Alacritty | F | Figma |
| E | Signal | S | Spotify | M | Mail |
| O | Messages | W | WhatsApp | G | Discord |
| X | Xcode | L | Slack | Z | zoom.us |
| N | Obsidian | H | IBKR Desktop | V | ProtonVPN |
