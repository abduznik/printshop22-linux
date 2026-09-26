#!/usr/bin/env bash
# Install The Print Shop 22 on Linux from the original CD images (.bin/.cue).
#
# Usage:  ./install-printshop22.sh [folder-with-bin-cue-files]
#         (default folder: the folder this script is in)
#
# Needs:  Steam with "Proton Experimental" installed (its Wine keeps classic 32-bit support),
#         python3, 7z (p7zip), internet access (winetricks downloads .NET 2.0 SP2 from Microsoft).
#
# Environment overrides:
#   PS22_PREFIX     - where to install            (default: ~/.wine-printshop22)
#   PS22_PROTON     - Proton "files" dir to use   (default: auto-detect)
#   PS22_WORK       - temporary work dir          (default: ~/.cache/printshop22-install)
#   PS22_KEEP_WORK=1  keep the work dir (extracted discs) afterwards
#   PS22_NO_MENU=1    don't create the application-menu entry
#
# Why the odd steps: the InstallShield installer does not work under Wine, so the MSI is
# unpacked and applied manually; .NET 1.1 is installed only to satisfy the app's startup
# check, and the app is pointed at .NET 2.0 (1.1 itself crashes under Wine).

set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SRC="$(readlink -f "${1:-$HERE}")"
PREFIX="${PS22_PREFIX:-$HOME/.wine-printshop22}"
WORK="${PS22_WORK:-$HOME/.cache/printshop22-install}"
LOG="$WORK/install.log"
APPREL="Program Files (x86)/The Print Shop 22"

mkdir -p "$WORK"
: >"$LOG"
step() { printf '\n==> %s\n' "$*"; printf '\n==> %s\n' "$*" >>"$LOG"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\nERROR: %s\n(see log: %s)\n' "$*" "$LOG" >&2; exit 1; }

# ---------------------------------------------------------------- helpers
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
    for d in "${cands[@]}"; do case "$d" in *"Proton - Experimental/files") echo "$d"; return 0;; esac; done
    printf '%s\n' "${cands[@]}" | sort -V | tail -1
}

w()       { wine "$@" >>"$LOG" 2>&1; }           # run a Windows program in the prefix
winpath() { printf 'Z:%s' "$1" | tr '/' '\\'; }   # unix path -> Windows path (Z: = /)

find_image() {  # $1 = disc id (PSSTD22INST / PSSTD22PROG)
    find -L "$SRC" -maxdepth 2 -type f \( -iname "$1*.bin" -o -iname "$1*.iso" \) | head -1
}

# ---------------------------------------------------------------- checks
step "Checking requirements"
need_deps=0
for c in python3 cabextract curl steam; do command -v "$c" >/dev/null || need_deps=1; done
command -v 7z >/dev/null || command -v 7za >/dev/null || need_deps=1
if [ "$need_deps" = 1 ]; then
    info "Some packages are missing - installing them (you may be asked for your password)"
    [ -f "$HERE/install-deps.sh" ] || die "install-deps.sh must be next to this script"
    bash "$HERE/install-deps.sh" || die "Installing dependencies failed"
fi
command -v python3 >/dev/null || die "python3 is required."
command -v cabextract >/dev/null || die "cabextract is required."
SEVENZ="$(command -v 7z || command -v 7za || true)"
[ -n "$SEVENZ" ] || die "7z is required (package 7zip / p7zip-full)."

INST_IMG="$(find_image PSSTD22INST)"; PROG_IMG="$(find_image PSSTD22PROG)"
[ -n "$INST_IMG" ] || die "PSSTD22INST .bin not found in $SRC"
[ -n "$PROG_IMG" ] || die "PSSTD22PROG .bin not found in $SRC"
info "Install disc: $INST_IMG"
info "Program disc: $PROG_IMG"

PROTON="${PS22_PROTON:-}"
if [ -z "$PROTON" ] && ! PROTON="$(find_proton)"; then
    command -v steam >/dev/null || die "Steam is not installed. Install Steam, then run this script again."
    info "Proton Experimental is not installed - asking Steam to install it."
    info "If Steam asks you to log in or confirm the install, please do so. Waiting (up to 60 min)..."
    setsid steam steam://install/1493710 >/dev/null 2>&1 </dev/null &
    for _ in $(seq 1 720); do
        sleep 5
        PROTON="$(find_proton)" && break
    done
    [ -n "$PROTON" ] || die "Proton Experimental did not appear. Install it in Steam (Library -> Tools) and run this script again."
    sleep 10   # let Steam finish writing the files
