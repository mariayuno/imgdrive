#!/sbin/sh
# imgdrive service.sh — late_start service hook
# Magisk / KernelSU / APatch compatible.

PRIMARY_CONF="/sdcard/Documents/imgdrive/imgdrive.conf"
CONFD_DIR="/sdcard/Documents/imgdrive/conf.d"
CTL="/data/adb/imgdrive/bin/imgdrive-ctl"
WRITE_CONF="/data/adb/imgdrive/bin/write-default-conf"
LOG_DIR="/data/adb/imgdrive/log"
LOGFILE="$LOG_DIR/service.log"

mkdir -p "$LOG_DIR"

_log()  { printf '%s %s\n'        "$(date '+%H:%M:%S')" "$*"       >> "$LOGFILE" 2>/dev/null; }
_logv() { printf '%s   [v] %s\n'  "$(date '+%H:%M:%S')" "$*"       >> "$LOGFILE" 2>/dev/null; }
_sep()  { printf '%s %-60s\n'     "$(date '+%H:%M:%S')" "===== $* =====" >> "$LOGFILE" 2>/dev/null; }

# Rotate log
if [ -f "$LOGFILE" ]; then
    tmp="$(tail -n 300 "$LOGFILE" 2>/dev/null)"; printf '%s\n' "$tmp" > "$LOGFILE" 2>/dev/null
fi

_sep "imgdrive service start"
_logv "PID=$$  shell=$(readlink /proc/$$/exe 2>/dev/null || echo unknown)"
_logv "uname=$(uname -a 2>/dev/null)"
_logv "KSU=${KSU:-}  APATCH=${APATCH:-}  MAGISK_VER=${MAGISK_VER:-}"

# ---------------------------------------------------------------------------
# PHASE 1: Wait for CE decryption (no timeout — we must not proceed without it)
# ---------------------------------------------------------------------------
_sep "PHASE 1: CE decryption"
_logv "Polling sys.user.0.ce_available / vold.decrypt every 5s (no timeout)"
i=0
while true; do
    ce="$(getprop sys.user.0.ce_available 2>/dev/null)"
    vd="$(getprop vold.decrypt 2>/dev/null)"
    _logv "  poll $i: ce_available='$ce'  vold.decrypt='$vd'"
    [ "$ce" = "1" ] || [ "$ce" = "true" ] && { _log "CE ready via sys.user.0.ce_available after $i polls"; break; }
    [ "$vd" = "trigger_restart_framework" ]  && { _log "CE ready via vold.decrypt after $i polls"; break; }
    sleep 5; i=$((i+1))
done

# ---------------------------------------------------------------------------
# PHASE 2: Wait for FUSE layer (/sdcard/Documents writable) — no timeout
# ---------------------------------------------------------------------------
_sep "PHASE 2: FUSE layer ready"
_logv "Probing /sdcard/Documents write access every 2s (no timeout)"
FUSE_PROBE="/sdcard/Documents/.imgdrive_fuse_probe_$$"
i=0
while true; do
    result="$(mkdir -p "$FUSE_PROBE" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then
        rmdir "$FUSE_PROBE" 2>/dev/null
        _log "FUSE ready: /sdcard/Documents writable after ${i}s"
        break
    fi
    _logv "  fuse probe $i: exit=$rc err='$result'"
    sleep 2; i=$((i+2))
done

# ---------------------------------------------------------------------------
# PHASE 3: Mount each drive — poll for config + keyfile + image, mount, stop
# ---------------------------------------------------------------------------
_sep "PHASE 3: mount handlers"

# Write default config if absent (FUSE is confirmed ready at this point)
if [ ! -f "$PRIMARY_CONF" ]; then
    _log "Config absent — writing default"
    conf_dir="$(dirname "$PRIMARY_CONF")"
    mkdir -p "$conf_dir" 2>/dev/null
    if [ -x "$WRITE_CONF" ]; then
        out="$("$WRITE_CONF" "$PRIMARY_CONF" 2>&1)"; rc=$?
        _logv "  write-default-conf exit=$rc out='$out'"
        [ "$rc" -ne 0 ] && _log "write-default-conf failed (exit $rc) — no default config written"
    else
        _log "write-default-conf not available — no default config written"
    fi
fi

