## v3.9

- feat: inotify block watcher for SD card remount (PHASE 4) (d3faff9)

## v3.8

- fix: simplify service.sh — block until CE+FUSE ready, then poll 30min for all deps (390f467)

## v3.7

- Update KernelSU reference to SuKisu in workflow (83ffba0)

## v3.6

- fix: use mkdir probe for /sdcard write-ready check (7411fe5)

## v3.5

- Minor update

## v3.4

- fix: abort setup if image exists, fix log wiped on fast poll (12d994a)

## v3.3

- fix: configurable inner filesystem (INNER_FS/MKFS_BIN), fix termux mkfs path, improve WebUI size picker (0039e1c)

## v3.2

- refactor+perf: delegate setupStorage to CLI, periodic deep refresh (1f550c3)

## v3.1

- perf+safety: fast polling, op locks, no-overwrite config, setup lock (f59c276)

## v3.0

- Refactor imgdrive-status script for clarity (4606166)

## v2.9

- Update main.yml (ba87cd7)

## v2.8

- Add Installation section to README (5b23695)

## v2.7

- Update README with installation instructions for v2.6 (003f146)
- Update version badge in README.md (1341953)
- Update version badge in README.md to v2.6 (aceb195)
- Change badge style from for-the-badge to flat-square (f4a0adc)
- Change version badge style to flat-square (aefdc74)
- Change version badge style in README (c90c5d6)
- Enhance README generation and validation in workflow (a5a7a52)

## v2.6

- Update README with installation and configuration info (90e8928)
- Fix README markers and update version checks (150e176)
- Enhance version bumping and README generation (67715cc)

## v2.5

- fix: remove duplicate closing brace in _log_tail() (b21eb8f)

## v2.4

- docs: versioned one-liner URLs, auto-updated by release workflow (89999dd)
- docs: add one-liner install commands with auto-update markers (e9c6d2f)

## v2.3

- fix: JSON log escaping, no-placeholder defaults, CLI for keys/setup/drives (c6ef348)

## v2.2

- Create main.yml (0079d31)
- chore: exclude workflows (no workflow scope) (05a95a5)
- fix+debug: /sdcard write probe, verbose stage logging (95c63c0)

## v2.1

- Add GitHub Actions workflow for automated releases (36a71e9)
- fix: /sbin/sh shebang breaks on KSU; mountpoint -q fails on symlinked /sdcard (22ef32f)
- chore: exclude workflow files (no workflow scope on token) (cf8de08)
- feat: multi-drive support, key management WebUI, -c flag for ctl/status (4035b34)

## v2.0

- Refactor GitHub Actions workflow for release process (0d573ff)
- Simplify version bumping in GitHub Actions workflow (2fdb4f2)

# Changelog

## v1.4

- fix: status always shows in web UI; fix f2fs mount detection
- fix: persistent config repopulation in service.sh and imgdrive-ctl
- fix: wait for /sdcard mountpoint before writing default config

## v1.3

- Initial public release
- Refactor release workflow for versioning and metadata
