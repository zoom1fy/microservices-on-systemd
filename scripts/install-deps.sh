#!/bin/bash
set -euo pipefail

# Install Debian packages via apt.
#
# Usage: install-deps.sh [package ...]

packages=("$@")
if [ "${#packages[@]}" -eq 0 ]; then
    packages=(nodejs npm python3 python3-venv postgresql postgresql-client)
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root: sudo $0" >&2
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "install-deps: apt-get not found; Debian or Ubuntu is required" >&2
    exit 1
fi

echo "==> installing via apt: ${packages[*]}"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
