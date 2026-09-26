#!/usr/bin/env bash
# Launch The Print Shop 22 (installed by install-printshop22.sh).
#
# Environment overrides:
#   PS22_PREFIX  - Wine prefix of the installation   (default: ~/.wine-printshop22)
#   PS22_PROTON  - Proton "files" dir to use          (default: auto-detect, prefers Proton - Experimental)

PREFIX="${PS22_PREFIX:-$HOME/.wine-printshop22}"
APPDIR="$PREFIX/drive_c/Program Files (x86)/The Print Shop 22"

die() {
    echo "run-printshop22: $*" >&2
    command -v notify-send >/dev/null && notify-send "The Print Shop 22" "$*"
    exit 1
}

# Locate a Proton build whose Wine still has classic 32-bit support (lib/wine/i386-unix).
find_proton() {
    local r l d libs=() cands=()
    for r in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root" \
             "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
        [ -d "$r" ] || continue
        r="$(readlink -f "$r")"; libs+=("$r")
        [ -f "$r/steamapps/libraryfolders.vdf" ] && while IFS= read -r l; do libs+=("$l"); done < <(
            sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$r/steamapps/libraryfolders.vdf")
    done
    while IFS= read -r l; do
        [ -n "$l" ] || continue
        for d in "$l/steamapps/common/Proton - Experimental" "$l"/steamapps/common/Proton* "$l"/compatibilitytools.d/*; do
            [ -x "$d/files/bin/wine" ] && [ -d "$d/files/lib/wine/i386-unix" ] && cands+=("$d/files")
        done
    done < <(printf '%s\n' "${libs[@]}" | sort -u)
    [ ${#cands[@]} -eq 0 ] && return 1
    # Prefer Proton - Experimental, otherwise the highest version.
    for d in "${cands[@]}"; do case "$d" in *"Proton - Experimental/files") echo "$d"; return 0;; esac; done
    printf '%s\n' "${cands[@]}" | sort -V | tail -1
}

[ -f "$APPDIR/PMW.exe" ] || die "Print Shop is not installed in $PREFIX. Run install-printshop22.sh first."

PROTON="${PS22_PROTON:-}"
[ -z "$PROTON" ] && [ -f "$PREFIX/.ps22-proton" ] && PROTON="$(cat "$PREFIX/.ps22-proton")"
if [ -z "$PROTON" ] || [ ! -x "$PROTON/bin/wine" ]; then
    PROTON="$(find_proton)" || die "Could not find Steam's Proton (install Steam and 'Proton Experimental')."
fi

export WINEPREFIX="$PREFIX"
export PATH="$PROTON/bin:$PATH"
export WINEDEBUG="${WINEDEBUG:--all}"
cd "$APPDIR" || die "Cannot enter $APPDIR"
exec wine PMW.exe "$@" >"$PREFIX/printshop22.log" 2>&1
