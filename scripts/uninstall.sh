#!/bin/zsh
# Removes everything scripts/install.sh installed. Run via `sudo make uninstall`.
set -uo pipefail

ID=io.github.simon-lumikello.moonkey

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo make uninstall" >&2; exit 1; }

launchctl bootout system/$ID.daemon 2>/dev/null
for uid in $(ps -axo uid=,comm= | awk '$2 ~ /loginwindow$/ && $1 >= 500 { print $1 }' | sort -u); do
  launchctl bootout gui/$uid/$ID.agent 2>/dev/null
done

rm -f /Library/LaunchDaemons/$ID.daemon.plist /Library/LaunchAgents/$ID.agent.plist
rm -f /usr/local/bin/moonkey
rm -rf /Applications/Moonkey.app "/Library/Application Support/Moonkey"

echo "Moonkey uninstalled."
