# The Print Shop 22 on Linux

Scripts that install and run **Broderbund The Print Shop 22** on Linux from your own original CD images (`.bin`/`.cue`), using the Wine that ships with Steam's **Proton Experimental**.

> You need your own copy of The Print Shop 22. This repository contains only scripts, no program files.

## Quick start

1. Put your 4 disc image files in this folder (next to the scripts):

   ```
   PSSTD22INST.bin  PSSTD22INST.cue
   PSSTD22PROG.bin  PSSTD22PROG.cue
   ```

2. Run the installer:

   ```bash
   ./install-printshop22.sh
   ```

   Everything else is automatic:
   - Missing packages are installed for you (you'll be asked for your password once).
   - If Proton Experimental isn't installed, Steam is asked to install it. Log in to Steam and confirm if it asks.
   - The whole install takes about 5–10 minutes. Wine windows may flash by; leave them alone.

3. Start **The Print Shop 22** from your application menu, or run:

   ```bash
   ./run-printshop22.sh
   ```

## Requirements

| | |
|---|---|
| **Distro** | Nobara / Fedora, or Debian / Ubuntu / Linux Mint / Pop!_OS |
| **Disk** | about 6 GB free |
| **Internet** | yes, during install (.NET 2.0 SP2 is downloaded from Microsoft by winetricks) |
| **Steam** | installed automatically if your repos have it (see below) |

### Dependencies

`install-printshop22.sh` runs `install-deps.sh` automatically when something is missing. You can also run it yourself:

```bash
./install-deps.sh
```

It installs `python3`, `7zip`, `cabextract`, `curl`, `winetricks` and `steam`:

| Distro | What it runs |
|---|---|
| Nobara / Fedora | `sudo dnf install python3 cabextract curl winetricks 7zip steam` |
| Debian / Ubuntu | enables i386, then `sudo apt-get install python3 cabextract curl 7zip winetricks steam-installer` |

Notes:
- **Fedora:** Steam comes from [RPM Fusion nonfree](https://rpmfusion.org/Configuration). Nobara already has it.
- **Debian:** `winetricks` and `steam-installer` are in `contrib`/`non-free`. **Ubuntu:** Steam is in `multiverse`. If winetricks can't be installed, the installer downloads it by itself.
- **winetricks is required.** It installs .NET 2.0, and needs `cabextract` to do so.

## Scripts

| Script | Purpose |
|---|---|
| `install-printshop22.sh [disc-folder]` | Full install from the disc images (default folder: the script's folder) |
| `run-printshop22.sh` | Starts the program (finds Proton automatically) |
| `install-deps.sh` | Installs required packages (Nobara/Fedora/Debian/Ubuntu) |

### Options (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `PS22_PREFIX` | `~/.wine-printshop22` | Install location (use the same value for both scripts) |
| `PS22_PROTON` | auto-detect | Path to a Proton `files` directory |
| `PS22_WORK` | `~/.cache/printshop22-install` | Temporary work folder |
| `PS22_KEEP_WORK=1` | off | Keep the extracted discs after installing |
| `PS22_NO_MENU=1` | off | Don't add an application-menu entry |

Example: `PS22_PREFIX=~/Games/printshop ./install-printshop22.sh ~/Downloads/discs`

## How it works (and why)

The normal Windows setup doesn't work under Wine, so the installer does the same work itself:

1. Converts the raw `.bin` images to ISO and extracts them.
2. Creates a **32-bit** Wine prefix with Proton's Wine. Newer system Wine builds (WoW64-only, e.g. Wine 11 on Nobara) can't run this program: the old .NET 2.0 fails to create AppDomains there with `OutOfMemoryException`.
3. Installs **.NET 2.0 SP2** (winetricks) and **.NET 1.1** (from the install disc). The program checks for 1.1, but 1.1 itself crashes under Wine, so the program is pointed at 2.0 with `PMW.exe.config`.
4. Reads the tables of the InstallShield MSI and applies them by hand: copies 2,600+ files from the cabinets, imports the registry entries, registers the COM components and installs the fonts. The MSI's own custom actions (`ISStartup`, `HashIt`, …) fail under Wine.
5. Disables the built-in help file (`pmw.chm`). Wine's HTML Help control crashes the program when it opens it at startup.

## Known limitations

- **Help (F1) is disabled.**
- **Spell check** may not work.
- **Not fully tested:** printing and some online features.

## Files and uninstalling

- **Logs:** `~/.wine-printshop22/install.log` and `~/.wine-printshop22/printshop22.log`
- **Uninstall:**

  ```bash
  rm -rf ~/.wine-printshop22 ~/.local/share/applications/printshop22.desktop
  ```
