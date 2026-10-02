#!/bin/sh
# Bygger screengrab.app i build/ med SwiftPM (ingen Xcode nødvendig) og signerer den.
# Gjenbruker det selvsignerte sertifikatet fra screenlogger (~/Git/screenlogger/sign/lag-sertifikat.sh),
# så tillatelsen til Skjermopptak overlever nye bygg.
# Bruk:  sh build.sh            (release)
#        sh build.sh --debug
set -eu
cd "$(dirname "$0")"
KONF=release; [ "${1:-}" = "--debug" ] && KONF=debug
swift build -c "$KONF" 2>&1 | grep -E "error|warning|Compiling|Build complete" | grep -v "search path" || true
BIN=".build/$KONF/screengrab"
[ -x "$BIN" ] || { echo "bygging feilet (ingen $BIN)"; exit 1; }
APP="build/screengrab.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/screengrab"
cp mac/Info.plist "$APP/Contents/Info.plist"
cp mac/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

IDENTITET="screenlogger selvsignert"
KC="$HOME/Library/Keychains/screenlogger-sign.keychain-db"
if [ -f "$KC" ] && security find-identity -v -p codesigning "$KC" | grep -q "$IDENTITET"; then
  PW="$(cat "$HOME/.screenlogger-sign/keychain-pw" 2>/dev/null || true)"
  [ -n "$PW" ] && security unlock-keychain -p "$PW" "$KC" 2>/dev/null || true
  codesign --force --sign "$IDENTITET" --keychain "$KC" --identifier net.flagan.screengrab \
    --timestamp=none "$APP" 2>&1 | grep -v "unable to build chain" || true
  echo "signert med: $IDENTITET"
else
  codesign --force --sign - --identifier net.flagan.screengrab "$APP"
  echo "ADVARSEL: ad hoc-signert (kjør ~/Git/screenlogger/sign/lag-sertifikat.sh for stabil identitet)"
fi
codesign --verify --verbose=1 "$APP" && echo "bygget: $APP"
