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

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Options:
  --setup       Run the app setup wizard after cloning
  --refresh     Reinstall if the app directory already exists
  --source <s>  Install source: release|git
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
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
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
      echo "prereq bootstrap: portable Node auto-install enabled"
      ;;
    *)
      echo "prereq bootstrap: manual"
      ;;
  esac
}

RUN_SETUP=0
FORCE_REFRESH=0
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

resolve_latest_release_meta() {
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

if [[ "$INSTALL_SOURCE" != "release" && "$INSTALL_SOURCE" != "git" ]]; then
  echo "Error: RAVEN_INSTALL_SOURCE must be 'release' or 'git'." >&2
  exit 1
fi

echo "== Raven Installer =="
echo "installer root: $ROOT_DIR"
echo "install source: $INSTALL_SOURCE"
echo "app dir: $APP_DIR"
print_prereq_behavior

if [[ "$INSTALL_SOURCE" == "release" ]]; then
  if [[ -z "$RELEASE_TAG" || -z "$RELEASE_ASSET_NAME" ]]; then
    echo "Resolving latest release metadata from ${RELEASE_REPO}..."
    latest_meta="$(resolve_latest_release_meta "$RELEASE_REPO")" || {
      echo "Error: failed to resolve latest release from ${RELEASE_REPO}." >&2
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

if [[ "$NON_TTY_SETUP_WARNED" -eq 1 ]]; then
  cat <<'NEXT'

Interactive setup was skipped because no TTY was available.
Run this next from your shell:
  raven setup
NEXT
fi
