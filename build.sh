#!/bin/bash
set -euo pipefail

ROOT="${INSTALL_ROOT:-$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd)}"

if [ -f "$ROOT/.env" ]; then
    set -a
    . "$ROOT/.env"
    set +a
fi

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

if python3 -c "import ensurepip" >/dev/null 2>&1; then
    python3 -m venv "$DEST/backend/.venv"
else
    echo "ensurepip missing, creating venv without pip and bootstrapping it"
    python3 -m venv --without-pip "$DEST/backend/.venv"
    if command -v wget >/dev/null 2>&1; then
        wget -qO "$DEST/get-pip.py" https://bootstrap.pypa.io/get-pip.py
        "$DEST/backend/.venv/bin/python" "$DEST/get-pip.py"
        rm -f "$DEST/get-pip.py"
    elif command -v curl >/dev/null 2>&1; then
        curl -sS -L https://bootstrap.pypa.io/get-pip.py -o "$DEST/get-pip.py"
        "$DEST/backend/.venv/bin/python" "$DEST/get-pip.py"
        rm -f "$DEST/get-pip.py"
    else
        echo "need curl or wget to bootstrap pip" >&2
        exit 1
    fi
fi

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

chmod -R a+rX "$DEST"

ln -sfn "$REV" "$ART/current"
echo "==> done: $DEST (current -> $REV)"
