#!/usr/bin/env zsh
# Platform-agnostic shell configuration
# Platform-specific settings are in ~/.sources_platform

set -o vi

# Source platform-specific configuration
[[ -f ~/.sources_platform ]] && source ~/.sources_platform

# Safely source credentials if they exist
[[ -f ~/.creds ]] && source ~/.creds

# Initialize tools
eval "$(direnv hook zsh)"
command -v nodenv &>/dev/null && eval "$(nodenv init -)"

# Carapace completion bridge
export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
source <(carapace _carapace)

# SOPS age key
export SOPS_AGE_KEY_FILE="$HOME/.age/key.txt"

# ===============================================
# ALIASES
# ===============================================

# Kubernetes
alias k="kubectl"

# Enhanced ls with eza
alias ls="eza"
alias ll="eza -la --git --header"
alias lt="eza --tree --level=2"
alias lsl="eza -lLsSuUhHa"
alias l="ls -lah"

# Modern CLI tool replacements
alias cat="bat"
alias grep="rg"
alias find="fd"
alias top="htop"
alias du="dust"
alias df="duf"
alias ps="procs"

# Git shortcuts
alias gs="git status"
alias gd="git diff"
alias gl="git log --oneline --graph --decorate"
alias gb="git branch"
alias gc="git checkout"
alias gp="git pull"
alias gps="git push"
alias gitchange="git add . && git commit --amend --no-edit"
alias gitrchange="gitchange && git push --force-with-lease"

# Misc
alias bazel="bazelisk"
alias enablepassword="sudo echo 'Password Entered'"

# ===============================================
# HISTORY SUBSTRING SEARCH BINDINGS
# ===============================================

# Bind up/down arrows to history substring search
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# Bind k/j in vi mode for history substring search
bindkey -M vicmd 'k' history-substring-search-up
bindkey -M vicmd 'j' history-substring-search-down

# ===============================================
# VIM-TMUX-NAVIGATOR INTEGRATION
# ===============================================

# Smart pane switching with awareness of Vim splits
# See: https://github.com/christoomey/vim-tmux-navigator
is_vim="ps -o state= -o comm= -t '#{pane_tty}' \
    | grep -iqE '^[^TXZ ]+ +(\\S+\\/)?g?(view|l?n?vim?x?|fzf)(diff)?$'"

# ===============================================
# FZF-POWERED FUNCTIONS
# ===============================================

fzf_git_log() {
  git log --oneline --color=always | fzf --ansi --preview 'git show --color=always {1}' --bind 'enter:execute(git show {1} | less -R)'
}

fzf_git_branch() {
  git branch -a | grep -v HEAD | sed 's/^..//' | fzf --preview 'git log --oneline --color=always {}' --bind 'enter:execute(git checkout {})'
}

fzf_kill() {
  ps aux | fzf | awk '{print $2}' | xargs kill
}

fzf_env() {
  env | fzf | cut -d= -f1 | xargs -I {} sh -c 'echo "{}=${}"'
}