fi
[ -x "$PROTON/bin/wine" ] || die "No wine in $PROTON/bin"
info "Using Wine from: $PROTON"

WINETRICKS="$(command -v winetricks || true)"
if [ -z "$WINETRICKS" ]; then
    info "winetricks not installed - downloading it into the work dir"
    WINETRICKS="$WORK/winetricks"
    if command -v curl >/dev/null; then curl -fsSL -o "$WINETRICKS" https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
    else wget -qO "$WINETRICKS" https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks; fi
    chmod +x "$WINETRICKS"
fi

FREE_KB=$(df -Pk "$(dirname "$PREFIX")" | awk 'NR==2{print $4}')
[ "$FREE_KB" -gt $((6*1024*1024)) ] || die "Need about 6 GB free disk space."

if [ -e "$PREFIX" ]; then
    printf '\n%s already exists. Delete it and reinstall? [y/N] ' "$PREFIX"
    read -r ans
    [[ "$ans" =~ ^[Yy] ]] || die "Aborted - choose another location with PS22_PREFIX=..."
    WINEPREFIX="$PREFIX" "$PROTON/bin/wineserver" -k 2>/dev/null || true
    rm -rf "$PREFIX"
fi

export WINEPREFIX="$PREFIX" WINEDEBUG=-all
export PATH="$PROTON/bin:$PATH" WINE="$PROTON/bin/wine" WINESERVER="$PROTON/bin/wineserver"

# ---------------------------------------------------------------- discs
step "Extracting the CD images (this takes a minute)"
python3 - "$INST_IMG" "$PROG_IMG" "$WORK" <<'PYEOF'
import os, sys
# Raw MODE1/2352 .bin -> plain 2048-byte-sector .iso (plain .iso/.bin copies are detected)
for img in sys.argv[1:3]:
    name = "INST" if "INST" in os.path.basename(img).upper() else "PROG"
    dst = os.path.join(sys.argv[3], name + ".iso")
    if os.path.exists(dst): continue
    size = os.path.getsize(img)
    with open(img, "rb") as f:
        f.seek(0); head = f.read(16)
    raw = head[:12] == b"\x00" + b"\xff" * 10 + b"\x00" and size % 2352 == 0
    with open(img, "rb") as f, open(dst + ".part", "wb") as o:
        if raw:
            while True:
                s = f.read(2352)
                if len(s) < 2352: break
                o.write(s[16:2064])
        else:
            while True:
                b = f.read(1 << 20)
                if not b: break
                o.write(b)
    os.rename(dst + ".part", dst)
PYEOF
for d in INST PROG; do
    if [ ! -d "$WORK/$d" ]; then
        "$SEVENZ" x -y -o"$WORK/$d.tmp" "$WORK/$d.iso" >>"$LOG" 2>&1 || die "Could not extract $d disc image."
        mv "$WORK/$d.tmp" "$WORK/$d"
    fi
done
MSI="$WORK/INST/Setup/The Print Shop 22.msi"
[ -f "$MSI" ] || die "Install disc does not look right (Setup/The Print Shop 22.msi missing)."

# ---------------------------------------------------------------- prefix + .NET
step "Creating 32-bit Wine prefix at $PREFIX"
WINEARCH=win32 w wineboot -i || die "wineboot failed"
"$WINESERVER" -w

step "Installing .NET Framework 2.0 SP2 (downloaded by winetricks)"
"$WINETRICKS" -q dotnet20sp2 >>"$LOG" 2>&1 || die "winetricks dotnet20sp2 failed"
[ -f "$PREFIX/drive_c/windows/Microsoft.NET/Framework/v2.0.50727/mscorwks.dll" ] || die ".NET 2.0 did not install"

step "Installing .NET Framework 1.1 (from the install disc)"
mkdir -p "$WORK/netfx11"
"$SEVENZ" x -y -o"$WORK/netfx11" "$WORK/INST/Setup/1033dotnetfx.exe" >>"$LOG" 2>&1 || die "Could not unpack 1033dotnetfx.exe"
# .NET 1.1's final ngen step hangs under Wine; it is optional, so kill it if it appears.
( while sleep 5; do
      if pgrep -f '[n]gen\.exe' >/dev/null; then sleep 30; pkill -f '[n]gen\.exe' || true; fi
  done ) &
