export ZSH="$HOME/.oh-my-zsh"

plugins=(
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source "$ZSH/oh-my-zsh.sh"

HISTFILE=~/.zsh_history
HISTSIZE=32768
SAVEHIST=32768

setopt interactivecomments

export PATH="$HOME/.local/bin:$PATH"

export MANROFFOPT="-c"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export BAT_THEME=ansi

if command -v omarchy-launch-editor >/dev/null 2>&1; then
  export EDITOR="omarchy-launch-editor --inline"
else
  export EDITOR=nvim
fi
export SUDO_EDITOR="$EDITOR"
export BROWSER=zen-browser

alias ls='eza --icons --color=auto --group-directories-first'
alias ll='eza -l --icons --color=auto --group-directories-first'
alias la='eza -la --icons --color=auto --group-directories-first'
alias dev='cd ~/dev'
alias notes='cd ~/notes'
alias home='cd ~/'
alias zshconfig='nvim ~/.zshrc'
alias claude-dio='CLAUDE_CONFIG_DIR="$HOME/.claude-dio" "$HOME/.local/bin/claude"'
alias kanata-start='systemctl --user enable --now kanata.service'
alias kanata-stop='systemctl --user disable --now kanata.service'

teach-new() {
  if [[ -z "$1" ]]; then
    echo "usage: teach-new <course name>" >&2
    return 1
  fi
  local d="$HOME/notes/Teach/$1"
  mkdir -p "$d/notebook" || return 1
  [[ -f "$d/notebook/Log.md" ]] || : > "$d/notebook/Log.md"
  cd "$d"
}

eval "$(mise activate zsh)"
eval "$(starship init zsh)"
eval "$(zoxide init zsh)"
source <(fzf --zsh)
