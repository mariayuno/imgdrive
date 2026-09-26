#!/sbin/sh
# imgdrive service.sh — late_start service hook
# Magisk / KernelSU / APatch compatible.

LOGFILE="/data/adb/imgdrive/log/service.log"
CONF_FILE="/sdcard/Documents/imgdrive/imgdrive.conf"
CTL="/data/adb/imgdrive/bin/imgdrive-ctl"
WRITE_CONF="/data/adb/imgdrive/bin/write-default-conf"

_log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOGFILE" 2>/dev/null; }

# Rotate log: keep last 200 lines.
if [ -f "$LOGFILE" ]; then
    tmp="$(tail -n 200 "$LOGFILE" 2>/dev/null)"
    printf '%s\n' "$tmp" > "$LOGFILE" 2>/dev/null
fi

_log "===== imgdrive service start ====="

# ---------------------------------------------------------------------------
# Wait for post-fs-data sentinel.
# ---------------------------------------------------------------------------
i=0
while [ ! -f /data/adb/imgdrive/.post_fs_done ] && [ "$i" -lt 30 ]; do
    sleep 1; i=$((i+1))
done

# ---------------------------------------------------------------------------
# Wait for /sdcard to become available (emulated storage may mount late).
# Poll up to 60 seconds.
# ---------------------------------------------------------------------------
i=0
while [ ! -d /sdcard/Documents ] && [ "$i" -lt 60 ]; do
    sleep 1; i=$((i+1))
done

# ---------------------------------------------------------------------------
# Repopulate config if missing.
# ---------------------------------------------------------------------------
if [ ! -f "$CONF_FILE" ]; then
    _log "Config not found — writing default: $CONF_FILE"
    if [ -x "$WRITE_CONF" ]; then
        "$WRITE_CONF" "$CONF_FILE" && \
            _log "Default config written — edit $CONF_FILE and run imgdrive-ctl mount" || \
            _log "Failed to write default config"
    else
        _log "write-default-conf not found at $WRITE_CONF"
    fi
    # A freshly written default config has placeholder values;
    # auto-mount will correctly bail out at the validation step.
fi

# ---------------------------------------------------------------------------
# Load config.
# ---------------------------------------------------------------------------
if [ ! -f "$CONF_FILE" ]; then
    _log "Config still absent — skipping auto-mount"
    exit 0
fi

# shellcheck disable=SC1090
. "$CONF_FILE"

AUTO_MOUNT="${AUTO_MOUNT:-1}"

if [ "$AUTO_MOUNT" -ne 1 ]; then
    _log "AUTO_MOUNT=0 — skipping"
    exit 0
fi

# ---------------------------------------------------------------------------
# Validate required config fields (catch unfilled placeholders).
# ---------------------------------------------------------------------------
for var in IMAGE_REAL KEYFILE NAME REAL_MOUNT USER_VIEW PUBLIC_VIEW \
           CRYPTSETUP_BIN LOSETUP_BIN BINDFS_BIN NSENTER_BIN ISODRIVE_BIN; do
    eval "val=\$$var"
    if [ -z "$val" ]; then
        _log "Config missing: $var — skipping auto-mount"
        exit 0
    fi
done

# Catch unfilled placeholder values.
case "$IMAGE_REAL" in
    *"<"*) _log "IMAGE_REAL still a placeholder — skipping auto-mount"; exit 0 ;;
esac
case "$KEYFILE" in
    *"<"*) _log "KEYFILE still a placeholder — skipping auto-mount"; exit 0 ;;
esac

# ---------------------------------------------------------------------------
# Phase 1: Wait for keyfile (signals storage decrypted post-boot).
# No hard timeout — must appear before we proceed.
# ---------------------------------------------------------------------------
_log "Waiting for keyfile: $KEYFILE"
while [ ! -r "$KEYFILE" ]; do
    sleep 10
done
_log "Keyfile visible"

# ---------------------------------------------------------------------------
# Phase 2: Try to mount Stage 1 for up to 30 minutes (10-second intervals).
# ---------------------------------------------------------------------------
_log "Beginning mount attempts (max 30 min, every 10 s)"

DEADLINE=$(( $(date +%s) + 1800 ))

while [ "$(date +%s)" -lt "$DEADLINE" ]; do
    if [ ! -f "$IMAGE_REAL" ]; then
        _log "Image not found yet: $IMAGE_REAL"
        sleep 10
        continue
    fi

    _log "Attempting Stage 1 mount"
    if "$CTL" mount >> "$LOGFILE" 2>&1; then
        _log "Stage 1 mount SUCCESS"
        exit 0
    fi

    _log "Mount attempt failed — retrying in 10 s"
    sleep 10
done

_log "Mount timed out after 30 minutes"
exit 1
