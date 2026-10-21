#!/bin/bash
set -euo pipefail

ROOT="${INSTALL_ROOT:-$(cd -- "$(dirname -- "$(readlink -f -- "$0")")/.." && pwd)}"

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root: sudo $0" >&2
    exit 1
fi

NODE="$(command -v node || echo /usr/bin/node)"

case "$ROOT" in
    /home/*|/root/*) PROTECT_HOME=read-only ;;
    *)               PROTECT_HOME=yes ;;
esac

for tmpl in "$ROOT"/systemd/*.service "$ROOT"/systemd/*.target; do
    unit="/etc/systemd/system/$(basename -- "$tmpl")"
    : > "$unit"
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line//@ROOT@/$ROOT}"
        line="${line//@PROTECTHOME@/$PROTECT_HOME}"
        printf '%s\n' "${line//@NODE@/$NODE}" >> "$unit"
    done < "$tmpl"
    chmod 0644 "$unit"
    echo "installed $unit"
done

systemctl daemon-reload