# _mount_drive: poll until config, keyfile, and image are all present,
# then mount once and exit. Times out after 30 min total.
_mount_drive() {
    conf="$1"
    base="$(basename "$conf" .conf)"
    dlog="$LOG_DIR/${base}.log"
    mkdir -p "$LOG_DIR"
    if [ -f "$dlog" ]; then
        tmp="$(tail -n 200 "$dlog" 2>/dev/null)"; printf '%s\n' "$tmp" > "$dlog" 2>/dev/null
    fi

    dl()  { printf '%s %s\n'       "$(date '+%H:%M:%S')" "$*"  >> "$dlog" 2>/dev/null; }
    dlv() { printf '%s   [v] %s\n' "$(date '+%H:%M:%S')" "$*"  >> "$dlog" 2>/dev/null; }

    dl "===== mount handler: $conf ====="

    DEADLINE=$(( $(date +%s) + 1800 ))
    attempt=0

    while [ "$(date +%s)" -lt "$DEADLINE" ]; do
        # --- config ---
        if [ ! -f "$conf" ]; then
            dlv "  poll $attempt: config not found ($conf)"; sleep 10; attempt=$((attempt+1)); continue
        fi

        # Source config fresh each iteration (it may have just appeared)
        AUTO_MOUNT=1; IMAGE_REAL=""; KEYFILE=""
        # shellcheck disable=SC1090
        . "$conf" 2>/dev/null

        if [ "${AUTO_MOUNT:-1}" -ne 1 ]; then dl "AUTO_MOUNT=0 — skipping"; return; fi
        case "$IMAGE_REAL" in *"<"*) dl "IMAGE_REAL is placeholder — skipping"; return;; esac
        case "$KEYFILE"    in *"<"*) dl "KEYFILE is placeholder — skipping";    return;; esac
        [ -n "$IMAGE_REAL" ] || { dl "IMAGE_REAL empty — skipping"; return; }
        [ -n "$KEYFILE"    ] || { dl "KEYFILE empty — skipping";    return; }

        # --- keyfile ---
        if [ ! -r "$KEYFILE" ]; then
            dlv "  poll $attempt: keyfile not readable ($KEYFILE)"; sleep 10; attempt=$((attempt+1)); continue
        fi

        # --- image ---
        if [ ! -f "$IMAGE_REAL" ]; then
            dlv "  poll $attempt: image not found ($IMAGE_REAL)"; sleep 10; attempt=$((attempt+1)); continue
        fi

        # --- all present: attempt mount ---
        attempt=$((attempt+1))
        dlv "  poll $attempt: config + keyfile + image all present — mounting"
        dl "Attempting mount"
        mount_out="$("$CTL" -c "$conf" mount 2>&1)"; mount_rc=$?
        dlv "  imgdrive-ctl exit=$mount_rc"
        printf '%s\n' "$mount_out" | while IFS= read -r line; do dlv "    ctl> $line"; done

        if [ "$mount_rc" -eq 0 ]; then
            dl "Mount SUCCESS"
            return 0
        fi

        dl "Mount failed (exit $mount_rc) — retry in 10s"
        sleep 10
    done

    dl "Timed out after 30 min — giving up"
    return 1
}

# Launch a handler for each conf file
for conf in "$PRIMARY_CONF" "$CONFD_DIR"/*.conf; do
    [ -f "$conf" ] || [ "$conf" = "$PRIMARY_CONF" ] || continue
    _log "Launching handler: $conf"
    _mount_drive "$conf" &
done

# ---------------------------------------------------------------------------
# PHASE 4: inotify block-device watcher — remount on SD card reappearance
# ---------------------------------------------------------------------------
_sep "PHASE 4: inotify block watcher"

TERMUX_BIN="/data/data/com.termux/files/usr/bin"
_INOTIFY="$TERMUX_BIN/inotifywait"
_PIDFILE="/tmp/.imgdrive_watcher.pid"

if [ ! -x "$_INOTIFY" ]; then
    _log "inotifywait not found — block watcher skipped"
else
    _log "Starting block watcher (inotifywait)"

    (
        "$_INOTIFY" -m -q -e create /dev/block 2>/dev/null | while IFS= read -r _line; do

            _dev="${_line##* }"
            case "$_dev" in mmcblk1) : ;; *) continue ;; esac

            # Ignore if a waiter is still alive
            if [ -f "$_PIDFILE" ] && kill -0 "$(cat "$_PIDFILE")" 2>/dev/null; then
                _log "block watcher: $_dev appeared but waiter still running — ignored"
                continue
            fi

            _log "block watcher: $_dev appeared — launching deferred mount"

            (
                _DEADLINE=$(( $(date +%s) + 7200 ))

                # Step 1: wait for /sdcard to be mounted before touching any paths
                while [ "$(date +%s)" -lt "$_DEADLINE" ]; do
                    mountpoint -q /sdcard 2>/dev/null && break
                    sleep 5
                done

                if ! mountpoint -q /sdcard 2>/dev/null; then
                    _log "block watcher: /sdcard never mounted — giving up"
                    rm -f "$_PIDFILE"; exit 1
                fi

                # Step 2: poll for config + image
                while [ "$(date +%s)" -lt "$_DEADLINE" ]; do
                    IMAGE_REAL=""
                    [ -f "$PRIMARY_CONF" ] && . "$PRIMARY_CONF" 2>/dev/null
                    if [ -n "$IMAGE_REAL" ] && [ -f "$IMAGE_REAL" ]; then
                        _log "block watcher: image ready ($IMAGE_REAL) — mounting"
                        "$CTL" -c "$PRIMARY_CONF" mount >> "$LOGFILE" 2>&1 \
                            && _log "block watcher: mount SUCCESS" \
                            || _log "block watcher: mount failed (exit $?)"
                        break
                    fi
                    _log "block watcher: image not ready — retry in 20s ($(( _DEADLINE - $(date +%s) ))s remaining)"
                    sleep 20
                done

                [ "$(date +%s)" -ge "$_DEADLINE" ] && _log "block watcher: timed out after 2h"
                rm -f "$_PIDFILE"
            ) &

            echo $! > "$_PIDFILE"

        done
    ) &

    _log "block watcher started (PID $!)"
fi

_sep "service.sh complete — handlers running in background"
wait
