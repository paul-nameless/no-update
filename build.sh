#!/bin/bash
set -e
swiftc main.swift -o NoUpdate
mkdir -p NoUpdate.app/Contents/MacOS
mkdir -p NoUpdate.app/Contents/Resources
mv NoUpdate NoUpdate.app/Contents/MacOS/
cp Info.plist NoUpdate.app/Contents/
cp logo.png NoUpdate.app/Contents/Resources/
# Sign with SIGN_ID (a stable identity keeps the Accessibility grant across
# rebuilds); ad-hoc fallback changes the cdhash every build and revokes it.
if [ -n "${SIGN_ID:-}" ]; then
    codesign -f --options runtime --timestamp -s "$SIGN_ID" NoUpdate.app
else
    codesign -f -s - NoUpdate.app
fi
echo "Built NoUpdate.app"
