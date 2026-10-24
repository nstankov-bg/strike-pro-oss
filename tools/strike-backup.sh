#!/bin/zsh
# strike-backup.sh — hard-linked snapshots of the Strike module's USB drives.
#
# The module exposes two drives, usually both labelled "NO NAME": the read-only internal (factory)
# drive and the writable user drive (SD card). Each is snapshotted on its own under
# ~/StrikeBackups/internal and ~/StrikeBackups/card.
#
#   tools/strike-backup.sh                 back up now (fails if no module drive is mounted)
#   tools/strike-backup.sh --if-present    exit quietly when no drive is mounted (for launchd)
#   tools/strike-backup.sh --force         take snapshots even if a drive looks much smaller than last time
#
# Env: STRIKE_BACKUP_DIR (default ~/StrikeBackups), STRIKE_BACKUP_KEEP (default 10),
#      STRIKE_VOLUME (skip detection and back up this one path straight into STRIKE_BACKUP_DIR).
# Uses only macOS built-ins (ioreg, diskutil, rsync), so no extra binaries need allowlisting.

DEST=${STRIKE_BACKUP_DIR:-$HOME/StrikeBackups}
KEEP=${STRIKE_BACKUP_KEEP:-10}
LOG=${STRIKE_BACKUP_LOG:-$HOME/Library/Logs/strike-backup.log}
SETTLE_SECONDS=${STRIKE_BACKUP_SETTLE:-5}
NOTIFY=${STRIKE_BACKUP_NOTIFY:-osascript}
IOREG=${STRIKE_IOREG:-ioreg}
DISKUTIL=${STRIKE_DISKUTIL:-diskutil}

log() { print -r -- "$(date '+%F %T') $*" | tee -a "$LOG" }

fail() {
  log "ERROR: $*"
  $NOTIFY -e "display notification \"$*\" with title \"Strike backup failed\"" 2>/dev/null || true
  return 1
}

# "internal" for the module's read-only factory drive, "card" for the writable user drive.
disk_role() {
  $DISKUTIL info "$1" 2>/dev/null | grep -q 'Media Read-Only: *Yes' && print internal || print card
}

# Prints "<role><TAB><mount point>" for every mounted drive under the IORegistry entry "Alesis Strike"
# (partition 1 of each whole disk, as the editor assumes). With STRIKE_VOLUME set, prints "-<TAB><path>"
# ("-" = no role: back up straight into STRIKE_BACKUP_DIR).
find_volumes() {
  if [[ -n ${STRIKE_VOLUME:-} ]]; then
    print -r -- "-"$'\t'"$STRIKE_VOLUME"
    return 0
  fi
  local bsd mnt
  for bsd in $($IOREG -r -n "Alesis Strike" -l 2>/dev/null | awk -F'"' '/"BSD Name" = "disk[0-9]+"$/{print $4}' | sort -u); do
    mnt=$($DISKUTIL info "${bsd}s1" 2>/dev/null | awk -F': *' '/Mount Point/{print $2; exit}')
    [[ -n $mnt ]] && print -r -- "$(disk_role "$bsd")"$'\t'"$mnt"
  done
  return 0
}

# NUL-separated content files of $1, without macOS metadata.
content_files() {
  find "$1" -type f ! -name '._*' ! -name '.DS_Store' ! -path '*/.Spotlight-V100/*' \
    ! -path '*/.fseventsd/*' ! -path '*/.Trashes/*' ! -path '*/.TemporaryItems/*' -print0 2>/dev/null
}

file_count() { content_files "$1" | tr -cd '\0' | wc -c | tr -d ' ' }

# Fingerprint of sizes, mtimes and names; changes while a transfer is in progress.
listing() { content_files "$1" | xargs -0 stat -f '%z %m %N' 2>/dev/null | shasum | cut -c1-40 }

# True unless the drive shrank to under half of a previous snapshot that had more than 20 files.
shrink_ok() {
  local count=$1 prev=$2
  (( prev <= 20 || count * 2 >= prev ))
}

latest_snapshot() {
  local snaps=("$DEST"/20*(N/On))
  print -r -- "${snaps[1]:-}"
}

# Keeps the newest $KEEP snapshots.
prune() {
  local snaps=("$DEST"/20*(N/On)) old
  for old in "${snaps[@]:$KEEP}"; do
    rm -rf "$old"
    log "pruned ${old:t}"
  done
}

# rsync $1 into a new timestamped snapshot, hard-linking unchanged files to $2 (may be empty).
take_snapshot() {
  local volume=$1 latest=$2 count=$3
  local stamp=$(date '+%Y-%m-%d_%H%M%S')
  local work="$DEST/.in-progress-$stamp"
  local link_args=()
  [[ -n $latest ]] && link_args=(--link-dest="$latest")
  log "backing up $volume ($count files) -> $DEST/$stamp"
  # FAT keeps 2-second timestamps; --modify-window avoids re-copying everything each run.
  /usr/bin/rsync -a --modify-window=2 "${link_args[@]}" \
    --exclude '._*' --exclude '.DS_Store' --exclude '.Spotlight-V100' --exclude '.fseventsd' \
    --exclude '.Trashes' --exclude '.TemporaryItems' \
    "$volume/" "$work/" || { fail "rsync failed (see $LOG)"; return 1 }
  print -r -- "$count" > "$work/.filecount"
  # Two runs in the same second (e.g. several volumes mounting at once) must not nest snapshots.
  local target="$DEST/$stamp" n=1
  while [[ -e $target ]]; do target="$DEST/$stamp-$((n++))"; done
  mv "$work" "$target"
  print -r -- "$target"
}

# One volume into $DEST: settle check, shrink guard, snapshot, prune. $2=1 skips the shrink guard.
backup_volume() {
  local volume=$1 force=${2:-0}
  mkdir -p "$DEST"
  # Avoid snapshotting a drive mid-write: wait until two consecutive listings match.
  local before=$(listing "$volume"); sleep "$SETTLE_SECONDS"
  [[ $before == $(listing "$volume") ]] || { fail "$volume still changing; try again when transfers finish"; return 1 }

  local latest=$(latest_snapshot) count=$(file_count "$volume")
  if [[ -n $latest && -f $latest/.filecount ]] && (( ! force )); then
    local prev=$(<"$latest/.filecount")
    shrink_ok "$count" "$prev" || { fail "$volume has $count files vs $prev in the last snapshot; refusing (use --force if intended)"; return 1 }
  fi

  local snap
  snap=$(take_snapshot "$volume" "$latest" "$count" | tail -n 1) || return 1
  prune
  log "done: $snap ($(du -sh "$snap" | cut -f1) apparent, shared with previous where unchanged)"
}

main() {
  local if_present=0 force=0 arg
  for arg in "$@"; do
    case $arg in
      --if-present) if_present=1 ;;
      --force) force=1 ;;
      *) print -u2 "unknown option: $arg"; return 2 ;;
    esac
  done
  mkdir -p "${LOG:h}"

  local base=$DEST rc=0 found=0 role volume
  while IFS=$'\t' read -r role volume; do
    [[ -d $volume ]] || continue
    found=1
    [[ $role == - ]] && DEST=$base || DEST=$base/$role
    backup_volume "$volume" "$force" || rc=1
  done < <(find_volumes)
  DEST=$base

  if (( ! found )); then
    (( if_present )) && return 0
    fail "Strike module drive not found (is it connected and mounted?)"
    return 1
  fi
  return $rc
}

# Run only when executed, not when sourced by the tests.
if [[ $ZSH_EVAL_CONTEXT == toplevel ]]; then
  main "$@"
fi
