#!/usr/bin/env bash
set -euo pipefail

# ===========================================
# Neemos' SC2 Remote Backup Script
# This should make a backup of your Cities Skyline 2 Important folders in Linux
# There is logic to automatically detect your install locations and copy the folders using rsync to a safe directory on a NAS or Server.
# It is designed to run silently so it can be scheduled to run at login, logout or with cron.
# As always do not run random scripts from the internet without understanding what it does.

# Notes:
# - Replace REMOTE_USER, REMOTE_HOST, SSH_KEY, and BACKUP_BASE_REMOTE with your own values.
# - The script defaults to dry-run when DRY_RUN="true". Set DRY_RUN="false" to perform real transfers.
# - Passwordless SSH should to be setup prior to use if you want silent operation. You can generate a new ssh id or use an existing one. Search online for how to do this.

# --- Editable configuration ---
DRY_RUN="true"
REMOTE_USER="remote_user_here"
REMOTE_HOST="remote.server.address.or.ip.here"
SSH_KEY="$HOME/.ssh/ssh.id.copied.to.server"
BACKUP_BASE_REMOTE="~/CS2Backup"
LOG_DIR="$HOME/.backup_logs"
DESKTOP_LOG="$HOME/Desktop/backup_log_$(date +%Y%m%d).txt"
STEAM_ID=949230

# New: toggle logging (true = write logs, false = disable logging)
ENABLE_LOGGING="true"
# If ENABLE_LOGGING is "false", LOG_FILE will be /dev/null and nothing will be recorded.

SOURCE_ITEMS=(
  "Saves"
  "Maps"
  "Screenshots"
  "ModsSettings"
  "ModsData"
  "ModsData/ExtraAssetsImporter"
)

BACKUP_FOLDER_NAMES=(
  "Saves"
  "Maps"
  "CSII_Screenshots"
  "ModSettings"
  "ModData"
  "CustomEAI"
)

EXCLUDES=(
  '.cache'
  '*.tmp'
  '**/Database/'
  '**/Database/**'
  '**/.[^/]*'
)
# --- End editable configuration ---

# Timestamp/log helpers
_ts(){ date '+%Y-%m-%d %H:%M:%S'; }
if [[ "${ENABLE_LOGGING,,}" == "true" ]]; then
  mkdir -p "$LOG_DIR"
  LOG_FILE="$LOG_DIR/rsync_debug_$(date +%Y%m%d_%H%M%S).log"
else
  LOG_FILE="/dev/null"
fi

# Log only to logfile (no console)
_log(){ printf '%s %s\n' "$(_ts)" "$*" >> "$LOG_FILE"; }
info(){ _log "[INFO] $*"; }
warn(){ _log "[WARN] $*"; }
err(){ _log "[ERROR] $*"; }

