# Moonkey

Keyboard backlight control for T2 MacBooks that have lost their display lid or its sensors.

## Why

On T2 MacBooks, macOS only drives the keyboard backlight while the ambient light sensor in the display lid is present. If the lid has been removed (a "headless" MacBook running from an external display), or the sensor or camera board is broken or disconnected, the backlight stays dark for good:

- the brightness keys do nothing,
- *Adjust keyboard brightness in low light* has no effect,
- private API tools such as `KeyboardBrightnessClient` report `-1`.

The backlight hardware itself still works. Moonkey talks to it directly through the T2 chip, bypassing macOS's brightness service (`corebrightnessd`), and gives you controls for it.

## Features

- **Touch Bar:** a Control Strip button that opens a brightness slider, styled like the system volume control.
- **Menu bar:** an icon whose dropdown holds a brightness slider, styled like a Control Center section. Shown by default on Macs without a Touch Bar.
- **Command line:** `moonkey 60`, `moonkey off`, `moonkey up`, …
- **Persistent:** the setting is restored at boot (before anyone logs in) and after every wake.
- **All users:** one shared setting; every account on the Mac gets the controls.

## Requirements

- An Intel MacBook with a T2 chip whose keyboard backlight is on the T2's *Touch Bar Backlight* device (see [How it works](#how-it-works) to check). Tested on a 16-inch 2019 MacBook Pro (MacBookPro16,1) with macOS 15; other Touch Bar models (2018–2020) are expected to work.
- Xcode Command Line Tools (`xcode-select --install`).
- An administrator account to install.

On other Macs the CLI and the app report that the backlight device wasn't found, and the restore daemon exits.

## Install

```sh
git clone https://github.com/simon-lumikello/moonkey.git
cd moonkey
make
sudo make install
```

For the Touch Bar button to appear, the Touch Bar must show the Control Strip: *System Settings → Keyboard → Touch Bar Settings → Show Control Strip*.

## Usage

**Touch Bar:** tap the light icon in the Control Strip. A brightness slider opens next to it, like the system volume control. Slide to the far left to turn the light off; ✕ closes the slider.

**Menu bar:** click the light icon and use the *Keyboard Brightness* slider, or *Backlight On* to switch it on and off.

**Command line:**

```
moonkey               show the current state, e.g. "on 60"
moonkey <0-100>       set brightness (0 turns it off)
moonkey up | down     step by 10%
moonkey on | off | toggle
moonkey restore       re-apply the saved setting
```

To use the brightness keys, bind `moonkey up` and `moonkey down` to shortcuts with a hotkey tool such as Shortcuts, skhd or BetterTouchTool.

### Choosing the controls

Each user can override which controls appear; changes apply immediately:

```sh
defaults write io.github.simon-lumikello.moonkey ShowMenuBarIcon -bool YES    # or NO
defaults write io.github.simon-lumikello.moonkey ShowTouchBarButton -bool NO  # or YES
defaults delete io.github.simon-lumikello.moonkey                            # back to defaults
```

## Uninstall

```sh
sudo make uninstall
```

## How it works

The keyboard backlight is a vendor HID interface on the T2's *Touch Bar Backlight* USB device (vendor `0x05ac`, product `0x8102`, usage page `0xFF00`, usage `0x0F`). With the light sensor gone, macOS attaches no driver to it, but the interface still accepts feature reports from user space:

| Report | Payload | Meaning |
|---|---|---|
| `0x01` | `u32` level (100–14660), `u32` fade ms | brightness |
| `0x03` | `u8` 0/1, `u32` fade ms | power |

To check that your Mac has the device:

```sh
hidutil list | grep -i '0x8102.*65280.*15'
```

Installed files:

| Path | Purpose |
|---|---|
| `/usr/local/bin/moonkey` | CLI; also runs as the restore daemon |
| `/Applications/Moonkey.app` | Touch Bar and menu bar controls |
| `/Library/LaunchDaemons/io.github.simon-lumikello.moonkey.daemon.plist` | restores the setting at boot and after wake (root) |
| `/Library/LaunchAgents/io.github.simon-lumikello.moonkey.agent.plist` | starts Moonkey.app for each user at login |
| `/Library/Application Support/Moonkey/state` | shared setting, e.g. `60 1` (level, on); writable by all users |

