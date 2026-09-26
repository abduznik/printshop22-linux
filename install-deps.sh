#!/usr/bin/env bash
# Install the packages install-printshop22.sh needs.
# Supports Nobara / Fedora (dnf) and Debian / Ubuntu / Linux Mint / Pop!_OS (apt).
# install-printshop22.sh runs this automatically when something is missing.
#
# Installs: python3, 7-Zip, cabextract, curl, winetricks, Steam.
# (Proton Experimental itself is installed through Steam by install-printshop22.sh.)

set -uo pipefail

info() { printf '    %s\n' "$*"; }
warn() { printf '    WARNING: %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ -r /etc/os-release ] || die "Cannot detect your Linux distribution (/etc/os-release missing)."
. /etc/os-release
DISTRO=" ${ID:-} ${ID_LIKE:-} "
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

have() { command -v "$1" >/dev/null 2>&1; }

if have python3 && have cabextract && have curl && have winetricks && have steam && { have 7z || have 7za; }; then
    echo "==> All dependencies are already installed."
    exit 0
fi

case "$DISTRO" in
*" fedora "*|*" nobara "*|*" rhel "*)
    echo "==> Installing dependencies with dnf (${PRETTY_NAME:-Fedora-based})"
    $SUDO dnf install -y python3 cabextract curl winetricks || die "dnf install failed"
    have 7z || have 7za || $SUDO dnf install -y 7zip || $SUDO dnf install -y p7zip p7zip-plugins \
        || die "Could not install 7-Zip"
    if ! have steam; then
        $SUDO dnf install -y steam || warn "Steam is not in your repos. On Fedora enable RPM Fusion nonfree first:
      https://rpmfusion.org/Configuration  (then: sudo dnf install steam)"
    fi
    ;;
*" debian "*|*" ubuntu "*)
    echo "==> Installing dependencies with apt (${PRETTY_NAME:-Debian-based})"
    # Steam needs 32-bit libraries
    if ! dpkg --print-foreign-architectures | grep -qx i386; then
        $SUDO dpkg --add-architecture i386 || die "Could not enable i386 architecture"
    fi
    $SUDO apt-get update || die "apt-get update failed"
    $SUDO apt-get install -y python3 cabextract curl || die "apt-get install failed"
    have 7z || have 7za || $SUDO apt-get install -y 7zip || $SUDO apt-get install -y p7zip-full \
        || die "Could not install 7-Zip"
    # winetricks lives in Debian 'contrib'; if unavailable the installer downloads it itself.
    have winetricks || $SUDO apt-get install -y winetricks \
        || warn "winetricks package not available - install-printshop22.sh will download it."
    if ! have steam; then
        $SUDO apt-get install -y steam-installer || $SUDO apt-get install -y steam \
            || warn "Could not install Steam from your repos. On Debian enable 'contrib non-free',
      on Ubuntu enable 'multiverse', or get it from https://store.steampowered.com/about/"
    fi
    ;;
*)
    die "Unsupported distribution '${ID:-unknown}'. Install manually: python3, 7-Zip (7z), cabextract, curl, winetricks, Steam."
    ;;
esac

echo "==> Dependency check"
for c in python3 cabextract curl; do have "$c" && info "ok: $c" || warn "missing: $c"; done
{ have 7z || have 7za; } && info "ok: 7z" || warn "missing: 7z"
have winetricks && info "ok: winetricks" || info "winetricks: will be downloaded by the installer"
have steam && info "ok: steam" || warn "missing: steam (needed for Proton)"
