# 🚀 Terminal Configuration Guide

**A comprehensive guide to the modern terminal setup with Zsh, FZF, and Ghostty for productive development workflows.**

---

## 📋 Table of Contents

- [🎯 Overview](#-overview)
- [✨ Key Features](#-key-features)
- [🚀 Getting Started](#-getting-started)
- [⌨️ Keyboard Shortcuts](#️-keyboard-shortcuts)
- [🔍 FZF Integration](#-fzf-integration)
- [🐚 Enhanced Shell Features](#-enhanced-shell-features)
- [🖥️ Ghostty Terminal](#️-ghostty-terminal)
- [🛠️ Configuration Files](#️-configuration-files)
- [🔧 Troubleshooting](#-troubleshooting)
- [⚡ Performance Tips](#-performance-tips)
- [🎓 Advanced Usage](#-advanced-usage)

---

## 🎯 Overview

This terminal configuration transforms your command-line experience into a **modern, productive development environment** with:

- **Ghostty**: Fast, native terminal emulator with excellent macOS integration
- **Zsh**: Enhanced shell with vi-mode, autosuggestions, and syntax highlighting  
- **FZF**: Fuzzy finder for history search, file navigation, and more
- **Enhanced CLI Tools**: Modern replacements for traditional Unix tools
- **Smart History**: 50K entries with deduplication and intelligent search
- **Git Integration**: Interactive git operations with visual previews

### 🏗️ Architecture

```
📁 Terminal Configuration Structure
├─ 🖥️ Ghostty Terminal          → Native macOS terminal emulator
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
- **Catppuccin theme** integration across all tools
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
Close and reopen Ghostty to load the new configuration.

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

### 🖥️ **Ghostty Terminal**
| Shortcut | Action | Description |
|----------|--------|-------------|
| `Cmd+T` | New tab | Create new terminal tab |
| `Cmd+N` | New window | Create new terminal window |
| `Cmd+W` | Close | Close current tab/window |
| `Cmd+D` | Split right | Split terminal vertically |
| `Cmd+Shift+D` | Split down | Split terminal horizontally |
| `Ctrl+Shift+H/L` | Navigate splits | Move between left/right splits |
| `Ctrl+Shift+J/K` | Navigate splits | Move between up/down splits |
| `Cmd+1-5` | Switch tabs | Jump to specific tab |
| `Cmd+K` | Clear screen | Clear terminal output |

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

FZF is configured with a beautiful **Catppuccin-inspired theme**:
- **Dark background** with high contrast
- **Purple highlights** for selected items
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

## 🖥️ Ghostty Terminal

### 🎯 **Key Features**

Ghostty is configured as a **modern, fast terminal emulator** with:

#### **Performance**
- **Native performance**: Written in Zig for maximum speed
- **GPU acceleration**: Smooth scrolling and rendering
- **Low latency**: Minimal input lag for responsive typing

#### **macOS Integration**
- **Native look and feel**: Matches macOS design language
- **Transparent titlebar**: Clean, modern appearance
- **Option key handling**: Proper Alt key behavior for terminal apps
- **Copy on select**: Automatic clipboard integration

#### **Developer Features**
- **Shell integration**: Enhanced prompt and directory tracking
- **Split terminals**: Multiple panes in one window
- **Tab management**: Organized workflow with multiple tabs
- **Customizable keybindings**: Productivity-focused shortcuts

### 🎨 **Visual Configuration**

- **Theme**: Catppuccin Mocha for consistent dark theme
- **Font**: Hack font at 14pt for excellent readability
- **Cursor**: Block cursor for better visibility
- **Padding**: 8px padding for comfortable viewing
- **Window decoration**: Native macOS window styling

### ⌨️ **Productivity Keybindings**

The configuration includes **macOS-friendly keybindings**:

```bash
# Window Management
Cmd+T           # New tab
Cmd+N           # New window  
Cmd+W           # Close current
Cmd+1-5         # Switch to tab 1-5

# Splits
Cmd+D           # Split right
Cmd+Shift+D     # Split down
Ctrl+Shift+H/L  # Navigate horizontal splits
Ctrl+Shift+J/K  # Navigate vertical splits

# Utilities
Cmd+K           # Clear screen
```

### 🔧 **Advanced Features**

- **Unbinds problematic keys**: Prevents conflicts with terminal applications
- **Mouse scroll optimization**: Comfortable scrolling speed
- **Shell integration**: Automatic Zsh detection and configuration
- **No close confirmation**: Streamlined workflow

---

## 🛠️ Configuration Files

### 📁 **File Structure**

```
home/
├── zsh/
│   ├── default.nix          # Main Zsh configuration
│   └── sources.sh           # Shell environment and functions
├── defaultPrograms/
│   ├── default.nix          # Program integration
│   └── ghostty              # Ghostty terminal config
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

### 🖥️ **Ghostty Configuration (`home/defaultPrograms/ghostty`)**

**Optimized for**:
- **macOS integration**: Native feel and behavior
- **Developer productivity**: Split management, tab organization
- **Visual consistency**: Catppuccin theme integration
- **Performance**: Optimized scrolling and rendering

**Key settings**:
```ini
# Theme and appearance
theme = catppuccin-mocha
font-family = "Hack"
font-size = 14

# macOS integration
macos-titlebar-style = transparent
macos-option-as-alt = left

# Productivity features
shell-integration = zsh
copy-on-select = true
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
2. **Restart terminal**: Close and reopen Ghostty
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

#### **4. Ghostty Configuration Not Applied**
**Symptoms**: Ghostty doesn't match expected appearance/behavior

**Diagnosis**:
```bash
# Check config file location
ls -la ~/.config/ghostty/config
# Should exist and contain your settings

# Check Ghostty version
ghostty --version
```

**Solutions**:
1. **Reload configuration**: `Ctrl+Shift+P` in Ghostty
2. **Restart Ghostty**: Close and reopen application
3. **Verify config syntax**: Check for syntax errors in config file

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
ls -la ~/.config/ghostty/
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
# Close all Ghostty windows and reopen

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

### 🖥️ **Tmux Integration**
```bash
# FZF session switcher for tmux
fzf_tmux_sessions() {
  tmux list-sessions | fzf | cut -d: -f1 | xargs tmux attach-session -t
}

# FZF window switcher
fzf_tmux_windows() {
  tmux list-windows | fzf | cut -d: -f1 | xargs tmux select-window -t
}
```

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