## Adding support for another Mac

Moonkey only ships code that has been tested on real hardware. If your MacBook isn't supported, you (or a coding agent working for you) can add it by following these steps. Agents: read this whole section before changing any code, and follow it in order.

### 1. Collect evidence

Run these on the unsupported Mac and keep the output; it goes into the pull request:

```sh
sysctl -n hw.model                                   # e.g. MacBookAir9,1
sw_vers -productVersion
hidutil list | awk 'NR<=2 || /0x5ac/'                # Apple HID devices and their usages
ioreg -r -c IOHIDInterface -d 1 -l -w0 | grep -E '"(Product|VendorID|PrimaryUsagePage|PrimaryUsage|ReportDescriptor)"'
```

Look for an Apple interface with a vendor usage page (`65280` = `0xFF00`, or similar) that has no driver, and decode its `ReportDescriptor` (any HID descriptor parser works). The backlight interface exposes feature reports for a level and usually an on/off flag. If you find `0x8102` with usage `65280`/`15`, the existing code should already work; open an issue instead.

The Linux T2 drivers ([t2linux](https://wiki.t2linux.org/), `drivers/hid/hid-apple.c`) are a good reference for how other Apple models expose the backlight. Treat them as a lead, and confirm everything on your own hardware.

### 2. Probe safely

- Read before you write: use `IOHIDDeviceGetReport` on the candidate feature reports and record what they return.
- Only send **feature** reports, only to the interface you identified, and only with report IDs and value ranges that its descriptor declares.
- Open the device without seizing it (`kIOHIDOptionsTypeNone`). Don't install kernel extensions, disable SIP or change system settings.
- Change one thing at a time. A reboot always returns the hardware to its normal state.

### 3. Implement

All hardware-specific code lives in `src/backlight.h`: `bl_open()` finds the device and `bl_apply()` drives it. The CLI, daemon, app and state file only call those two functions, so **don't change anything outside `backlight.h` to add a model**.

- When you add the second protocol, turn the existing constants into a small table of backends, each with its device-matching values, raw level range and an apply function. `bl_open()` tries the backends in order; `bl_apply()` calls the matched backend's function. Keep both public function signatures.
- The existing `0x8102` backend must keep behaving exactly as it does now.
- Document the new protocol at the top of `backlight.h` in the same format as the existing one: device, usages, report layouts, value ranges.
- Keep the style: C in the core, Objective-C only in `src/app/`, comments explaining *why*, and no new dependencies.

### 4. Test on the new Mac

All of these must pass on the real hardware:

- `make` builds with no warnings.
- `moonkey 1`, `moonkey 100`, `moonkey 0`, `moonkey on`, `moonkey up`, `moonkey down` and `moonkey toggle` each change the light as expected.
- After `sudo make install`, the setting survives a sleep/wake cycle and a reboot.
- The menu bar slider works, and so does the Touch Bar slider if the Mac has a Touch Bar.
- `sudo make uninstall` removes everything.

### 5. Open a pull request

- One model family per pull request, titled like `Add support for MacBookAir9,1`.
- In the description, include the evidence from step 1 (trimmed to the relevant interface), the decoded report layout, and which checks from step 4 you ran, on which model and macOS version.
- Say clearly that the existing `0x8102` backend wasn't re-tested on a Touch Bar Mac if you don't have one; a maintainer will check it.
- Update this README: add the model to [Requirements](#requirements) as tested, and add the new device and reports to [How it works](#how-it-works).
- Don't include untested code paths, guessed values for models you don't have, or unrelated refactors.

## Limitations

- macOS has no public API for Control Strip buttons, so the Touch Bar button uses the same private APIs as other Touch Bar customisers. A future macOS update could break it; the menu bar icon, the CLI and the restore daemon don't depend on those APIs.
- Third-party Control Center modules can't host sliders, so the menu bar icon stands in for one.
- No automatic brightness and no idle dimming: the backlight stays at the level you set.
- The built-in brightness keys still go to macOS and won't change the backlight.

## License

[MIT](LICENSE)
