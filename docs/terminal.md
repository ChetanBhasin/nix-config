# Terminal Configuration Guide

This guide covers the comprehensive terminal setup including Zsh, Alacritty, and tmux configurations optimized for development workflows.

## 🚀 **Key Improvements Summary**

### ✅ **What We've Achieved**
1. **🎯 Command Palette System** - Legendary-style interface for tmux operations
2. **🔍 FZF Integration** - Fuzzy finding throughout the terminal stack
3. **🔧 Modern Plugin Ecosystem** - Updated to latest, maintained plugins
4. **💾 Session Persistence** - Automatic save/restore with smart management
5. **🎨 Beautiful Status Line** - Informative, themed status with system info
6. **⌨️ Conflict-Free Keybindings** - No more Ctrl+L conflicts, intuitive patterns
7. **🐚 Proper Shell Integration** - Nix-managed shell paths and environment

### 🎯 **Quick Start**
- **Command Palette**: `C-Space Space` - Your central hub for all operations
- **FZF Menu**: `C-Space f` - Fuzzy find sessions, windows, files, processes
- **Project Switcher**: `C-Space P` - Jump between your ~/Projects instantly
- **Session Switcher**: `C-Space s` - FZF-powered session navigation
- **Help System**: `C-Space F1` - Built-in documentation

---

## 📋 Table of Contents

