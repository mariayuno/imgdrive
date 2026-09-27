#!/sbin/sh
# imgdrive service.sh — late_start service hook
# Magisk / KernelSU / APatch compatible.
#
# Multi-drive: primary config at /sdcard/Documents/imgdrive/imgdrive.conf
# Additional drives in /sdcard/Documents/imgdrive/conf.d/*.conf
# Each drive gets its own background mount handler and per-drive log.

PRIMARY_CONF="/sdcard/Documents/imgdrive/imgdrive.conf"
CONFD_DIR="/sdcard/Documents/imgdrive/conf.d"
CTL="/data/adb/imgdrive/bin/imgdrive-ctl"
WRITE_CONF="/data/adb/imgdrive/bin/write-default-conf"
LOG_DIR="/data/adb/imgdrive/log"
LOGFILE="$LOG_DIR/service.log"

_log() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "$LOGFILE" 2>/dev/null; }

# Rotate shared log.
if [ -f "$LOGFILE" ]; then
    tmp="$(tail -n 200 "$LOGFILE" 2>/dev/null)"
    printf '%s\n' "$tmp" > "$LOGFILE" 2>/dev/null
fi
mkdir -p "$LOG_DIR"

_log "===== imgdrive service start ====="

# ---------------------------------------------------------------------------
# Wait for post-fs-data sentinel.
# ---------------------------------------------------------------------------
i=0
while [ ! -f /data/adb/imgdrive/.post_fs_done ] && [ "$i" -lt 30 ]; do
    sleep 1; i=$((i+1))
done

# ---------------------------------------------------------------------------
# Wait for CE storage decryption.
# ---------------------------------------------------------------------------
_log "Waiting for CE storage decryption (sys.user.0.ce_available)..."
i=0
while true; do
    ce="$(getprop sys.user.0.ce_available 2>/dev/null)"
    [ "$ce" = "1" ] || [ "$ce" = "true" ] && break
    vd="$(getprop vold.decrypt 2>/dev/null)"
    [ "$vd" = "trigger_restart_framework" ] && break
    if [ "$i" -eq 0 ]; then
        _log "CE not yet available — polling every 5 s (no timeout)"
    fi
    sleep 5; i=$((i+1))
done
_log "CE storage decrypted — proceeding"

# ---------------------------------------------------------------------------
# Wait for /sdcard to be functionally readable.
# /sdcard may be a symlink (-> /storage/self/primary) rather than a real
# mountpoint, so mountpoint -q is unreliable. FUSE can also exist as a
# directory but have a dead transport ("Transport endpoint is not connected").
# Poll with an actual ls until the filesystem responds.
# ---------------------------------------------------------------------------
_log "Waiting for /sdcard to be writable…"
i=0
while [ "$i" -lt 120 ]; do
    if touch /sdcard/.imgdrive_ready 2>/dev/null; then
        rm -f /sdcard/.imgdrive_ready 2>/dev/null
        break
    fi
    sleep 1; i=$((i+1))
done
if touch /sdcard/.imgdrive_ready 2>/dev/null; then
    rm -f /sdcard/.imgdrive_ready 2>/dev/null
    _log "/sdcard writable after ${i}s"
else
    _log "WARNING: /sdcard not writable after 120s — continuing anyway"
fi

# ---------------------------------------------------------------------------
# Repopulate primary config if missing.
# Inline the config generation (cat heredoc) so this never depends on
# write-default-conf being executable — that script had a /sbin/sh shebang
# that KSU doesn't provide. The external script is still used when available
# (it may include newer defaults), with the inline as a guaranteed fallback.
# ---------------------------------------------------------------------------
_write_default_conf() {
    dest="$1"
    conf_dir="$(dirname "$dest")"
    mkdir -p "$conf_dir" || return 1
    cat > "$dest" << CONF
# imgdrive configuration
# Edit IMAGE_REAL, KEYFILE, then run: imgdrive-ctl mount

IMAGE_REAL="/mnt/media_rw/<sdcard_id>/drive.img"
IMAGE_USB="/storage/emulated/0/ext/sdcard/drive.img"
KEYFILE="${conf_dir}/imgdrive.key"
NAME="drive"
REAL_MOUNT="/mnt/media_rw/drive"
USER_VIEW="/data/media/0/drive"
PUBLIC_VIEW="/storage/emulated/0/drive"
BIND_UID=1023
BIND_GID=1023
BIND_PERMS=0770
AUTO_MOUNT=1
CRYPTSETUP_BIN="/data/data/com.termux/files/usr/bin/cryptsetup"
LOSETUP_BIN="/data/data/com.termux/files/usr/bin/losetup"
BINDFS_BIN="/data/data/com.termux/files/usr/bin/bindfs"
NSENTER_BIN="/data/data/com.termux/files/usr/bin/nsenter"
ISODRIVE_BIN="/system/bin/isodrive"
CONF
}

