#!/bin/bash
#
# helium-widevine-macos.sh
#
# Makes DRM video (Spotify, Prime Video, etc.) play in the Helium
# browser on macOS by copying Google's Widevine module from Chrome, Brave or
# Edge into Helium.
#
# See usage() below or run with --help.
#
# Written for the bash 3.2 that ships with macOS.

set -euo pipefail

HELIUM_APP="${HELIUM_APP:-/Applications/Helium.app}"
APP_SUPPORT="$HOME/Library/Application Support"
TEST_URL="https://bitmovin.com/demos/drm"

MODE="install"
RESIGN=0
SOURCE_OVERRIDE=""

usage() {
  cat <<'EOF'
Usage: helium-widevine-macos.sh [option]

  (no option)    Copy Widevine into Helium. On most Macs this alone is not
                 enough; see --resign.
  --resign       Copy Widevine into Helium AND re-sign Helium so macOS lets
                 it load Widevine. This is the one that makes video play.
  --check        Show what is installed and what was found. Changes nothing.
  --uninstall    Remove Widevine from Helium.
  --source DIR   Use a specific WidevineCdm folder as the source.
  --help         Show this message.

Environment overrides:
  HELIUM_APP       path to Helium.app   (default: /Applications/Helium.app)
  HELIUM_DATA_DIR  Helium profile dir   (default: auto-detected)
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --resign)    RESIGN=1 ;;
    --check)     MODE="check" ;;
    --uninstall) MODE="uninstall" ;;
    --source)    shift; [ $# -gt 0 ] || { echo "--source needs a path" >&2; exit 1; }; SOURCE_OVERRIDE="$1" ;;
    -h|--help)   usage ;;
    *)           echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
  esac
  shift
done

# --- Output helpers -----------------------------------------------------------
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
step()   { echo; bold "==> $*"; }
die()    { echo; red "Stopped: $*" >&2; exit 1; }

# Prompts read from the keyboard even when the script itself is piped in.
pause() {
  echo
  printf '%s' "${1:-Press Return to continue...}"
  read -r _ </dev/tty
}

# Returns success for yes. Default answer is yes.
ask_yes() {
  local ans
  echo
  printf '%s [Y/n] ' "$1"
  read -r ans </dev/tty
  case "$ans" in
    n|N|no|No|NO) return 1 ;;
    *) return 0 ;;
  esac
}

[ "$(uname -s)" = "Darwin" ] || die "This script is for macOS only."

# --- Helium locations ---------------------------------------------------------
# Helium on macOS stores its profile in "net.imput.helium", not "Helium".
find_data_dir() {
  if [ -n "${HELIUM_DATA_DIR:-}" ]; then
    echo "$HELIUM_DATA_DIR"
    return
  fi
  local d
  for d in "$APP_SUPPORT/net.imput.helium" "$APP_SUPPORT/Helium"; do
    if [ -f "$d/Local State" ]; then
      echo "$d"
      return
    fi
  done
  echo "$APP_SUPPORT/net.imput.helium"
}

DATA_DIR="$(find_data_dir)"
DEST_ROOT="$DATA_DIR/WidevineCdm"

# Helium also checks for Widevine inside its own app bundle, next to its
# framework: Helium Framework.framework/Versions/<version>/Libraries/WidevineCdm
bundle_libraries_dirs() {
  local d
  for d in "$HELIUM_APP/Contents/Frameworks/Helium Framework.framework/Versions/"*; do
    [ -d "$d" ] && [ ! -L "$d" ] && echo "$d/Libraries"
  done
  return 0
}

# --- Architecture -------------------------------------------------------------
# The Widevine folder must contain a file for the chip Helium runs on, or
# Helium treats the folder as broken and deletes it.
detect_platform_dir() {
  local machine helium_bin archs
  machine="$(uname -m)"
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ]; then
    machine="arm64"
  fi
  helium_bin="$HELIUM_APP/Contents/MacOS/Helium"
  if [ "$machine" = "arm64" ] && [ -f "$helium_bin" ]; then
    archs="$(lipo -archs "$helium_bin" 2>/dev/null || true)"
    case " $archs " in
      *" arm64 "*) ;;
      *) machine="x86_64" ;;  # Intel build of Helium running under Rosetta
    esac
  fi
  if [ "$machine" = "arm64" ]; then echo "mac_arm64"; else echo "mac_x64"; fi
}