# Override git log and git branch with FZF versions when called without arguments
git() {
  case $1 in
    log)
      if [[ $# -eq 1 ]]; then
        fzf_git_log
      else
        command git "$@"
      fi
      ;;
    branch)
      if [[ $# -eq 1 ]]; then
        fzf_git_branch
      else
        command git "$@"
      fi
      ;;
    *)
      command git "$@"
      ;;
  esac
}

# ===============================================
# HISTORY FUNCTIONS
# ===============================================

hist_search() {
  history | fzf --tac --no-sort | sed 's/^[[:space:]]*[0-9]*[[:space:]]*//'
}

hist_stats() {
  history | awk '{print $2}' | sort | uniq -c | sort -nr | head -20
}

# ===============================================
# NIX FUNCTIONS
# ===============================================

# Install nix packages in local default profile
ninstall() {
  nix profile install "github:NixOS/nixpkgs#$1"
}

# Search nix packages
nsearch() {
  nix search nixpkgs $1
}

# ===============================================
# KUBERNETES FUNCTIONS
# ===============================================

# Finds pods using a search term
# Run using `podname <namespace> <search-term>
podname() {
  kubectl -n $1 get pods | grep -i "$2" | awk '{print $1;}'
}

# Find the namespace that matches a string
# Run using `findns <search-term>`
findns() {
  kubectl get namespaces | grep -i "$@" | awk '{print $1;}'
}

# Deletes all pods matching a given search term
# Run using `deletepod <namespace> <search-term>`
deletepod() {
  kubectl -n $1 delete pod `podname "$1" "$2"`
}

# Describes all pods matching a given search term
# Run using `descpod <namespace> <search-term>`
descpod() {
  kubectl -n $1 describe pod `podname "$1" "$2"`
}

# Watches pods for changes in a given namespace
# Run using `watchnspods <namespace>`
watchpods() {
  kubectl -n $1 get pods -w
}

# Gets a resource from kubernetes by `kubectl get <resource list>`
# Run using `kget <resource-list>`
# To use a namespace, run using `kget -n <namespace> <resource-list>`
kget() {
  kubectl get "$@"
}

# Finds all the pods in a given namespace using `kget` function
# Run using `npods <namespace>`
npods() {
  kget pods -n "$@"
}

# Finds a type of resources for a given searchable namespace
# Run using `knget <namespace-search-term> <resource>`
knget() {
  kubectl -n `findns $1` get $2
}

# Starts tailing the logs of a pod defined in a namespace after
# looking up the name of the pod
# Run using `klogs <namespace> <podname>`
klogs() {
  export ns=$(findns $1)
  export pod=$(podname $ns $2)
  kubectl logs -f -n $ns $pod
}

# Starts tailing the logs of a pod defined in a namespace after
# looking up the name of the pod. It also takes the container name
# inside the pod for pods that have more than one container.
kclogs() {
  export ns=$(findns $1)
  export pod=$(podname $ns $2)
  kubectl logs -f -n $ns $pod $3 $4
}

# Runs fblog on klogs
fklogs() {
  klogs "$@" | fblog
}

# Runs fblog on kclogs
fkclogs() {
  kclogs "$@" | fblog
}

# Forwards ports from a given pod by searching for a namespace
# and pod name from other functions
# Run using `kfwd <namespace-search-term> <podname-search-term> <port-to-forward>`
kfwd() {
  export ns=$(findns $1)
  export pod=$(podname $ns $2)
  kubectl -n $ns port-forward $pod $3:$3
}

# Generate kubernetes secret for the dashboard
k8_dash_sec() {
  kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')
}

# ===============================================
# UTILITY FUNCTIONS
# ===============================================

# Universal archive extractor
extract() {
  if [ -f $1 ]; then
    case $1 in
      *.tar.bz2)   tar xvjf $1    ;;
      *.tar.gz)    tar xvzf $1    ;;
      *.tar.xz)    tar Jxvf $1    ;;
      *.bz2)       bunzip2 $1     ;;
      *.rar)       rar x $1       ;;
      *.gz)        gunzip $1      ;;
      *.tar)       tar xvf $1     ;;
      *.tbz2)      tar xvjf $1    ;;
      *.tgz)       tar xvzf $1    ;;
      *.zip)       unzip -d `echo $1 | sed 's/\(.*\)\.zip/\1/'` $1;;
      *.Z)         uncompress $1  ;;
      *.7z)        7z x $1        ;;
      *)           echo "don't know how to extract '$1'" ;;
    esac
  else
    echo "'$1' is not a valid file!"
  fi
}

# Amend a specific git commit
git-ammend-old() (
  # Stash, apply to past commit, and rebase the current branch on top of the result.
  current_branch="$(git rev-parse --abbrev-ref HEAD)"
  apply_to="$1"
  git stash
  git checkout "$apply_to"
  git stash apply
  git add -u
  git commit --amend --no-edit
  new_sha="$(git log --format="%H" -n 1)"
  git checkout "$current_branch"
  git rebase --onto "$new_sha" "$apply_to"
)

# ===============================================
# PATH ADDITIONS
# ===============================================

# Rust/Cargo binaries
export PATH="$PATH:$HOME/.cargo/bin"

# NPM global packages
export PATH="$PATH:$HOME/.local/lib/bin"
