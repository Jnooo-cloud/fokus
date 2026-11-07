#!/bin/zsh
# Renders every Fokus page to PNG without screen recording rights. With --demo it uses a throwaway
# data folder filled with sample data, so screenshots never show your own usage.
set -euo pipefail
cd "${0:A:h:h}"
out=${1:-$PWD/build/snapshots}
mkdir -p "$out"
binary=/Applications/Fokus.app/Contents/MacOS/Fokus
if [[ "${2:-}" == "--demo" ]]; then
  demo=$(mktemp -d)
  python3 -I scripts/demo-data.py "$demo/usage"
  FOKUS_DATA_DIR="$demo" FOKUS_SNAPSHOT="$out" "$binary"
  rm -rf -- "$demo"
else
  FOKUS_SNAPSHOT="$out" "$binary"
fi
print "Bilder in $out"