PLATFORM_DIR="$(detect_platform_dir)"

# --- Widevine helpers ---------------------------------------------------------
manifest_version() {
  local manifest="$1/manifest.json" v=""
  [ -f "$manifest" ] || return 1
  v="$(plutil -extract version raw -o - "$manifest" 2>/dev/null || true)"
  if [ -z "$v" ]; then
    v="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([0-9.]*\)".*/\1/p' "$manifest" | head -n 1)"
  fi
  [ -n "$v" ] || return 1
  echo "$v"
}

is_valid_cdm_dir() {
  [ -d "$1" ] &&
    [ -f "$1/manifest.json" ] &&
    [ -f "$1/_platform_specific/$PLATFORM_DIR/libwidevinecdm.dylib" ] &&
    manifest_version "$1" >/dev/null
}

newest_version_subdir() {
  local base="$1" name
  [ -d "$base" ] || return 1
  name="$(ls -1 "$base" 2>/dev/null |
    grep -E '^[0-9]+(\.[0-9]+){1,3}$' |
    sort -t. -k1,1n -k2,2n -k3,3n -k4,4n |
    tail -n 1)"
  [ -n "$name" ] || return 1
  echo "$base/$name"
}

list_candidates() {
  local base d
  for base in \
    "$APP_SUPPORT/Google/Chrome/WidevineCdm" \
    "$APP_SUPPORT/BraveSoftware/Brave-Browser/WidevineCdm" \
    "$APP_SUPPORT/Microsoft Edge/WidevineCdm" \
    "$APP_SUPPORT/Google/Chrome Beta/WidevineCdm"; do
    newest_version_subdir "$base" || true
  done
  # Chrome also keeps a copy inside its app, without a version folder.
  for d in "/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/"*/Libraries/WidevineCdm; do
    [ -d "$d" ] && echo "$d"
  done
  return 0
}

find_source() {
  local c
  if [ -n "$SOURCE_OVERRIDE" ]; then
    if is_valid_cdm_dir "$SOURCE_OVERRIDE"; then
      echo "$SOURCE_OVERRIDE"; return 0
    fi
    c="$(newest_version_subdir "$SOURCE_OVERRIDE" || true)"
    if [ -n "$c" ] && is_valid_cdm_dir "$c"; then
      echo "$c"; return 0
    fi
    return 1
  fi
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    if is_valid_cdm_dir "$c"; then
      echo "$c"; return 0
    fi
  done <<EOF
$(list_candidates)
EOF
  return 1
}

# --- Helium app control -------------------------------------------------------
helium_running() {
  pgrep -x Helium >/dev/null 2>&1
}

quit_helium() {
  helium_running || return 0
  echo "Closing Helium (your tabs will come back when it reopens)..."
  osascript -e "quit app \"$HELIUM_APP\"" >/dev/null 2>&1 || true
  local i=0
  while helium_running && [ $i -lt 30 ]; do
    sleep 0.5
    i=$((i + 1))
  done
  while helium_running; do
    yellow "Helium is still open. Click on Helium and press Command (⌘) + Q to quit it."
    pause "Then come back here and press Return..."
  done
  green "Helium is closed."
}

# Opens Helium once so it creates its profile folder, then closes it.
ensure_profile() {
  [ -f "$DATA_DIR/Local State" ] && return 0
  echo "Helium hasn't been opened on this Mac yet. Opening it once to set it up..."
  open "$HELIUM_APP"
  local i=0
  while [ ! -d "$DATA_DIR/Default" ] && [ $i -lt 60 ]; do
    sleep 1
    i=$((i + 1))
  done
  sleep 3
  quit_helium
  [ -f "$DATA_DIR/Local State" ] ||
    die "Helium didn't finish setting up. Open Helium yourself, wait for a window, quit it with Command (⌘) + Q, then run this again."
}

