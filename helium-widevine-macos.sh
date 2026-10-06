#!/bin/bash
#
# helium-widevine-macos.sh
#
# Copies a Widevine CDM from a browser that already has one (Chrome, Brave,
# Edge) into Helium's component directory on macOS, in the exact layout
# Chromium's component installer expects:
#
#   ~/Library/Application Support/net.imput.helium/WidevineCdm/<version>/
#       manifest.json
#       LICENSE
#       _platform_specific/mac_arm64/libwidevinecdm.dylib   (or mac_x64)
#
# Helium.app itself is never modified or re-signed.
#
# Usage:
#   ./helium-widevine-macos.sh              install
#   ./helium-widevine-macos.sh --check      show what is installed / found, change nothing
#   ./helium-widevine-macos.sh --uninstall  remove Widevine from Helium
#   ./helium-widevine-macos.sh --source DIR use a specific WidevineCdm folder
#
# Environment overrides:
#   HELIUM_APP       path to Helium.app        (default: /Applications/Helium.app)
#   HELIUM_DATA_DIR  Helium user data dir      (default: auto-detected)
#
# Written for the bash 3.2 that ships with macOS.

set -euo pipefail

HELIUM_APP="${HELIUM_APP:-/Applications/Helium.app}"
APP_SUPPORT="$HOME/Library/Application Support"

MODE="install"
SOURCE_OVERRIDE=""

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }
die()    { red "Error: $*" >&2; exit 1; }

usage() {
  sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check)     MODE="check" ;;
    --uninstall) MODE="uninstall" ;;
    --source)    shift; [ $# -gt 0 ] || die "--source needs a path"; SOURCE_OVERRIDE="$1" ;;
    -h|--help)   usage ;;
    *)           die "Unknown option: $1 (try --help)" ;;
  esac
  shift
done

[ "$(uname -s)" = "Darwin" ] || die "This script is for macOS only."

# --- Helium user data directory ---------------------------------------------
# Helium on macOS stores its profile in "net.imput.helium", not "Helium".
# Pointing at the wrong folder is the most common reason the manual fix fails.
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

