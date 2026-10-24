#!/bin/zsh
# build.sh — builds "Strike Pro OSS.app" from your own installed copy of Alesis Strike Editor 1.1.6.
#
#   ./build.sh                     build into ./build
#   ./build.sh --install           also copy to /Applications, migrate settings, disable App Nap
#   ./build.sh --theme graphite    apply an optional colour theme (see branding/skin.py)
#   ./build.sh --source <app>      use a different source bundle
#
# The executable is never modified. Resources and Info.plist change, so the bundle is re-signed
# ad hoc; the script prints the resulting CDHash (needed if your Mac runs Santa in Lockdown).

ROOT=${0:A:h}
PRODUCT="Strike Pro OSS"
BUNDLE_ID=${STRIKE_BUNDLE_ID:-io.github.strike-pro-oss.editor}
VERSION_SUFFIX="oss1"
VENDOR_TEAM="NDEA34327T"
INSTALL_DIR=${STRIKE_INSTALL_DIR:-/Applications}
DEFAULTS=${STRIKE_DEFAULTS:-defaults}
OUT_DIR=${STRIKE_OUT_DIR:-$ROOT/build}
APP="$OUT_DIR/$PRODUCT.app"
STAMP="$OUT_DIR/.inputs.sha256"

SOURCE="/Applications/Alesis Strike Editor.app"
THEME=""
INSTALL=0

usage() { sed -n '2,11p' "$ROOT/build.sh" }

parse_args() {
  while (( $# )); do
    case $1 in
      --install) INSTALL=1 ;;
      --theme) THEME=$2; shift ;;
      --source) SOURCE=$2; shift ;;
      -h|--help) usage; return 3 ;;
      *) print -u2 "unknown option: $1"; return 2 ;;
    esac
    shift
  done
}

# Fails when $1 is missing; warns when it isn't the tested, vendor-signed 1.1.6.
check_source() {
  local src=$1
  [[ -d $src ]] || { print -u2 "source app not found: $src"; return 1 }
  local version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$src/Contents/Info.plist")
  local team=$(codesign -dv "$src" 2>&1 | awk -F= '/^TeamIdentifier/{print $2}')
  [[ $version == 1.1.6 ]] || print -u2 "warning: tested with 1.1.6, source is $version"
  [[ $team == $VENDOR_TEAM ]] || print -u2 "warning: source is not signed by the original vendor (team $team)"
  return 0
}

# One hash over everything that feeds the build: source files, our scripts, and the theme.
inputs_hash() {
  local src=$1 theme=$2
  { shasum -a 256 "$src/Contents/MacOS/Panel" "$src/Contents/Resources/StringTables.xml" \
                  "$src/Contents/Resources/Skins.xml" "$ROOT"/branding/* "$ROOT/build.sh" | awk '{print $1}'
    print -r -- "$theme" } | shasum -a 256 | awk '{print $1}'
}

build_app() {
  local src=$1 theme=$2
  print "==> copying $src"
  mkdir -p "$OUT_DIR"
  rm -rf "$APP" "$OUT_DIR/AppIcon.iconset"
  ditto "$src" "$APP" || return 1
  local res="$APP/Contents/Resources"

  print "==> UI text"
  python3 -I "$ROOT/branding/strings.py" "$res/StringTables.xml" --product "$PRODUCT" || return 1

  print "==> logos and icon"
  swift "$ROOT/branding/logos.swift" "$res" "$OUT_DIR/AppIcon.iconset" | tail -n 1
  iconutil -c icns "$OUT_DIR/AppIcon.iconset" -o "$res/Strike.icns" || return 1

  if [[ -n $theme ]]; then
    print "==> theme $theme"
    python3 -I "$ROOT/branding/skin.py" "$res/Skins.xml" --theme "$theme" || return 1
  fi
  xmllint --noout "$res/Skins.xml" || return 1

  print "==> Info.plist"
  local plist="$APP/Contents/Info.plist" version
  version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
  local cmd
  for cmd in "Set :CFBundleName '$PRODUCT'" \
             "Add :CFBundleDisplayName string '$PRODUCT'" \
             "Set :CFBundleIdentifier $BUNDLE_ID" \
             "Set :CFBundleShortVersionString $version-$VERSION_SUFFIX" \
             "Set :NSHumanReadableCopyright 'Unofficial community build. Not affiliated with or endorsed by Alesis or inMusic.'" \
             "Add :NSHighResolutionCapable bool true" \
             "Add :NSRequiresAquaSystemAppearance bool true"; do
    /usr/libexec/PlistBuddy -c "$cmd" "$plist" || return 1
  done

  print "==> signing (ad hoc, no hardened runtime)"
  rm -rf "$APP/Contents/_CodeSignature"
  xattr -cr "$APP"
  codesign --force --deep --sign - "$APP" 2>&1 | grep -v "replacing existing signature"
  codesign --verify --deep --strict "$APP"
}

# arm64 CDHash of the bundle at $1.
cdhash() { codesign -dvvv -a arm64 "$1" 2>&1 | awk -F= '/^CDHash=/{print $2}' }

# The editor keeps UserSettings.ini under Application Support/<CFBundleName>; copy it over once.
migrate_settings() {
  local old="$HOME/Library/Application Support/Alesis Strike Preset Editor"
  local new="$HOME/Library/Application Support/$PRODUCT"
  if [[ -f "$old/UserSettings.ini" && ! -f "$new/UserSettings.ini" ]]; then
    mkdir -p "$new"
    cp "$old/UserSettings.ini" "$new/"
    print "    migrated UserSettings.ini"
  fi
}

install_app() {
  local dest="$INSTALL_DIR/$PRODUCT.app"
  print "==> installing to $dest"
  rm -rf "$dest"
  ditto "$APP" "$dest" || return 1
  migrate_settings
  # App Nap can throttle the timer that sends the module's keep-alive messages.
  $DEFAULTS write "$BUNDLE_ID" NSAppSleepDisabled -bool YES
  print "    App Nap disabled for $BUNDLE_ID"
}

main() {
  parse_args "$@"
  local rc=$?
  (( rc == 3 )) && return 0
  (( rc )) && return $rc
  check_source "$SOURCE" || return 1

  local inputs=$(inputs_hash "$SOURCE" "$THEME")
  if [[ -d $APP && -f $STAMP && $(<$STAMP) == $inputs ]]; then
    print "==> inputs unchanged, keeping existing build"
  else
    build_app "$SOURCE" "$THEME" || { print -u2 "build failed"; return 1 }
    print -r -- "$inputs" > "$STAMP"
  fi

  local hash=$(cdhash "$APP")
  print "\n==> built: $APP"
  print "    arm64 CDHash: $hash"
  print "    Santa (Lockdown) rule: rule_type=CDHASH policy=ALLOWLIST identifier=$hash"
  (( INSTALL )) && install_app
  return 0
}

# Run only when executed, not when sourced by the tests.
if [[ $ZSH_EVAL_CONTEXT == toplevel ]]; then
  main "$@"
fi
