#!/bin/zsh
# install-backup-agent.sh — run strike-backup.sh automatically whenever a volume mounts.
#
#   tools/install-backup-agent.sh            install (or update) the LaunchAgent
#   tools/install-backup-agent.sh --remove   uninstall it
#
# The agent fires on every mount and exits immediately unless the Strike drive is present.
# If backups don't appear, check ~/Library/Logs/strike-backup.log and grant /bin/zsh access to
# removable volumes in System Settings > Privacy & Security if macOS asks.
set -euo pipefail

LABEL="io.github.strike-pro-oss.backup"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT="${0:A:h}/strike-backup.sh"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
if [[ ${1:-} == --remove ]]; then
  rm -f "$PLIST"
  print "removed $LABEL"
  exit 0
fi

chmod +x "$SCRIPT"
mkdir -p "${PLIST:h}"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/zsh</string><string>$SCRIPT</string><string>--if-present</string></array>
  <key>StartOnMount</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/strike-backup.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/strike-backup.log</string>
</dict>
</plist>
EOF
plutil -lint -s "$PLIST"
launchctl bootstrap "gui/$UID" "$PLIST"
print "installed $LABEL -> $SCRIPT"
