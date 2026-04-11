#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${BASH_SOURCE[0]:-}" ]] && [[ -e "${BASH_SOURCE[0]}" ]]; then
  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  ROOT_DIR="$(pwd)"
fi
APP_REPO_URL="${RAVEN_APP_REPO_URL:-}"
APP_BRANCH="${RAVEN_APP_BRANCH:-main}"
RELEASE_REPO="${RAVEN_RELEASE_REPO:-jaekanglee/raven_installer}"
RELEASE_TAG="${RAVEN_RELEASE_TAG:-}"
RELEASE_ASSET_NAME="${RAVEN_RELEASE_ASSET_NAME:-}"
RAVEN_HOME="${RAVEN_HOME:-$HOME/.Raven}"
APP_DIR="${RAVEN_APP_DIR:-$RAVEN_HOME}"
INSTALL_SOURCE="${RAVEN_INSTALL_SOURCE:-release}"
RAVEN_NODE_VERSION="${RAVEN_NODE_VERSION:-v22.15.1}"
RAVEN_BOOTSTRAP_DIR="${RAVEN_BOOTSTRAP_DIR:-$HOME/.local/share/raven/bootstrap}"
RAVEN_USE_SYSTEM_NODE="${RAVEN_USE_SYSTEM_NODE:-0}"
RAVEN_ENV_TEMPLATE_OUT="${RAVEN_ENV_TEMPLATE_OUT:-$RAVEN_HOME/ingress-env.template.sh}"
RAVEN_BIN_DIR_INPUT="${RAVEN_BIN_DIR:-}"
RAVEN_LAUNCHER_PATH_INPUT="${RAVEN_LAUNCHER_PATH:-}"
RAVEN_BIN_DIR="${RAVEN_BIN_DIR_INPUT:-$HOME/.local/bin}"
RAVEN_LAUNCHER_PATH="${RAVEN_LAUNCHER_PATH_INPUT:-$RAVEN_BIN_DIR/raven}"

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Options:
  --setup       Run the app setup wizard after cloning
  --refresh     Reinstall if the app directory already exists
  --source <s>  Install source: release|git
  --uninstall   Remove Raven launcher, PATH setup, app files, and bootstrap files
  -h, --help    Show this help
USAGE
}

node_platform_suffix() {
  local arch
  arch="$(uname -m)"
  case "$os_name:$arch" in
    Linux:x86_64) printf '%s' "linux-x64" ;;
    Linux:aarch64|Linux:arm64) printf '%s' "linux-arm64" ;;
    Darwin:x86_64) printf '%s' "darwin-x64" ;;
    Darwin:arm64) printf '%s' "darwin-arm64" ;;
    *)
      echo "Error: unsupported platform for automatic Node bootstrap: ${os_name}/${arch}" >&2
      exit 1
      ;;
  esac
}

install_node_toolchain_portable() {
  local suffix archive_url install_root extract_dir archive_path
  suffix="$(node_platform_suffix)"
  install_root="${RAVEN_BOOTSTRAP_DIR}/node-${RAVEN_NODE_VERSION}-${suffix}"
  extract_dir="${RAVEN_BOOTSTRAP_DIR}"
  archive_path="${RAVEN_BOOTSTRAP_DIR}/node-${RAVEN_NODE_VERSION}-${suffix}.tar.xz"
  archive_url="https://nodejs.org/dist/${RAVEN_NODE_VERSION}/node-${RAVEN_NODE_VERSION}-${suffix}.tar.xz"

  if [[ -x "${install_root}/bin/node" && -x "${install_root}/bin/npm" ]]; then
    export PATH="${install_root}/bin:${PATH}"
    return
  fi

  mkdir -p "$extract_dir"
  rm -f "$archive_path"

  echo "Node.js/npm not found. Attempting portable bootstrap: ${RAVEN_NODE_VERSION} (${suffix})"
  curl --fail --location "$archive_url" -o "$archive_path"
  tar -xJf "$archive_path" -C "$extract_dir"
  rm -f "$archive_path"

  if [[ ! -x "${install_root}/bin/node" || ! -x "${install_root}/bin/npm" ]]; then
    echo "Error: portable node/npm bootstrap did not complete successfully." >&2
    exit 1
  fi

  export PATH="${install_root}/bin:${PATH}"
}

