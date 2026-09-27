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
_logv "PATH=$PATH"
_logv "KSU=${KSU:-}  APATCH=${APATCH:-}  MAGISK_VER=${MAGISK_VER:-}"

# ---------------------------------------------------------------------------
# STAGE 0: post-fs-data sentinel
# ---------------------------------------------------------------------------
_sep "STAGE 0: post-fs-data sentinel"
SENTINEL="/data/adb/imgdrive/.post_fs_done"
_logv "Waiting for sentinel: $SENTINEL"
i=0
while [ ! -f "$SENTINEL" ] && [ "$i" -lt 30 ]; do
    _logv "  attempt $i/30: not found yet"; sleep 1; i=$((i+1))
done
if [ -f "$SENTINEL" ]; then
    _log "Sentinel found after ${i}s"
else
    _log "WARNING: sentinel never appeared — continuing anyway"
fi

# ---------------------------------------------------------------------------
# STAGE 1: CE storage decryption
# ---------------------------------------------------------------------------
_sep "STAGE 1: CE storage decryption"
_logv "Polling sys.user.0.ce_available / vold.decrypt every 5s (no timeout)"
i=0
while true; do
    ce="$(getprop sys.user.0.ce_available 2>/dev/null)"
    vd="$(getprop vold.decrypt 2>/dev/null)"
    _logv "  attempt $i: ce_available='$ce'  vold.decrypt='$vd'"
    [ "$ce" = "1" ] || [ "$ce" = "true" ] && { _log "CE available via sys.user.0.ce_available='$ce' after $i polls"; break; }
    [ "$vd" = "trigger_restart_framework" ]  && { _log "CE available via vold.decrypt='$vd' after $i polls"; break; }
    sleep 5; i=$((i+1))
done

# ---------------------------------------------------------------------------
# STAGE 2: /sdcard write-ready
# ---------------------------------------------------------------------------
_sep "STAGE 2: /sdcard write-ready"
_logv "Probing /sdcard write access every 1s (max 120s)"
_logv "  /sdcard symlink: $(ls -ld /sdcard 2>&1)"
_logv "  /storage/self/primary: $(ls -ld /storage/self/primary 2>&1)"
_logv "  mountpoint -q /sdcard: $(mountpoint -q /sdcard 2>/dev/null && echo YES || echo NO)"
_logv "  /proc/mounts sdcard line: $(grep sdcard /proc/mounts 2>/dev/null | head -3 || echo '(none)')"
_logv "  /proc/mounts emulated line: $(grep emulated /proc/mounts 2>/dev/null | head -3 || echo '(none)')"

PROBE="/sdcard/.imgdrive_probe_$$"
i=0
while [ "$i" -lt 120 ]; do
    result="$(touch "$PROBE" 2>&1)"; rc=$?
    _logv "  write probe attempt $i/120: exit=$rc ${result:+err='$result'}"
    if [ "$rc" -eq 0 ]; then
        rm -f "$PROBE" 2>/dev/null
        _log "/sdcard writable after ${i}s"
        break
    fi
    sleep 1; i=$((i+1))
done
if [ "$i" -ge 120 ]; then
    _log "WARNING: /sdcard not writable after 120s"
    _logv "  Final /proc/mounts: $(cat /proc/mounts 2>/dev/null | grep -E 'sdcard|emulated|fuse|media' || echo '(none)')"
fi
# Post-success diagnostics
_logv "  Post-probe /sdcard stat: $(stat /sdcard 2>&1)"
_logv "  /sdcard contents: $(ls /sdcard 2>&1 | head -5)"

# ---------------------------------------------------------------------------
# STAGE 3: write-default-conf binary check
# ---------------------------------------------------------------------------
_sep "STAGE 3: write-default-conf binary"
_logv "  Path: $WRITE_CONF"
if [ -e "$WRITE_CONF" ]; then
    _logv "  exists: YES"
    _logv "  ls -l: $(ls -l "$WRITE_CONF" 2>&1)"
    _logv "  executable: $([ -x "$WRITE_CONF" ] && echo YES || echo NO)"
    _logv "  shebang: $(head -1 "$WRITE_CONF" 2>/dev/null)"
    _logv "  shebang binary exists: $(head -1 "$WRITE_CONF" 2>/dev/null | sed 's/^#!//' | awk '{print $1}' | xargs -I{} sh -c '[ -e "{}" ] && echo YES || echo NO' 2>/dev/null)"
    _logv "  file type: $(file "$WRITE_CONF" 2>/dev/null || echo 'file cmd unavailable')"
