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