WATCHDOG=$!
( cd "$WORK/netfx11" && WINEDLLOVERRIDES="regsvcs.exe=b" timeout 1200 wine msiexec /i netfx.msi /qn >>"$LOG" 2>&1 ) || true
kill "$WATCHDOG" 2>/dev/null || true
"$WINESERVER" -w
[ -f "$PREFIX/drive_c/windows/Microsoft.NET/Framework/v1.1.4322/mscorwks.dll" ] || die ".NET 1.1 did not install"

# ---------------------------------------------------------------- application files
step "Reading the Print Shop installer database"
mkdir -p "$WORK/tables"
w 'C:\windows\system32\msidb.exe' -d "$(winpath "$MSI")" -f "$(winpath "$WORK/tables")" -e '*'
[ -f "$WORK/tables/File.idt" ] || die "Could not read the MSI tables"

step "Copying program files, registry settings and fonts"
cat >"$WORK/deploy.py" <<'PYEOF'
import os, re, sys, shutil, subprocess, collections, getpass
WORK, PREFIX, SEVENZ = sys.argv[1], sys.argv[2], sys.argv[3]
T = os.path.join(WORK, "tables"); DRIVE_C = os.path.join(PREFIX, "drive_c")
DISC = {"PSSTD22INST": os.path.join(WORK, "INST"), "PSSTD22PROG": os.path.join(WORK, "PROG")}
STAGE = os.path.join(WORK, "cabs"); USER = os.environ.get("USER") or getpass.getuser()

def idt(name):
    lines = open(os.path.join(T, name + ".idt"), "rb").read().decode("cp1252", "replace").replace("\r\n", "\n").split("\n")
    cols = lines[0].split("\t"); rows = []
    for ln in lines[3:]:
        if ln:
            v = ln.split("\t"); v += [""] * (len(cols) - len(v)); rows.append(dict(zip(cols, v)))
    return rows
longname = lambda s: s.split("|")[-1]

SYSDIRS = {"ProgramFilesFolder": "Program Files (x86)", "CommonFilesFolder": "Program Files (x86)/Common Files",
    "CommonAppDataFolder": "ProgramData", "SystemFolder": "windows/system32", "System16Folder": "windows/system",
    "WindowsFolder": "windows", "FontsFolder": "windows/Fonts", "TempFolder": "windows/temp",
    "AppDataFolder": f"users/{USER}/AppData/Roaming", "LocalAppDataFolder": f"users/{USER}/AppData/Local",
    "PersonalFolder": f"users/{USER}/Documents", "MyPicturesFolder": f"users/{USER}/Pictures",
    "DesktopFolder": f"users/{USER}/Desktop", "WindowsVolume": "",
    "ProgramMenuFolder": f"users/{USER}/AppData/Roaming/Microsoft/Windows/Start Menu/Programs",
    "StartMenuFolder": f"users/{USER}/AppData/Roaming/Microsoft/Windows/Start Menu"}
dirs = {r["Directory"]: r for r in idt("Directory")}
_t, _s = {}, {}
def tpath(d):
    if d not in _t:
        if d in SYSDIRS: p = SYSDIRS[d]
        elif d == "TARGETDIR": p = ""
        else:
            r = dirs[d]; name = longname(r["DefaultDir"].split(":")[0])
            par = tpath(r["Directory_Parent"]) if r["Directory_Parent"] else ""
            p = par if name == "." else (os.path.join(par, name) if par else name)
        _t[d] = p
    return _t[d]
def spath(d):
    if d not in _s:
        if d == "TARGETDIR": p = ""
        else:
            r = dirs[d]; parts = r["DefaultDir"].split(":"); name = longname(parts[-1])
            par = spath(r["Directory_Parent"]) if r["Directory_Parent"] else ""
            p = par if name == "." else (os.path.join(par, name) if par else name)
        _s[d] = p
    return _s[d]
def fdir(comp):  # target dir of a component; merge-module runtimes (TARGETDIR) go app-local
    return tpath(comps[comp]["Directory_"]) or tpath("INSTALLDIR")