detect_steam_dir_noninteractive() {
    local candidates=()

    candidates+=("$HOME/.steam/steam" "$HOME/.local/share/Steam" "/usr/lib/steam" "/snap/steam/common/.steam/steam")

    local vdf_paths=( "$HOME/.steam/steam/steamapps/libraryfolders.vdf" "$HOME/.local/share/Steam/steamapps/libraryfolders.vdf" )
    for vdf in "${vdf_paths[@]}"; do
        if [[ -f "$vdf" ]]; then
            info "Parsing library file: $vdf"
            while IFS= read -r line; do
                if [[ $line =~ \"[0-9]+\"[[:space:]]+\"([^\"]+)\" ]]; then
                    candidates+=("${BASH_REMATCH[1]}")
                fi
            done <"$vdf"
        fi
    done

    if [[ -d "/run/media/$USER" ]]; then
        while IFS= read -r -d '' d; do candidates+=("$d"); done < <(find "/run/media/$USER" -maxdepth 2 -type d -print0 2>/dev/null)
    fi
    if [[ -d "/mnt" ]]; then
        while IFS= read -r -d '' d; do candidates+=("$d"); done < <(find "/mnt" -maxdepth 2 -type d -print0 2>/dev/null)
    fi

    declare -A seen=()
    local uniq_candidates=()
    for c in "${candidates[@]}"; do
        [[ -z "$c" ]] && continue
        c="${c/#\~/$HOME}"
        c="${c%/}"
        if command -v realpath >/dev/null 2>&1; then
            c="$(realpath -m "$c" 2>/dev/null || echo "$c")"
        fi
        if [[ -z "${seen[$c]+x}" ]]; then
            seen[$c]=1
            uniq_candidates+=("$c")
        fi
    done

    for cand in "${uniq_candidates[@]}"; do
        if [[ -d "$cand/steamapps/compatdata/$STEAM_ID" ]]; then
            STEAM_DIR="$cand"
            info "Selected Steam/library path: $STEAM_DIR (found compatdata)"
            return 0
        fi
        if [[ -x "$cand/steam" && -d "$cand/steamapps/compatdata/$STEAM_ID" ]]; then
            STEAM_DIR="$cand"
            info "Selected Steam installation: $STEAM_DIR"
            return 0
        fi
        if [[ -d "$cand/Steam/steamapps/compatdata/$STEAM_ID" ]]; then
            STEAM_DIR="$cand/Steam"
            info "Selected Steam library: $STEAM_DIR"
            return 0
        fi
        if [[ -d "$cand/.steam/steam/steamapps/compatdata/$STEAM_ID" ]]; then
            STEAM_DIR="$cand/.steam/steam"
            info "Selected Steam path: $STEAM_DIR"
            return 0
        fi
    done

    info "Scanning candidate directories for compatdata/$STEAM_ID (this may take a moment)..."
    for cand in "${uniq_candidates[@]}"; do
        if [[ -d "$cand" ]]; then
            local found
            found="$(find "$cand" -maxdepth 4 -type d -name "$STEAM_ID" -print -quit 2>/dev/null || true)"
            if [[ -n "$found" ]]; then
                local parent
                parent="$(dirname "$found")"
                STEAM_DIR="$(cd "$parent/.." && pwd 2>/dev/null || echo "$cand")"
                info "Inferred Steam/library path from scan: $STEAM_DIR (found $found)"
                return 0
            fi
        fi
    done

    warn "No Steam/library path with compatdata/$STEAM_ID found; continuing without STEAM_DIR. Sources will be skipped if missing."
    return 1
}

info "Starting detection for Steam app id: $STEAM_ID"

if detect_steam_dir_noninteractive; then
    info "Steam directory set to: $STEAM_DIR"
else
    warn "Steam directory not found; will still attempt to build source paths but most will be missing."
    STEAM_DIR="${STEAM_DIR:-/nonexistent_steam_dir}"
fi

BASE_COMPATDATA_PATH="$STEAM_DIR/steamapps/compatdata/$STEAM_ID/pfx/drive_c/users/steamuser/AppData/LocalLow/Colossal Order/Cities Skylines II"

# Log start
_log "=========================================="
_log "Backup started: $(_ts)"
_log "Base compatdata path: $BASE_COMPATDATA_PATH"
_log "Dry run: $DRY_RUN"
_log "Logging enabled: $ENABLE_LOGGING"
_log "=========================================="

if [ "${#SOURCE_ITEMS[@]}" -ne "${#BACKUP_FOLDER_NAMES[@]}" ]; then
  err "SOURCE_ITEMS and BACKUP_FOLDER_NAMES length mismatch."
  exit 1
fi

TOTAL_EXIT_CODE=0

RSYNC_BASE_OPTS=(--archive --compress --partial)
if [[ "${DRY_RUN,,}" == "true" ]]; then RSYNC_BASE_OPTS+=(--dry-run); fi

if [ -n "$SSH_KEY" ]; then
  SSH_CMD=(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
else
  SSH_CMD=(ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
fi
SSH_CMD_STR="${SSH_CMD[*]}"

info "Rsync base opts: ${RSYNC_BASE_OPTS[*]}"
info "SSH command: ${SSH_CMD_STR}"
info "Remote base: ${REMOTE_USER}@${REMOTE_HOST}:${BACKUP_BASE_REMOTE}"

for idx in "${!SOURCE_ITEMS[@]}"; do
    SRC_REL="${SOURCE_ITEMS[$idx]}"
    FOLDER_NAME="${BACKUP_FOLDER_NAMES[$idx]}"
    SOURCE="$BASE_COMPATDATA_PATH/$SRC_REL"
    DEST="${BACKUP_BASE_REMOTE%/}/$FOLDER_NAME/"

    info "Starting backup iteration $((idx+1))/${#SOURCE_ITEMS[@]}: SOURCE='$SOURCE' -> DEST='$DEST'"

    if [ ! -d "$SOURCE" ]; then
        warn "Source directory '$SOURCE' does not exist. Logging and skipping."
        printf '%s %s\n' "$(_ts)" "[SKIP] Missing source: $SOURCE" >> "$LOG_FILE"
        continue
    fi

    RSYNC_OPTS=("${RSYNC_BASE_OPTS[@]}")
    for e in "${EXCLUDES[@]}"; do RSYNC_OPTS+=(--exclude="$e"); done

    # Log exact rsync+ssh command to logfile
    info "Running rsync: rsync ${RSYNC_OPTS[*]} -e \"${SSH_CMD_STR}\" \"$SOURCE/\" \"${REMOTE_USER}@${REMOTE_HOST}:${DEST}\""

    # Run rsync and write only transferred filenames to the log
    # --out-format='%n' prints only the pathname of each transferred file (one per line).
    # We'll capture rsync output to a temp file, then prefix each filename with a timestamp and append to LOG_FILE.
    TMP_RS_OUT="$(mktemp)"
    if rsync "${RSYNC_OPTS[@]}" --out-format='%n' -e "$SSH_CMD_STR" "$SOURCE/" "${REMOTE_USER}@${REMOTE_HOST}:${DEST}" >"$TMP_RS_OUT" 2>>"$LOG_FILE"; then
        RC=0
        info "SUCCESS: Backup completed for $SOURCE"
    else
        RC=${PIPESTATUS[0]:-1}
        err "Backup failed for $SOURCE (Exit code: $RC). See log for details."
        TOTAL_EXIT_CODE=1
    fi

    # Append concise transferred-file list with timestamps to the main log (one file per line).
    if [[ "${ENABLE_LOGGING,,}" == "true" ]]; then
        if [[ -s "$TMP_RS_OUT" ]]; then
            while IFS= read -r fname; do
                printf '%s [FILE] %s\n' "$(_ts)" "$fname" >> "$LOG_FILE"
            done <"$TMP_RS_OUT"
        else
            # No files transferred in this iteration (common in dry-run or nothing to sync).
            _log "[FILELIST] (no files transferred for this source)"
        fi
    fi

    rm -f "$TMP_RS_OUT" || true

    printf '\n' >>"$LOG_FILE"
done

_log "=========================================="
_log "All backups finished: $(_ts)"
_log "Overall Status: $([ $TOTAL_EXIT_CODE -eq 0 ] && echo 'Success' || echo 'Some failures occurred')"
_log "=========================================="

if [[ "${ENABLE_LOGGING,,}" == "true" ]]; then
  if cp "$LOG_FILE" "$DESKTOP_LOG" 2>/dev/null; then
    info "Copied log to $DESKTOP_LOG"
  else
    warn "Failed to copy log to Desktop"
  fi
fi

if command -v notify-send >/dev/null 2>&1; then
  if [ $TOTAL_EXIT_CODE -eq 0 ]; then
      notify-send "Backup Script: Success — $(date +%Y-%m-%d)" "All directories backed up successfully."
  else
      notify-send "Backup Script Finished with Errors - $(date +%Y-%m-%d)" "Check $DESKTOP_LOG for details."
  fi
fi

exit $TOTAL_EXIT_CODE