is_adhoc_signed() {
  codesign -dv "$HELIUM_APP" 2>&1 | grep -q 'Signature=adhoc'
}

# Runs a command; if it fails for lack of permission, explains and retries
# with sudo.
SUDO_EXPLAINED=0
run_admin() {
  if "$@" 2>/dev/null; then
    return 0
  fi
  if [ $SUDO_EXPLAINED -eq 0 ]; then
    echo
    yellow "macOS needs your permission to change Helium."
    echo "Type the password you use to log in to this Mac, then press Return."
    echo "Nothing will appear on screen while you type. That's normal."
    SUDO_EXPLAINED=1
  fi
  sudo "$@"
}

# --- Modes --------------------------------------------------------------------
do_check() {
  bold "Helium Widevine check"
  echo "Helium app:      $HELIUM_APP $( [ -d "$HELIUM_APP" ] && echo '(found)' || echo '(NOT FOUND)')"
  echo "Helium profile:  $DATA_DIR $( [ -f "$DATA_DIR/Local State" ] && echo '(found)' || echo '(not set up yet)')"
  echo "Chip type:       $PLATFORM_DIR"
  if [ -d "$HELIUM_APP" ]; then
    if is_adhoc_signed; then
      echo "Helium signature: re-signed locally (Widevine can load)"
    else
      echo "Helium signature: original (macOS will block Widevine; run with --resign)"
    fi
  fi
  echo
  bold "Widevine in Helium's profile:"
  local found=0 d
  if [ -d "$DEST_ROOT" ]; then
    for d in "$DEST_ROOT"/*/; do
      [ -d "$d" ] || continue
      d="${d%/}"
      found=1
      if is_valid_cdm_dir "$d"; then
        green "  OK      $d"
      else
        red   "  INVALID $d (Helium will delete this)"
      fi
    done
  fi
  [ $found -eq 1 ] || yellow "  none"
  echo
  bold "Widevine inside Helium.app:"
  found=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -d "$d/WidevineCdm" ]; then
      found=1
      if is_valid_cdm_dir "$d/WidevineCdm"; then
        green "  OK      $d/WidevineCdm"
      else
        red   "  INVALID $d/WidevineCdm"
      fi
    fi
  done <<EOF
$(bundle_libraries_dirs)
EOF
  [ $found -eq 1 ] || yellow "  none"
  echo
  bold "Browsers to copy Widevine from:"
  found=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    found=1
    if is_valid_cdm_dir "$d"; then
      green "  OK      $d (version $(manifest_version "$d"))"
    else
      yellow "  SKIP    $d (not usable on this Mac)"
    fi
  done <<EOF
$(list_candidates)
EOF
  [ $found -eq 1 ] || yellow "  none found. Install Google Chrome, then run this again."
}

do_uninstall() {
  quit_helium
  rm -rf "$DEST_ROOT"
  local d
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -d "$d/WidevineCdm" ]; then
      run_admin rm -rf "$d/WidevineCdm"
    fi
  done <<EOF
$(bundle_libraries_dirs)
EOF
  green "Widevine removed from Helium."
  if [ -d "$HELIUM_APP" ] && is_adhoc_signed; then
    echo
    echo "Helium is still re-signed. To put back the original signature,"
    echo "download Helium again from https://helium.computer and replace the app."
  fi
}

explain_resign() {
  cat <<'EOF'

About re-signing Helium
-----------------------
macOS only lets Helium load add-ons signed by Helium's own developer.
Widevine is signed by Google, so macOS blocks it. Re-signing Helium on
this Mac removes that block. Here's what that changes:

  * The first time Helium opens afterwards, macOS will ask to let Helium
    use your Keychain. Type your Mac password and click "Always Allow"
    so your saved passwords keep working.
  * Passkeys stored in your Mac's keychain may stop working in Helium.
  * When Helium updates itself, the fix is undone. Just run this same
    command again after an update.
  * Helium loses some of macOS's protection against other programs
    tampering with it. This only matters if something harmful is
    already on your Mac.

To undo it any time: download Helium again from https://helium.computer
and replace the app.
EOF
}

do_install() {
  local total=4
  [ $RESIGN -eq 1 ] && total=5

  bold "Helium Widevine setup"
  echo "This will set up Helium to play protected video (Spotify, Prime Video, etc.)."
  echo "Note: Netflix will still refuse to play in Helium. Use Safari for Netflix."
  echo "Helium will close and reopen during this. Your tabs will come back."
  if [ $RESIGN -eq 1 ]; then
    explain_resign
    ask_yes "Continue?" || die "Cancelled. Nothing was changed."
  else
    pause
  fi

  # 1. Helium is installed and has been opened once.
  step "Step 1 of $total: Checking Helium"
  if [ ! -d "$HELIUM_APP" ]; then
    red "Helium isn't in your Applications folder."
    echo "Opening the Helium download page. Install Helium, drag it into"
    echo "Applications, open it once, then run this command again."
    open "https://helium.computer" || true
    exit 1
  fi
  ensure_profile
  green "Helium found."

  # 2. A browser with Widevine.
  step "Step 2 of $total: Finding Widevine in Chrome, Brave or Edge"
  local src=""
  while ! src="$(find_source)"; do
    yellow "No browser with Widevine was found."
    echo "Opening the Google Chrome download page. Download Chrome, open the"
    echo "downloaded file, and drag Chrome into Applications."
    open "https://www.google.com/chrome/" || true
    pause "When Chrome is in your Applications folder, press Return..."
  done
  local version
  version="$(manifest_version "$src")"
  green "Found Widevine $version."

  # 3. Close Helium.
  step "Step 3 of $total: Closing Helium"
  quit_helium

  # 4. Copy.
  step "Step 4 of $total: Copying Widevine into Helium"
  local staging
  staging="$(mktemp -d "${TMPDIR:-/tmp}/helium-widevine.XXXXXX")"
  ditto "$src" "$staging/$version"
  xattr -dr com.apple.quarantine "$staging" 2>/dev/null || true

  # Into the profile folder: survives Helium updates.
  mkdir -p "$DEST_ROOT"
  rm -rf "$DEST_ROOT"/*
  ditto "$staging/$version" "$DEST_ROOT/$version"
  is_valid_cdm_dir "$DEST_ROOT/$version" || die "The copy didn't come out right: $DEST_ROOT/$version"

  # Into the app itself: only when re-signing, because changing the app
  # breaks its original signature anyway.
  if [ $RESIGN -eq 1 ]; then
    local libs
    while IFS= read -r libs; do
      [ -n "$libs" ] || continue
      run_admin rm -rf "$libs/WidevineCdm"
      run_admin mkdir -p "$libs"
      run_admin ditto "$staging/$version" "$libs/WidevineCdm"
    done <<EOF
$(bundle_libraries_dirs)
EOF
  fi
  rm -rf "$staging"
  green "Copied."

  # 5. Re-sign.
  if [ $RESIGN -eq 1 ]; then
    step "Step 5 of $total: Re-signing Helium so macOS allows Widevine"
    echo "This can take up to a minute."
    run_admin xattr -cr "$HELIUM_APP"
    run_admin codesign --force --deep --sign - "$HELIUM_APP"
    is_adhoc_signed || die "Re-signing didn't take. Run this command again; if it fails twice, reinstall Helium and try once more."
    green "Re-signed."
  fi

  echo
  green "All done!"
  echo
  if [ $RESIGN -eq 1 ]; then
    bold "What happens next:"
    echo "  1. Helium will open to a test video page."
    echo "  2. If macOS asks to let Helium use your Keychain, type your Mac"
    echo "     password and click \"Always Allow\"."
    echo "  3. On the test page, you should see a video start playing."
    echo
    echo "After Helium updates itself, run this same command again."
  else
    yellow "Heads-up: on most Macs, video still won't play until Helium is re-signed."
    echo "If the test page shows an error, run this script again with --resign."
  fi
  pause "Press Return to open Helium..."
  open -a "$HELIUM_APP" "$TEST_URL" || open "$HELIUM_APP"
}

case "$MODE" in
  check)     do_check ;;
  uninstall) do_uninstall ;;
  install)   do_install ;;
esac
