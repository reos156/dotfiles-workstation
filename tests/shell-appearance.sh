#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="$(cd -- "$TEST_DIR/.." && pwd -P)"
ZSHRC="$ROOT/ubuntu/config/zsh/.zshrc"
STARSHIP_CONFIG="$ROOT/ubuntu/config/starship.toml"

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }

CASE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-shell-appearance.XXXXXX")"
cleanup() { rm -rf -- "$CASE_DIR"; }
trap cleanup EXIT

if ! command -v zsh >/dev/null 2>&1; then
  printf 'SKIP - shell appearance startup checks require zsh\n'
else
  STUB_BIN="$CASE_DIR/bin"
  TEST_HOME="$CASE_DIR/home"
  mkdir -p "$STUB_BIN" "$TEST_HOME"

  cat >"$STUB_BIN/locale" <<'STUB'
#!/usr/bin/env sh
if [ "${1-}" = -a ]; then
  printf '%s\n' ${DWS_TEST_LOCALES:-C POSIX}
  exit 0
fi
if [ "${1-}" = charmap ]; then
  effective=${LC_ALL-${LC_CTYPE-${LANG-C}}}
  case "$effective" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) printf '%s\n' UTF-8 ;;
    *) printf '%s\n' ANSI_X3.4-1968 ;;
  esac
  exit 0
fi
exit 1
STUB
  cat >"$STUB_BIN/colorls" <<'STUB'
#!/usr/bin/env sh
if [ "$(locale charmap)" = UTF-8 ]; then
  printf '\356\227\275 colorls-glyph\n'
else
  printf ' colorls-glyph\n'
fi
STUB
  chmod +x "$STUB_BIN/locale" "$STUB_BIN/colorls"

  run_zshrc() {
    local output_file="$1" error_file="$2"
    shift 2
    env -i \
      HOME="$TEST_HOME" \
      XDG_DATA_HOME="$TEST_HOME/.local/share" \
      PATH="$STUB_BIN:/usr/bin:/bin" \
      ZDOTDIR="$CASE_DIR/no-zdotdir" \
      DWS_TEST_LOCALES="${DWS_TEST_LOCALES:-C C.utf8 POSIX}" \
      "$@" \
      zsh -f -d -c 'source "$1"; printf "LANG=%s\nLC_ALL=%s\nLC_CTYPE=%s\n" "${LANG-<unset>}" "${LC_ALL-<unset>}" "${LC_CTYPE-<unset>}"; colorls' zsh "$ZSHRC" \
      >"$output_file" 2>"$error_file"
  }

  run_zshrc "$CASE_DIR/default.out" "$CASE_DIR/default.err"
  grep -Fqx 'LC_ALL=<unset>' "$CASE_DIR/default.out" || fail 'default ASCII startup left LC_ALL in control'
  grep -Eq '^LC_CTYPE=C\.(UTF-8|utf8)$' "$CASE_DIR/default.out" || fail 'default ASCII startup did not select an available C UTF-8 locale'
  grep -Fq ' colorls-glyph' "$CASE_DIR/default.out" || fail 'default ASCII startup lost the colorls private-use glyph'
  pass 'default ASCII startup selects shell-scoped UTF-8 and preserves glyph bytes'

  run_zshrc "$CASE_DIR/posix.out" "$CASE_DIR/posix.err" LC_ALL=POSIX LANG=en_US.UTF-8
  grep -Fqx 'LC_ALL=<unset>' "$CASE_DIR/posix.out" || fail 'POSIX LC_ALL still overrode the UTF-8 fallback'
  grep -Eq '^LC_CTYPE=C\.(UTF-8|utf8)$' "$CASE_DIR/posix.out" || fail 'POSIX LC_ALL did not fall back to an available UTF-8 locale'
  pass 'LC_ALL precedence is handled when its effective locale is POSIX'

  run_zshrc "$CASE_DIR/user-utf8.out" "$CASE_DIR/user-utf8.err" LANG=en_GB.UTF-8
  grep -Fqx 'LANG=en_GB.UTF-8' "$CASE_DIR/user-utf8.out" || fail 'valid user UTF-8 LANG was changed'
  grep -Fqx 'LC_ALL=<unset>' "$CASE_DIR/user-utf8.out" || fail 'valid user UTF-8 locale gained LC_ALL'
  grep -Fqx 'LC_CTYPE=<unset>' "$CASE_DIR/user-utf8.out" || fail 'valid user UTF-8 locale gained LC_CTYPE'
  pass 'valid user UTF-8 locale selection is preserved'

  run_zshrc "$CASE_DIR/user-lc-all-utf8.out" "$CASE_DIR/user-lc-all-utf8.err" LC_ALL=fr_FR.UTF-8 LC_CTYPE=POSIX LANG=C
  grep -Fqx 'LC_ALL=fr_FR.UTF-8' "$CASE_DIR/user-lc-all-utf8.out" || fail 'UTF-8 LC_ALL was not preserved as the effective user selection'
  grep -Fqx 'LC_CTYPE=POSIX' "$CASE_DIR/user-lc-all-utf8.out" || fail 'lower-precedence LC_CTYPE was changed under UTF-8 LC_ALL'
  pass 'UTF-8 LC_ALL precedence is preserved without rewriting lower selections'

  DWS_TEST_LOCALES='C POSIX' run_zshrc "$CASE_DIR/unavailable.out" "$CASE_DIR/unavailable.err" LANG=C
  grep -Fqx 'LANG=C' "$CASE_DIR/unavailable.out" || fail 'unavailable fallback changed LANG dishonestly'
  grep -Fqx 'LC_CTYPE=<unset>' "$CASE_DIR/unavailable.out" || fail 'unavailable fallback exported a nonexistent locale'
  grep -Fq 'Install or generate C.UTF-8 (or C.utf8)' "$CASE_DIR/unavailable.err" || fail 'unavailable fallback lacks actionable nonfatal guidance'
  pass 'missing UTF-8 locale is nonfatal and reports actionable guidance'
