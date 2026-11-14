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

## Limitations

- macOS has no public API for Control Strip buttons, so the Touch Bar button uses the same private APIs as other Touch Bar customisers. A future macOS update could break it; the menu bar icon, the CLI and the restore daemon don't depend on those APIs.
- Third-party Control Center modules can't host sliders, so the menu bar icon stands in for one.
- No automatic brightness and no idle dimming: the backlight stays at the level you set.
- The built-in brightness keys still go to macOS and won't change the backlight.

## License

[MIT](LICENSE)
