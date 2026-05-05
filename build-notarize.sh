#!/bin/bash
# Build, sign, notarize, and staple MDViewer.app
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
SCHEME="MDViewer"
BUNDLE_ID="com.mdviewer.app"
TEAM_ID="REDACTED-TEAM-ID"
SIGN_IDENTITY="Developer ID Application: MASANORI SAKAI (REDACTED-TEAM-ID)"

EXPORT_DIR="$(pwd)/build/export"
ARCHIVE_PATH="$(pwd)/build/MDViewer.xcarchive"
APP_PATH="${EXPORT_DIR}/MDViewer.app"
ZIP_PATH="$(pwd)/build/MDViewer-notarize.zip"

# Apple ID / app-specific password for notarytool
# Set these as environment variables before running, or hard-code here:
#   export APPLE_ID="your@apple.id"
#   export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
APPLE_ID="${APPLE_ID:-REDACTED-APPLE-ID}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"

# ── Preflight checks ───────────────────────────────────────────────────────────
if [[ -z "$APPLE_ID" || -z "$APPLE_APP_PASSWORD" ]]; then
    echo "Error: APPLE_ID and APPLE_APP_PASSWORD must be set."
    echo "  export APPLE_ID=your@apple.id"
    echo "  export APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx"
    exit 1
fi

# ── 1. Archive ─────────────────────────────────────────────────────────────────
echo "==> Archiving..."
rm -rf build
xcodebuild archive \
    -project MDViewer.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGNING_REQUIRED=YES \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    | xcpretty --simple 2>/dev/null || true

# ── 2. Export ──────────────────────────────────────────────────────────────────
echo "==> Exporting..."
mkdir -p "$EXPORT_DIR"

# Generate a temporary ExportOptions.plist
EXPORT_OPTS="$(mktemp).plist"
cat > "$EXPORT_OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>${SIGN_IDENTITY}</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTS" \
    | xcpretty --simple 2>/dev/null || true

rm -f "$EXPORT_OPTS"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: Export failed — $APP_PATH not found."
    exit 1
fi

# ── 3. Verify signature ────────────────────────────────────────────────────────
echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH" 2>&1 || true

# ── 4. Create zip for notarization ────────────────────────────────────────────
echo "==> Creating zip for notarization..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# ── 5. Notarize ────────────────────────────────────────────────────────────────
echo "==> Submitting to Apple notary service (this may take a few minutes)..."
NOTARY_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$TEAM_ID" \
    --wait \
    --output-format json)

echo "$NOTARY_OUTPUT"

STATUS=$(echo "$NOTARY_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status',''))")
if [[ "$STATUS" != "Accepted" ]]; then
    SUBMISSION_ID=$(echo "$NOTARY_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))")
    echo "Error: Notarization failed (status: $STATUS)."
    if [[ -n "$SUBMISSION_ID" ]]; then
        echo "Fetching log..."
        xcrun notarytool log "$SUBMISSION_ID" \
            --apple-id "$APPLE_ID" \
            --password "$APPLE_APP_PASSWORD" \
            --team-id "$TEAM_ID"
    fi
    exit 1
fi

# ── 6. Staple ──────────────────────────────────────────────────────────────────
echo "==> Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"

# ── 7. Final re-zip (stapled) ─────────────────────────────────────────────────
echo "==> Creating final distributable zip..."
FINAL_ZIP="$(pwd)/build/MDViewer.zip"
ditto -c -k --keepParent "$APP_PATH" "$FINAL_ZIP"

echo ""
echo "==> Done!"
echo "    App:  $APP_PATH"
echo "    Zip:  $FINAL_ZIP"
