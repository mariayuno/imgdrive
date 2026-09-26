#!/sbin/sh
# imgdrive customize.sh
# Sourced by Magisk/KSU/APatch installer after extraction.

# Permissions are set in update-binary; this file handles any
# root-solution-specific tweaks.

if [ -n "$KSU" ]; then
    ui_print "- KernelSU detected"
elif [ -n "$APATCH" ]; then
    ui_print "- APatch detected"
else
    ui_print "- Magisk detected"
fi

# Ensure the module service script is executable.
chmod 0755 "$MODPATH/service.sh"
chmod 0755 "$MODPATH/post-fs-data.sh"
