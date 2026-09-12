#!/usr/bin/env bash

pws_toolchain_root() {
  printf '%s\n' "$(pws_data_home)/dotfiles-workstation/tools"
}

pws_toolchain_lock() {
  local lock="${DOTFILES_WORKSTATION_TOOLCHAIN_LOCK:-$SCRIPT_DIR/toolchain.lock.tsv}"
  if [[ -n "${DOTFILES_WORKSTATION_TOOLCHAIN_LOCK:-}" && "${DOTFILES_WORKSTATION_TEST_MODE:-0}" != 1 ]]; then
    pws_die 'A toolchain lock override is allowed only in test mode.'
  fi
  printf '%s\n' "$lock"
}

pws_validate_toolchain_platform() {
  local os_id os_version architecture
  if [[ "${DOTFILES_WORKSTATION_TEST_MODE:-0}" == 1 ]]; then
    os_id="${DOTFILES_WORKSTATION_TEST_OS_ID:-ubuntu}"
    os_version="${DOTFILES_WORKSTATION_TEST_OS_VERSION:-26.04}"
    architecture="${DOTFILES_WORKSTATION_TEST_ARCH:-x86_64}"
  else
    # preflight already established that this is Ubuntu.
    # shellcheck disable=SC1091
    source /etc/os-release
    os_id="${ID:-}"
    os_version="${VERSION_ID:-}"
    architecture="$(uname -m)"
  fi
  [[ "$os_id" == ubuntu && "$os_version" == 26.04 && "$architecture" == x86_64 ]] ||
    pws_die "The source-toolchain profile currently supports Ubuntu 26.04 Linux x86_64 only (detected: ${os_id:-unknown} ${os_version:-unknown} ${architecture:-unknown})."
}

