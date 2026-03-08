#!/bin/bash
set -e
swiftc main.swift -o NoUpdate
mkdir -p NoUpdate.app/Contents/MacOS
mkdir -p NoUpdate.app/Contents/Resources
mv NoUpdate NoUpdate.app/Contents/MacOS/
cp Info.plist NoUpdate.app/Contents/
cp logo.png NoUpdate.app/Contents/Resources/
codesign -f -s - NoUpdate.app
echo "Built NoUpdate.app"
