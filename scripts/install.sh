#!/bin/zsh
# Installs Moonkey system-wide. Run via `sudo make install` (builds first).
#
#   /usr/local/bin/moonkey                          CLI and restore daemon
#   /Applications/Moonkey.app                       Touch Bar and menu bar controls
#   /Library/LaunchDaemons/<id>.daemon.plist        restore at boot and after wake (root)
#   /Library/LaunchAgents/<id>.agent.plist          Moonkey.app for every user at login
#   /Library/Application Support/Moonkey/state      shared setting, writable by all users
set -euo pipefail
cd "${0:A:h}/.."

ID=io.github.simon-lumikello.moonkey
DAEMON_PLIST=/Library/LaunchDaemons/$ID.daemon.plist
AGENT_PLIST=/Library/LaunchAgents/$ID.agent.plist
STATE_DIR="/Library/Application Support/Moonkey"

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo make install" >&2; exit 1; }
[[ -x build/moonkey && -d build/Moonkey.app ]] || { echo "Build first: make" >&2; exit 1; }

# UIDs of users with a GUI session (each runs its own loginwindow).
gui_uids() { ps -axo uid=,comm= | awk '$2 ~ /loginwindow$/ && $1 >= 500 { print $1 }' | sort -u }

# Stop a previous installation, if any.
launchctl bootout system/$ID.daemon 2>/dev/null || true
for uid in $(gui_uids); do launchctl bootout gui/$uid/$ID.agent 2>/dev/null || true; done

install -d -m 755 /usr/local/bin
install -m 755 build/moonkey /usr/local/bin/moonkey

rm -rf /Applications/Moonkey.app
ditto build/Moonkey.app /Applications/Moonkey.app
chown -R root:wheel /Applications/Moonkey.app

install -d -m 755 "$STATE_DIR"
[[ -f "$STATE_DIR/state" ]] || echo "50 1" > "$STATE_DIR/state"
chmod 666 "$STATE_DIR/state"

install -m 644 -o root -g wheel resources/$ID.daemon.plist "$DAEMON_PLIST"
install -m 644 -o root -g wheel resources/$ID.agent.plist "$AGENT_PLIST"

launchctl bootstrap system "$DAEMON_PLIST"
# Start Moonkey.app for users already logged in; others get it at login.
for uid in $(gui_uids); do launchctl bootstrap gui/$uid "$AGENT_PLIST" || true; done

echo "Moonkey installed. Backlight: $(/usr/local/bin/moonkey)"