else
    _log "  EXISTS: NO — post-fs-data may not have copied it"
    _logv "  /data/adb/imgdrive/bin contents: $(ls -la /data/adb/imgdrive/bin/ 2>&1)"
fi

# ---------------------------------------------------------------------------
# Config write helpers
# ---------------------------------------------------------------------------
_write_default_conf_inline() {
    dest="$1"; conf_dir="$(dirname "$dest")"
    _logv "  inline: mkdir -p '$conf_dir'"
    mkdir_out="$(mkdir -p "$conf_dir" 2>&1)"; mkdir_rc=$?
    _logv "  inline: mkdir exit=$mkdir_rc ${mkdir_out:+out='$mkdir_out'}"
    [ "$mkdir_rc" -ne 0 ] && return 1
    _logv "  inline: writing heredoc to '$dest'"
    cat > "$dest" << CONF
# imgdrive configuration — auto-generated default
# Defaults use internal storage — works out of the box.
# Run: imgdrive-ctl setup 10G   (or use WebUI → Create Encrypted Drive)

IMAGE_REAL="/data/media/0/imgdrive/drive.img"
IMAGE_USB="/storage/emulated/0/imgdrive/drive.img"
KEYFILE="$(dirname "$dest")/imgdrive.key"
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
    cat_rc=$?
    _logv "  inline: cat exit=$cat_rc"
    return $cat_rc
}

_repopulate_conf() {
    conf="$1"
    _logv "  _repopulate_conf: target='$conf'"
    if [ -x "$WRITE_CONF" ]; then
        _logv "  trying external write-default-conf…"
        ext_out="$("$WRITE_CONF" "$conf" 2>&1)"; ext_rc=$?
        _logv "  external exit=$ext_rc out='$ext_out'"
        if [ "$ext_rc" -eq 0 ] && [ -f "$conf" ]; then
            _log "Config written via write-default-conf: $conf"; return 0
        fi
        _log "write-default-conf failed (exit $ext_rc) — trying inline fallback"
    else
        _log "write-default-conf not executable — trying inline fallback"
    fi
    _write_default_conf_inline "$conf"; inline_rc=$?
    _logv "  inline fallback exit=$inline_rc  file_exists=$([ -f "$conf" ] && echo YES || echo NO)"
    if [ "$inline_rc" -eq 0 ] && [ -f "$conf" ]; then
        _log "Config written via inline fallback: $conf"; return 0
    fi
    _log "ERROR: both methods failed for $conf"
    # Last-resort diagnostics
    _logv "  df /sdcard: $(df /sdcard 2>&1)"
    _logv "  /sdcard perms: $(ls -ld /sdcard 2>&1)"
    _logv "  /sdcard/Documents perms: $(ls -ld /sdcard/Documents 2>&1)"
    _logv "  /sdcard/Documents/imgdrive perms: $(ls -ld /sdcard/Documents/imgdrive 2>&1)"
    return 1
}

# ---------------------------------------------------------------------------
# STAGE 4: primary config
# ---------------------------------------------------------------------------
_sep "STAGE 4: primary config"
if [ ! -f "$PRIMARY_CONF" ]; then
    _log "Primary config absent — writing default"
    _repopulate_conf "$PRIMARY_CONF"
else
    _log "Primary config present: $PRIMARY_CONF"
    _logv "  first 5 lines: $(head -5 "$PRIMARY_CONF" 2>/dev/null)"
fi

# Background config watcher
(
    while true; do
        sleep 30
        PROBE2="/sdcard/.imgdrive_probe_watcher"
        touch "$PROBE2" 2>/dev/null && rm -f "$PROBE2" 2>/dev/null || continue
        [ ! -f "$PRIMARY_CONF" ] || continue
        _log "Config missing (watcher) — repopulating"
        _repopulate_conf "$PRIMARY_CONF"
    done
) &