pws_toolchain_each_row() {
  local callback="$1" lock
  lock="$(pws_toolchain_lock)"
  [[ -f "$lock" ]] || pws_die "Toolchain lock is missing: $lock"
  local name version url integrity member format provenance extra
  while IFS=$'\t' read -r name version url integrity member format provenance extra; do
    [[ -z "$name" || "$name" == \#* ]] && continue
    [[ -n "$version" && -n "$url" && -n "$integrity" && -n "$member" && -n "$format" && -n "$provenance" && -z "$extra" ]] ||
      pws_die "Invalid toolchain lock row for ${name:-unknown}."
    "$callback" "$name" "$version" "$url" "$integrity" "$member" "$format" "$provenance"
  done <"$lock"
}

pws_print_toolchain_row() {
  printf '  %s %s -> %s/%s\n' "$1" "$2" "$(pws_toolchain_root)" "$1/$2"
}

pws_print_source_toolchain_contract() {
  cat <<CONTRACT
Profile: source-toolchain
Platform boundary: Ubuntu 26.04 Linux x86_64 only.
APT prerequisites: zsh git curl ca-certificates fzf bat fd-find build-essential pkg-config unzip xz-utils python3 wget locales ruby ruby-dev pulseaudio-utils.
Pinned user-local tools under $(pws_toolchain_root):
CONTRACT
  pws_toolchain_each_row pws_print_toolchain_row
  cat <<CONTRACT
Activation links: $HOME/.local/bin/{starship,atuin,zoxide,herdr,nvim,node,npm,npx,colorls,bat,fd,brew} (owned symlinks only; conflicts fail closed).
Integrity boundary: pinned downloads are SHA256-verified before extraction or execution; Homebrew is verified by Git tag and commit identity.
Snapshot boundary: configuration snapshots remain config-only. Tool versions are retained for manual activation rollback.
Optional boundary: pulseaudio-utils provides tested command availability only, not audio playback. win32yank, Zellij, and Carapace are not installed.
Runtime bootstrap: deferred to unit3; this profile does not claim Neovim plugins, parsers, Mason tools, or runtime health complete.
CONTRACT
}

pws_marker_matches() {
  local destination="$1" name="$2" version="$3" integrity="$4" artifact="$5"
  [[ -f "$destination/.installed.tsv" && ! -L "$destination/.installed.tsv" && -x "$artifact" ]] || return 1
  grep -Fqx "$name"$'\t'"$version"$'\t'"$integrity" "$destination/.installed.tsv"
}

pws_safe_extract() {
  local archive="$1" staging="$2" expected="$3" format="$4"
  python3 - "$archive" "$staging" "$expected" "$format" <<'PY'
import os, pathlib, posixpath, shutil, sys, tarfile

archive, staging, expected, mode = sys.argv[1:]


def safe_member_path(name):
    if not name or "\0" in name:
        raise SystemExit(f"Unsafe archive member: {name}")
    path = pathlib.PurePosixPath(name)
    normalized = posixpath.normpath(name)
    if path.is_absolute() or normalized in ("", ".", "..") or normalized.startswith("../"):
        raise SystemExit(f"Unsafe archive member: {name}")
    return pathlib.PurePosixPath(normalized)


def safe_link_target(item, member_path, top=None):
    linkname = item.linkname
    if not linkname or "\0" in linkname:
        raise SystemExit(f"Unsafe archive member link: {item.name} -> {linkname}")
    link = pathlib.PurePosixPath(linkname)
    if link.is_absolute():
        raise SystemExit(f"Unsafe archive member link: {item.name} -> {linkname}")
    if item.issym():
        normalized = posixpath.normpath(posixpath.join(str(member_path.parent), linkname))
    else:
        normalized = posixpath.normpath(linkname)
    if normalized in ("", ".", "..") or normalized.startswith("../") or normalized.startswith("/"):
        raise SystemExit(f"Unsafe archive member link: {item.name} -> {linkname}")
    target = pathlib.PurePosixPath(normalized)
    if top is not None and target.parts[:1] != (top,):
        raise SystemExit(f"Unsafe archive member link: {item.name} -> {linkname}")
    return target


with tarfile.open(archive, "r:*") as tf:
    members = tf.getmembers()
    indexed = []
    by_path = {}
    for item in members:
        path = safe_member_path(item.name)
        if path in by_path:
            raise SystemExit(f"Unsafe duplicate archive member: {item.name}")
        if not (item.isfile() or item.isdir() or item.issym() or item.islnk()):
            raise SystemExit(f"Unsafe archive member type: {item.name}")
        indexed.append((item, path))
        by_path[path] = item

    expected_path = safe_member_path(expected)
    selected = by_path.get(expected_path)
    if selected is None:
        raise SystemExit(f"Expected archive member is missing: {expected}")
    if not selected.isfile():
        raise SystemExit(f"Expected archive member is not a file: {expected}")

    top = expected_path.parts[0] if mode == "tree" else None
    relevant = [(item, path) for item, path in indexed if top is None or path.parts[:1] == (top,)]
    relevant_paths = {path: item for item, path in relevant}

    for item, path in indexed:
        if item.issym() or item.islnk():
            target = safe_link_target(item, path, top if path in relevant_paths else None)
            if item.islnk():
                target_item = by_path.get(target)
                if target_item is None or not target_item.isfile():
                    raise SystemExit(f"Unsafe archive member link: {item.name} -> {item.linkname}")
        for parent in path.parents:
            if str(parent) == ".":
                break
            parent_item = by_path.get(parent)
            if parent_item is not None and not parent_item.isdir():
                raise SystemExit(f"Unsafe archive member path hierarchy: {item.name}")

    extraction = os.path.join(staging, ".extract")
    os.mkdir(extraction, 0o700)

    def extracted_path(path):
        return os.path.join(extraction, *path.parts)

    directories = []
    for item, path in relevant:
        target = extracted_path(path)
        if item.isdir():
            os.makedirs(target, exist_ok=True)
            directories.append((target, item.mode & 0o777))
        elif item.isfile():
            os.makedirs(os.path.dirname(target), exist_ok=True)
            source = tf.extractfile(item)
            if source is None:
                raise SystemExit(f"Cannot read archive member: {item.name}")
            with source, open(target, "xb") as output:
                shutil.copyfileobj(source, output)
            os.chmod(target, item.mode & 0o777)

    for item, path in relevant:
        if not item.islnk():
            continue
        target_path = safe_link_target(item, path, top)
        os.makedirs(os.path.dirname(extracted_path(path)), exist_ok=True)
        os.link(extracted_path(target_path), extracted_path(path))

    for item, path in relevant:
        if not item.issym():
            continue
        safe_link_target(item, path, top)
        os.makedirs(os.path.dirname(extracted_path(path)), exist_ok=True)
        os.symlink(item.linkname, extracted_path(path))

    for directory, permissions in reversed(directories):
        os.chmod(directory, permissions)

    if mode == "tree":
        source = extracted_path(pathlib.PurePosixPath(top))
        for entry in os.listdir(source):
            if entry in (".download", ".extract"):
                raise SystemExit(f"Unsafe archive member conflicts with staging: {top}/{entry}")
            os.rename(os.path.join(source, entry), os.path.join(staging, entry))
    else:
        target_name = expected_path.name
        if target_name in (".download", ".extract"):
            raise SystemExit(f"Unsafe archive member conflicts with staging: {expected}")
        os.rename(extracted_path(expected_path), os.path.join(staging, target_name))

    shutil.rmtree(extraction)
PY
}

pws_artifact_path() {
  local destination="$1" name="$2" member="$3" format="$4"
  case "$name" in
    node) printf '%s/bin/node\n' "$destination" ;;
    nvim) printf '%s/bin/nvim\n' "$destination" ;;
    colorls) printf '%s/bin/colorls\n' "$destination" ;;
    homebrew) printf '%s/bin/brew\n' "$destination" ;;
    *)
      if [[ "$format" == raw ]]; then
        printf '%s/%s\n' "$destination" "$name"
      else
        printf '%s/%s\n' "$destination" "${member##*/}"
      fi
      ;;
  esac
}

