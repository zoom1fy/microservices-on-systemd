#!/bin/bash
set -euo pipefail

ROOT=/opt/demo-app

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root: sudo $0" >&2
    exit 1
fi

echo "==> installing system dependencies"
"$ROOT/scripts/install-deps.sh" node npm python postgres

echo "==> preparing demo user home and .env permissions"
install -d -o demo -g demo /home/demo
chmod 600 "$ROOT/.env"

echo "==> deploying systemd units"
for unit in demo-app.system-deps.service \
            demo-app.backend-deps.service \
            demo-app.frontend-deps.service \
            demo-app.db-init.service; do
    systemctl disable "$unit" 2>/dev/null || true
done
rm -f /etc/systemd/system/demo-app.system-deps.service \
      /etc/systemd/system/demo-app.backend-deps.service \
      /etc/systemd/system/demo-app.frontend-deps.service
install -m 0644 "$ROOT"/systemd/*.service "$ROOT"/systemd/*.target /etc/systemd/system/
systemctl daemon-reload

echo "==> stopping previously running services"
systemctl stop demo-app.frontend.service demo-app.backend.service 2>/dev/null || true

echo "==> building artifacts (if missing)"
if [ ! -e "$ROOT/artifacts/current" ]; then
    "$ROOT/build.sh"
else
    echo "artifacts/current exists; run $ROOT/build.sh to refresh"
fi

echo "==> initializing demo database (dev helper)"
systemctl start demo-app.db-init.service

echo "==> enabling and starting demo-app.target"
systemctl enable --now demo-app.target

echo
echo "=== status ==="
systemctl status demo-app.target --no-pager -n 3 || true