- [🎯 Overview](#-overview)
- [✨ Key Features](#-key-features)
- [🚀 Getting Started](#-getting-started)
- [⌨️ Keyboard Shortcuts](#️-keyboard-shortcuts)
- [🔍 FZF Integration](#-fzf-integration)
- [🐚 Enhanced Shell Features](#-enhanced-shell-features)
- [🖥️ Alacritty Terminal](#️-alacritty-terminal)
- [🛠️ Configuration Files](#️-configuration-files)
- [🔧 Troubleshooting](#-troubleshooting)
- [⚡ Performance Tips](#-performance-tips)
- [🎓 Advanced Usage](#-advanced-usage)
- [🖥️ Tmux Configuration](#️-tmux-configuration)

---

## 🎯 Overview

This terminal configuration transforms your command-line experience into a **modern, productive development environment** with:

- **Alacritty**: Fast, GPU-accelerated terminal emulator with excellent cross-platform support
- **Zsh**: Enhanced shell with vi-mode, autosuggestions, and syntax highlighting  
- **FZF**: Fuzzy finder for history search, file navigation, and more
- **Enhanced CLI Tools**: Modern replacements for traditional Unix tools
- **Smart History**: 50K entries with deduplication and intelligent search
- **Git Integration**: Interactive git operations with visual previews

### 🏗️ Architecture

```
📁 Terminal Configuration Structure
├─ 🖥️ Alacritty Terminal        → GPU-accelerated terminal emulator
├─ 🐚 Zsh Shell                 → Enhanced shell with plugins
├─ 🔍 FZF Integration           → Fuzzy finding for everything
├─ 🛠️ Modern CLI Tools          → bat, ripgrep, fd, exa, etc.
└─ 📚 Rich Documentation        → Comprehensive guides and tips
```

---

## ✨ Key Features

### 🔍 **FZF Integration (Fuzzy Finder)**
- **Ctrl+R**: Fuzzy search through command history with preview
- **Ctrl+T**: Fuzzy file finder with syntax highlighting preview
- **Alt+C**: Fuzzy directory navigation with tree preview
- **Ctrl+Y**: Copy selected command to clipboard (in history search)
- **Ctrl+/**: Toggle preview window in any FZF interface

### 🛠️ **Enhanced Commands**
```bash
# Modern CLI tool aliases (automatically applied)
cat → bat          # Syntax highlighting and paging
grep → ripgrep     # Faster, better search with colors
find → fd          # Faster, more intuitive file finding
ls → exa           # Better file listing with git status
top → htop         # Better process viewer
du → dust          # Better disk usage visualization
df → duf           # Better filesystem info with colors
ps → procs         # Better process listing with colors
```

### 🎯 **Git Integration Functions**
```bash
fzf_git_log    # Interactive git log browser with previews
fzf_git_branch # Interactive branch switcher with commit info
fzf_kill       # Interactive process killer with search
fzf_env        # Interactive environment variable browser
```

### 📚 **History Management**
```bash
hist_search    # Alternative history search with FZF
hist_stats     # Show most used commands statistics
```

### 🎨 **Visual Enhancements**
- **Gruvbox dark theme** integration across all tools
- **Syntax highlighting** in file previews
- **Git status indicators** in file listings
- **Color-coded output** for better readability

---

## 🚀 Getting Started

### 1. **Apply Configuration**
```bash
# Navigate to your nix-config directory
cd ~/path/to/nix-config

# Apply the configuration
home-manager switch

# For system-wide changes (if needed)
sudo darwin-rebuild switch
```

### 2. **Restart Terminal**
Close and reopen Alacritty to load the new configuration.

### 3. **Verify Installation**
```bash
# Check FZF installation
which fzf        # Should show ~/.nix-profile/bin/fzf
fzf --version    # Should show 0.62.0+

# Verify key bindings
bindkey | grep "^R"  # Should show fzf-history-widget

# Test modern tools
bat --version    # Syntax highlighter
rg --version     # Ripgrep
fd --version     # File finder
exa --version    # Enhanced ls
```

### 4. **Essential First Steps**
- **History search**: Press `Ctrl+R` and start typing
- **File finder**: Press `Ctrl+T` to find files
- **Directory navigation**: Press `Alt+C` to change directories
- **Try new commands**: Use `ll`, `cat some_file.txt`, `grep pattern`

---

## ⌨️ Keyboard Shortcuts

### 🔍 **FZF Core Shortcuts**
| Shortcut | Action | Description |
|----------|--------|-------------|
| `Ctrl+R` | **History Search** | Fuzzy search command history with preview |
| `Ctrl+T` | **File Finder** | Find files with syntax highlighting preview |
| `Alt+C` | **Directory Nav** | Navigate directories with tree preview |
| `Ctrl+Y` | **Copy Command** | Copy selected command to clipboard (in history) |
| `Ctrl+/` | **Toggle Preview** | Show/hide preview in any FZF interface |

### 🖥️ **Alacritty Terminal**
| Shortcut | Action | Description |
|----------|--------|-------------|
| `Cmd+N` | New window | Create new terminal window |
| `Cmd+W` | Close | Close current window |
| `Cmd+K` | Clear | Clear terminal history |
| `Cmd+C/V` | Copy/Paste | Standard clipboard operations |
| `Cmd++/-/0` | Font size | Increase/decrease/reset font size |
| `Super+1-9` | Switch tmux window | Jump to tmux window 1-9 (Super = Cmd on macOS, Ctrl+Shift on Linux) |

### 🐚 **Zsh Navigation**
| Shortcut | Action | Description |
|----------|--------|-------------|
| `Ctrl+A` | Beginning of line | Jump to start of command |
| `Ctrl+E` | End of line | Jump to end of command |
| `Ctrl+U` | Clear line | Delete entire command line |
| `Ctrl+W` | Delete word | Delete word before cursor |
| `Ctrl+L` | Clear screen | Clear terminal (alternative) |

---

## 🔍 FZF Integration

### 🎯 **Core Features**

FZF (Fuzzy Finder) is the heart of the enhanced terminal experience, providing:

#### **1. Command History Search (Ctrl+R)**
- **Fuzzy matching**: Type partial commands, get intelligent matches
- **Preview window**: See full command before executing
- **Copy to clipboard**: `Ctrl+Y` to copy without executing
- **Chronological toggle**: `Ctrl+R` again to sort by time vs relevance

#### **2. File Finding (Ctrl+T)**
- **Respects .gitignore**: Automatically excludes ignored files
- **Syntax highlighting**: Preview files with `bat` integration
- **Multiple selection**: `Tab` to select multiple files
- **Smart filtering**: Exclude hidden files by default, include with options

#### **3. Directory Navigation (Alt+C)**
- **Tree preview**: See directory structure before changing
- **Smart completion**: Works with partial directory names
- **Hidden directories**: Includes hidden dirs when needed

### 🎨 **Visual Configuration**

FZF is configured with a beautiful **Gruvbox-inspired theme**:
- **Dark background** with high contrast
- **Warm highlights** for selected items
- **Blue accents** for information text
- **Consistent theming** across all interfaces

### ⚙️ **Environment Variables**

The configuration sets up these FZF environment variables:

```bash
# Default command (uses fd for better performance)
FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'

# File finder options
FZF_CTRL_T_OPTS="--preview 'bat --color=always --line-range :50 {}'"

# History search options  
FZF_CTRL_R_OPTS="--preview 'echo {}' --bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'"

# Directory navigation options
FZF_ALT_C_OPTS="--preview 'tree -C {} | head -200'"
```

---

## 🐚 Enhanced Shell Features

### 🎯 **Modern CLI Tool Aliases**

The configuration automatically replaces traditional Unix tools with modern alternatives:

```bash
# File Operations
ls → exa           # Enhanced listing with git status, icons
ll → exa -la --git --header  # Detailed listing with git info
lt → exa --tree --level=2    # Tree view with 2 levels
cat → bat          # Syntax highlighting, line numbers, paging

# Search and Find
grep → ripgrep     # Faster search with better output
find → fd          # Intuitive syntax, faster performance

# System Monitoring
top → htop         # Interactive process viewer
du → dust          # Visual disk usage
df → duf           # Colorful filesystem info
ps → procs         # Modern process listing
```

### 🎯 **Git Productivity Aliases**

Quick git shortcuts for common operations:

```bash
gs  → git status              # Quick status check
gd  → git diff               # Show changes
gl  → git log --oneline --graph --decorate  # Pretty log
gb  → git branch             # List branches
gc  → git checkout           # Switch branches
gp  → git pull               # Pull changes
gps → git push               # Push changes
```

### 🔍 **FZF-Powered Functions**

Interactive functions that leverage FZF for better UX:

#### **Git Operations**
```bash
fzf_git_log     # Browse git log with commit previews
fzf_git_branch  # Switch branches interactively
```

#### **System Operations**
```bash
fzf_kill        # Find and kill processes interactively
fzf_env         # Browse environment variables
```

#### **History Management**
```bash
hist_search     # Alternative history search
hist_stats      # Show command usage statistics
```

### 📚 **Enhanced History Configuration**

- **50,000 entries**: Massive history for long-term reference
- **Deduplication**: Automatic removal of duplicate commands
- **Session sharing**: History shared across all terminal sessions
- **Smart ignore**: Ignores commands starting with space
- **Persistence**: History survives system restarts

---

## 🖥️ Alacritty Terminal

### 🎯 **Key Features**

Alacritty is configured as a **modern, GPU-accelerated terminal emulator** with:

#### **Performance**
- **GPU-accelerated rendering**: Smooth scrolling and fast output
- **Cross-platform**: Works on macOS, Linux, and Windows
- **Low latency**: Minimal input lag for responsive typing

#### **macOS Integration**
- **Native look and feel**: Buttonless window decorations
- **Option as Alt**: Left option key works as Alt for terminal apps
- **Copy on select**: Automatic clipboard integration

#### **Developer Features**
- **Tmux integration**: Super+1-9 switches tmux windows directly (Super = Cmd on macOS, Ctrl+Shift on Linux)
- **Theme support**: Uses alacritty-theme package for easy theming
- **Customizable keybindings**: Productivity-focused shortcuts

### 🎨 **Visual Configuration**

- **Theme**: Gruvbox dark for consistent dark theme
- **Font**: JetBrains Mono Nerd Font at 14pt for excellent readability
- **Cursor**: Block cursor with unfocused hollow
- **Padding**: 8px padding for comfortable viewing
- **Window**: 150x100 dimensions with dynamic padding

### ⌨️ **Productivity Keybindings**

The configuration includes **macOS-friendly keybindings**:

```bash
# Window Management (macOS)
Cmd+N           # New window
Cmd+W           # Close current window
Cmd+K           # Clear history
Cmd+C/V         # Copy/Paste
Cmd++/-/0       # Font size control

# Tmux Window Switching (cross-platform "Super" key)
Super+1-9       # Switch to tmux window 1-9
                # Super = Cmd (macOS) or Ctrl+Shift (Linux)
```

The "Super" key abstraction allows the same mental model across platforms while using the natural modifier for each OS.

---

## 🛠️ Configuration Files

### 📁 **File Structure**

```
home/
├── zsh/
│   ├── default.nix          # Main Zsh configuration
│   └── sources.sh           # Shell environment and functions
├── defaultPrograms/
│   └── default.nix          # Program integration (includes Alacritty)
└── default.nix              # Package definitions
```

### 🐚 **Zsh Configuration (`home/zsh/default.nix`)**

**Key features configured**:
- **FZF integration**: Proper shell bindings for all FZF features
- **Plugin management**: Autosuggestions, syntax highlighting, fzf-tab
- **History settings**: 50K entries with smart deduplication
- **Vi-mode**: Vi keybindings with insert mode as default
- **Modern tool integration**: Automatic setup for enhanced CLI tools

**Important settings**:
```nix
programs.fzf = {
  enable = true;
  enableZshIntegration = true;
  # Comprehensive FZF configuration with previews and keybindings
};

history = {
  size = 50000;
  save = 50000;
  share = true;
  ignoreDups = true;
  ignoreSpace = true;
  expireDuplicatesFirst = true;
};
```

### 🌍 **Shell Environment (`home/zsh/sources.sh`)**

**Contains**:
- **FZF environment variables**: Custom colors, preview commands, keybindings
- **Modern CLI aliases**: Automatic replacement of traditional tools
- **Git productivity shortcuts**: Quick git operations
- **FZF-powered functions**: Interactive git, process, and history management
- **Safe credential loading**: Conditional sourcing of sensitive files

**Key environment variables**:
```bash
# FZF with custom colors and options
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border --inline-info"

# Enhanced commands with fd and bat
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
```

### 🖥️ **Alacritty Configuration (`home/defaultPrograms/default.nix`)**

**Optimized for**:
- **Cross-platform**: Works on macOS and Linux
- **Tmux integration**: Super+1-9 switches tmux windows (Cmd on macOS, Ctrl+Shift on Linux)
- **Visual consistency**: Gruvbox dark theme
- **Performance**: GPU-accelerated rendering

**Key settings**:
```nix
programs.alacritty = {
  enable = true;
  theme = "gruvbox_dark";
  settings = {
    font.normal.family = "JetBrainsMono Nerd Font";
    font.size = 14.0;
    window.option_as_alt = "OnlyLeft";  # macOS
    selection.save_to_clipboard = true;
  };
};
```

### 📦 **Package Dependencies (`home/default.nix`)**

**Modern CLI tools included**:
```nix
# Enhanced replacements
bat          # Better cat with syntax highlighting
ripgrep      # Better grep with colors and speed
fd           # Better find with intuitive syntax
exa          # Better ls with git integration
dust         # Better du with visualization
duf          # Better df with colors
procs        # Better ps with modern output
tree         # Directory tree visualization
fzf          # Fuzzy finder core
```

---

## 🔧 Troubleshooting

### 🚨 **Common Issues & Solutions**

#### **1. Ctrl+R Not Working**
**Symptoms**: Pressing Ctrl+R doesn't open FZF history search

**Diagnosis**:
```bash
# Check key binding
bindkey | grep "^R"
# Should show: "^R" fzf-history-widget
# If shows: "^R" redisplay → FZF not properly configured

# Check FZF installation
which fzf  # Should show ~/.nix-profile/bin/fzf
fzf --version  # Should show 0.62.0+
```

**Solutions**:
1. **Rebuild configuration**:
   ```bash
   home-manager switch
   ```
2. **Restart terminal**: Close and reopen Alacritty
3. **Manual fix** (if needed):
   ```bash
   # Source FZF manually to test
   source ~/.nix-profile/share/fzf/key-bindings.zsh
   ```

#### **2. FZF Preview Not Working**
**Symptoms**: FZF opens but no preview window or broken previews

**Diagnosis**:
```bash
# Check preview dependencies
bat --version    # For file previews
tree --version   # For directory previews
fd --version     # For file finding
```

**Solutions**:
1. **Verify tools are in PATH**:
   ```bash
   which bat tree fd  # All should show ~/.nix-profile/bin/...
   ```
2. **Test preview manually**:
   ```bash
   echo "test" | fzf --preview 'bat --color=always {}'
   ```

#### **3. Modern CLI Tools Not Working**
**Symptoms**: `cat`, `grep`, `ls` still use old versions

**Diagnosis**:
```bash
# Check aliases
alias | grep -E "cat|grep|ls"
# Should show modern tool replacements

# Check tool availability
which bat rg exa  # Should all be available
```

**Solutions**:
1. **Reload shell configuration**:
   ```bash
   source ~/.zshrc
   # Or restart terminal
   ```
2. **Check Nix profile**:
   ```bash
   nix profile list | grep -E "bat|ripgrep|exa"
   ```

#### **4. Alacritty Configuration Not Applied**
**Symptoms**: Alacritty doesn't match expected appearance/behavior

**Diagnosis**:
```bash
# Check config file location
ls -la ~/.config/alacritty/alacritty.toml
# Should exist and contain your settings

# Check Alacritty version
alacritty --version
```

**Solutions**:
1. **Restart Alacritty**: Close and reopen application (config is loaded on startup)
2. **Verify config syntax**: Check for TOML syntax errors in config file
3. **Rebuild home-manager**: `home-manager switch`

#### **5. Zsh Plugins Not Loading**
**Symptoms**: No syntax highlighting, autosuggestions, or tab completion

**Diagnosis**:
```bash
# Check plugin status
echo $fpath | tr ':' '\n' | grep -E "zsh-|fzf"
# Should show plugin paths

# Test specific features
# Type a command and see if it highlights
# Press Tab to test completion
```

**Solutions**:
1. **Rebuild home-manager**:
   ```bash
   home-manager switch
   ```
2. **Clear Zsh cache**:
   ```bash
   rm -rf ~/.zcompdump*
   compinit
   ```

### 🔍 **Debugging Commands**

```bash
# FZF debugging
echo $FZF_DEFAULT_COMMAND
echo $FZF_DEFAULT_OPTS
bindkey | grep fzf

# Zsh debugging
echo $SHELL
zsh --version
echo $fpath

# Tool availability
which fzf bat rg fd exa tree dust duf procs

# Configuration files
ls -la ~/.config/alacritty/
ls -la ~/.nix-profile/share/fzf/
```

### 🚑 **Emergency Reset**

If everything breaks:

```bash
# 1. Reset Nix profile
nix profile remove '.*'
home-manager switch

# 2. Clear Zsh cache
rm -rf ~/.zcompdump* ~/.zsh_history

# 3. Restart terminal completely
# Close all Alacritty windows and reopen

# 4. Test basic functionality
fzf --version
echo "test" | fzf
```

---

## ⚡ Performance Tips

### 🚀 **Optimization Strategies**

#### **1. Large Repository Performance**
```bash
# FZF automatically respects .gitignore for speed
# For very large repos, you can limit depth:
export FZF_DEFAULT_COMMAND='fd --type f --max-depth 5 --exclude .git'

# Or exclude specific large directories:
export FZF_DEFAULT_COMMAND='fd --type f --exclude node_modules --exclude target --exclude .git'
```

#### **2. History Search Optimization**
```bash
# Use exact mode for faster searches in large history
# In FZF: type 'exact-term (with single quotes for exact match)

# Or configure exact mode by default for history:
export FZF_CTRL_R_OPTS="$FZF_CTRL_R_OPTS --exact"
```

#### **3. Shell Startup Speed**
```bash
# Profile shell startup time
time zsh -i -c exit

# If slow, disable specific plugins temporarily to identify bottlenecks
# Check plugin loading in home/zsh/default.nix
```

#### **4. FZF Preview Performance**
```bash
# Limit preview size for large files
export FZF_CTRL_T_OPTS="--preview 'bat --color=always --line-range :100 {}'"

# Disable preview for very large directories
export FZF_ALT_C_OPTS="--preview 'if [ \$(find {} -maxdepth 1 | wc -l) -lt 100 ]; then tree -C {} | head -200; fi'"
```

### 📊 **Performance Monitoring**

```bash
# Monitor FZF performance
time find . -type f | fzf --filter "search-term"

# Monitor shell startup
hyperfine 'zsh -i -c exit'

# Monitor tool performance
hyperfine 'rg "pattern" .' 'grep -r "pattern" .'
hyperfine 'fd "pattern"' 'find . -name "*pattern*"'
```

---

## 🎓 Advanced Usage

### 🔍 **Custom FZF Commands**

Create your own FZF-powered functions:

```bash
# Search and edit files
fe() { 
  local file
  file=$(fzf --preview 'bat --color=always {}') && [ -f "$file" ] && $EDITOR "$file"
}

# Search and cd to directory
fcd() {
  local dir
  dir=$(fd --type d | fzf --preview 'tree -C {} | head -200') && [ -d "$dir" ] && cd "$dir"
}

# Search git commits and show
fshow() {
  git log --oneline --color=always | 
  fzf --ansi --preview 'git show --color=always {1}' --bind 'enter:execute(git show {1} | less -R)'
}

# Search processes and get details
fproc() {
  procs | fzf --header-lines=1 --preview 'echo {}' --bind 'enter:execute(kill -9 {1})'
}

# Search environment variables
fenv() {
  env | sort | fzf --preview 'echo "Variable: {1}" | cut -d= -f1'
}
```

### 🎯 **Git Integration Workflows**

#### **Interactive Git Operations**
```bash
# Browse git log with file changes
fzf_git_log_files() {
  git log --oneline --color=always | 
  fzf --ansi --preview 'git show --stat --color=always {1}'
}

# Interactive branch management
fzf_git_branch_manager() {
  git branch -a | grep -v HEAD | sed 's/^..//' | 
  fzf --preview 'git log --oneline --color=always {}' \
      --bind 'enter:execute(git checkout {})'
      --bind 'ctrl-d:execute(git branch -d {})'
      --bind 'ctrl-r:execute(git branch -m {} {q})'
}

# Interactive stash management
fzf_git_stash() {
  git stash list | 
  fzf --preview 'git stash show -p {1}' \
      --bind 'enter:execute(git stash apply {1})'
      --bind 'ctrl-d:execute(git stash drop {1})'
}
```

#### **File History and Blame**
```bash
# Browse file history
fzf_file_history() {
  git log --oneline --follow -- "$1" | 
  fzf --preview "git show --color=always {1} -- $1"
}

# Interactive git blame
fzf_git_blame() {
  git blame --line-porcelain "$1" | 
  fzf --preview 'git show --color=always {1}'
}
```

### 🛠️ **System Administration**

#### **Process Management**
```bash
# Interactive process tree
fzf_process_tree() {
  pstree -p | fzf --preview 'ps -f -p {-1}'
}

# Service management (macOS)
fzf_services() {
  launchctl list | fzf --header-lines=1 --preview 'launchctl print {3}'
}

# Network connections
fzf_network() {
  netstat -an | fzf --preview 'lsof -i :{-1}'
}
```

#### **File System Operations**
```bash
# Disk usage explorer
fzf_disk_usage() {
  dust -d 1 | fzf --preview 'dust {-1}'
}

# Large file finder
fzf_large_files() {
  fd --type f --exec stat -f "%z %N" {} \; | sort -rn | 
  fzf --preview 'ls -lh {2..} && echo "---" && head {2..}'
}

# Recent files
fzf_recent_files() {
  fd --type f --exec stat -f "%m %N" {} \; | sort -rn | head -100 |
  fzf --preview 'ls -lh {2..} && echo "---" && bat --color=always {2..}'
}
```

### 🔧 **Development Workflows**

#### **Project Management**
```bash
# Project switcher
fzf_projects() {
  find ~/Projects -maxdepth 2 -type d -name ".git" | sed 's|/.git||' |
  fzf --preview 'ls -la {} && echo "---" && git -C {} log --oneline -10'
}

# Docker container management
fzf_docker() {
  docker ps -a | fzf --header-lines=1 \
    --preview 'docker inspect {1}' \
    --bind 'enter:execute(docker exec -it {1} /bin/bash)'
}

# Log file browser
fzf_logs() {
  fd "\.log$" /var/log ~/Library/Logs 2>/dev/null |
  fzf --preview 'tail -100 {} | bat --color=always -l log'
}
```

#### **Code Navigation**
```bash
# Function finder (works with many languages)
fzf_functions() {
  rg "^(function|def|fn|func)" --line-number --no-heading . |
  fzf --delimiter : --preview 'bat --color=always --highlight-line {2} {1}'
}

# TODO/FIXME finder
fzf_todos() {
  rg "(TODO|FIXME|HACK|XXX|BUG)" --line-number --no-heading . |
  fzf --delimiter : --preview 'bat --color=always --highlight-line {2} {1}'
}

# Import/require finder
fzf_imports() {
  rg "(import|require|use|include)" --line-number --no-heading . |
  fzf --delimiter : --preview 'bat --color=always --highlight-line {2} {1}'
}
```

### 🎨 **Customization Examples**

#### **Theme Customization**
```bash
# Light theme for FZF
export FZF_DEFAULT_OPTS="
  --color=bg+:#ccd0da,bg:#eff1f5,spinner:#dc8a78,hl:#d20f39
  --color=fg:#4c4f69,header:#d20f39,info:#8839ef,pointer:#dc8a78
  --color=marker:#dc8a78,fg+:#4c4f69,prompt:#8839ef,hl+:#d20f39"

# Custom preview commands
export FZF_CTRL_T_OPTS="
  --preview '([[ -f {} ]] && (bat --style=numbers --color=always {} || cat {})) || 
             ([[ -d {} ]] && (tree -C {} | head -200)) || 
             echo {} 2> /dev/null | head -200'"
```

#### **Keybinding Customization**
```bash
# Custom FZF keybindings
export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS
  --bind 'ctrl-a:select-all'
  --bind 'ctrl-d:deselect-all'
  --bind 'ctrl-t:toggle-all'
  --bind 'alt-up:preview-page-up'
  --bind 'alt-down:preview-page-down'"
```

---

## 🎯 **Integration with Other Tools**

### 🚀 **Neovim Integration**
- **Telescope**: FZF-style file finding within Neovim
- **File navigation**: Consistent fuzzy finding experience
- **Git integration**: Same git functions work in terminal and editor

### 🖥️ **Tmux Configuration**

#### 🎯 **Command Palette System**
Like Legendary in Neovim or VS Code's Command Palette:

**Primary Command Palette:**
- `Ctrl+g Space` - Opens the main command palette
- Organized by categories: Sessions, Windows, Panes, Utilities
- Visual documentation for all commands

**FZF Integration Menu:**
- `Ctrl+g f` - Opens FZF-powered menu
- Switch sessions, find windows, manage processes
- File browsing with preview
- URL extraction and opening

#### 🔧 **Enhanced Keybindings**

**Prefix Key:** `C-Space` (ergonomic, no conflicts with shell/terminal/neovim)

**Session Management:**
```bash
C-Space s    # Switch session (FZF)
C-Space S    # New session
C-Space R    # Rename session
C-Space X    # Kill session
Alt+1-5      # Quick session switching
```

**Window Management:**
```bash
C-Space c    # New window
C-Space n/p  # Next/Previous window
C-Space w    # Choose window
Alt+h/l      # Navigate windows
```

**Pane Management:**
```bash
C-Space |    # Split vertical
C-Space -    # Split horizontal
C-Space h/j/k/l  # Navigate panes (vim-style)
C-Space H/J/K/L  # Resize panes
C-Space z    # Zoom pane
```

#### 📋 **Advanced Copy & Clipboard**
- Vi-style copy mode bindings
- System clipboard integration
- Smart text selection with Extrakto
- Mouse support for copy/paste

#### 🔍 **Search & Navigation**
```bash
C-Space /    # Search backward
C-Space ?    # Search forward
C-Space [    # Enter copy mode
```

#### 🚀 **Productivity Features**

**Project Integration:**
- `C-Space P` - Project switcher (integrates with ~/Projects)
- Automatic session naming based on project directories

**Development Helpers:**
- `C-Space g` - Git status popup
- `C-Space !` - Quick command execution
- Smart URL detection and opening

**System Integration:**
- Battery status in status line
- CPU usage monitoring
- Activity indicators

#### 🎨 **Beautiful Status Line**
- Gruvbox dark theme
- Battery status with icons
- Date/time display
- Session and window information
- Prefix key highlighting

#### 💾 **Session Persistence**
- Automatic session saving every 15 minutes
- Restore sessions on system restart
- Capture pane contents and shell history
- Boot-time session restoration

### 🐳 **Docker Integration**
```bash
# Container management
alias dps='docker ps | fzf --header-lines=1'
alias dimg='docker images | fzf --header-lines=1'
alias dlog='docker logs $(docker ps | fzf --header-lines=1 | awk "{print \$1}")'
```

---

**🎉 Enjoy your supercharged terminal! This configuration provides a modern, efficient command-line environment that will significantly boost your productivity and make terminal work enjoyable.**

> **💡 Pro Tip**: Start with the basic FZF shortcuts (Ctrl+R, Ctrl+T, Alt+C) and gradually incorporate the advanced functions into your daily workflow. The more you use these tools, the more natural and powerful they become! 
