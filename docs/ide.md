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
- [🎨 Customization](#-customization)
- [🔧 Troubleshooting](#-troubleshooting)

---

## 🎯 Overview

This Neovim configuration transforms your editor into a **modern, feature-rich IDE** with:

- **Type annotations and inlay hints** for static languages (Rust, TypeScript, Go, etc.)
- **Centralized, well-organized keybinding system**
- **Advanced LSP integration** with comprehensive language support
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

---

**🎉 Enjoy your powerful Neovim IDE! This configuration provides a modern, efficient development environment with professional-grade features for any project.**

> **💡 Pro Tip**: The more you use the keybindings, the more natural they become. Start with the basic navigation shortcuts and gradually incorporate the advanced features into your workflow. 