_repopulate_conf() {
    conf="$1"
    # Prefer the external script (may have richer defaults); fall back to inline.
    if [ -x "$WRITE_CONF" ]; then
        "$WRITE_CONF" "$conf" 2>/dev/null && \
            { _log "Default config written via write-default-conf: $conf"; return 0; }
        _log "write-default-conf failed (exit $?) — using inline fallback"
    else
        _log "write-default-conf not executable at $WRITE_CONF — using inline fallback"
    fi
    _write_default_conf "$conf" && \
        _log "Default config written (inline): $conf" || \
        _log "ERROR: inline config write also failed for $conf"
}

if [ ! -f "$PRIMARY_CONF" ]; then
    _log "Primary config not found — writing default"
    _repopulate_conf "$PRIMARY_CONF"
fi

# ---------------------------------------------------------------------------
# Background config watcher (primary conf only).
# ---------------------------------------------------------------------------
(
    while true; do
        sleep 30
        if ! touch /sdcard/.imgdrive_ready 2>/dev/null; then continue; fi
        rm -f /sdcard/.imgdrive_ready 2>/dev/null
        [ ! -f "$PRIMARY_CONF" ] || continue
        _log "Primary config missing — repopulating"
        _repopulate_conf "$PRIMARY_CONF"
    done
) &

# ---------------------------------------------------------------------------
# Per-drive mount handler — launched as a background process per conf.
# Each drive is independent: one failing doesn't block the others.
# ---------------------------------------------------------------------------
_handle_drive() {
    conf="$1"
    # Derive drive name from conf filename for per-drive log.
    base="$(basename "$conf" .conf)"
    dlog="$LOG_DIR/${base}.log"

    dlog() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" >> "$dlog" 2>/dev/null; }

    # Rotate per-drive log.
    if [ -f "$dlog" ]; then
        tmp="$(tail -n 200 "$dlog" 2>/dev/null)"
        printf '%s\n' "$tmp" > "$dlog" 2>/dev/null
    fi

    dlog "===== drive handler start: $conf ====="

    # Source config.
    AUTO_MOUNT=1; IMAGE_REAL=""; KEYFILE=""
    # shellcheck disable=SC1090
    . "$conf" 2>/dev/null

    if [ "${AUTO_MOUNT:-1}" -ne 1 ]; then
        dlog "AUTO_MOUNT=0 — skipping"
        return
    fi

    # Catch unfilled placeholders.
    case "$IMAGE_REAL" in *"<"*) dlog "IMAGE_REAL is a placeholder — skipping"; return ;; esac
    case "$KEYFILE"    in *"<"*) dlog "KEYFILE is a placeholder — skipping";    return ;; esac
    [ -n "$IMAGE_REAL" ] || { dlog "IMAGE_REAL empty — skipping"; return; }
    [ -n "$KEYFILE"    ] || { dlog "KEYFILE empty — skipping";    return; }

    # Wait for keyfile.
    dlog "Waiting for keyfile: $KEYFILE"
    while [ ! -r "$KEYFILE" ]; do sleep 10; done
    dlog "Keyfile visible"

    # Mount loop (30-minute window).
    DEADLINE=$(( $(date +%s) + 1800 ))
    while [ "$(date +%s)" -lt "$DEADLINE" ]; do
        if [ ! -f "$IMAGE_REAL" ]; then
            dlog "Image not found yet: $IMAGE_REAL"
            sleep 10; continue
        fi
        dlog "Attempting Stage 1 mount"
        if "$CTL" -c "$conf" mount >> "$dlog" 2>&1; then
            dlog "Stage 1 mount SUCCESS"; return
        fi
        dlog "Mount attempt failed — retrying in 10 s"
        sleep 10
    done
    dlog "Mount timed out after 30 minutes"
}

# ---------------------------------------------------------------------------
# Launch handler for primary conf + all conf.d/*.conf
# ---------------------------------------------------------------------------
if [ -f "$PRIMARY_CONF" ]; then
    _log "Launching handler: $PRIMARY_CONF"
    _handle_drive "$PRIMARY_CONF" &
fi

mkdir -p "$CONFD_DIR"
for extra_conf in "$CONFD_DIR"/*.conf; do
    [ -f "$extra_conf" ] || continue
    _log "Launching handler: $extra_conf"
    _handle_drive "$extra_conf" &
done

wait
