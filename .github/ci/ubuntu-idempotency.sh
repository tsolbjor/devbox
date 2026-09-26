#!/usr/bin/env bash
# Rerun-safety test for setup-ubuntu.sh, run as root inside a fresh ubuntu:24.04
# container with the repo mounted read-only at /src:
#
#   docker run --rm -e GITHUB_TOKEN -v "$PWD:/src:ro" ubuntu:24.04 \
#     bash /src/.github/ci/ubuntu-idempotency.sh
#
# 1. setup-ubuntu.sh on a blank machine, as a normal sudo-capable user
# 2. setup-ubuntu.sh again — every step must report ✓; any → line means a check
#    that never recognises its own work, which is exactly how rerun bugs look
# 3. audit-ubuntu.sh — must report no drift against the setup it just watched
#
# Same script in CI and locally, so a red build reproduces with one command.
set -euo pipefail

USER_NAME=dev
HOME_DIR="/home/$USER_NAME"
REPO="$HOME_DIR/devbox"
LOGS="${LOGS:-/tmp/devbox-ci}"
mkdir -p "$LOGS"

echo "::group::Prepare a WSL-like Ubuntu"
export DEBIAN_FRONTEND=noninteractive
# The Docker image is minimized: dpkg skips /usr/share/doc, which the WSL image
# keeps — and Ubuntu 24.04's fzf 0.44 (too old for `fzf --zsh`) ships its
# key-binding scripts only under /usr/share/doc/fzf/examples.
rm -f /etc/dpkg/dpkg.cfg.d/excludes
apt-get update -qq
# What the WSL Ubuntu image already ships and the container image lacks: setup
# assumes sudo and ssh-keygen are there, as they are on every WSL install.
apt-get install -y -qq sudo openssh-client ca-certificates locales >/dev/null
useradd -m -s /bin/bash "$USER_NAME"
{
  echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL"
  # sudo resets the environment; keep apt non-interactive for the script's own sudo calls
  echo 'Defaults env_keep += "DEBIAN_FRONTEND"'
} > /etc/sudoers.d/devbox-ci
chmod 0440 /etc/sudoers.d/devbox-ci
cp -r /src "$REPO"
chown -R "$USER_NAME:$USER_NAME" "$REPO"
echo "::endgroup::"

# A login shell each time, like a user opening a new terminal: ~/.profile puts
# ~/.local/bin on PATH once it exists, which the second run relies on to find
# what the first installed there (starship, zoxide, claude, the shims).
as_user() {
  sudo -u "$USER_NAME" -H env \
    DEBIAN_FRONTEND=noninteractive \
    GITHUB_TOKEN="${GITHUB_TOKEN:-}" \
    GIT_NAME="CI Runner" GIT_EMAIL="ci@example.com" \
    MIGRATE_LEGACY_NODE=no \
    bash -lc "cd '$REPO' && $1"
}

echo "::group::Run 1 — blank machine"
as_user "bash setup-ubuntu.sh" 2>&1 | tee "$LOGS/run1.log"
echo "::endgroup::"

echo "::group::Run 2 — rerun must change nothing"
as_user "bash setup-ubuntu.sh" 2>&1 | tee "$LOGS/run2.log"
echo "::endgroup::"

echo "::group::Audit"
as_user "bash audit-ubuntu.sh" 2>&1 | tee "$LOGS/audit.log"
echo "::endgroup::"

status=0
# Line-leading only: the closing "Next steps" text says "GitHub → https://…".
if grep -nE '^[[:space:]]*→' "$LOGS/run2.log" > "$LOGS/run2-actions.txt"; then
  echo "::error::setup-ubuntu.sh is not idempotent — the rerun took action:"
  cat "$LOGS/run2-actions.txt"
  status=1
fi
if ! grep -q '^No drift detected' "$LOGS/audit.log"; then
  echo "::error::audit-ubuntu.sh reports drift right after setup:"
  grep -A3 '^⚠' "$LOGS/audit.log" || true
  status=1
fi
[[ $status -eq 0 ]] && echo "✓ rerun changed nothing and the audit is clean"
exit $status