# ---------------------------------------------------------------------------
# STAGE 5: per-drive mount handlers
# ---------------------------------------------------------------------------
_sep "STAGE 5: per-drive mount handlers"

_handle_drive() {
    conf="$1"
    base="$(basename "$conf" .conf)"
    dlog="$LOG_DIR/${base}.log"
    mkdir -p "$LOG_DIR"
    if [ -f "$dlog" ]; then
        tmp="$(tail -n 200 "$dlog" 2>/dev/null)"; printf '%s\n' "$tmp" > "$dlog" 2>/dev/null
    fi

    dl()  { printf '%s %s\n'       "$(date '+%H:%M:%S')" "$*"      >> "$dlog" 2>/dev/null; }
    dlv() { printf '%s   [v] %s\n' "$(date '+%H:%M:%S')" "$*"      >> "$dlog" 2>/dev/null; }

    dl  "===== drive handler: $conf ====="
    dlv "AUTO_MOUNT/IMAGE_REAL/KEYFILE pre-source: unset"

    AUTO_MOUNT=1; IMAGE_REAL=""; KEYFILE=""
    # shellcheck disable=SC1090
    . "$conf" 2>/dev/null
    dlv "Post-source: AUTO_MOUNT='$AUTO_MOUNT' IMAGE_REAL='$IMAGE_REAL' KEYFILE='$KEYFILE'"

    if [ "${AUTO_MOUNT:-1}" -ne 1 ]; then dl "AUTO_MOUNT=0 — skipping"; return; fi

    case "$IMAGE_REAL" in *"<"*) dl "IMAGE_REAL is placeholder — skipping"; return;; esac
    case "$KEYFILE"    in *"<"*) dl "KEYFILE is placeholder — skipping";    return;; esac
    [ -n "$IMAGE_REAL" ] || { dl "IMAGE_REAL empty — skipping"; return; }
    [ -n "$KEYFILE"    ] || { dl "KEYFILE empty — skipping";    return; }

    dl "Waiting for keyfile: $KEYFILE"
    i=0
    while [ ! -r "$KEYFILE" ]; do
        dlv "  keyfile poll $i: not readable yet ($(ls -l "$KEYFILE" 2>&1))"; sleep 10; i=$((i+1))
    done
    dl "Keyfile readable after $((i*10))s"
    dlv "  keyfile: $(ls -lh "$KEYFILE" 2>/dev/null)"

    DEADLINE=$(( $(date +%s) + 1800 ))
    attempt=0
    while [ "$(date +%s)" -lt "$DEADLINE" ]; do
        attempt=$((attempt+1))
        if [ ! -f "$IMAGE_REAL" ]; then
            dlv "  mount attempt $attempt: image not found at $IMAGE_REAL"; sleep 10; continue
        fi
        dlv "  mount attempt $attempt: image found ($(ls -lh "$IMAGE_REAL" 2>/dev/null | awk '{print $5}'))"
        dl "Attempting mount (attempt $attempt)"
        mount_out="$("$CTL" -c "$conf" mount 2>&1)"; mount_rc=$?
        dlv "  imgdrive-ctl exit=$mount_rc"
        printf '%s\n' "$mount_out" | while IFS= read -r line; do dlv "    ctl> $line"; done
        if [ "$mount_rc" -eq 0 ]; then dl "Mount SUCCESS (attempt $attempt)"; return; fi
        dl "Mount failed (attempt $attempt, exit $mount_rc) — retry in 10s"
        sleep 10
    done
    dl "Mount timed out after 30 min"
}

if [ -f "$PRIMARY_CONF" ]; then
    _log "Launching handler: $PRIMARY_CONF"
    _handle_drive "$PRIMARY_CONF" &
else
    _log "Primary config still absent — no handler launched"
fi

mkdir -p "$CONFD_DIR"
for extra_conf in "$CONFD_DIR"/*.conf; do
    [ -f "$extra_conf" ] || continue
    _log "Launching handler: $extra_conf"
    _handle_drive "$extra_conf" &
done

_sep "service.sh complete — handlers running in background"
wait
