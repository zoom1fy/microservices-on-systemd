#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root: sudo $0" >&2
    exit 1
fi

echo "==> stopping and disabling demo-app"
systemctl disable --now demo-app.target 2>/dev/null || true
systemctl disable demo-app.frontend.service demo-app.backend.service \
                   demo-app.db-init.service 2>/dev/null || true
systemctl stop demo-app.frontend.service demo-app.backend.service \
               demo-app.db-init.service 2>/dev/null || true

echo "==> removing systemd units"
rm -f /etc/systemd/system/demo-app.target \
      /etc/systemd/system/demo-app.backend.service \
      /etc/systemd/system/demo-app.frontend.service \
      /etc/systemd/system/demo-app.db-init.service \
      /etc/systemd/system/demo-app.system-deps.service \
      /etc/systemd/system/demo-app.backend-deps.service \
      /etc/systemd/system/demo-app.frontend-deps.service

systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

echo "done; built artifacts left in /opt/demo-app/artifacts"
