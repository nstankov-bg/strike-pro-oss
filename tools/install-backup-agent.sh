#!/bin/zsh
# install-backup-agent.sh — run strike-backup.sh automatically whenever a volume mounts.
#
#   tools/install-backup-agent.sh            install (or update) the LaunchAgent
#   tools/install-backup-agent.sh --remove   uninstall it
#
# The agent fires on every mount and exits immediately unless the Strike drive is present.
# If backups don't appear, check ~/Library/Logs/strike-backup.log and grant /bin/zsh access to
# removable volumes in System Settings > Privacy & Security if macOS asks.

LABEL="io.github.strike-pro-oss.backup"
AGENTS_DIR=${LAUNCH_AGENTS_DIR:-$HOME/Library/LaunchAgents}
LAUNCHCTL=${LAUNCHCTL:-launchctl}
PLIST="$AGENTS_DIR/$LABEL.plist"
BACKUP_SCRIPT="${0:A:h}/strike-backup.sh"

# Prints the LaunchAgent plist for running script $1 on every mount, logging to $2.
plist_xml() {
  local script=$1 logfile=$2
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/zsh</string><string>$script</string><string>--if-present</string></array>
  <key>StartOnMount</key><true/>
  <key>StandardOutPath</key><string>$logfile</string>
  <key>StandardErrorPath</key><string>$logfile</string>
</dict>
</plist>
EOF
}

remove_agent() {
  $LAUNCHCTL bootout "gui/$UID/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
}

install_agent() {
  remove_agent
  chmod +x "$BACKUP_SCRIPT"
  mkdir -p "$AGENTS_DIR"
  plist_xml "$BACKUP_SCRIPT" "$HOME/Library/Logs/strike-backup.log" > "$PLIST"
  plutil -lint -s "$PLIST" || return 1
  $LAUNCHCTL bootstrap "gui/$UID" "$PLIST"
}

main() {
  if [[ ${1:-} == --remove ]]; then
    remove_agent
    print "removed $LABEL"
  else
    install_agent || return 1
    print "installed $LABEL -> $BACKUP_SCRIPT"
  fi
}

# Run only when executed, not when sourced by the tests.
if [[ $ZSH_EVAL_CONTEXT == toplevel ]]; then
  main "$@"
fi
