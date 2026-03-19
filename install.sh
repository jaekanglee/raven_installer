#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_REPO_URL="${RAVEN_APP_REPO_URL:-}"
APP_BRANCH="${RAVEN_APP_BRANCH:-main}"
RELEASE_REPO="${RAVEN_RELEASE_REPO:-jaekanglee/raven_core}"
RELEASE_TAG="${RAVEN_RELEASE_TAG:-v1.0.0}"
RAVEN_HOME="${RAVEN_HOME:-$HOME/.Raven}"
APP_DIR="${RAVEN_APP_DIR:-$RAVEN_HOME}"
INSTALL_SOURCE="${RAVEN_INSTALL_SOURCE:-release}"

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

RUN_SETUP=0
FORCE_REFRESH=0
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
need_cmd tar
need_cmd curl

resolve_github_token() {
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    printf '%s' "$GITHUB_TOKEN"
    return 0
  fi

  if command -v gh >/dev/null 2>&1; then
    gh auth token 2>/dev/null || true
    return 0
  fi

  return 0
}

download_release_archive() {
  local repo="$1"
  local tag="$2"
  local output="$3"
  local url="https://api.github.com/repos/${repo}/tarball/${tag}"
  local token

  token="$(resolve_github_token)"

  if [[ -n "$token" ]]; then
    curl --fail --location \
      -H "Authorization: Bearer ${token}" \
      -H "Accept: application/vnd.github+json" \
      "$url" \
      -o "$output"
    return
  fi

  if ! curl --fail --location "$url" -o "$output"; then
    echo "Error: failed to download release archive." >&2
    echo "If ${repo} is private, set GITHUB_TOKEN or login with gh auth login." >&2
    exit 1
  fi
}

install_from_release() {
  local repo="$1"
  local tag="$2"
  local tmp_dir
  local archive

  tmp_dir="$(mktemp -d)"
  archive="${tmp_dir}/raven.tar.gz"

  echo "Downloading release archive: ${repo}@${tag}"
  download_release_archive "$repo" "$tag" "$archive"

  rm -rf "$APP_DIR"
  mkdir -p "$APP_DIR"
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

if [[ -d "$APP_DIR/.git" && "$FORCE_REFRESH" -eq 0 ]]; then
  echo "Existing checkout detected. Use --refresh to reinstall."
else
  if [[ "$INSTALL_SOURCE" == "release" ]]; then
    echo "release repo: $RELEASE_REPO"
    echo "release tag: $RELEASE_TAG"
    install_from_release "$RELEASE_REPO" "$RELEASE_TAG"
  else
    if [[ -z "$APP_REPO_URL" ]]; then
      echo "Error: RAVEN_APP_REPO_URL is required when --source git is used." >&2
      exit 1
    fi
    echo "app repo: $APP_REPO_URL"
    echo "app branch: $APP_BRANCH"
    install_from_git "$APP_REPO_URL" "$APP_BRANCH"
  fi
fi

cd "$APP_DIR"

if [[ -x "./install.sh" ]]; then
  echo "== Running app installer =="
  if [[ "$RUN_SETUP" -eq 1 ]]; then
    bash ./install.sh --setup
  else
    bash ./install.sh
  fi
else
  echo "Error: app installer not found at $APP_DIR/install.sh" >&2
  exit 1
fi
