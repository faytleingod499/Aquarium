#!/bin/bash
# Makes the Thunderstore zip from package/ (rebuild package/Aquarium/Aquarium.pck first with pack.gd, see the README):
#   out/Aquarium-<version>.zip   the Thunderstore upload
set -e
cd "$(dirname "$0")"
mkdir -p out
V=$(python3 -c "import json;print(json.load(open('thunderstore/manifest.json'))['version_number'])")
rm -f out/Aquarium-$V.zip
T=$(mktemp -d)
cp thunderstore/manifest.json thunderstore/README.md thunderstore/CHANGELOG.md thunderstore/icon.png $T/
cp LICENSE $T/
mkdir -p $T/GDWeave/mods/Aquarium
cp package/Aquarium/manifest.json package/Aquarium/Aquarium.pck $T/GDWeave/mods/Aquarium/
(cd $T && zip -qr - .) > out/Aquarium-$V.zip
rm -rf $T
echo "out/Aquarium-$V.zip"
