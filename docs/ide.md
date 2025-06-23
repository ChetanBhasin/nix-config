# 🚀 Neovim IDE Configuration Guide

**A comprehensive guide to using your custom Neovim IDE setup with advanced features for modern development.**

---

## 📋 Table of Contents

- [🎯 Overview](#-overview)
- [✨ Key Features](#-key-features)
- [🚀 Getting Started](#-getting-started)
- [⌨️ Keyboard Shortcuts](#️-keyboard-shortcuts)
- [🧠 Language Server Features](#-language-server-features)
- [🦀 Rust Development](#-rust-development)
- [🔍 Search & Navigation](#-search--navigation)
- [📁 File Management](#-file-management)
- [💻 Terminal Integration](#-terminal-integration)
- [🤖 Claude AI Integration](#-claude-ai-integration)
- [🎨 Customization](#-customization)
- [🔧 Troubleshooting](#-troubleshooting)

---

## 🎯 Overview

This Neovim configuration transforms your editor into a **modern, feature-rich IDE** with:

- **Type annotations and inlay hints** for static languages (Rust, TypeScript, Go, etc.)
- **Centralized, well-organized keybinding system**
- **Advanced LSP integration** with comprehensive language support
- **Claude AI integration** for code review, architecture advice, and learning
- **Modern plugin ecosystem** with consistent theming
- **Professional development workflow** tools

### 🏗️ Architecture

```
📁 home/neovim/config/lua/custom/
├─ 📄 remap.lua          → Basic settings + loads keymaps
├─ 📄 keymaps.lua        → 🎯 ALL KEYBINDINGS (centralized)
├─ 📄 init.lua           → Configuration loader
├─ 📁 plugins/
│  ├─ lsp.lua            → Language Server Protocol setup
│  ├─ rust.lua           → Rust-specific configuration
│  ├─ telescope.lua      → Fuzzy finder configuration
│  ├─ harpoon.lua        → Quick file navigation
│  ├─ fterm.lua          → Floating terminal
│  └─ ...                → Other plugin configurations
└─ 📄 colors.lua         → Theme and color settings
```

---

## ✨ Key Features

### 🔍 **Type Annotations & Inlay Hints**
- **Rust**: Variable types, parameter names, return types, method chaining
- **TypeScript/JavaScript**: All type information, parameter hints
- **Go**: Composite types, parameter names, return types
- **Python**: Type hints via Pyright
- **Toggle on/off**: `<leader>th`

### 🎯 **Smart Navigation**
- **Go to definition/declaration**: `gd` / `gD`
- **Find references**: `gr`
- **Type definitions**: `go`
- **Symbol search**: Telescope integration
- **Harpoon quick files**: Instant access to frequently used files

### 🔧 **Advanced Code Actions**
- **Rename symbols**: `<F2>` or `<leader>rn`
- **Code actions**: `<F4>` or `<leader>ca`
- **Auto-formatting**: `<F3>` or automatic on save
- **Error diagnostics**: `[d` / `]d` for navigation

### 🦀 **Rust Specialization**
- **Run/Test/Debug**: `<leader>rr/rt/rd`
- **Macro expansion**: `<leader>rm`
- **Error explanation**: `<leader>re`
- **Clippy integration**: Automatic linting
- **Cargo.toml access**: `<leader>rc`

---

## 🚀 Getting Started

### 1. **Apply Configuration**
```bash
# Navigate to your nix-config directory
cd ~/path/to/nix-config

# Apply the configuration
make apply-darwin host=hugh  # Replace 'hugh' with your host
```

### 2. **First Launch**
When you first open Neovim:
1. All plugins will be automatically installed
2. Language servers will be set up via Mason
3. Press `<C-Space>` to see all available keybindings

### 3. **Essential First Steps**
- **Open a project**: `nvim .` in your project directory
- **Find files**: `<C-p>` to search filenames
- **Search content**: `<leader>fw` to search inside files
- **File explorer**: `<leader>f` to toggle file tree
- **Terminal**: `<C-t>` for floating terminal

---

## ⌨️ Keyboard Shortcuts

> **💡 Tip**: Press `<C-Space>` anytime to see all available shortcuts with descriptions!

### 🏠 **Core Navigation**
| Shortcut | Action | Description |
|----------|--------|-------------|
| `<C-h/j/k/l>` | Window navigation | Move between editor windows |
| `<leader>es` | Horizontal split | Split window horizontally |
| `<leader>ev` | Vertical split | Split window vertically |
| `<leader>ew` | Edit file | Open file in current directory |

### 🔍 **Search & Files**
| Shortcut | Action | Description |
|----------|--------|-------------|
| `<C-p>` | Find files | Quick file search |
| `<leader>ff` | Find files | Alternative file search |
| `<leader>fw` | Live grep | Search inside files |
| `<leader>fr` | Find related | Files related to current |
| `<leader>fb` | Find buffers | Search open buffers |
| `<leader>fh` | Help tags | Search help documentation |
| `<leader>fc` | Commands | Search available commands |
| `<leader>fk` | Keymaps | Search keybindings |

### 🏹 **Harpoon (Quick Files)**
| Shortcut | Action | Description |
|----------|--------|-------------|
| `<leader>ha` | Add to harpoon | Mark current file |
| `<leader>hh` | Harpoon menu | Show marked files |
| `<leader>h1-4` | Quick access | Jump to marked file 1-4 |
| `<C-S-P/N>` | Previous/Next | Navigate marked files |

### 🧠 **Language Server (LSP)**
| Shortcut | Action | Description |
|----------|--------|-------------|
| `gd` | Go to definition | Jump to symbol definition |
| `gD` | Go to declaration | Jump to symbol declaration |
| `gi` | Go to implementation | Find implementations |
| `go` | Go to type definition | Jump to type definition |
| `gr` | Show references | Find all references |
| `gs` | Signature help | Show function signature |
| `K` | Hover info | Show documentation |
| `<F2>` | Rename symbol | Rename across project |
| `<F3>` | Format code | Auto-format file |
| `<F4>` | Code actions | Show available actions |

### 🔧 **Diagnostics**
| Shortcut | Action | Description |
|----------|--------|-------------|
| `[d` / `]d` | Navigate diagnostics | Previous/Next error |
| `<leader>dl` | Location list | Diagnostics to location list |
| `<leader>dq` | Quickfix | Diagnostics to quickfix |

### 🦀 **Rust Specific**
| Shortcut | Action | Description |
|----------|--------|-------------|
| `<leader>rr` | Runnables | Run Rust code/examples |
| `<leader>rt` | Testables | Run tests |
| `<leader>rd` | Debuggables | Debug current target |
| `<leader>re` | Explain error | Detailed error explanation |
| `<leader>rm` | Expand macro | Show macro expansion |
| `<leader>rp` | Parent module | Navigate to parent |
| `<leader>rc` | Open Cargo | Jump to Cargo.toml |
| `<leader>rs` | SSR | Structural search/replace |

### 💻 **Terminal & Tools**
| Shortcut | Action | Description |
|----------|--------|-------------|
| `<C-t>` | Toggle terminal | Floating terminal |
| `<leader>th` | Toggle hints | Show/hide inlay hints (enabled by default) |
| `<leader>f` | File explorer | Toggle file tree |

### 🤖 **Claude AI Assistant**
| Shortcut | Action | Description |
|----------|--------|-------------|
| `<leader>co` | **Smart Toggle** | Conversation picker first time, then hide/show |
| `<leader>cc` | Continue | Resume last conversation (manual) |
| `<leader>cr` | Resume | Pick from previous conversations (manual) |
| `<leader>cv` | Verbose | Claude with detailed output |
| `<leader>cq` | **Quit** | Gracefully terminate Claude session |
| `<leader>cn` | **New** | Start fresh session (ignore existing) |
| `<leader>ch` | Help | Show Claude commands |

---

## 🧠 Language Server Features

### 📝 **Supported Languages**

| Language | LSP Server | Features |
|----------|------------|----------|
| **Rust** | `rust-analyzer` | Full inlay hints, debugging, testing |
| **TypeScript/JS** | `tsserver` | Parameter hints, type information |
| **Python** | `pyright` | Type checking, imports |
| **Go** | `gopls` | Comprehensive inlay hints |
| **Lua** | `lua_ls` | Parameter types, Neovim API |
| **Nix** | `rnix` | Syntax, basic completion |
| **YAML** | `yamlls` | Schema validation |
| **Docker** | `dockerls` | Dockerfile support |
| **Bash** | `bashls` | Shell scripting |
| **Gleam** | `gleam` | Functional language support |

### 🎯 **Inlay Hints Configuration**

**Inlay hints are enabled by default** for all supported languages. You can toggle them on/off using `<leader>th`.

**Rust** (Most comprehensive):
```rust
// Variable type hints
let items = vec![1, 2, 3];  // : Vec<i32>

// Parameter name hints
process_data(input);  // input: &str

// Method chaining hints
data.iter()          // : Iterator<Item = &i32>
    .map(|x| x * 2)  // : Map<...>
    .collect();      // : Vec<i32>
```

**TypeScript**:
```typescript
// Parameter names and types
function process(data, options) {
    //           ^^^^: DataType  ^^^^^^^: Options
    return data.transform();
}
```

**Go**:
```go
// Composite literal types and parameter names
items := []string{"a", "b"}  // : []string
process(data, options)       // data: DataType, options: Options
```

---

## 🦀 Rust Development

Your IDE is specially optimized for Rust development with **rustaceanvim** providing advanced features:

### 🔧 **Core Features**

1. **Type Information Everywhere**
   - Variable types shown inline
   - Function parameter names
   - Return type annotations
   - Method chaining types

2. **Smart Code Actions**
   - Extract function/variable
   - Implement traits
   - Add missing imports
   - Fix compiler suggestions

3. **Testing & Running**
   - `<leader>rr`: Show all runnables (examples, binaries, tests)
   - `<leader>rt`: Run specific tests
   - `<leader>rd`: Debug configurations

4. **Error Analysis**
   - `<leader>re`: Detailed error explanations
   - Clippy integration with suggestions
   - Real-time error highlighting

5. **Advanced Navigation**
   - `<leader>rm`: Expand macros inline
   - `<leader>rp`: Jump to parent module
   - `<leader>rc`: Quick access to Cargo.toml

### 🎯 **Rust-Specific Settings**

- **Clippy on save**: Automatic linting with `cargo clippy`
- **All features enabled**: `cargo.allFeatures = true`
- **Proc macros**: Full support for procedural macros
- **Build scripts**: Integration with build.rs
- **Cargo integration**: Automatic project structure detection

### 🔍 **Code Lens Features**

Above functions and types, you'll see clickable links for:
- **Run**: Execute the function/test
- **Debug**: Debug the function
- **References**: Find all usages
- **Implementations**: See trait implementations

---

## 🔍 Search & Navigation

### 🔭 **Telescope (Fuzzy Finder)**

**Primary search interface** - blazingly fast fuzzy finding:

- **Files**: `<C-p>` or `<leader>ff`
  - Search by filename across entire project
  - Respects `.gitignore`
  - Preview files before opening

- **Content**: `<leader>fw` (live grep)
  - Search inside files with regex support
  - Real-time results as you type
  - Context preview

- **Symbols**: `<leader>ls` / `<leader>lw`
  - Search functions, classes, variables
  - Document or workspace-wide
  - Jump directly to definitions

### 🏹 **Harpoon (Quick Files)**

**Instant access** to your most important files:

1. **Mark files**: `<leader>ha` on important files
2. **Quick menu**: `<leader>hh` to see all marked files
3. **Direct access**: `<leader>h1`, `<leader>h2`, etc.
4. **Navigation**: `<C-S-P/N>` to cycle through marked files

**Use case**: Mark your main.rs, lib.rs, config files, etc. for instant access.

### 🧭 **LSP Navigation**

**Symbol-aware navigation**:
- **Definition**: `gd` - Where is this defined?
- **References**: `gr` - Where is this used?
- **Implementation**: `gi` - How is this implemented?
- **Type definition**: `go` - What type is this?

---

## 📁 File Management

### 🌳 **NvimTree (File Explorer)**

- **Toggle**: `<leader>f`
- **Find current file**: `<leader>nf`
- **Navigation**: Arrow keys or `hjkl`
- **Actions**: `a` (add), `d` (delete), `r` (rename), `c` (copy)

### 📋 **Buffer Management**

- **List buffers**: `<leader>ft` or `<leader>fb`
- **Close others**: `<leader>ct` (close all except current)
- **Switch buffers**: `:b <tab>` for autocomplete

---

## 💻 Terminal Integration

### 🔄 **FTerm (Floating Terminal)**

- **Toggle**: `<C-t>` (works in both normal and terminal mode)
- **Features**:
  - Floating window design
  - Persistent across sessions
  - Double border styling
  - 80% screen coverage

### 💡 **Usage Tips**

1. **Quick commands**: `<C-t>` → run command → `<C-t>` to hide
2. **Development workflow**: Keep terminal open while coding
3. **Git operations**: Perfect for quick git commands
4. **Testing**: Run tests without leaving your editing context

---

## 🤖 Claude AI Integration

Your IDE includes **Claude AI integration** via the `claude-code.nvim` plugin, providing AI-powered code assistance directly within Neovim.

### 🎯 **What Claude Provides**

- **Code review and suggestions** with full project context
- **Architecture advice** and design pattern recommendations  
- **Bug detection and fixes** with explanations
- **Code refactoring** suggestions and implementations
- **Documentation generation** for functions and modules
- **Learning assistance** - explanations of complex code patterns

### ⌨️ **Claude Keybindings**

| Shortcut | Action | Description |
|----------|--------|-------------|
| `<leader>co` | **Smart Toggle** | First time: conversation picker; existing: hide/show |
| `<leader>cc` | Continue conversation | Resume last Claude conversation (manual) |
| `<leader>cr` | Resume with picker | Choose from previous conversations (manual) |
| `<leader>cv` | Verbose mode | Claude with detailed output |
| `<leader>cq` | **Quit session** | Gracefully terminate Claude session |
| `<leader>cn` | **New session** | Start fresh (ignore existing) |
| `<leader>ch` | Show help | Display all Claude commands |

### 🔄 **Background Persistence**

**Claude runs in background when hidden:**
- `<leader>co` first time → Conversation picker appears
- `<leader>co` again → Hides Claude (keeps running in background)
- `<leader>co` again → Shows Claude instantly (same session)
- **Lightning fast toggles** - no startup delay!

### 🚪 **Session Management**

**From normal mode:**
- `<leader>co` → Toggle Claude visibility (hide/show)
- `<leader>cq` → End Claude session completely

**From within Claude terminal:**
- `<leader>co` → Toggle Claude from within
- `<C-q>` → Exit to normal mode

### 🔄 **How It Works**

Claude integrates as a **terminal-based AI assistant**:

1. **Smart Toggle**: `<leader>co` opens Claude in a right sidebar terminal
2. **Real Toggle**: Same key closes it (unlike the original plugin)
3. **Context Aware**: Claude automatically detects your project structure
4. **File Integration**: Add files to context using Claude's built-in commands

### 💻 **Claude CLI Commands**

Once in the Claude terminal, use these commands:

```bash
# File management
add file.rs           # Add file to Claude's context
add src/              # Add entire directory
add .                 # Add current project
clear                 # Clear context

# Conversation management  
/reset               # Start fresh conversation
/help                # Show all Claude CLI commands

# Just ask questions directly!
How can I improve this Rust code?
Can you review my error handling?
What's the best way to structure this module?
```

### 🎯 **Typical Workflow**

1. **Code with LSP**: Use your existing LSP setup for real-time feedback
2. **Open Claude**: `<leader>co` → Choose from conversation picker
3. **Add context**: `add src/main.rs` to include files in conversation
4. **Ask questions**: Type directly to Claude about your code
5. **Hide Claude**: `<leader>co` → Claude runs in background
6. **Continue coding**: LSP provides real-time feedback
7. **Show Claude**: `<leader>co` → Instant return to same conversation
8. **Apply changes**: Use your normal editing workflow
9. **Version control**: Git handles tracking changes as usual

### 🔧 **Integration with LSP**

Claude **complements** your existing LSP setup:

- **LSP**: Real-time syntax checking, completion, navigation
- **Claude**: High-level code review, architecture advice, learning

They work together without conflicts - LSP for immediate feedback, Claude for deeper insights.

### ✨ **Example Use Cases**

**Code Review:**
```bash
add src/lib.rs
Can you review this code for potential improvements?
```

**Bug Hunting:**
```bash
add src/main.rs src/errors.rs
I'm getting a panic here, can you help debug this?
```

**Architecture Advice:**
```bash
add src/
How should I restructure this code to follow better patterns?
```

**Learning:**
```bash
add examples/advanced.rs
Can you explain how this async code works?
```

### 🎨 **Configuration**

Claude is configured to match your preferences:
- **Right sidebar positioning** (35% width)
- **No auto-start** - manual toggle only
- **No auto-file-selection** - you control what Claude sees
- **Persistent sessions** - conversations survive editor restarts

### 💡 **Pro Tips**

1. **Context Management**: Only add relevant files to keep responses focused
2. **Specific Questions**: Ask targeted questions for better responses
3. **Iterative Refinement**: Build on previous responses in the same session
4. **Code Blocks**: Claude can generate code that you copy/paste into your editor
5. **Documentation**: Ask Claude to explain unfamiliar code patterns

### 🔄 **Claude vs Terminal**

Don't confuse Claude terminal with the floating terminal:
- **`<C-t>`**: Floating terminal for shell commands, git, etc.
- **`<leader>co`**: Claude AI terminal for code assistance

Both serve different purposes in your development workflow.

---

## 🎨 Customization

### 🎯 **Modifying Keybindings**

All keybindings are in `home/neovim/config/lua/custom/keymaps.lua`:

```lua
-- Add your custom keybinding
keymap("n", "<leader>custom", ":CustomCommand<CR>", { desc = "My custom command" })
```

### 🔧 **LSP Configuration**

Modify language servers in `home/neovim/config/lua/custom/plugins/lsp.lua`:

```lua
-- Add new language server
lspconfig.your_language_server.setup({
    capabilities = lsp_capabilities,
    on_attach = on_attach,
    settings = {
        -- Your custom settings
    }
})
```

### 🦀 **Rust-Specific Customization**

Edit `home/neovim/config/lua/custom/plugins/rust.lua` for Rust-specific settings:

```lua
-- Modify inlay hints
inlayHints = {
    typeHints = {
        enable = false,  -- Disable type hints if desired
    },
}
```

### 🎨 **Theme and Appearance**

- **Color scheme**: Catppuccin (can be changed in color configuration)
- **Inlay hint styling**: Subtle gray italic text
- **Status line**: Lualine with file information
- **Icons**: Nerdfont icons throughout

---

## 🔧 Troubleshooting

### 🚨 **Common Issues**

**1. Inlay hints not showing**
```bash
# Inlay hints should be enabled by default
# If not showing, check if LSP is running
:LspInfo

# Toggle hints manually (they should be on by default)
<leader>th
```



**2. Language server not starting**
```bash
# Install missing language server
:Mason
# Then install the required LSP
```

**3. Keybindings not working**
```bash
# Check keybinding conflicts
:verbose map <your-key>

# View all keybindings
<C-Space>
```

**4. Rust analyzer issues**
```bash  
# Restart rust-analyzer
:RustLsp restart

# Check Cargo.toml is in project root
:RustLsp openCargo
```

**5. Claude not responding**
```bash
# Check if Claude terminal is open
<leader>co

# Reset Claude conversation
# In Claude terminal: /reset

# Check Claude CLI status
# In Claude terminal: /help
```

### 🔍 **Debugging Steps**

1. **Check LSP status**: `:LspInfo`
2. **View logs**: `:lua vim.lsp.set_log_level("debug")`
3. **Restart LSP**: `:LspRestart`
4. **Plugin status**: `:Legendary` to see all commands
5. **Mason status**: `:Mason` to manage language servers

### 🛠️ **Performance Optimization**

If Neovim feels slow:

1. **Disable unused features**:
   ```lua
   -- In your config files
   enable = false  -- for specific features
   ```

2. **Reduce inlay hint frequency**:
   ```lua
   vim.api.nvim_set_option('updatetime', 1000)  -- Slower updates
   ```

3. **Limit treesitter parsers**:
   - Remove unused languages from treesitter config

---

## 🎓 **Learning Resources**

### 📚 **Neovim Basics**
- `:help nvim` - Built-in help system
- `:Tutor` - Interactive Neovim tutorial
- [Neovim documentation](https://neovim.io/doc/)

### 🔧 **LSP & Development**
- `:help lsp` - LSP documentation
- [rust-analyzer manual](https://rust-analyzer.github.io/)
- [Telescope documentation](https://github.com/nvim-telescope/telescope.nvim)

### ⌨️ **Keybinding Discovery**
- `<C-Space>` - Interactive keybinding menu
- `:help keymaps` - Keymap documentation
- `:map` - List all current keybindings

---

## 🚀 **Advanced Workflows**

### 🦀 **Rust Development Workflow**

1. **Start new project**:
   ```bash
   cargo new my_project
   cd my_project
   nvim .
   ```

2. **Development cycle**:
   - Edit code with full type information
   - `<leader>rr` to run/test quickly
   - `<leader>re` to understand errors
   - `<F3>` to format before committing

3. **Debugging**:
   - `<leader>rd` for debug configurations
   - Set breakpoints with built-in debugger
   - Inspect variables and call stack

### 🔍 **Large Codebase Navigation**

1. **Project overview**:
   - `<leader>lw` for workspace symbols
   - `<leader>ff` for file overview
   - Harpoon for frequent files

2. **Understanding code**:
   - `gd` to jump to definitions
   - `gr` to see all usages
   - `K` for inline documentation
   - Inlay hints for type context

3. **Refactoring**:
   - `<F2>` for safe renaming
   - `<F4>` for code actions
   - `<leader>rs` for structural find/replace (Rust)

### 🤖 **AI-Assisted Development with Claude**

1. **Code Review Workflow**:
   - Open Claude: `<leader>co`
   - Add context: `add src/main.rs`
   - Ask: "Can you review this code for improvements?"
   - Apply suggested changes in your editor
   - Continue conversation for follow-up questions

2. **Learning Complex Code**:
   - Add unfamiliar files: `add examples/advanced.rs`
   - Ask: "Can you explain how this pattern works?"
   - Get detailed explanations with examples
   - Ask follow-up questions for clarification

3. **Architecture Planning**:
   - Add project structure: `add src/`
   - Ask: "How should I refactor this for better maintainability?"
   - Get high-level design suggestions
   - Implement changes using LSP tools

---

**🎉 Enjoy your powerful Neovim IDE! This configuration provides a modern, efficient development environment with professional-grade features for any project.**

> **💡 Pro Tip**: The more you use the keybindings, the more natural they become. Start with the basic navigation shortcuts and gradually incorporate the advanced features into your workflow.
