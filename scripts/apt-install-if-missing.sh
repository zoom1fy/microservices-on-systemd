#!/bin/bash
set -eu

missing=()
for pkg in "$@"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        missing+=("$pkg")
    fi
done
if [ "${#missing[@]}" -eq 0 ]; then
    exit 0
fi

exec 9>/run/demo-app-apt.lock
flock 9

missing=()
for pkg in "$@"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        missing+=("$pkg")
    fi
done
if [ "${#missing[@]}" -eq 0 ]; then
    exit 0
fi

stamp=/var/lib/apt/periodic/update-success-stamp
if [ ! -e "$stamp" ] || [ -z "$(find "$stamp" -mmin -60 2>/dev/null)" ]; then
    apt-get update
fi

DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${missing[@]}"
