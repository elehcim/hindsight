#!/bin/sh
set -eu

cd -- "$(dirname -- "$0")"

if [ -z "${COPILOT_GITHUB_TOKEN:-}" ]; then
    if ! command -v gh >/dev/null 2>&1; then
        printf '%s\n' 'Install gh and run gh auth login, or set COPILOT_GITHUB_TOKEN.' >&2
        exit 1
    fi
    COPILOT_GITHUB_TOKEN=$(gh auth token --hostname github.com)
    if [ -z "$COPILOT_GITHUB_TOKEN" ]; then
        printf '%s\n' 'GitHub token unavailable; run gh auth login.' >&2
        exit 1
    fi
    export COPILOT_GITHUB_TOKEN
fi

exec docker compose up --detach --wait --wait-timeout 1200 "$@"
