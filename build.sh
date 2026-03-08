#!/bin/bash
set -e
swiftc main.swift -o NoUpdate
mkdir -p NoUpdate.app/Contents/MacOS
mv NoUpdate NoUpdate.app/Contents/MacOS/
cp Info.plist NoUpdate.app/Contents/
codesign -f -s - NoUpdate.app
echo "Built NoUpdate.app"
