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
all seven rule groups enabled in the **Linux shortcuts** profile. Later applies
automatically refresh this profile's Nix rule groups and add new ones. Karabiner
reloads changes automatically; removing and reimporting rules is unnecessary.

Custom rule groups, their priority, device settings, other profiles and the
selected profile are preserved. Edits to the Nix rule groups in Karabiner are
replaced on apply; make those changes in `home/darwin/karabiner.nix` instead.
Keep their descriptions unchanged so activation can identify them.

An existing config without a **Linux shortcuts** profile is left unchanged.
Create a profile with that name and select it to receive automatic updates.
For another profile, add rules manually from **Complex Modifications → Add
predefined rule → nix-config keyboard shortcuts**; those copies are not refreshed.

## Ctrl shortcuts

In GUI apps, Ctrl plus **A, C, D, F, G, K, L, N, O, P, Q, R, S, T, V, W, X, Z**
sends the corresponding Command shortcut. Both Control keys work, and Shift
is preserved, including Ctrl+Shift+Z for redo, except Ctrl+Shift+Q (to avoid the
macOS logout shortcut). Slack accepts Ctrl+K; Ctrl+C/X/V
copy, cut and paste. Ctrl+plus/minus/0 controls zoom where the app supports it.
Original Command shortcuts keep working.

Alacritty, Terminal, iTerm2, kitty and WezTerm preserve ordinary Ctrl commands,
including Ctrl+C, Ctrl+Z, Ctrl+K and tmux's Ctrl+Space. Use **Ctrl+Shift+C/V**
for terminal copy/paste. Alacritty sends the CSI-u Ctrl+Space sequence that the
old Hammerspoon handler injected. Activation disables macOS's **Select the
previous input source** shortcut so Ctrl+Space reaches tmux, preserving other
system shortcuts.

These are common aliases rather than a complete Linux keyboard layer. Other
Ctrl combinations retain their app behavior; Ctrl+H does not become Command+H
(Hide). To resolve an app-specific conflict, edit the GUI rule's application
condition. Boris is unchanged: its Linux config still swaps physical Ctrl and Super.

## Text navigation

Outside the five terminals above, these shortcuts send macOS's native editing
commands. Both Control keys work; hold Shift with Home/End to select text.

| Shortcut | Action while editing | macOS shortcut sent |
| --- | --- | --- |
| Ctrl+Backspace | Delete the previous word | Option+Backspace |
| Home/End | Move to the start/end of the line | Command+Left/Right |

Ctrl+Left/Right switches workspaces in every app. Use native Option+Left/Right
to move by word in GUI apps.
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

## Mouse workspace switching

Enable **Modify events** for the mouse in Karabiner's **Devices** tab. The
**Linux shortcuts** profile receives the workspace rule automatically on apply.
The LIFT connected through a Bolt receiver appears as **USB Receiver**.

The directions match the previous OpenLogi configuration:

| Mouse button | Action | macOS shortcut sent |
| --- | --- | --- |
| Back (`button4`) | Next workspace | Ctrl+Right |
| Forward (`button5`) | Previous workspace | Ctrl+Left |

Keep **Move left a space** and **Move right a space** enabled under macOS
**Keyboard → Keyboard Shortcuts → Mission Control**. Karabiner emits these
shortcuts directly, so the text-navigation rules do not change them.

OpenLogi is no longer installed on Darwin. The LIFT's DPI button does not
produce an event in Karabiner, so its former screenshot action is dropped.

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
