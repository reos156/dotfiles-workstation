# Managed by dotfiles-workstation.
# Optional tools are discovered at startup; missing tools do not break the shell.

export EDITOR='nvim'
export VISUAL='nvim'
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
export FZF_DEFAULT_COMMAND=''

if command -v fd >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
elif command -v fdfind >/dev/null 2>&1; then
  export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
fi
[[ -n "$FZF_DEFAULT_COMMAND" ]] && export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

dws_source_if_readable() {
  [[ -r "$1" ]] && source "$1"
}

DWS_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DWS_DEPS="$DWS_DATA_HOME/dotfiles-workstation/deps"
export ZSH="$DWS_DEPS/oh-my-zsh"

# Ruby-based prompt and listing tools need a UTF-8 character locale to retain
# Nerd Font glyph bytes. Respect an effective UTF-8 locale selected by the user.
DWS_EFFECTIVE_LOCALE="${LC_ALL:-${LC_CTYPE:-${LANG:-C}}}"
case "${DWS_EFFECTIVE_LOCALE:l}" in
  ''|c|posix)
    DWS_UTF8_LOCALE=''
    if command -v locale >/dev/null 2>&1; then
      while IFS= read -r DWS_AVAILABLE_LOCALE; do
        case "${DWS_AVAILABLE_LOCALE:l}" in
          c.utf-8|c.utf8)
            DWS_UTF8_LOCALE="$DWS_AVAILABLE_LOCALE"
            break
            ;;
        esac
      done <<< "$(locale -a 2>/dev/null)"
    fi
    if [[ -n "$DWS_UTF8_LOCALE" ]]; then
      # LC_ALL would override LC_CTYPE, so release only its C/POSIX value.
      unset LC_ALL
      export LC_CTYPE="$DWS_UTF8_LOCALE"
    else
      print -u2 'dotfiles-workstation: UTF-8 locale unavailable; icons may be omitted. Install or generate C.UTF-8 (or C.utf8), then start a new shell.'
    fi
    ;;
  *utf-8*|*utf8*)
    # Preserve the user's effective UTF-8 locale and its precedence unchanged.
    ;;
esac
unset DWS_EFFECTIVE_LOCALE DWS_UTF8_LOCALE DWS_AVAILABLE_LOCALE

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
  plugins=(git command-not-found)
  source "$ZSH/oh-my-zsh.sh"
fi

dws_source_if_readable "$DWS_DEPS/zsh-autocomplete/zsh-autocomplete.plugin.zsh"
dws_source_if_readable "$DWS_DEPS/zsh-autosuggestions/zsh-autosuggestions.zsh"
# Syntax highlighting should be sourced after other widgets.
dws_source_if_readable "$DWS_DEPS/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# FZF widgets load before Atuin so Atuin remains the owner of Ctrl+R.
if command -v fzf >/dev/null 2>&1; then
  if fzf --zsh >/dev/null 2>&1; then
    eval "$(fzf --zsh)"
  else
    dws_source_if_readable /usr/share/doc/fzf/examples/key-bindings.zsh
    dws_source_if_readable /usr/share/doc/fzf/examples/completion.zsh
  fi
fi
if command -v atuin >/dev/null 2>&1; then
  eval "$(atuin init zsh)"
fi
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

dws_file_candidates() {
  if command -v fd >/dev/null 2>&1; then
    fd --type f --hidden --follow --exclude .git
  elif command -v fdfind >/dev/null 2>&1; then
    fdfind --type f --hidden --follow --exclude .git
  else
    find . -type f -not -path '*/.git/*' -print | cut -c3-
  fi
}

fzfbat() {
  command -v fzf >/dev/null 2>&1 || { print -u2 'fzf is not installed.'; return 127; }
  local preview='printf "%s\n" {}'
  if command -v bat >/dev/null 2>&1; then
    preview='bat --color=always --style=numbers --line-range=:500 -- {}'
  elif command -v batcat >/dev/null 2>&1; then
    preview='batcat --color=always --style=numbers --line-range=:500 -- {}'
  fi
  dws_file_candidates | fzf --preview "$preview" "$@"
}

fzfnvim() {
  command -v nvim >/dev/null 2>&1 || { print -u2 'nvim is not installed.'; return 127; }
  local selected
  selected="$(fzfbat "$@")" || return
  [[ -n "$selected" ]] || return 1
  nvim -- "$selected"
}

alias fb='fzfbat'
alias fv='fzfnvim'

if command -v colorls >/dev/null 2>&1; then
  alias ls='colorls'
  if (( $+functions[compdef] )) && (( $+functions[_gnu_generic] )); then
    compdef _gnu_generic colorls
  fi
fi

unset DWS_DATA_HOME DWS_DEPS
