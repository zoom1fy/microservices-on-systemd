#!/bin/bash
set -euo pipefail

ROOT=/opt/demo-app
SRC="$ROOT/src"
ART="$ROOT/artifacts"
REV="${REV:-$(date -u +%Y%m%d%H%M%S)}"
DEST="$ART/$REV"

for bin in python3 npm; do
    command -v "$bin" >/dev/null 2>&1 || {
        echo "missing '$bin'; run as root: sudo $ROOT/install.sh" >&2
        exit 1
    }
done

mkdir -p "$ART"

if [ -e "$DEST" ]; then
    echo "artifact '$REV' already exists; set REV=<new-id> or remove $DEST" >&2
    exit 1
fi

echo "==> building backend ($REV)"
mkdir -p "$DEST/backend"
cp "$SRC/backend/main.py" "$SRC/backend/requirements.txt" "$DEST/backend/"
python3 -m venv "$DEST/backend/.venv"
"$DEST/backend/.venv/bin/pip" install --upgrade pip
"$DEST/backend/.venv/bin/pip" install -r "$DEST/backend/requirements.txt"

echo "==> building frontend ($REV)"
mkdir -p "$DEST/frontend"
cp "$SRC/frontend/package.json" "$SRC/frontend/package-lock.json" \
   "$SRC/frontend/next.config.js" "$DEST/frontend/"
cp -r "$SRC/frontend/app" "$DEST/frontend/app"
(
    cd "$DEST/frontend"
    npm ci
    npm run build
)

ln -sfn "$REV" "$ART/current"
echo "==> done: $DEST (current -> $REV)"
