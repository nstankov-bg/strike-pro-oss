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
set -euo pipefail

ROOT=${0:A:h}
SOURCE="/Applications/Alesis Strike Editor.app"
PRODUCT="Strike Pro OSS"
BUNDLE_ID="io.github.strike-pro-oss.editor"
VERSION_SUFFIX="oss1"
THEME=""
INSTALL=0

while (( $# )); do
  case $1 in
    --install) INSTALL=1 ;;
    --theme) THEME=$2; shift ;;
    --source) SOURCE=$2; shift ;;
    -h|--help) sed -n '2,11p' $0; exit 0 ;;
    *) print -u2 "unknown option: $1"; exit 2 ;;
  esac
  shift
done

OUT_DIR="$ROOT/build"
APP="$OUT_DIR/$PRODUCT.app"
STAMP="$OUT_DIR/.inputs.sha256"

[[ -d $SOURCE ]] || { print -u2 "source app not found: $SOURCE"; exit 1; }
SRC_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SOURCE/Contents/Info.plist")
SRC_TEAM=$(codesign -dv "$SOURCE" 2>&1 | awk -F= '/^TeamIdentifier/{print $2}')
[[ $SRC_VERSION == 1.1.6 ]] || print -u2 "warning: tested with 1.1.6, source is $SRC_VERSION"
[[ $SRC_TEAM == NDEA34327T ]] || print -u2 "warning: source is not signed by the original vendor (team $SRC_TEAM)"

# Skip the rebuild (and the CDHash change it causes) when nothing that feeds the build changed.
inputs=$( { shasum -a 256 "$SOURCE/Contents/MacOS/Panel" "$SOURCE/Contents/Resources/StringTables.xml" \
                         "$SOURCE/Contents/Resources/Skins.xml" "$ROOT"/branding/* "$0" | awk '{print $1}';
            print "$THEME" } | shasum -a 256 | awk '{print $1}')
if [[ -d $APP && -f $STAMP && $(<$STAMP) == $inputs ]]; then
  print "==> inputs unchanged, keeping existing build"
else
  print "==> copying $SOURCE"
  mkdir -p "$OUT_DIR"
  rm -rf "$APP" "$OUT_DIR/AppIcon.iconset"
  ditto "$SOURCE" "$APP"
  RES="$APP/Contents/Resources"

  print "==> UI text"
  python3 -I "$ROOT/branding/strings.py" "$RES/StringTables.xml" --product "$PRODUCT"

  print "==> logos and icon"
  swift "$ROOT/branding/logos.swift" "$RES" "$OUT_DIR/AppIcon.iconset" | tail -n 1
  iconutil -c icns "$OUT_DIR/AppIcon.iconset" -o "$RES/Strike.icns"

  if [[ -n $THEME ]]; then
    print "==> theme $THEME"
    python3 -I "$ROOT/branding/skin.py" "$RES/Skins.xml" --theme "$THEME"
  fi
  xmllint --noout "$RES/Skins.xml"

  print "==> Info.plist"
  PLIST="$APP/Contents/Info.plist"
  pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST" }
  pb "Set :CFBundleName '$PRODUCT'"
  pb "Add :CFBundleDisplayName string '$PRODUCT'"
  pb "Set :CFBundleIdentifier $BUNDLE_ID"
  pb "Set :CFBundleShortVersionString $SRC_VERSION-$VERSION_SUFFIX"
  pb "Set :NSHumanReadableCopyright 'Unofficial community build. Not affiliated with or endorsed by Alesis or inMusic.'"
  pb "Add :NSHighResolutionCapable bool true"
  pb "Add :NSRequiresAquaSystemAppearance bool true"

  print "==> signing (ad hoc, no hardened runtime)"
  rm -rf "$APP/Contents/_CodeSignature"
  xattr -cr "$APP"
  codesign --force --deep --sign - "$APP"
  codesign --verify --deep --strict "$APP"
  print -r -- "$inputs" > "$STAMP"
fi

CDHASH=$(codesign -dvvv -a arm64 "$APP" 2>&1 | awk -F= '/^CDHash=/{print $2}')
print "\n==> built: $APP"
print "    arm64 CDHash: $CDHASH"
print "    Santa (Lockdown) rule: rule_type=CDHASH policy=ALLOWLIST identifier=$CDHASH"

if (( INSTALL )); then
  DEST="/Applications/$PRODUCT.app"
  print "==> installing to $DEST"
  rm -rf "$DEST"
  ditto "$APP" "$DEST"

  # The editor keeps UserSettings.ini under Application Support/<CFBundleName>.
  OLD_SUPPORT="$HOME/Library/Application Support/Alesis Strike Preset Editor"
  NEW_SUPPORT="$HOME/Library/Application Support/$PRODUCT"
  if [[ -f "$OLD_SUPPORT/UserSettings.ini" && ! -f "$NEW_SUPPORT/UserSettings.ini" ]]; then
    mkdir -p "$NEW_SUPPORT"
    cp "$OLD_SUPPORT/UserSettings.ini" "$NEW_SUPPORT/"
    print "    migrated UserSettings.ini"
  fi

  # App Nap can throttle the timer that sends the module's keep-alive messages.
  defaults write "$BUNDLE_ID" NSAppSleepDisabled -bool YES
  print "    App Nap disabled for $BUNDLE_ID"
fi
