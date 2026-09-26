#!/sbin/sh
# imgdrive action.sh — Magisk action button
# Shown in Magisk Manager when user taps the module's action button.

CTL="/data/adb/imgdrive/bin/imgdrive-ctl"
STATUS="/data/adb/imgdrive/bin/imgdrive-status"

echo "==============================="
echo "        imgdrive control"
echo "==============================="
echo ""

# Show current state
if [ -x "$STATUS" ]; then
    raw="$("$STATUS" 2>/dev/null)"
    state="$(printf '%s' "$raw" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)"
    usb="$(  printf '%s' "$raw" | grep -o '"usb":[^,}]*'   | cut -d: -f2)"
    echo "Current state : $state"
    echo "USB connected : $usb"
    echo ""
fi

if [ ! -x "$CTL" ]; then
    echo "ERROR: imgdrive-ctl not found at $CTL"
    exit 1
fi

echo "Running: imgdrive-ctl toggle"
echo "-------------------------------"
"$CTL" toggle
echo "-------------------------------"
echo ""

# Show new state
if [ -x "$STATUS" ]; then
    raw="$("$STATUS" 2>/dev/null)"
    state="$(printf '%s' "$raw" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)"
    echo "New state : $state"
fi
