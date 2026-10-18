#!/bin/bash
set -euo pipefail

ROOT="${INSTALL_ROOT:-$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)}"

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root: sudo $0" >&2
    exit 1
fi

echo "==> installing system dependencies"
"$ROOT/scripts/install-deps.sh" nodejs npm python3 python3-venv postgresql postgresql-client

echo "==> creating demo system user/group (if missing)"
if ! getent group demo >/dev/null 2>&1; then
    groupadd --system demo
fi
if ! id demo >/dev/null 2>&1; then
    useradd --system --gid demo --home-dir /home/demo --shell /usr/sbin/nologin demo
fi
install -d -o demo -g demo /home/demo
chmod 600 "$ROOT/.env"

echo "==> granting service accounts access to $ROOT"
grant_traverse() {
    local dir=$1 mode
    while [ "$dir" != "/" ] && [ -n "$dir" ]; do
        if command -v setfacl >/dev/null 2>&1 && \
           setfacl -m u:demo:x -m u:postgres:x "$dir" 2>/dev/null; then
            :
        else
            mode=$(stat -c '%a' "$dir" 2>/dev/null || echo "")
            case "$mode" in
                *[13579]|"") ;;
                *) chmod o+x "$dir" 2>/dev/null || true ;;
            esac
        fi
        dir=$(dirname -- "$dir")
    done
}
grant_traverse "$(dirname -- "$ROOT")"

echo "==> starting PostgreSQL"
systemctl enable --now postgresql.service

echo "==> allowing local 'postgres' peer authentication"
hba="$(ls /etc/postgresql/*/main/pg_hba.conf 2>/dev/null | head -n1 || true)"
if [ -n "$hba" ] && \
   ! grep -qE '^[[:space:]]*local[[:space:]]+all[[:space:]]+postgres[[:space:]]+(peer|trust)' "$hba"; then
    tmp="$(mktemp)"
    { echo "local   all   postgres   peer"; cat "$hba"; } > "$tmp"
    cat "$tmp" > "$hba"
    rm -f "$tmp"
    systemctl reload postgresql.service
fi

echo "==> deploying systemd units"
systemctl disable "demo-app.db-init.service" 2>/dev/null || true

"$ROOT/scripts/install-systemd-units.sh"

echo "==> stopping previously running services"
systemctl stop demo-app.frontend.service demo-app.backend.service 2>/dev/null || true

echo "==> building artifacts (if missing)"
if [ ! -e "$ROOT/artifacts/current" ]; then
    "$ROOT/build.sh"
else
    echo "artifacts/current exists; run $ROOT/build.sh to refresh"
fi

echo "==> initializing demo database (dev helper)"
systemctl reset-failed demo-app.db-init.service 2>/dev/null || true
systemctl start demo-app.db-init.service

echo "==> enabling and starting demo-app.target"
systemctl enable --now demo-app.target

echo
echo "=== status ==="
systemctl status demo-app.target --no-pager -n 3 || true