comps = {r["Component"]: r for r in idt("Component")}
media = sorted(idt("Media"), key=lambda r: int(r["LastSequence"]))
files = idt("File")
# Old Windows system DLLs from the MSI would break Wine's own versions
SKIP_SYS = {"oleaut32.dll", "olepro32.dll", "comcat.dll", "asycfilt.dll", "stdole2.tlb",
            "twain.dll", "twain_32.dll", "twunk_16.exe", "twunk_32.exe"}

# 1. files
os.makedirs(STAGE, exist_ok=True)
for m in media:
    if m["Cabinet"] and not os.path.isdir(os.path.join(STAGE, m["Cabinet"])):
        subprocess.run([SEVENZ, "x", "-y", "-o" + os.path.join(STAGE, m["Cabinet"]),
                        os.path.join(DISC["PSSTD22INST"], "Setup", m["Cabinet"])], check=True, stdout=subprocess.DEVNULL)
stats = collections.Counter(); missing = []
for f in files:
    d = comps[f["Component_"]]["Directory_"]; tdir = fdir(f["Component_"]); name = longname(f["FileName"])
    if tdir.startswith("windows") and not tdir.startswith("windows/Fonts") and name.lower() in SKIP_SYS:
        stats["skipped"] += 1; continue
    m = next(x for x in media if int(f["Sequence"]) <= int(x["LastSequence"]))
    src = (os.path.join(STAGE, m["Cabinet"], f["File"]) if m["Cabinet"]
           else os.path.join(DISC.get(m["VolumeLabel"], DISC["PSSTD22INST"]), "Setup", spath(d), name))
    if not os.path.exists(src): missing.append(src); continue
    dst = os.path.join(DRIVE_C, tdir, name)
    os.makedirs(os.path.dirname(dst), exist_ok=True); shutil.copy2(src, dst); stats["files"] += 1
if missing:
    print("missing files:", *missing[:10], sep="\n  "); sys.exit(2)

# 2. registry (.reg for regedit)
winp = lambda rel: "C:\\" + rel.replace("/", "\\")
props = {r["Property"]: r["Value"] for r in idt("Property")}
fileinfo = {f["File"]: winp(fdir(f["Component_"]) + "/" + longname(f["FileName"])) for f in files}
def fmt(s):
    def rep(m):
        k = m.group(1)
        if k[0] in "#!": return fileinfo.get(k[1:], "")
        if k[0] == "$": return winp(fdir(k[1:])) + "\\"
        if k == "~": return ""
        if k in dirs or k in SYSDIRS: return winp(tpath(k)) + "\\"
        return props.get(k, "")
    for _ in range(3): s = re.sub(r"\[([^\[\]]+)\]", rep, s)
    return s
SKIPC = ("Global_System_OLEAUT32", "Global_System_STDOLE", "Global_Controls_COMCATDLL", "Global_Controls_MSCOMCTLOCX")
ROOT = {"0": "HKEY_CLASSES_ROOT", "1": "HKEY_CURRENT_USER", "2": "HKEY_LOCAL_MACHINE", "3": "HKEY_USERS", "-1": "HKEY_LOCAL_MACHINE"}
esc = lambda s: s.replace("\\", "\\\\").replace('"', '\\"')
keys = collections.OrderedDict()
for r in idt("Registry"):
    if r["Component_"].startswith(SKIPC): continue
    key = ROOT[r["Root"]] + "\\" + fmt(r["Key"]); name, val = r["Name"], r["Value"]
    if name in ("+", "-", "*") and not val: keys.setdefault(key, []); continue
    if name.startswith("-"): continue
    nm = "@" if fmt(name) in ("", "*", "+") else '"%s"' % esc(fmt(name))
    if val.startswith("#x"): v = "hex:" + ",".join(val[i:i+2] for i in range(2, len(val), 2))
    elif val.startswith(("#%", "##")): v = '"%s"' % esc(fmt(val[2:] if val[1] == "%" else val[1:]))
    elif val.startswith("#"): v = "dword:%08x" % (int(val[1:]) & 0xffffffff)
    else: v = '"%s"' % esc(fmt(val))
    keys.setdefault(key, []).append(f"{nm}={v}")