fi

grep -Fq 'palette = '\''catppuccin_mocha'\''' "$STARSHIP_CONFIG" || fail 'Starship Catppuccin Mocha palette selection is missing'
grep -Fq '[](surface0)' "$STARSHIP_CONFIG" || fail 'Starship opening Powerline segment is missing'
grep -Fq '[](bg:peach fg:surface0)' "$STARSHIP_CONFIG" || fail 'Starship peach transition background is missing'
grep -Fq '[](fg:green bg:teal)' "$STARSHIP_CONFIG" || fail 'Starship green-to-teal transition is missing'
grep -Fq '[ ](fg:purple)' "$STARSHIP_CONFIG" || fail 'Starship closing Powerline segment is missing'
grep -Fq 'success_symbol = '\''[](bold fg:green)'\''' "$STARSHIP_CONFIG" || fail 'Starship Nerd Font success glyph is missing'

grep -Fq 'Zsh and Starship produce the layout' "$ROOT/README.md" || fail 'README does not identify the shell-driven prompt boundary'
grep -Fq 'The installer does not automate terminal fonts, themes, input modes, or other host settings.' "$ROOT/README.md" || fail 'README does not preserve the manual terminal-settings boundary'
grep -Fq 'Warp is one documented renderer, not the only supported visual reference.' "$ROOT/README.md" || fail 'README still treats Warp as the sole visual reference'
grep -Fq 'shell_utf8_fallback:' "$ROOT/manifest.yaml" || fail 'manifest omits the shell UTF-8 fallback contract'
grep -Fq 'terminal_rendering_boundary:' "$ROOT/manifest.yaml" || fail 'manifest omits the terminal rendering boundary'
grep -Fq 'Zsh and Starship own the portable Powerline layout.' "$ROOT/windows/WARP-SETUP.md" || fail 'Warp guide does not describe the portable shell-owned layout'
grep -Fq 'causality is unknown' "$ROOT/docs/installation-runtime-remedies.md" || fail 'runtime remedies overstate the autosuggestion report'
pass 'appearance and locale documentation preserves ownership and safety boundaries'

if command -v starship >/dev/null 2>&1; then
  STARSHIP_BIN="$(command -v starship)"
  mkdir -p "$CASE_DIR/starship-home" "$CASE_DIR/starship-config" "$CASE_DIR/starship-cache"
  if ! timeout 10s env -i \
    HOME="$CASE_DIR/starship-home" \
    XDG_CONFIG_HOME="$CASE_DIR/starship-config" \
    XDG_CACHE_HOME="$CASE_DIR/starship-cache" \
    STARSHIP_CONFIG="$STARSHIP_CONFIG" \
    "$STARSHIP_BIN" prompt --path "$CASE_DIR" --status 0 --cmd-duration 0 \
    >"$CASE_DIR/starship-render.out" 2>"$CASE_DIR/starship-render.err"; then
    fail 'installed Starship could not render the portable prompt in isolated state'
  fi
  grep -Fq '' "$CASE_DIR/starship-render.out" || fail 'rendered Starship prompt omitted the opening private-use glyph'
  grep -Fq $'\033[48;2;' "$CASE_DIR/starship-render.out" || fail 'rendered Starship prompt omitted truecolor backgrounds'
  pass 'installed Starship renders private-use glyphs and truecolor backgrounds in isolated state'
else
  printf 'SKIP - starship executable unavailable; static glyph, palette, and segment contracts passed\n'
fi
