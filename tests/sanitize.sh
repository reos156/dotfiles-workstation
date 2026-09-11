#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd -P)"
NVIM_ROOT="$ROOT/ubuntu/config/nvim"
stale_name='portable''-wsl-stack'
stale_env='PORTABLE''_WSL_STACK'

if grep -RqE "$stale_name|$stale_env" "$ROOT"; then
  printf 'Sanitization failed: stale project identifier found.\n' >&2
  exit 1
fi

# Repository-owner names are valid in canonical Git URLs. Reject them only
# when they appear in machine-specific filesystem paths.
bad_user_one='reo''s156'
bad_user_two='reo''s1'
hard_home='/'"home"'/[[:alnum:]_.-]+/'
windows_home="(/mnt/[[:alpha:]]/Users/($bad_user_one|$bad_user_two)/|[[:alpha:]]:\\\\Users\\\\($bad_user_one|$bad_user_two)(\\\\|/))"
if grep -RqE "$hard_home|$windows_home" "$ROOT"; then
  printf 'Sanitization failed: machine-specific home path found.\n' >&2
  exit 1
fi
if grep -RqE '(api[_-]?key|access[_-]?token|client[_-]?secret|authorization)[[:space:]]*[:=][[:space:]]*[^<[:space:]]+' "$ROOT"; then
  printf 'Sanitization failed: credential-like payload found.\n' >&2
  exit 1
fi
if grep -RqiE '(copilot|avante|claude.?code|codecompanion|gemini|opencode|obsidian|nvim-dap|debugpy|neo-tree|snacks_explorer|mini.files|oil.nvim)' "$NVIM_ROOT"; then
  printf 'Sanitization failed: excluded AI, notes, debugger, or explorer plugin found.\n' >&2
  exit 1
fi
if grep -RqE '(/mnt/[a-zA-Z]/Users/|\.nvm/versions/node/v[0-9]+|[Vv]aults?/|/projects?/|/proyectos/)' "$NVIM_ROOT"; then
  printf 'Sanitization failed: machine-specific editor path found.\n' >&2
  exit 1
fi
# A canonical checkout has one root .git directory; nested metadata is vendored.
if find "$ROOT" -mindepth 2 -type d -name .git -print -quit | grep -q .; then
  printf 'Sanitization failed: vendored Git metadata found.\n' >&2
  exit 1
fi
if find "$ROOT" -type f \( -name '*.db' -o -name '*.sqlite*' -o -name '*.sock' -o -name '*.history' -o -name '*.log' -o -name '*.token' -o -name '*.pem' -o -name '*.key' \) -print -quit | grep -q .; then
  printf 'Sanitization failed: sensitive or runtime payload found.\n' >&2
  exit 1
fi
printf 'Sanitization passed.\n'
