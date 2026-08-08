#!/usr/bin/env bash
# Aladdin prebuilt installer (distributed from aladdin.bz).
# Developers with repo access should keep using `make install` in the
# repository — that is the certified transactional path with rollback.
# This script only covers quick installation of the prebuilt app.
set -euo pipefail
umask 077

# The whole script is wrapped in main() so bash must parse the entire
# file before executing anything: a truncated download can never
# half-execute.
main() {

BASE_URL="${1:-}"
if [[ -z "$BASE_URL" ]]; then
  echo "ERROR: missing download base URL. Copy the full install command from the website (curl ... -o /tmp/aladdin-install.sh && bash /tmp/aladdin-install.sh <url>)." >&2
  exit 1
fi
BASE_URL="${BASE_URL%/}"
APP_DST="$HOME/Applications/Aladdin.app"
CONFIG_DIR="$HOME/.config/aladdin"
CONFIG="$CONFIG_DIR/config.json"
PLIST="$HOME/Library/LaunchAgents/com.internal.aladdin.plist"
LABEL="com.internal.aladdin"
DOMAIN="gui/$(id -u)"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: this build supports Apple Silicon (arm64) only." >&2
  exit 1
fi

echo "==> Downloading Aladdin.app (about 15 MB)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$BASE_URL/downloads/Aladdin.app.zip" -o "$TMP/Aladdin.app.zip"
ditto -x -k "$TMP/Aladdin.app.zip" "$TMP/unpacked"
if [[ ! -d "$TMP/unpacked/Aladdin.app" ]]; then
  echo "ERROR: unexpected archive contents; aborting." >&2
  exit 1
fi

echo "==> Stopping any running instance"
/bin/launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
/usr/bin/pkill -x Aladdin 2>/dev/null || true

echo "==> Installing to ~/Applications"
mkdir -p "$HOME/Applications"
rm -rf "$APP_DST"
ditto "$TMP/unpacked/Aladdin.app" "$APP_DST"
/usr/bin/xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true

if [[ -f "$CONFIG" ]]; then
  echo "==> Existing config found at ${CONFIG}; leaving it untouched"
else
  echo "==> First-time setup: you need your team gateway URL and your personal token (ask your gateway admin)"
  read -r -p "Gateway URL (e.g. https://gw.aladdin.bz): " GATEWAY </dev/tty
  case "$GATEWAY" in
    https://*) ;;
    http://localhost*|http://127.0.0.1*|"http://[::1]"*) ;;
    *) echo "ERROR: gateway must be https:// (or loopback http://)." >&2; exit 1 ;;
  esac
  GATEWAY="${GATEWAY%/}"
  read -r -s -p "Personal token (input hidden): " TOKEN </dev/tty
  echo
  if [[ -z "$TOKEN" || ! "$TOKEN" =~ ^[A-Za-z0-9._~+/=-]+$ ]]; then
    echo "ERROR: token is empty or contains unexpected characters." >&2
    exit 1
  fi
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
  OLD_UMASK="$(umask)"
  umask 177
  cat > "$CONFIG" <<EOF
{
  "gateway_url": "$GATEWAY",
  "token": "$TOKEN",
  "language": "auto",
  "dictionary": [],
  "allow_remote_personal_context_egress": false
}
EOF
  umask "$OLD_UMASK"
  unset TOKEN
fi

echo "==> Registering launch-at-login"
mkdir -p "$HOME/Library/LaunchAgents"
OLD_UMASK="$(umask)"
umask 177
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>KeepAlive</key>
	<false/>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$HOME/Applications/Aladdin.app/Contents/MacOS/Aladdin</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF
umask "$OLD_UMASK"
/bin/launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null || true
/usr/bin/open "$APP_DST"

cat <<'DONE'

OK: Aladdin is installed and starting (look for the Starry Night icon in the menu bar).

A few system permissions remain — only you can click these (the app will
also guide you):
  1. System Settings -> Privacy & Security -> Microphone       -> enable Aladdin
  2. System Settings -> Privacy & Security -> Accessibility    -> enable Aladdin
  3. System Settings -> Privacy & Security -> Input Monitoring -> enable Aladdin
  4. System Settings -> Keyboard -> "Press Globe key to"       -> "Do Nothing"
  5. System Settings -> Keyboard -> Dictation                  -> off

Then: tap Fn to start dictation and tap again to commit; or hold Fn,
speak, and release to commit.
DONE

}

main "$@"
