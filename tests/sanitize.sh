#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd -P)"
stale_name='portable''-wsl-stack'
stale_env='PORTABLE''_WSL_STACK'

# In a Git checkout, only tracked paths are distribution candidates. A
# normalized archive has no .git directory, so every extracted entry is part of
# that tracked-like payload and must be checked.
declare -a CANDIDATE_ENTRIES=()
declare -a CANDIDATE_FILES=()
declare -a CANDIDATE_SYMLINK_TARGETS=()
declare -a NVIM_FILES=()
declare -a NVIM_SYMLINK_TARGETS=()
if git_root="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" && [[ "$git_root" == "$ROOT" ]]; then
  mapfile -d '' -t CANDIDATE_ENTRIES < <(git -C "$ROOT" ls-files -z)
else
  mapfile -d '' -t CANDIDATE_ENTRIES < <(
    cd -- "$ROOT"
    find . -mindepth 1 -printf '%P\0'
  )
fi

for entry in "${CANDIDATE_ENTRIES[@]}"; do
  if [[ -L "$ROOT/$entry" ]]; then
    target="$(readlink -- "$ROOT/$entry")"
    CANDIDATE_SYMLINK_TARGETS+=("$target")
    case "$entry" in
      ubuntu/config/nvim/*) NVIM_SYMLINK_TARGETS+=("$target") ;;
    esac
  elif [[ -f "$ROOT/$entry" ]]; then
    CANDIDATE_FILES+=("$ROOT/$entry")
    case "$entry" in
      ubuntu/config/nvim/*) NVIM_FILES+=("$ROOT/$entry") ;;
    esac
  fi
done

content_matches() {
  local pattern="$1"
  if ((${#CANDIDATE_FILES[@]})) && grep -qE -- "$pattern" "${CANDIDATE_FILES[@]}"; then
    return 0
  fi
  ((${#CANDIDATE_SYMLINK_TARGETS[@]})) || return 1
  printf '%s\n' "${CANDIDATE_SYMLINK_TARGETS[@]}" | grep -qE -- "$pattern"
}

nvim_content_matches() {
  local pattern="$1"
  if ((${#NVIM_FILES[@]})) && grep -qE -- "$pattern" "${NVIM_FILES[@]}"; then
    return 0
  fi
  ((${#NVIM_SYMLINK_TARGETS[@]})) || return 1
  printf '%s\n' "${NVIM_SYMLINK_TARGETS[@]}" | grep -qE -- "$pattern"
}

content_matches_insensitive() {
  local pattern="$1"
  if ((${#CANDIDATE_FILES[@]})) && grep -qiE -- "$pattern" "${CANDIDATE_FILES[@]}"; then
    return 0
  fi
  ((${#CANDIDATE_SYMLINK_TARGETS[@]})) || return 1
  printf '%s\n' "${CANDIDATE_SYMLINK_TARGETS[@]}" | grep -qiE -- "$pattern"
}

if content_matches "$stale_name|$stale_env"; then
  printf 'Sanitization failed: stale project identifier found.\n' >&2
  exit 1
fi

# Repository-owner names are valid in canonical Git URLs. Reject them only
# when they appear in machine-specific filesystem paths.
bad_user_one='reo''s156'
bad_user_two='reo''s1'
hard_home='/'"home"'/[[:alnum:]_.-]+/'
windows_home="(/mnt/[[:alpha:]]/Users/($bad_user_one|$bad_user_two)/|[[:alpha:]]:\\\\Users\\\\($bad_user_one|$bad_user_two)(\\\\|/))"
home_matches=''
if ((${#CANDIDATE_FILES[@]})); then
  home_matches="$(grep -hE -- "$hard_home|$windows_home" "${CANDIDATE_FILES[@]}" || true)"
fi
if ((${#CANDIDATE_SYMLINK_TARGETS[@]})); then
  home_matches+=$'\n'"$(printf '%s\n' "${CANDIDATE_SYMLINK_TARGETS[@]}" | grep -E -- "$hard_home|$windows_home" || true)"
fi
home_matches="${home_matches//\/home\/linuxbrew\/.linuxbrew\//<standard-linuxbrew>\/}"
if grep -qE "$hard_home|$windows_home" <<<"$home_matches"; then
  printf 'Sanitization failed: machine-specific home path found.\n' >&2
  exit 1
fi
credential_assignment='(password|passwd|pwd|token|api[_-]?key|access[_-]?token|client[_-]?secret|authorization)[[:space:]]*[:=][[:space:]]*[^<[:space:]]+'
private_key_block='-----BEGIN[[:space:]]+([A-Z0-9]+[[:space:]]+)*PRIVATE[[:space:]]+KEY-----'
known_token_prefix='(gh[pousr]_[[:alnum:]]{20,}|github_pat_[[:alnum:]_]{20,})'
if content_matches_insensitive "$credential_assignment|$private_key_block|$known_token_prefix"; then
  printf 'Sanitization failed: credential-like payload found.\n' >&2
  exit 1
fi
# AI, provider, debugger, explorer, and Obsidian specs/prompts are expected
# configuration. Reject only embedded machine paths, credentials, and payloads.
if nvim_content_matches '(/mnt/[a-zA-Z]/Users/|[A-Za-z]:\\Users\\|\.nvm/versions/node/v[0-9]+|/Users/[[:alnum:]_.-]+/|/projects?/|/proyectos/)'; then
  printf 'Sanitization failed: machine-specific editor path found.\n' >&2
  exit 1
fi

for entry in "${CANDIDATE_ENTRIES[@]}"; do
  if [[ "$entry" == ubuntu/config/nvim/* ]]; then
    basename="${entry##*/}"
    case "$basename" in
      *.spl|en_custom.txt|en_words.txt|es_words.txt)
        printf 'Sanitization failed: generated or bulk dictionary payload found.\n' >&2
        exit 1
        ;;
    esac
  fi
  if [[ "$entry" =~ ^ubuntu/config/nvim/(.*\/)?(\.atl|lazy|mason)(/|$) ]]; then
    printf 'Sanitization failed: generated Neovim metadata or runtime checkout found.\n' >&2
    exit 1
  fi
  if [[ "$entry" =~ (^|/)\.git(/|$) ]]; then
    printf 'Sanitization failed: vendored Git metadata found.\n' >&2
    exit 1
  fi
  if [[ "$entry" =~ \.(db|sqlite[^/]*|sock|history|log|token|pem|key)$ ]]; then
    printf 'Sanitization failed: sensitive or runtime payload found.\n' >&2
    exit 1
  fi
done
printf 'Sanitization passed.\n'