pws_install_git_tool() {
  local name="$1" version="$2" url="$3" commit="$4" tag="$5" destination="$6" staging="$7"
  run git clone --depth 1 --branch "$tag" "$url" "$staging"
  if ((DRY_RUN)); then return; fi
  local actual
  actual="$(git -C "$staging" rev-parse HEAD)"
  [[ "$actual" == "$commit" ]] || pws_die "$name Git commit mismatch for tag $tag: expected $commit, got $actual"
  mkdir -p "$staging/activation"
  cat >"$staging/activation/brew" <<WRAPPER
#!/usr/bin/env bash
export HOMEBREW_NO_AUTO_UPDATE=1
exec "$destination/bin/brew" "\$@"
WRAPPER
  chmod 0755 "$staging/activation/brew"
  printf '%s\t%s\t%s\n' "$name" "$version" "$commit" >"$staging/.installed.tsv"
  mv -- "$staging" "$destination"
}

pws_install_tool_row() {
  local name="$1" version="$2" url="$3" integrity="$4" member="$5" format="$6" provenance="$7"
  local root destination artifact staging download actual
  root="$(pws_toolchain_root)"
  [[ ! -L "$root" ]] || pws_die "Toolchain root must not be a symlink: $root"
  if [[ -e "$root/$name" && ! -d "$root/$name" ]] || [[ -L "$root/$name" ]]; then
    pws_die "Tool version parent is not an owned directory: $root/$name"
  fi
  destination="$root/$name/$version"
  artifact="$(pws_artifact_path "$destination" "$name" "$member" "$format")"
  if pws_marker_matches "$destination" "$name" "$version" "$integrity" "$artifact"; then
    pws_log "$name $version already verified and active candidate."
    return
  fi
  [[ ! -e "$destination" && ! -L "$destination" ]] || pws_die "$destination exists without a matching verified artifact marker."
  if ((DRY_RUN)); then
    printf '+ download %q -> verified staging for %q\n' "$url" "$destination"
    return
  fi
  mkdir -p "$root/$name"
  staging="$(mktemp -d "$root/$name/.${version}.staging.XXXXXX")"
  case "$format" in
    gem)
      [[ "$name" != */* && "$name" != . && "$name" != .. ]] ||
        pws_die "Invalid gem tool name: $name"
      download="$staging/$name.gem"
      ;;
    *) download="$staging/.download" ;;
  esac
  trap '[[ -z "${staging:-}" ]] || rm -rf -- "$staging"' RETURN EXIT
  if [[ "$format" == git ]]; then
    rmdir -- "$staging"
    pws_install_git_tool "$name" "$version" "$url" "$integrity" "$member" "$destination" "$staging"
    staging=''
    trap - RETURN EXIT
    return
  fi
  curl --fail --location --silent --show-error -o "$download" "$url"
  actual="$(sha256sum "$download" | awk '{print $1}')"
  [[ "$actual" == "$integrity" ]] || pws_die "SHA256 mismatch for $name $version: expected $integrity, got $actual"
  case "$format" in
    tar|tree) pws_safe_extract "$download" "$staging" "$member" "$format" ;;
    raw)
      [[ "$name" != */* && "$name" != . && "$name" != .. && "$member" != */* && "$member" != . && "$member" != .. ]] ||
        pws_die "Invalid raw executable name for $name: $member"
      cp -- "$download" "$staging/$member"
      chmod 0755 "$staging/$member"
      [[ "$member" == "$name" ]] || mv -- "$staging/$member" "$staging/$name"
      ;;
    gem)
      mkdir -p "$staging/bin" "$staging/gems" "$staging/activation"
      gem install --install-dir "$staging/gems" --bindir "$staging/bin" --no-document "$download"
      {
        printf '#!/usr/bin/env bash\n'
        printf 'export GEM_HOME=%q\n' "$destination/gems"
        printf 'export GEM_PATH=%q\n' "$destination/gems"
        printf 'exec %q "$@"\n' "$destination/bin/$name"
      } >"$staging/activation/$name"
      chmod 0755 "$staging/activation/$name"
      ;;
    *) pws_die "Unsupported toolchain format for $name: $format" ;;
  esac
  rm -f -- "$download"
  artifact="$(pws_artifact_path "$staging" "$name" "$member" "$format")"
  [[ -f "$artifact" && ! -L "$artifact" ]] || pws_die "Installed artifact is missing for $name: $artifact"
  chmod 0755 "$artifact"
  printf '%s\t%s\t%s\n' "$name" "$version" "$integrity" >"$staging/.installed.tsv"
  mv -- "$staging" "$destination"
  staging=''
  trap - RETURN EXIT
}

pws_activation_commands() {
  local callback="$1" root
  root="$(pws_toolchain_root)"
  "$callback" starship "$root/starship/1.26.0/starship"
  "$callback" atuin "$root/atuin/18.19.0/atuin"
  "$callback" zoxide "$root/zoxide/0.10.0/zoxide"
  "$callback" herdr "$root/herdr/0.7.5/herdr"
  "$callback" nvim "$root/nvim/0.12.4/bin/nvim"
  "$callback" node "$root/node/22.23.1/bin/node"
  "$callback" npm "$root/node/22.23.1/bin/npm"
  "$callback" npx "$root/node/22.23.1/bin/npx"
  "$callback" colorls "$root/colorls/1.5.0/activation/colorls"
  "$callback" bat "$root/bat/0.26.1/bat"
  "$callback" fd "$root/fd/10.4.2/fd"
  "$callback" brew "$root/homebrew/6.0.22/activation/brew"
}

pws_activation_is_locked() {
  local command="$1" lock name
  lock="$(pws_toolchain_lock)"
  name="$command"
  case "$command" in npm|npx) name=node ;; brew) name=homebrew ;; esac
  grep -q "^${name}"$'\t' "$lock"
}

pws_preflight_activation() {
  local command="$1" target="$2" destination root
  destination="$HOME/.local/bin/$command"
  root="$(pws_toolchain_root)"
  [[ -x "$target" ]] || pws_die "Activation target is missing or not executable: $target"
  if [[ -L "$destination" ]]; then
    local prior ledger
    prior="$(readlink -- "$destination")"
    ledger="$root/activation.tsv"
    [[ "$prior" == "$root"/* && -f "$ledger" && ! -L "$ledger" ]] || pws_die "Refusing unowned activation destination: $destination -> $prior"
    awk -F '\t' -v command="$command" -v prior="$prior" '$1 == command && $3 == prior { found=1 } END { exit !found }' "$ledger" ||
      pws_die "Refusing unowned activation destination: $destination -> $prior"
  elif [[ -e "$destination" ]]; then
    pws_die "Refusing unowned activation destination: $destination"
  fi
}

pws_activate_one() {
  local command="$1" target="$2" destination prior='absent' temporary
  destination="$HOME/.local/bin/$command"
  if [[ -L "$destination" ]]; then
    prior="$(readlink -- "$destination")"
    [[ "$prior" == "$target" ]] && { pws_log "$command already verified and active."; return; }
  fi
  printf '%s\t%s\t%s\n' "$command" "$prior" "$target" >>"$(pws_toolchain_root)/activation.tsv"
  temporary="$HOME/.local/bin/.${command}.dotfiles-workstation.$$"
  ln -s -- "$target" "$temporary"
  mv -f -- "$temporary" "$destination"
}

pws_preflight_if_locked() {
  pws_activation_is_locked "$1" || return 0
  pws_preflight_activation "$1" "$2"
}

pws_activate_if_locked() {
  pws_activation_is_locked "$1" || return 0
  pws_activate_one "$1" "$2"
}

pws_install_source_toolchain() {
  pws_toolchain_each_row pws_install_tool_row
  ((DRY_RUN)) && return
  mkdir -p "$HOME/.local/bin"
  local ledger
  ledger="$(pws_toolchain_root)/activation.tsv"
  [[ ! -e "$ledger" || ( -f "$ledger" && ! -L "$ledger" ) ]] || pws_die "Activation ledger is not a regular file: $ledger"
  pws_activation_commands pws_preflight_if_locked
  pws_activation_commands pws_activate_if_locked
}
