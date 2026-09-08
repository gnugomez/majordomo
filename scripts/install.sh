#!/bin/sh
# Builds a release bundle and installs it over /Applications/Majordomo.app.
set -eu

cd "$(dirname "$0")/.."

./scripts/bundle.sh
rm -rf /Applications/Majordomo.app
ditto dist/Majordomo.app /Applications/Majordomo.app

echo "Installed /Applications/Majordomo.app"
echo "Note: an ad-hoc-signed rebuild re-prompts for Keychain access on first"
echo "launch — click \"Always Allow\" so the stored token stays readable."
