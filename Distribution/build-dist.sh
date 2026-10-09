#!/bin/zsh
# Builds "dist/Working Hours <version>.dmg" to share with others: universal, signed locally
# (no Apple Developer account needed), with only the sandbox entitlements and no personal data.
set -euo pipefail

ROOT="${0:A:h:h}"
cd "$ROOT"

BUILD="${TMPDIR:-/tmp}/working-hours-dist"
APP="$BUILD/Build/Products/Release/Working Hours.app"
STAGE="$BUILD/stage"

fail() {
    print -u2 "build-dist: $1"
    exit 1
}

rm -rf "${BUILD:?}"
xcodebuild -project "Working Hours.xcodeproj" -scheme "Working Hours" -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$BUILD" \
    CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
    build -quiet

# Local signing adds get-task-allow, which lets other processes attach to the app and read its memory.
# Sign again with an explicit list. CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO is no alternative: it drops the sandbox too.
codesign --force --sign - --options runtime --entitlements Distribution/dist.entitlements "$APP"

codesign --verify --deep --strict "$APP" || fail "invalid signature"
entitlements=$(codesign -d --entitlements - "$APP" 2>/dev/null)
[[ $entitlements == *app-sandbox* ]] || fail "sandbox entitlement missing"
[[ $entitlements != *get-task-allow* ]] || fail "get-task-allow still present"
[[ $(codesign -dvv "$APP" 2>&1) == *"flags=0x10002(adhoc,runtime)"* ]] || fail "hardened runtime missing"

archs=$(lipo -archs "$APP/Contents/MacOS/Working Hours")
[[ $archs == *arm64* && $archs == *x86_64* ]] || fail "not universal: $archs"

# Nothing that identifies the person who built it. The patterns come from this Mac, not from this file.
team=$(sed -n 's/^DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*/\1/p' Config/Local.xcconfig 2>/dev/null | head -1)
# The login name alone is not checked: it can be part of the public bundle identifier.
patterns=("/Users/" "$HOME" "-demo")
[[ -n $team ]] && patterns+=("$team")
fullName=$(id -F 2>/dev/null || true)
[[ -n $fullName ]] && patterns+=("$fullName")
contents=$(find "$APP" -type f -print0 | xargs -0 strings -a 2>/dev/null)
for pattern in $patterns; do
    [[ $contents != *"$pattern"* ]] || fail "app contains \"$pattern\""
done

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
dmg="dist/Working Hours $version.dmg"

mkdir -p "$STAGE" dist
ditto "$APP" "$STAGE/Working Hours.app"
ln -s /Applications "$STAGE/Applications"
cp "Distribution/Read Me.txt" "$STAGE/"

rm -f "$dmg"
hdiutil create -volname "Working Hours" -srcfolder "$STAGE" -format UDZO "$dmg" >/dev/null 2>&1 || fail "hdiutil create failed"
hdiutil verify "$dmg" >/dev/null 2>&1 || fail "disk image does not verify"

print "$dmg ($archs, macOS $(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP/Contents/Info.plist")+)"
