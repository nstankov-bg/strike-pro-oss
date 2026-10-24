#!/bin/zsh
# strike-backup.sh — hard-linked snapshots of the Strike module's USB drive.
#
#   tools/strike-backup.sh                 back up now (fails if the module drive isn't mounted)
#   tools/strike-backup.sh --if-present    exit quietly when the drive isn't mounted (for launchd)
#   tools/strike-backup.sh --force         take the snapshot even if it looks much smaller than the last one
#
# Env: STRIKE_BACKUP_DIR (default ~/StrikeBackups), STRIKE_BACKUP_KEEP (default 10),
#      STRIKE_VOLUME (skip detection and back up this path instead).
# Uses only macOS built-ins (ioreg, diskutil, rsync), so no extra binaries need allowlisting.
set -euo pipefail

DEST=${STRIKE_BACKUP_DIR:-$HOME/StrikeBackups}
KEEP=${STRIKE_BACKUP_KEEP:-10}
LOG="$HOME/Library/Logs/strike-backup.log"
IF_PRESENT=0
FORCE=0
for arg in "$@"; do
  case $arg in
    --if-present) IF_PRESENT=1 ;;
    --force) FORCE=1 ;;
    *) print -u2 "unknown option: $arg"; exit 2 ;;
  esac
done

mkdir -p "$DEST" "${LOG:h}"
log() { print -r -- "$(date '+%F %T') $*" | tee -a "$LOG" }
fail() {
  log "ERROR: $*"
  osascript -e "display notification \"$*\" with title \"Strike backup failed\"" 2>/dev/null || true
  exit 1
}

# Locate the drive the same way the editor does: IORegistry entry "Alesis Strike" -> BSD disk -> partition 1.
volume=${STRIKE_VOLUME:-}
if [[ -z $volume ]]; then
  bsd=$(ioreg -r -n "Alesis Strike" -l 2>/dev/null | awk -F'"' '/"BSD Name" = "disk[0-9]+"$/{print $4; exit}')
  if [[ -n $bsd ]]; then
    volume=$(diskutil info "${bsd}s1" 2>/dev/null | awk -F': *' '/Mount Point/{print $2; exit}')
  fi
fi
if [[ -z $volume || ! -d $volume ]]; then
  (( IF_PRESENT )) && exit 0
  fail "Strike module drive not found (is it connected and mounted?)"
fi

content_files() {
  find "$volume" -type f ! -name '._*' ! -name '.DS_Store' ! -path '*/.Spotlight-V100/*' \
    ! -path '*/.fseventsd/*' ! -path '*/.Trashes/*' ! -path '*/.TemporaryItems/*' -print0 2>/dev/null
}

# Avoid snapshotting a drive mid-write: wait until two consecutive listings match.
listing() { content_files | xargs -0 stat -f '%z %m %N' 2>/dev/null | shasum | cut -c1-40 }
before=$(listing); sleep 5; after=$(listing)
[[ $before == $after ]] || fail "drive contents still changing; try again when transfers finish"

existing=("$DEST"/20*(N/On))
latest=${existing[1]:-}
count=$(content_files | tr -cd '\0' | wc -c | tr -d ' ')
if [[ -n $latest && -f $latest/.filecount ]] && (( ! FORCE )); then
  prev=$(<"$latest/.filecount")
  if (( prev > 20 && count * 2 < prev )); then
    fail "drive has $count files vs $prev in the last snapshot; refusing (use --force if intended)"
  fi
fi

stamp=$(date '+%Y-%m-%d_%H%M%S')
work="$DEST/.in-progress-$stamp"
link_args=()
[[ -n $latest ]] && link_args=(--link-dest="$latest")

log "backing up $volume ($count files) -> $DEST/$stamp"
# FAT keeps 2-second timestamps; --modify-window avoids re-copying everything each run.
/usr/bin/rsync -a --modify-window=2 "${link_args[@]}" \
  --exclude '._*' --exclude '.DS_Store' --exclude '.Spotlight-V100' --exclude '.fseventsd' \
  --exclude '.Trashes' --exclude '.TemporaryItems' \
  "$volume/" "$work/" || fail "rsync failed (see $LOG)"
print -r -- "$count" > "$work/.filecount"
mv "$work" "$DEST/$stamp"

# Keep the newest $KEEP snapshots.
snapshots=("$DEST"/20*(N/On))
for old in "${snapshots[@]:$KEEP}"; do
  rm -rf "$old"
  log "pruned ${old:t}"
done
log "done: $DEST/$stamp ($(du -sh "$DEST/$stamp" | cut -f1) apparent, shared with previous where unchanged)"