ensure_node_toolchain() {
  if [[ "$RAVEN_USE_SYSTEM_NODE" == "1" ]] && command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    return
  fi

  case "$os_name" in
    Linux|Darwin)
      install_node_toolchain_portable
      ;;
    *)
      echo "Error: node and npm are required." >&2
      exit 1
      ;;
  esac
}

print_prereq_behavior() {
  case "$os_name" in
    Linux|Darwin)
      if [[ "$RAVEN_USE_SYSTEM_NODE" == "1" ]]; then
        echo "prereq bootstrap: system Node preferred"
      else
        echo "prereq bootstrap: portable Node preferred"
      fi
      ;;
    *)
      echo "prereq bootstrap: manual"
      ;;
  esac
}

ensure_line_in_file() {
  local file="$1"
  local line="$2"
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -Fqx "$line" "$file" 2>/dev/null; then
    return
  fi
  printf "\n%s\n" "$line" >> "$file"
}

path_contains_dir() {
  local target="$1"
  local entry
  IFS=':' read -r -a path_entries <<< "${PATH:-}"
  for entry in "${path_entries[@]}"; do
    if [[ "$entry" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

dir_is_writable_or_creatable() {
  local dir="$1"
  if [[ -d "$dir" ]]; then
    [[ -w "$dir" ]]
    return
  fi

  local parent
  parent="$(dirname "$dir")"
  [[ -d "$parent" && -w "$parent" ]]
}

build_path_export_line() {
  local dir="$1"
  if [[ "$dir" == "$HOME" ]]; then
    printf '%s\n' 'export PATH="$HOME:$PATH"'
    return
  fi
  if [[ "$dir" == "$HOME/"* ]]; then
    printf 'export PATH="$HOME/%s:$PATH"\n' "${dir#"$HOME/"}"
    return
  fi
  printf 'export PATH="%s:$PATH"\n' "$dir"
}

resolve_launcher_location() {
  if [[ -n "$RAVEN_LAUNCHER_PATH_INPUT" ]]; then
    RAVEN_LAUNCHER_PATH="$RAVEN_LAUNCHER_PATH_INPUT"
    RAVEN_BIN_DIR="$(dirname "$RAVEN_LAUNCHER_PATH")"
    return
  fi

  if [[ -n "$RAVEN_BIN_DIR_INPUT" ]]; then
    RAVEN_BIN_DIR="$RAVEN_BIN_DIR_INPUT"
    RAVEN_LAUNCHER_PATH="${RAVEN_BIN_DIR}/raven"
    return
  fi

  local candidates=(
    "$HOME/.local/bin"
    "$HOME/bin"
    "/opt/homebrew/bin"
    "/usr/local/bin"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if path_contains_dir "$candidate" && dir_is_writable_or_creatable "$candidate"; then
      RAVEN_BIN_DIR="$candidate"
      RAVEN_LAUNCHER_PATH="${RAVEN_BIN_DIR}/raven"
      return
    fi
  done

  RAVEN_BIN_DIR="$HOME/.local/bin"
  RAVEN_LAUNCHER_PATH="${RAVEN_BIN_DIR}/raven"
}

remove_line_from_file() {
  local file="$1"
  local line="$2"
  if [[ ! -f "$file" ]]; then
    return
  fi
  local tmp_file
  tmp_file="$(mktemp)"
  awk -v target="$line" '$0 != target { print }' "$file" > "$tmp_file"
  mv "$tmp_file" "$file"
}

safe_remove_dir() {
  local dir="$1"
  if [[ -z "$dir" || "$dir" == "/" ]]; then
    echo "Error: refusing to remove unsafe directory: ${dir}" >&2
    exit 1
  fi
  if [[ -e "$dir" ]]; then
    rm -rf "$dir"
  fi
}

write_env_template_from_app() {
  local out_file="$RAVEN_ENV_TEMPLATE_OUT"
  mkdir -p "$(dirname "$out_file")"

  if command -v raven >/dev/null 2>&1; then
    if raven env-template >"$out_file" 2>/dev/null; then
      echo "Generated ingress env template: $out_file"
      return
    fi
  fi

  if [[ -x "$APP_DIR/bin/raven.js" ]] && command -v node >/dev/null 2>&1; then
    if node "$APP_DIR/bin/raven.js" env-template >"$out_file" 2>/dev/null; then
      echo "Generated ingress env template: $out_file"
      return
    fi
  fi

  echo "Notice: could not generate ingress env template automatically." >&2
}

ensure_launcher_bin_path() {
  local export_line
  export_line="$(build_path_export_line "$RAVEN_BIN_DIR")"
  local rc_files=()
  rc_files+=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")
  local seen=()
  local rc
  for rc in "${rc_files[@]}"; do
    local duplicate=0
    local existing
    if (( ${#seen[@]} > 0 )); then
      for existing in "${seen[@]}"; do
        if [[ "$existing" == "$rc" ]]; then
          duplicate=1
          break
        fi
      done
    fi
    if [[ "$duplicate" -eq 1 ]]; then
      continue
    fi
    seen+=("$rc")
    ensure_line_in_file "$rc" "$export_line"
  done
}

remove_launcher_bin_path() {
  local export_line
  export_line="$(build_path_export_line "$RAVEN_BIN_DIR")"
  local legacy_export_line='export PATH="$HOME/.local/bin:$PATH"'
  local rc_files=()
  rc_files+=("$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc")
  local seen=()
  local rc
  for rc in "${rc_files[@]}"; do
    local duplicate=0
    local existing
    if (( ${#seen[@]} > 0 )); then
      for existing in "${seen[@]}"; do
        if [[ "$existing" == "$rc" ]]; then
          duplicate=1
          break
        fi
      done
    fi
    if [[ "$duplicate" -eq 1 ]]; then
      continue
    fi
    seen+=("$rc")
    remove_line_from_file "$rc" "$export_line"
    if [[ "$legacy_export_line" != "$export_line" ]]; then
      remove_line_from_file "$rc" "$legacy_export_line"
    fi
  done
}

perform_uninstall() {
  echo "== Raven Uninstall =="
  echo "app dir: $APP_DIR"
  echo "launcher: $RAVEN_LAUNCHER_PATH"
  echo "bootstrap dir: $RAVEN_BOOTSTRAP_DIR"

  remove_launcher_bin_path

  if [[ -f "$RAVEN_LAUNCHER_PATH" ]]; then
    rm -f "$RAVEN_LAUNCHER_PATH"
  fi

  if [[ -f "$RAVEN_ENV_TEMPLATE_OUT" ]]; then
    rm -f "$RAVEN_ENV_TEMPLATE_OUT"
  fi

  safe_remove_dir "$APP_DIR"

  if [[ "$RAVEN_USE_SYSTEM_NODE" != "1" ]]; then
    safe_remove_dir "$RAVEN_BOOTSTRAP_DIR"
  fi

  printf '\nRaven uninstall complete. New terminals will no longer include the Raven PATH entry automatically.\n'
}

RUN_SETUP=0
FORCE_REFRESH=0
RUN_UNINSTALL=0
NON_TTY_SETUP_WARNED=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --setup)
      RUN_SETUP=1
      shift
      ;;
    --refresh)
      FORCE_REFRESH=1
      shift
      ;;
    --source)
      if [[ $# -lt 2 ]]; then
        echo "Error: --source requires a value" >&2
        exit 1
      fi
      INSTALL_SOURCE="$2"
      shift 2
      ;;
    --uninstall)
      RUN_UNINSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command not found: $1" >&2
    exit 1
  fi
}

need_cmd bash
need_cmd curl
need_cmd tar

resolve_latest_release_tag_from_feed() {
  local repo="$1"
  local atom_url="https://github.com/${repo}/releases.atom"
  local body
  body="$(curl --fail --silent --show-error --location \
    -H 'User-Agent: raven-installer' \
    "$atom_url")" || return 1

  local tag
  tag="$(printf '%s' "$body" | awk '
    /<entry>/ { in_entry=1 }
    in_entry && /<title>/ {
      line=$0
      sub(/^.*<title>/, "", line)
      sub(/<\/title>.*$/, "", line)
      print line
      exit
    }
  ')"

  if [[ -z "$tag" ]]; then
    return 1
  fi

  printf '%s\n' "$tag"
}

resolve_latest_release_meta_via_api() {
  local repo="$1"
  local api_url="https://api.github.com/repos/${repo}/releases/latest"
  local body
  body="$(curl --fail --silent --show-error --location \
    -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: raven-installer' \
    "$api_url")" || return 1

  local tag
  local asset

  tag="$(printf '%s' "$body" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  asset="$(printf '%s' "$body" | grep -o 'raven_core-[^"]*\.tar\.gz' | head -n1)"

  if [[ -z "$tag" ]]; then
    return 1
  fi
  if [[ -z "$asset" ]]; then
    asset="raven_core-${tag}.tar.gz"
  fi

  printf '%s|%s\n' "$tag" "$asset"
}

resolve_latest_release_meta() {
  local repo="$1"
  local tag
  local api_meta

  tag="$(resolve_latest_release_tag_from_feed "$repo")" || tag=""
  if [[ -n "$tag" ]]; then
    printf '%s|%s\n' "$tag" "raven_core-${tag}.tar.gz"
    return 0
  fi

  api_meta="$(resolve_latest_release_meta_via_api "$repo")" || return 1
  printf '%s\n' "$api_meta"
}

download_release_asset() {
  local repo="$1"
  local tag="$2"
  local asset_name="$3"
  local output="$4"
  local url="https://github.com/${repo}/releases/download/${tag}/${asset_name}"

  if ! curl --fail --location "$url" -o "$output"; then
    echo "Error: failed to download release asset ${asset_name}." >&2
    echo "Expected public release: ${repo} ${tag}" >&2
    exit 1
  fi
}

install_from_release() {
  local repo="$1"
  local tag="$2"
  local asset_name="$3"
  local replace_existing="${4:-1}"
  local tmp_dir
  local archive

  tmp_dir="$(mktemp -d)"
  archive="${tmp_dir}/raven.tar.gz"

  echo "Downloading release asset: ${repo}@${tag}/${asset_name}"
  download_release_asset "$repo" "$tag" "$asset_name" "$archive"

  mkdir -p "$APP_DIR"
  if [[ "$replace_existing" -eq 1 ]]; then
    rm -rf "$APP_DIR"
    mkdir -p "$APP_DIR"
  fi
  tar -xzf "$archive" --strip-components=1 -C "$APP_DIR"
  rm -rf "$tmp_dir"
}

install_from_git() {
  local repo_url="$1"
  local branch="$2"

  need_cmd git

  rm -rf "$APP_DIR"
  git clone --branch "$branch" --single-branch "$repo_url" "$APP_DIR"
}

os_name="$(uname -s)"
case "$os_name" in
  Darwin|Linux)
    ;;
  *)
    echo "Unsupported operating system: $os_name" >&2
    exit 1
    ;;
esac

if [[ "$RUN_UNINSTALL" -eq 1 ]]; then
  perform_uninstall
  exit 0
fi

if [[ "$INSTALL_SOURCE" != "release" && "$INSTALL_SOURCE" != "git" ]]; then
  echo "Error: RAVEN_INSTALL_SOURCE must be 'release' or 'git'." >&2
  exit 1
fi

echo "== Raven Installer =="
echo "installer root: $ROOT_DIR"
echo "install source: $INSTALL_SOURCE"
echo "app dir: $APP_DIR"
print_prereq_behavior
resolve_launcher_location
export RAVEN_BIN_DIR
export RAVEN_LAUNCHER_PATH

if [[ "$INSTALL_SOURCE" == "release" ]]; then
  if [[ -z "$RELEASE_TAG" || -z "$RELEASE_ASSET_NAME" ]]; then
    echo "Resolving latest published release tag from ${RELEASE_REPO}..."
    latest_meta="$(resolve_latest_release_meta "$RELEASE_REPO")" || {
      echo "Error: failed to resolve the latest published release tag from ${RELEASE_REPO}." >&2
      echo "Set RAVEN_RELEASE_TAG / RAVEN_RELEASE_ASSET_NAME explicitly and retry." >&2
      exit 1
    }
    latest_tag="${latest_meta%%|*}"
    latest_asset="${latest_meta#*|}"
    if [[ -z "$RELEASE_TAG" ]]; then
      RELEASE_TAG="$latest_tag"
    fi
    if [[ -z "$RELEASE_ASSET_NAME" ]]; then
      RELEASE_ASSET_NAME="$latest_asset"
    fi
  fi

  if [[ -z "$RELEASE_ASSET_NAME" ]]; then
    RELEASE_ASSET_NAME="raven_core-${RELEASE_TAG}.tar.gz"
  fi

  echo "release repo: $RELEASE_REPO"
  echo "release tag: $RELEASE_TAG"
  echo "release asset: $RELEASE_ASSET_NAME"
  if [[ -e "$APP_DIR/install.sh" && "$FORCE_REFRESH" -eq 0 ]]; then
    echo "Existing Raven core detected. Updating in place while preserving runtime data."
    install_from_release "$RELEASE_REPO" "$RELEASE_TAG" "$RELEASE_ASSET_NAME" 0
  elif [[ -d "$APP_DIR" && "$FORCE_REFRESH" -eq 0 ]]; then
    echo "Existing Raven runtime detected. Installing core files into the current runtime directory."
    install_from_release "$RELEASE_REPO" "$RELEASE_TAG" "$RELEASE_ASSET_NAME" 0
  else
    install_from_release "$RELEASE_REPO" "$RELEASE_TAG" "$RELEASE_ASSET_NAME" 1
  fi
else
  if [[ -d "$APP_DIR" && "$FORCE_REFRESH" -eq 0 ]]; then
    echo "Existing app directory detected for git install. Use --refresh to replace it." >&2
    exit 1
  fi
  if [[ -z "$APP_REPO_URL" ]]; then
    echo "Error: RAVEN_APP_REPO_URL is required when --source git is used." >&2
    exit 1
  fi
  echo "app repo: $APP_REPO_URL"
  echo "app branch: $APP_BRANCH"
  install_from_git "$APP_REPO_URL" "$APP_BRANCH"
fi

cd "$APP_DIR"

if [[ -x "./install.sh" ]]; then
  ensure_node_toolchain
  echo "== Running app installer =="
  if [[ "$RUN_SETUP" -eq 1 ]]; then
    if [[ ! -t 0 || ! -t 1 ]]; then
      NON_TTY_SETUP_WARNED=1
      echo "Notice: --setup was requested from a non-interactive shell."
      echo "The app installer will skip the interactive wizard and finish installation first."
      echo "Run 'raven setup' afterwards from your terminal."
    fi
    bash ./install.sh --setup
  else
    bash ./install.sh
  fi
else
  echo "Error: app installer not found at $APP_DIR/install.sh" >&2
  exit 1
fi

if ! path_contains_dir "$RAVEN_BIN_DIR"; then
  ensure_launcher_bin_path
fi
write_env_template_from_app

if [[ "$NON_TTY_SETUP_WARNED" -eq 1 ]]; then
  cat <<'NEXT'

Interactive setup was skipped because no TTY was available.
Run this next from your shell:
  raven setup
NEXT
fi

if path_contains_dir "$RAVEN_BIN_DIR"; then
  printf '\nLauncher installed into current PATH: %s\n' "$RAVEN_LAUNCHER_PATH"
  printf 'If this shell still does not resolve `raven`, run: hash -r\n'
else
  printf '\nPATH updated in shell startup files. New terminals will pick it up automatically.\n'
fi
