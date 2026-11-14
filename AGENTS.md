# AGENTS.md

Instructions for coding agents working on Moonkey. Read [README.md](README.md) for what the project does; this file covers how to change it.

## Project map

| Path | What it is |
|---|---|
| `src/backlight.h` | The only hardware-specific code: `bl_open()` finds the backlight HID device, `bl_apply()` drives it. Also the shared state file helpers. |
| `src/moonkey.c` | CLI and the restore daemon (`moonkey daemon`, run as root by launchd). |
| `src/app/` | `Moonkey.app` (Objective-C, ARC): `MKBacklight` (model), `MKTouchBarController`, `MKMenuBarController`, `main.m` (visibility settings). |
| `resources/` | `Info.plist` and the launchd plists. |
| `scripts/` | `install.sh` / `uninstall.sh`, run through `sudo make install` / `sudo make uninstall`. |

## Build and verify

```sh
make            # must finish with no warnings (-Wall -Wextra)
make clean
```

There is no automated test suite: behaviour can only be verified on a real MacBook. Use the checklist in [README → Adding support for another Mac → Test on the new Mac](README.md#4-test-on-the-new-mac), and report exactly which checks you ran, on which model (`sysctl -n hw.model`) and macOS version.

## Hard rules

- **No untested hardware code.** Don't add device IDs, report layouts or value ranges you haven't confirmed on the hardware in front of you. Never guess support for a model you don't have.
- **Hardware specifics stay in `src/backlight.h`.** Keep the `bl_open()` / `bl_apply()` signatures; the CLI, daemon and app must not need changes to support a new model.
- **Don't break existing installs.** Keep the bundle ID and launchd labels (`io.github.simon-lumikello.moonkey.*`), the state file path and format (`<level 1-100> <on 0|1>`), and the `defaults` keys (`ShowMenuBarIcon`, `ShowTouchBarButton`).
- **Probe hardware safely**, following [README → Probe safely](README.md#2-probe-safely): read reports before writing them, send only feature reports the descriptor declares, never seize the device, and don't install kernel extensions, disable SIP or change system settings.
- **Private APIs** are confined to `MKTouchBarController.m` and must be resolved at runtime with a fallback. Don't add new ones elsewhere.
- **No new dependencies.** Plain C, Objective-C, Apple frameworks and `make` only.

## Ask the person first

Stop and ask before you:

- run `sudo make install`, `sudo make uninstall` or anything else with `sudo`;
- send HID reports while probing an unknown device;
- commit, push, or open or update a pull request.

## Adding support for another Mac

Follow [README → Adding support for another Mac](README.md#adding-support-for-another-mac) step by step: collect evidence, probe safely, implement in `backlight.h`, test on the real Mac, then prepare the pull request as described there. One model family per pull request.

## Code style

- Match the surrounding code: 4-space indentation, `bl_` prefix for C core functions, `MK` prefix for Objective-C classes, named constants instead of magic numbers.
- Comments explain *why*; document every HID report layout at the top of `backlight.h`.
- Keep commits focused and their messages descriptive (a short subject line, then what changed and why).
