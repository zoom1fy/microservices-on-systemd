#!/bin/bash
set -euo pipefail

# Install the app's system dependencies, mapping each *logical* dependency to
# whatever the local distribution calls it. Detection is based on the actual
# command/binary, so a package already present (under any name) is skipped.
#
# Usage: install-deps.sh [node] [npm] [python] [postgres]

want=("$@")
if [ "${#want[@]}" -eq 0 ]; then
    want=(node npm python postgres)
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "must run as root: sudo $0" >&2
    exit 1
fi

# --- identify the distribution family --------------------------------------
. /etc/os-release 2>/dev/null || true
ident="${ID:-} ${ID_LIKE:-}"
case "$ident" in
    *debian*|*ubuntu*|*mint*|*raspbian*|*pop*) family=debian ;;
    *alt*)                                     family=alt ;;
    *fedora*|*rhel*|*centos*|*rocky*|*alma*)   family=rhel ;;
    *arch*|*manjaro*)                          family=arch ;;
    *suse*|*opensuse*)                         family=suse ;;
    *)                                         family=unknown ;;
esac

# --- pick a package manager ------------------------------------------------
if   command -v apt-get >/dev/null 2>&1; then pm=apt
elif command -v dnf     >/dev/null 2>&1; then pm=dnf
elif command -v yum     >/dev/null 2>&1; then pm=yum
elif command -v pacman  >/dev/null 2>&1; then pm=pacman
elif command -v zypper  >/dev/null 2>&1; then pm=zypper
else
    echo "install-deps: no supported package manager found" >&2
    exit 1
fi

# --- logical dependency -> distro package names ----------------------------
map_pkg() {
    case "$family:$1" in
        debian:node)     echo nodejs ;;
        debian:npm)      echo npm ;;
        debian:python)   echo python3 python3-venv ;;
        debian:postgres) echo postgresql postgresql-client ;;

        alt:node)        echo node ;;
        alt:npm)         echo npm ;;
        alt:python)      echo python3 ;;
        alt:postgres)    echo postgresql15-server postgresql15 ;;

        rhel:node)       echo nodejs ;;
        rhel:npm)        echo npm ;;
        rhel:python)     echo python3 ;;
        rhel:postgres)   echo postgresql-server postgresql ;;

        arch:node)       echo nodejs ;;
        arch:npm)        echo npm ;;
        arch:python)     echo python ;;
        arch:postgres)   echo postgresql ;;

        suse:node)       echo nodejs ;;
        suse:npm)        echo npm ;;
        suse:python)     echo python3 ;;
        suse:postgres)   echo postgresql-server postgresql ;;

        *)               echo "" ;;
    esac
}

# --- is a logical dependency already satisfied? ----------------------------
satisfied() {
    case "$1" in
        node)     command -v node >/dev/null 2>&1 ;;
        npm)      command -v npm  >/dev/null 2>&1 ;;
        python)   command -v python3 >/dev/null 2>&1 \
                  && python3 -c 'import venv' >/dev/null 2>&1 \
                  && python3 -m ensurepip --version >/dev/null 2>&1 ;;
        postgres) command -v psql >/dev/null 2>&1 \
                  || systemctl list-unit-files --type=service 2>/dev/null \
                     | grep -qiE '^postgresql[^[:space:]]*\.service' ;;
        *)        return 1 ;;
    esac
}

packages=()
for dep in "${want[@]}"; do
    if satisfied "$dep"; then
        echo "==> $dep already present"
        continue
    fi
    mapped=$(map_pkg "$dep")
    if [ -z "$mapped" ]; then
        echo "install-deps: no package mapping for '$dep' on family '$family'" >&2
        exit 1
    fi
    for p in $mapped; do
        packages+=("$p")
    done
done

if [ "${#packages[@]}" -eq 0 ]; then
    echo "==> all dependencies already satisfied"
    exit 0
fi

mapfile -t packages < <(printf '%s\n' "${packages[@]}" | sort -u)

echo "==> installing via $pm ($family): ${packages[*]}"
case "$pm" in
    apt)    apt-get update
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}" ;;
    dnf)    dnf install -y "${packages[@]}" ;;
    yum)    yum install -y "${packages[@]}" ;;
    pacman) pacman -Sy --noconfirm "${packages[@]}" ;;
    zypper) zypper --non-interactive install "${packages[@]}" ;;
esac
