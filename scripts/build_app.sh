#!/bin/zsh
# Builds 绝境 (Brink.app) in Release mode and copies it to ./dist/
set -e
setopt pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null && xcodegen generate --spec project.yml >/dev/null
# universal: Apple silicon and Intel
xcodebuild -project Brink.xcodeproj -scheme Brink -configuration Release \
  -derivedDataPath build/DerivedData -destination 'generic/platform=macOS' \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
mkdir -p dist
rm -rf dist/Brink.app
cp -R build/DerivedData/Build/Products/Release/Brink.app dist/
# A release build keeps its debug map, which holds the absolute paths of the machine that built it (the account
# name included). Strip it, and refuse to ship if a home-directory path is still anywhere in the bundle.
strip -S -x dist/Brink.app/Contents/MacOS/Brink 2>/dev/null
if /usr/bin/grep -r -a -q -e "/Users/" -e "$(whoami)" dist/Brink.app; then
  echo "dist/Brink.app still contains a path or the account name of this machine: not shipping it"; exit 1
fi
# ad-hoc signature with the hardened runtime (no Apple Developer ID here)
codesign --force --deep --options runtime -s - dist/Brink.app
codesign --verify --strict dist/Brink.app && echo "dist/Brink.app ($(defaults read "$PWD/dist/Brink.app/Contents/Info" CFBundleShortVersionString))"
