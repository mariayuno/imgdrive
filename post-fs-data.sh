#!/sbin/sh
# imgdrive post-fs-data
# Runs early in boot; /sdcard is NOT available here.

MODDIR="${0%/*}"
INSTALL_DIR="/data/adb/imgdrive/bin"

mkdir -p "$INSTALL_DIR"
mkdir -p /data/adb/imgdrive/log

# Ensure binaries are always present in the data path
for bin in imgdrive-ctl imgdrive-status write-default-conf; do
    src="$MODDIR/common/$bin"
    dst="$INSTALL_DIR/$bin"
    if [ -f "$src" ] && { [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; }; then
        cp -f "$src" "$dst"
        chmod 0755 "$dst"
    fi
done

# Write a sentinel so service.sh knows post-fs-data ran.
touch /data/adb/imgdrive/.post_fs_done
