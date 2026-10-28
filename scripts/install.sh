#!/bin/bash
# Builds FinderCut, installs it to /Applications and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh

pkill -x FinderCut 2>/dev/null || true
rm -rf /Applications/FinderCut.app
# Moved rather than copied: Spotlight would find a copy left in build/ and list the app twice.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -u "$PWD/build/FinderCut.app" 2>/dev/null || true
mv build/FinderCut.app /Applications/

# An ad-hoc signed rebuild has a new signature, so any old Accessibility
# entry no longer matches. Clear it so macOS asks again cleanly.
tccutil reset Accessibility com.matteonardone.FinderCut >/dev/null 2>&1 || true

open /Applications/FinderCut.app
echo "Installed /Applications/FinderCut.app — grant Accessibility access when prompted."
