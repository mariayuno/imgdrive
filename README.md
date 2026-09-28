```
██╗███╗   ███╗ ██████╗ ██████╗ ██████╗ ██╗██╗   ██╗███████╗
██║████╗ ████║██╔════╝ ██╔══██╗██╔══██╗██║██║   ██║██╔════╝
██║██╔████╔██║██║  ███╗██║  ██║██████╔╝██║██║   ██║█████╗  
██║██║╚██╔╝██║██║   ██║██║  ██║██╔══██╗██║╚██╗ ██╔╝██╔══╝  
██║██║ ╚═╝ ██║╚██████╔╝██████╔╝██║  ██║██║ ╚████╔╝ ███████╗
╚═╝╚═╝     ╚═╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝  ╚══════╝
```

<p align="center">
  <strong>Two-stage encrypted image drive manager for Android</strong><br>
  LUKS2 + F2FS local mount &nbsp;·&nbsp; raw USB export via isodrive &nbsp;·&nbsp; Magisk · KernelSU · APatch
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android-3ddc84?logo=android&logoColor=white">
  <img alt="Root" src="https://img.shields.io/badge/root-Magisk%20%7C%20KernelSU%20%7C%20APatch-black">
  <img alt="License" src="https://img.shields.io/badge/license-GPL--3.0-blue">
<!-- VERSION_BADGE_START -->
<img alt="Version" src="https://img.shields.io/badge/version-v3.6-7c3aed?style=flat-square&logo=github&logoColor=white">
<!-- VERSION_BADGE_END -->
</p>

---

## What is imgdrive?

imgdrive manages a single encrypted image file as a **switchable two-stage drive**. At any moment the image is either:

- **Stage 1 — local mount:** decrypted and accessible as a normal folder in Android shared storage (`/storage/emulated/0/…`), readable and writable by any file manager.
- **Stage 2 — USB export:** the local stack is completely torn down and the raw image is exported over USB as a mass-storage device (read-write), so a PC can access it directly as a block device.

Switching between stages is one command. The module auto-mounts Stage 1 on every boot once the LUKS keyfile is readable and the image file appears on the SD card.

---

## The Stack

```
SD card physical partition
  └── /mnt/media_rw/<id>/          ← outer F2FS (raw block path)
        └── image.img               ← raw 29 G image file
              └── LUKS2             ← AES-XTS-512 / Argon2id / 4096-byte sectors
                    └── F2FS        ← inner encrypted filesystem
                          │
                          │  losetup  (4 K logical sectors + direct I/O)
                          │  cryptsetup open
                          │  mount -t f2fs
                          ▼
                    /mnt/media_rw/rena       ← real root-owned mount
                          │
                          │  bindfs  (uid/gid 1023, perms 0770)
                          ▼
                    /data/media/0/rena       ← Android media_rw view
                          │
                          │  Android emulated storage
                          ▼
               /storage/emulated/0/rena      ← what your file manager sees
```

For USB export (Stage 2) the local stack is fully torn down and replaced with:

```
image.img  →  isodrive -rw  →  USB gadget LUN  →  PC block device
```

---

## Requirements