# --- Architecture -------------------------------------------------------------
# The CDM folder must contain a dylib for the architecture Helium runs as,
# otherwise Helium's component installer treats it as broken and deletes it.
detect_platform_dir() {
  local machine helium_bin archs
  machine="$(uname -m)"
  # uname reports x86_64 under Rosetta; ask the kernel about the hardware.
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

# --- Helpers ------------------------------------------------------------------
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

# A CDM folder is usable only if it has a manifest with a version and a dylib
# for our architecture.
is_valid_cdm_dir() {
  [ -d "$1" ] &&
    [ -f "$1/manifest.json" ] &&
    [ -f "$1/_platform_specific/$PLATFORM_DIR/libwidevinecdm.dylib" ] &&
    manifest_version "$1" >/dev/null
}

# Prints the highest-versioned subfolder of a component-updater WidevineCdm dir.
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

helium_running() {
  pgrep -f "$HELIUM_APP/Contents/MacOS/Helium" >/dev/null 2>&1
}

# --- Find a source CDM --------------------------------------------------------
# Candidates are tried in order; the first one valid for this Mac wins.
list_candidates() {
  local base d
  for base in \
    "$APP_SUPPORT/Google/Chrome/WidevineCdm" \
    "$APP_SUPPORT/BraveSoftware/Brave-Browser/WidevineCdm" \
    "$APP_SUPPORT/Microsoft Edge/WidevineCdm" \
    "$APP_SUPPORT/Google/Chrome Beta/WidevineCdm"; do
    newest_version_subdir "$base" || true
  done
  # Chrome also bundles a copy inside its framework. This one has no version
  # folder around it, which is why copying "WidevineCdm/*" from here does
  # nothing: Helium only scans WidevineCdm/<version>/.
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
    # Accept a component-updater WidevineCdm dir that holds version folders.
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

# --- Modes --------------------------------------------------------------------
do_check() {
  bold "Helium Widevine check"
  echo "Helium app:      $HELIUM_APP $( [ -d "$HELIUM_APP" ] && echo '(found)' || echo '(NOT FOUND)')"
  echo "Helium data dir: $DATA_DIR $( [ -f "$DATA_DIR/Local State" ] && echo '(found)' || echo '(no Local State yet)')"
  echo "Architecture:    $PLATFORM_DIR"
  echo
  bold "Installed in Helium:"
  local found=0 d
  if [ -d "$DEST_ROOT" ]; then
    for d in "$DEST_ROOT"/*/; do
      [ -d "$d" ] || continue
      d="${d%/}"
      found=1
      if is_valid_cdm_dir "$d"; then
        green "  OK      $d"
      else
        red   "  INVALID $d (missing manifest or $PLATFORM_DIR dylib; Helium will delete this)"
      fi
    done
  fi
  [ $found -eq 1 ] || yellow "  nothing in $DEST_ROOT"
  echo
  bold "Available sources:"
  found=0
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    found=1
    if is_valid_cdm_dir "$d"; then
      green "  OK      $d (version $(manifest_version "$d"))"
    else
      yellow "  SKIP    $d (no $PLATFORM_DIR dylib or manifest)"
    fi
  done <<EOF
$(list_candidates)
EOF
  [ $found -eq 1 ] || yellow "  none found. Install Google Chrome, open it once, then rerun."
}

do_uninstall() {
  if helium_running; then die "Quit Helium (Cmd+Q) first."; fi
  if [ -d "$DEST_ROOT" ]; then
    rm -rf "$DEST_ROOT"
    green "Removed $DEST_ROOT"
  else
    yellow "Nothing to remove at $DEST_ROOT"
  fi
}

do_install() {
  [ -d "$HELIUM_APP" ] || die "Helium not found at $HELIUM_APP (set HELIUM_APP=/path/to/Helium.app)."

  if [ ! -f "$DATA_DIR/Local State" ]; then
    die "Helium profile not found at $DATA_DIR. Open Helium once, quit it, then rerun."
  fi

  if helium_running; then
    die "Helium is running. Quit it completely (Cmd+Q), then rerun. It only picks up Widevine at launch."
  fi

  local src version dest
  if ! src="$(find_source)"; then
    red "No usable Widevine CDM found for $PLATFORM_DIR."
    echo "Install Google Chrome, open it once (and play something on https://bitmovin.com/demos/drm),"
    echo "then rerun. Or point at a folder with: --source \"/path/to/WidevineCdm\""
    exit 1
  fi
  version="$(manifest_version "$src")"
  dest="$DEST_ROOT/$version"

  bold "Installing Widevine $version for Helium"
  echo "  from: $src"
  echo "  to:   $dest"

  # Stage first, in case --source points inside Helium's own WidevineCdm folder.
  local staging
  staging="$(mktemp -d "${TMPDIR:-/tmp}/helium-widevine.XXXXXX")"
  # ditto preserves the dylib's code signature and extended attributes.
  ditto "$src" "$staging/$version"

  mkdir -p "$DEST_ROOT"
  # Leave only one version so there is no question which one Helium loads.
  rm -rf "$DEST_ROOT"/*
  mv "$staging/$version" "$dest"
  rm -rf "$staging"
  # Files copied out of a downloaded app can carry the quarantine flag.
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true

  local dylib="$dest/_platform_specific/$PLATFORM_DIR/libwidevinecdm.dylib"
  if codesign --verify "$dylib" >/dev/null 2>&1; then
    green "  dylib signature OK"
  else
    yellow "  warning: codesign could not verify $dylib (it may still load)"
  fi

  is_valid_cdm_dir "$dest" || die "Copy finished but the result does not look valid: $dest"

  echo
  green "Done."
  cat <<EOF

Next steps:
  1. Open Helium.
  2. Go to helium://components and confirm "Widevine Content Decryption Module"
     shows version $version (not 0.0.0.0). An "update error" status there is
     expected; Helium cannot fetch updates for it.
  3. Make sure helium://settings/content/protectedContent allows protected content.
  4. Test at https://bitmovin.com/demos/drm

If Widevine disappears after launch, run: $0 --check
When Chrome updates its CDM, rerun this script to copy the newer one over.
EOF
}

case "$MODE" in
  check)     do_check ;;
  uninstall) do_uninstall ;;
  install)   do_install ;;
esac
