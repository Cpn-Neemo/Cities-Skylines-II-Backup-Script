#!/usr/bin/env bash
set -euo pipefail

# ===========================================
# Neemos' SC2 Local Backup Script
# Backs up Cities Skylines 2 important folders to a local directory using rsync.
# Designed to run silently and can be scheduled via cron or login/logout hooks.
# Always review scripts before running them.

# --- Editable configuration ---
DRY_RUN="true"
BACKUP_BASE_LOCAL="$HOME/CS2Backup"  # Change this to your desired local backup path
LOG_DIR="$HOME/.backup_logs"
DESKTOP_LOG="$HOME/Desktop/backup_log_$(date +%Y%m%d).txt"
STEAM_ID=949230

ENABLE_LOGGING="true"

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
_log "Local Backup started: $(_ts)"
_log "Base compatdata path: $BASE_COMPATDATA_PATH"
_log "Dry run: $DRY_RUN"
_log "Logging enabled: $ENABLE_LOGGING"
_log "Backup destination: $BACKUP_BASE_LOCAL"
_log "=========================================="

if [ "${#SOURCE_ITEMS[@]}" -ne "${#BACKUP_FOLDER_NAMES[@]}" ]; then
  err "SOURCE_ITEMS and BACKUP_FOLDER_NAMES length mismatch."
  exit 1
fi

TOTAL_EXIT_CODE=0

RSYNC_BASE_OPTS=(--archive --compress --partial)
if [[ "${DRY_RUN,,}" == "true" ]]; then RSYNC_BASE_OPTS+=(--dry-run); fi

# Ensure backup directory exists
mkdir -p "$BACKUP_BASE_LOCAL"

info "Rsync base opts: ${RSYNC_BASE_OPTS[*]}"
info "Local backup base: $BACKUP_BASE_LOCAL"

for idx in "${!SOURCE_ITEMS[@]}"; do
    SRC_REL="${SOURCE_ITEMS[$idx]}"
    FOLDER_NAME="${BACKUP_FOLDER_NAMES[$idx]}"
    SOURCE="$BASE_COMPATDATA_PATH/$SRC_REL"
    DEST="$BACKUP_BASE_LOCAL/$FOLDER_NAME/"

    info "Starting backup iteration $((idx+1))/${#SOURCE_ITEMS[@]}: SOURCE='$SOURCE' -> DEST='$DEST'"

    if [ ! -d "$SOURCE" ]; then
        warn "Source directory '$SOURCE' does not exist. Logging and skipping."
        printf '%s %s\n' "$(_ts)" "[SKIP] Missing source: $SOURCE" >> "$LOG_FILE"
        continue
    fi

    RSYNC_OPTS=("${RSYNC_BASE_OPTS[@]}")
    for e in "${EXCLUDES[@]}"; do RSYNC_OPTS+=(--exclude="$e"); done

    # Log exact rsync command to logfile
    info "Running rsync: rsync ${RSYNC_OPTS[*]} \"$SOURCE/\" \"$DEST\""

    # Run rsync and write only transferred filenames to the log
    TMP_RS_OUT="$(mktemp)"
    if rsync "${RSYNC_OPTS[@]}" --out-format='%n' "$SOURCE/" "$DEST" >"$TMP_RS_OUT" 2>>"$LOG_FILE"; then
        RC=0
        info "SUCCESS: Backup completed for $SOURCE"
    else
        RC=${PIPESTATUS[0]:-1}
        err "Backup failed for $SOURCE (Exit code: $RC). See log for details."
        TOTAL_EXIT_CODE=1
    fi

    # Append concise transferred-file list with timestamps to the main log
    if [[ "${ENABLE_LOGGING,,}" == "true" ]]; then
        if [[ -s "$TMP_RS_OUT" ]]; then
            while IFS= read -r fname; do
                printf '%s [FILE] %s\n' "$(_ts)" "$fname" >> "$LOG_FILE"
            done <"$TMP_RS_OUT"
        else
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
      notify-send "Local Backup Script: Success — $(date +%Y-%m-%d)" "All directories backed up successfully."
  else
      notify-send "Local Backup Script Finished with Errors - $(date +%Y-%m-%d)" "Check $DESKTOP_LOG for details."
  fi
fi

exit $TOTAL_EXIT_CODE
