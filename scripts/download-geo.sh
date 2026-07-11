#!/usr/bin/env bash
# Download geoip.dat and geosite.dat into a directory.
# Usage: download-geo.sh <out-dir> [upstream-tag-for-fallback]
set -euo pipefail

OUT="${1:?output directory required}"
UPSTREAM_TAG="${2:-}"
mkdir -p "$OUT"

PRIMARY_BASE="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"
UPSTREAM_REPO="XTLS/Xray-core"

download() {
  local url="$1" dest="$2"
  echo "Fetching $url"
  curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$dest"
}

ok_geo() {
  [[ -s "$OUT/geoip.dat" && -s "$OUT/geosite.dat" ]]
}

if download "$PRIMARY_BASE/geoip.dat" "$OUT/geoip.dat" \
  && download "$PRIMARY_BASE/geosite.dat" "$OUT/geosite.dat" \
  && ok_geo; then
  echo "OK: geo data from primary source -> $OUT"
  ls -lh "$OUT/geoip.dat" "$OUT/geosite.dat"
  exit 0
fi

echo "WARN: primary geo source failed; trying upstream release assets" >&2
rm -f "$OUT/geoip.dat" "$OUT/geosite.dat"

if [[ -z "$UPSTREAM_TAG" ]]; then
  if command -v gh >/dev/null 2>&1; then
    UPSTREAM_TAG="$(gh api "repos/${UPSTREAM_REPO}/releases/latest" --jq .tag_name)"
  else
    UPSTREAM_TAG="$(curl -fsSL "https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  fi
fi

[[ -n "$UPSTREAM_TAG" ]] || { echo "ERROR: cannot resolve upstream tag for geo fallback" >&2; exit 1; }

# Prefer direct asset URLs from a known platform zip is heavy; try common asset names first.
for name in geoip.dat geosite.dat; do
  url="https://github.com/${UPSTREAM_REPO}/releases/download/${UPSTREAM_TAG}/${name}"
  if ! download "$url" "$OUT/$name"; then
    # Some releases only ship geo inside platform zips; try linux-64 zip extract.
    echo "WARN: direct $name missing; extracting from platform zip" >&2
    tmp="$(mktemp -d)"
    zipurl="https://github.com/${UPSTREAM_REPO}/releases/download/${UPSTREAM_TAG}/Xray-linux-64.zip"
    curl -fsSL --retry 3 "$zipurl" -o "$tmp/pkg.zip"
    unzip -jo "$tmp/pkg.zip" "$name" -d "$OUT" || unzip -jo "$tmp/pkg.zip" "*/$name" -d "$OUT" || true
    rm -rf "$tmp"
  fi
done

ok_geo || { echo "ERROR: geo files missing or empty in $OUT" >&2; exit 1; }
echo "OK: geo data from fallback -> $OUT"
ls -lh "$OUT/geoip.dat" "$OUT/geosite.dat"
