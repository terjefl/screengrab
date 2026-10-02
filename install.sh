#!/bin/sh
# Installerer screengrab for denne brukeren (ingen administrator nødvendig):
#   ~/Applications/screengrab.app                       appen (fra build/)
#   ~/Library/LaunchAgents/net.flagan.screengrab.plist  start ved innlogging + omstart ved krasj
# Bruk:  sh install.sh             (bygger ikke; kjør build.sh først)
#        sh install.sh --fjern     (avinstaller)
set -eu
cd "$(dirname "$0")"
UID_="$(id -u)"
MAL="$HOME/Applications/screengrab.app"
LA="$HOME/Library/LaunchAgents/net.flagan.screengrab.plist"

launchctl bootout "gui/$UID_/net.flagan.screengrab" 2>/dev/null || true
pkill -x screengrab 2>/dev/null || true
sleep 1

if [ "${1:-}" = "--fjern" ]; then
  rm -rf "$MAL" "$LA"
  echo "fjernet screengrab (innstillinger ligger igjen i defaults-domenet net.flagan.screengrab)"
  exit 0
fi

[ -d build/screengrab.app ] || { echo "kjør sh build.sh først"; exit 1; }
mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" "$HOME/Library/Application Support/screengrab"
rm -rf "$MAL"
ditto build/screengrab.app "$MAL"
echo "installert: $MAL"
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSR" -u "$PWD/build/screengrab.app" 2>/dev/null || true
"$LSR" -f "$MAL" 2>/dev/null || true

sed "s|REPLACE_HOME|$HOME|g" mac/net.flagan.screengrab.plist > "$LA"
launchctl bootstrap "gui/$UID_" "$LA" \
  && echo "LaunchAgent lastet: appen starter nå og ved innlogging" \
  || echo "kunne ikke laste LaunchAgent (er den allerede lastet?)"
echo
echo "Første gang: gi screengrab tillatelse til Skjermopptak når macOS spør"
echo "(Systeminnstillinger → Personvern og sikkerhet → Skjerm- og systemlydopptak)."
