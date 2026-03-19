#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_REPO_URL="${RAVEN_APP_REPO_URL:-}"
APP_BRANCH="${RAVEN_APP_BRANCH:-main}"
RAVEN_HOME="${RAVEN_HOME:-$HOME/.Raven}"
APP_DIR="${RAVEN_APP_DIR:-$RAVEN_HOME}"

usage() {
  cat <<'USAGE'
Usage: ./install.sh [options]

Options:
  --setup       Run the app setup wizard after cloning
  --refresh     Reinstall if the app directory already exists
  -h, --help    Show this help
USAGE
}

RUN_SETUP=0
FORCE_REFRESH=0

for arg in "$@"; do
  case "$arg" in
    --setup) RUN_SETUP=1 ;;
    --refresh) FORCE_REFRESH=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
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

need_cmd git
need_cmd bash

os_name="$(uname -s)"
case "$os_name" in
  Darwin|Linux)
    ;;
  *)
    echo "Unsupported operating system: $os_name" >&2
    exit 1
    ;;
esac

if [[ -z "$APP_REPO_URL" ]]; then
  echo "Error: RAVEN_APP_REPO_URL is required." >&2
  exit 1
fi

echo "== Raven Installer =="
echo "installer root: $ROOT_DIR"
echo "app repo: $APP_REPO_URL"
echo "app branch: $APP_BRANCH"
echo "app dir: $APP_DIR"

if [[ -d "$APP_DIR/.git" && "$FORCE_REFRESH" -eq 0 ]]; then
  echo "Existing checkout detected. Use --refresh to reclone."
else
  if [[ -e "$APP_DIR" ]]; then
    rm -rf "$APP_DIR"
  fi
  git clone --branch "$APP_BRANCH" --single-branch "$APP_REPO_URL" "$APP_DIR"
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