| Requirement | Notes |
|---|---|
| Magisk ≥ 20400, KernelSU, or APatch | Any modern root solution works |
| [Termux](https://termux.dev) | Must be installed before use |
| Termux: `cryptsetup` | `pkg install cryptsetup` |
| Termux: `util-linux` | provides `losetup` and `nsenter` — `pkg install util-linux` |
| Termux: `bindfs` | `pkg install bindfs` |
| [isodrive](https://github.com/nitanmarcel/isodrive-magisk) | bundled — no separate install needed |

> **Why Termux `losetup` and not the system one?**  
> Android's `/system/bin/losetup` is a Toybox symlink that lacks `--sector-size` and `--direct-io` flags. These flags are **required** on Android 6.6 kernels with F2FS-backed images — without them every read through the loop device returns `EIO`. Termux's `util-linux` build exposes the full option set.

---

## Installation

<!-- INSTALL_ONELINER_START -->
<table>
<tr>
<td valign="top" width="70%">

### One-liner(Just run it in a root shell)

> Downloads the current release and installs it directly.

**KernelSU / APatch**

```sh
curl -Lo /tmp/imgdrive.zip https://github.com/rexackermann/imgdrive/releases/download/v3.6/imgdrive-v3.6.zip && /data/adb/ksud module install /tmp/imgdrive.zip
```

**Magisk**

```sh
curl -Lo /tmp/imgdrive.zip https://github.com/rexackermann/imgdrive/releases/download/v3.6/imgdrive-v3.6.zip && magisk --install-module /tmp/imgdrive.zip
```

**APatch**

```sh
curl -Lo /tmp/imgdrive.zip https://github.com/rexackermann/imgdrive/releases/download/v3.6/imgdrive-v3.6.zip && /data/adb/apd module install /tmp/imgdrive.zip
```

</td>
<td valign="top" align="right" width="30%">

<p align="right">
<img alt="Version" src="https://img.shields.io/badge/v3.6-7c3aed?style=for-the-badge&logo=github&logoColor=white"><br>
<img alt="Package" src="https://img.shields.io/badge/package-imgdrive-v3.6.zip-2563eb?style=for-the-badge&logo=files&logoColor=white"><br>
<img alt="Version Code" src="https://img.shields.io/badge/version%20code-27-0891b2?style=for-the-badge">
</p>

</td>
</tr>
</table>

<!-- INSTALL_ONELINER_END -->

---

> [!CAUTION]
> **The WebUI is experimental and not recommended for regular use.**
>
> The web interface (`http://localhost:…`) is provided for diagnostic visibility only. It has limited error handling, no confirmation dialogs for destructive actions, and its shell execution path depends on root API availability that may silently degrade. **Configure and operate imgdrive exclusively through the config file and `imgdrive-ctl` commands.** Do not rely on the WebUI for setup, mounting, or key management on a drive containing data you care about.

---

## Getting Started

**1. Install Termux dependencies**

Open Termux and run:

```sh
pkg install cryptsetup util-linux bindfs f2fs-tools
```

**2. Reboot**

After installing the module and rebooting, imgdrive writes a default config on first boot at:

```
/sdcard/Documents/imgdrive/imgdrive.conf
```

**3. Edit the config**

Open the config in any text editor and set at minimum:

```sh
IMAGE_REAL="/data/media/0/imgdrive/drive.img"   # path to your image file
KEYFILE="/sdcard/Documents/imgdrive/imgdrive.key" # path to your LUKS keyfile
NAME="drive"                                       # name for the dm-crypt mapper
INNER_FS="f2fs"                                    # f2fs or ext4 — must match what you format with
```

See the full [Configuration](#configuration) section for all options.

**4. Create the encrypted drive**

In a root shell (Termux with `su`):

```sh
imgdrive-ctl setup 10G   # replace 10G with your desired size
```

This generates the keyfile, allocates the image, formats LUKS2, and formats the inner filesystem. It will refuse to run if the image already exists.

**5. Mount**

```sh
imgdrive-ctl mount
```

Your drive appears at `/storage/emulated/0/<NAME>` in any file manager.

**6. Toggle between local and USB**

```sh
imgdrive-ctl toggle   # Stage 1 ↔ Stage 2
```

Or tap the **Action** button in Magisk / KernelSU — it runs `toggle` and prints the old and new state.

From here on, **the drive auto-mounts at every boot** once internal storage is decrypted (no interaction needed).

---

## Configuration

`imgdrive.conf` is a plain shell-sourced file. It is written once on first boot and **never overwritten** by module updates.

```sh
# /sdcard/Documents/imgdrive/imgdrive.conf

# Path to image on the raw SD block mount (NOT /storage/emulated/0/...)
IMAGE_REAL=/mnt/media_rw/<your-sd-uuid>/yourimage.img

# Android-facing path to the same image (used by isodrive for USB export)
IMAGE_USB=/storage/emulated/0/ext/sdcard/yourimage.img

# LUKS keyfile (must be on internal storage, available before SD)
KEYFILE=/data/adb/yourkey

# dm-crypt device name → /dev/mapper/<NAME>
NAME=imgdrive

# Where the decrypted F2FS is mounted (real mount, not the public view)
REAL_MOUNT=/mnt/media_rw/imgdrive

# bindfs target (Android media_rw layer)
USER_VIEW=/data/media/0/imgdrive

# What the user actually sees in a file manager
PUBLIC_VIEW=/storage/emulated/0/imgdrive

# bindfs ownership (1023 = Android media_rw)
BIND_UID=1023
BIND_GID=1023

# bindfs permission mask
BIND_PERMS=0770

# Set to 0 to disable auto-mount on boot
AUTO_MOUNT=1

# Full paths to Termux binaries
CRYPTSETUP_BIN=/data/data/com.termux/files/usr/bin/cryptsetup
LOSETUP_BIN=/data/data/com.termux/files/usr/bin/losetup
BINDFS_BIN=/data/data/com.termux/files/usr/bin/bindfs
NSENTER_BIN=/data/data/com.termux/files/usr/bin/nsenter
ISODRIVE_BIN=/system/bin/isodrive
```

> **IMAGE_REAL vs IMAGE_USB:** These are two names for the same file. The loop device for local use **must** point at the raw block path (`/mnt/media_rw/…`) to avoid a FUSE-over-FUSE situation that causes `EIO`. `isodrive` for USB export **must** use the Android-facing path because that is what the gadget layer expects.

---

## Commands

`imgdrive-ctl` is available as `/system/bin/imgdrive-ctl` (system overlay) and `/data/adb/imgdrive/bin/imgdrive-ctl`.

```sh
imgdrive-ctl status      # show current state (Stage 1 / Stage 2 / BROKEN / OFF)
imgdrive-ctl mount       # ensure Stage 1 (idempotent — safe to run when already mounted)
imgdrive-ctl usb         # switch to Stage 2 (USB export, requires cable)
imgdrive-ctl toggle      # Stage 1 → Stage 2, or Stage 2 → Stage 1
imgdrive-ctl sync        # USB connected → Stage 2; USB absent → Stage 1
imgdrive-ctl off         # tear down everything cleanly
imgdrive-ctl -v status   # verbose — prints every invariant check
```

All commands are **idempotent**: running `mount` when already mounted is safe, running `usb` when already exporting is safe, etc.

---

## State Machine

imgdrive is invariant-based. The current state is not determined by a stored flag — it is determined by checking the actual system state on every call.

```
                      ┌─────────────┐
                      │  imgdrive   │
                      └──────┬──────┘
                             │
                   ┌─────────▼─────────┐
                   │   detect state    │
                   └─────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ▼              ▼              ▼
           STAGE 1        STAGE 2        BROKEN
              │              │              │
              │              │       ┌──────┴──────┐
              │              │       │             │
              │              │   USB yes       USB no
              │              │       │             │
              │              │       ▼             ▼
              │              │   repair S2     repair S1
              │              │
       toggle │              │ toggle
              │              │
              ▼              ▼
           Stage 2        Stage 1
```

### Stage 1 invariants (all must be true)

| # | Check |
|---|---|
| 1 | USB/isodrive export is not active |
| 2 | `/dev/mapper/<NAME>` is active and read-write |
| 3 | Mapper is backed by the correct image loop |
| 4 | Loop backing file is exactly `IMAGE_REAL` |
| 5 | Loop logical sector size is 4096 |
| 6 | Loop direct I/O is enabled |
| 7 | Loop is read-write |
| 8 | Inner F2FS is mounted read-write at `REAL_MOUNT` |
| 9 | bindfs view exists at `USER_VIEW` with source `REAL_MOUNT` |
| 10 | bindfs presents uid/gid 1023 and perms 0770 |
| 11 | `PUBLIC_VIEW` exists as the Android-facing path |

### Stage 2 invariants (all must be true)

| # | Check |
|---|---|
| 1 | USB is available |
| 2 | isodrive is active and exporting the expected image |
| 3 | `/dev/mapper/<NAME>` is absent |
| 4 | `REAL_MOUNT` is not mounted |
| 5 | bindfs view is absent |
| 6 | Image loop is detached |

Anything else is `BROKEN`. Recovery is automatic on the next `mount`, `usb`, `toggle`, or `sync` call.

---

## Boot Behaviour

`service.sh` runs as a late-start service after every boot:

```
boot
  │
  ├─ wait for post-fs-data sentinel (up to 30 s)
  │
  ├─ wait for /sdcard/Documents to appear (up to 60 s)
  │
  ├─ if config missing → write default config
  │
  ├─ load and validate config
  │
  ├─ if AUTO_MOUNT=0 → exit
  │
  ├─ poll every 10 s for KEYFILE to become readable
  │    (signals internal storage is decrypted)
  │
  └─ poll every 10 s for IMAGE_REAL to appear (up to 30 min)
       → on success: imgdrive-ctl mount → exit 0
       → on timeout: exit 1
```

Logs are written to `/data/adb/imgdrive/log/service.log` (last 200 lines kept).

---

## USB Workflow

### Phone → expose image to PC

```sh
imgdrive-ctl usb
```

On the PC (Linux example):

```sh
sudo cryptsetup open --key-file ~/Documents/yourkey /dev/sda imgdrive
sudo mkdir -p /mnt/imgdrive
sudo mount -t f2fs /dev/mapper/imgdrive /mnt/imgdrive

# ... work with files ...

sudo umount /mnt/imgdrive
sudo cryptsetup close imgdrive
```

Then on the phone to resume local access:

```sh
imgdrive-ctl mount
```

---

## Creating an Image (reference)

This is what was used to create the image this module manages. Adapt paths and sizes to your setup.

**On the PC (Fedora / any Linux with cryptsetup + f2fs-tools):**

```sh
# Prepare the SD card
sudo wipefs -a /dev/mmcblk0
sudo sgdisk -n 1:0:0 -t 1:0700 -c 1:"imgdrive" /dev/mmcblk0
sudo mkfs.f2fs -l imgdrive /dev/mmcblk0p1
sudo mount -t f2fs /dev/mmcblk0p1 /mnt/sdcard

# Create the image file
sudo fallocate -l 29G /mnt/sdcard/image.img

# Format with LUKS2
sudo cryptsetup luksFormat --type luks2 \
  --cipher aes-xts-plain64 --key-size 512 \
  --hash sha256 --pbkdf argon2id --sector-size 4096 \
  --key-file ~/Documents/yourkey \
  /mnt/sdcard/image.img

# Format the inner filesystem
sudo cryptsetup open --key-file ~/Documents/yourkey /mnt/sdcard/image.img imgdrive
sudo mkfs.f2fs -l imgdrive -O extra_attr,inode_checksum,sb_checksum -f /dev/mapper/imgdrive
sudo cryptsetup close imgdrive
```

---

## Implementation Notes

These are hard-won findings from development on a MediaTek / Android 6.6 / KernelSU device. They explain why the module looks the way it does.

### The loop device EIO problem

On Android 6.6 kernels with an outer F2FS filesystem, the default `losetup` configuration produces `EIO` on every read through the loop device. This affects both Toybox and Termux `losetup` with default settings. The fix is:

```sh
losetup --sector-size 4096 --direct-io=on ...
```

Both flags are required. `--sector-size 4096` alone still produces `EIO`. Only the combination works. This is why Termux `util-linux` is a hard dependency — Toybox `losetup` does not expose these flags.

### Use the physical SD path for the loop

Use `/mnt/media_rw/<id>/image.img`, not `/storage/emulated/0/ext/sdcard/image.img`. The latter path is already a FUSE/bindfs presentation of the SD card. Backing a loop device through another FUSE layer creates unnecessary complexity and has been shown to aggravate the block I/O path.

For isodrive (USB export), the Android-facing path is fine and is in fact required.

### The cryptsetup chown warning is harmless

```
/dev/mapper/rena: chown failed: Operation not permitted
```

This always appears on LUKS open on this device. It is **not** a failure. Always verify mapper state with `cryptsetup status <name>` and check `mode: read/write`.

### mountinfo parsing

`/proc/*/mountinfo` contains variable-length optional fields before the `-` separator. Field positions are not fixed. The module searches for the `-` separator dynamically before reading the filesystem type and source device. Assuming fixed positions produces false `BROKEN` states.

### bindfs and Android shared storage

The decrypted F2FS is mounted at a root-owned path. `bindfs` provides a second view with `uid=1023 gid=1023 --perms=0770 --create-with-perms=g+s`, mounted at `/data/media/0/<name>`. Android's emulated storage layer exposes this as `/storage/emulated/0/<name>`, which is what ordinary file managers see.

The `nsenter -t 1 -m` wrapper ensures the `bindfs` mount appears in PID 1's mount namespace, where Android's storage propagation picks it up.

### Loop devices on Android

Android loop device nodes live at `/dev/block/loopN`, not `/dev/loopN`. Use `losetup -j <imagepath>` to find which loop is backing a given file rather than scanning all loop nodes on every status check. When the LUKS mapper is active, `cryptsetup status` already reports the backing loop directly.

---

## File Layout

```
/data/adb/imgdrive/
  ├── bin/
  │   ├── imgdrive-ctl        ← main control script
  │   ├── imgdrive-status     ← status helper
  │   └── write-default-conf  ← config generator
  └── log/
      └── service.log

/system/bin/                  ← module system overlay
  ├── imgdrive-ctl
  ├── imgdrive-status
  ├── write-default-conf
  └── isodrive                ← bundled, from nitanmarcel/isodrive-magisk

/sdcard/Documents/imgdrive/
  └── imgdrive.conf           ← user config (never overwritten by updates)
```

---

## Troubleshooting

**`write-default-conf not found` in service.log**  
The binaries weren't populated in `/data/adb/imgdrive/bin/`. Reflash the module — `post-fs-data.sh` now copies them from `common/` on every boot as a self-healing step.

**Status shows `BROKEN` after boot**  
Run `imgdrive-ctl -v status` to see which invariant failed. Most commonly: the SD card mounted after the boot service already gave up, or `AUTO_MOUNT=0` is set.

**File manager can see the folder but can't write**  
The lower stack is working. Check that bindfs is presenting `1023:1023` and `0770` — run `ls -ldn /data/media/0/<name>`. If the permissions look correct, the issue is above the FUSE layer and is specific to your Android version's scoped-storage enforcement.

**USB export: PC sees the device as read-only**  
Make sure you used `imgdrive-ctl usb` (which calls `isodrive -rw`) and not a manual `isodrive` call without the flag.

**Loop EIO even after install**  
Verify Termux is installed and `losetup` from `util-linux` is available at the path in your config. The system Toybox `losetup` cannot set sector size or direct I/O and will always fail on this storage configuration.

---

## Credits

The `isodrive` binary is from **[nitanmarcel/isodrive-magisk](https://github.com/nitanmarcel/isodrive-magisk)** by [Nitan Alexandru Marcel](https://github.com/nitanmarcel), licensed under GPL-3.0. This module uses the `isodrive` binary unmodified.

The bindfs-based Android LUKS mounter pattern draws from prior community work on encrypted storage on Android.

---

## Author

**Rex Ackermann** · [github.com/rexackermann](https://github.com/rexackermann)

---

## License

GPL-3.0 — see [LICENSE](LICENSE)