with open(os.path.join(WORK, "printshop22.reg"), "w", encoding="cp1252", errors="replace") as o:
    o.write("REGEDIT4\r\n\r\n")
    for k, vals in keys.items(): o.write("[%s]\r\n%s\r\n" % (k, "".join(x + "\r\n" for x in vals)))

# 3. fonts (Wine picks up anything in C:\windows\Fonts)
fmap = {f["File"]: f for f in files}
for r in idt("Font"):
    f = fmap[r["File_"]]; src = os.path.join(DRIVE_C, fdir(f["Component_"]), longname(f["FileName"]))
    dst = os.path.join(DRIVE_C, "windows/Fonts", longname(f["FileName"]))
    if os.path.exists(src) and not os.path.lexists(dst): os.symlink(src, dst); stats["fonts"] += 1

# 4. COM servers to self-register
want = {"mscomctl.ocx", "connmgr.dll", "pmappbuilder.dll", "cdintf.dll", "pmovieserver.dll", "pretzelspellcheck.dll"}
with open(os.path.join(WORK, "selfreg.txt"), "w") as o:
    for f in files:
        if longname(f["FileName"]).lower() in want:
            o.write(os.path.join(DRIVE_C, fdir(f["Component_"]), longname(f["FileName"])) + "\n")
print(dict(stats))
PYEOF
python3 "$WORK/deploy.py" "$WORK" "$PREFIX" "$SEVENZ" | tee -a "$LOG" || die "Copying program files failed"

w 'C:\windows\regedit.exe' /S "$(winpath "$WORK/printshop22.reg")" || die "Registry import failed"
while IFS= read -r dll; do
    [ -f "$dll" ] || continue
    if w 'C:\windows\system32\regsvr32.exe' /s "$(winpath "$dll")"; then info "registered $(basename "$dll")"
    else info "could not register $(basename "$dll") (not needed to start)"; fi
done <"$WORK/selfreg.txt"

step "Applying Wine fixes"
APPDIR="$PREFIX/drive_c/$APPREL"
[ -f "$APPDIR/PMW.exe" ] || die "PMW.exe is missing after copying"
# Run on .NET 2.0 (1.1 crashes under Wine)
cat >"$APPDIR/PMW.exe.config" <<'EOF'
<?xml version="1.0"?>
<configuration>
  <startup>
    <supportedRuntime version="v2.0.50727"/>
    <supportedRuntime version="v1.1.4322"/>
  </startup>
</configuration>
EOF
# Wine's HTML Help control crashes the app when it opens pmw.chm at startup
[ -f "$APPDIR/pmw.chm" ] && mv "$APPDIR/pmw.chm" "$APPDIR/pmw.chm.disabled"
echo "$PROTON" >"$PREFIX/.ps22-proton"
"$WINESERVER" -w

# ---------------------------------------------------------------- launcher + menu
step "Creating launcher"
LAUNCHER="$HERE/run-printshop22.sh"
[ -f "$LAUNCHER" ] || die "run-printshop22.sh must be next to this script"
chmod +x "$LAUNCHER"
cp "$LAUNCHER" "$PREFIX/run-printshop22.sh"; chmod +x "$PREFIX/run-printshop22.sh"
if [ "${PS22_NO_MENU:-0}" != 1 ]; then
    ICON="$APPDIR/PMW.ico"
    mkdir -p "$HOME/.local/share/applications"
    cat >"$HOME/.local/share/applications/printshop22.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=The Print Shop 22
Comment=Broderbund The Print Shop 22 (Wine)
Exec=env PS22_PREFIX="$PREFIX" "$PREFIX/run-printshop22.sh"
Icon=$ICON
Categories=Graphics;Office;
StartupWMClass=pmw.exe
EOF
    command -v update-desktop-database >/dev/null && update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
    info "Added 'The Print Shop 22' to the application menu"
fi

if [ "${PS22_KEEP_WORK:-0}" != 1 ]; then
    cp "$LOG" "$PREFIX/install.log"
    rm -rf "$WORK"
    LOG="$PREFIX/install.log"
fi

step "Done!"
info "Start it from the application menu, or run:"
info "  PS22_PREFIX=\"$PREFIX\" \"$LAUNCHER\""
info "(the prefix also has its own copy: $PREFIX/run-printshop22.sh)"
info "Note: the built-in Help (F1) is disabled because it crashes under Wine."
