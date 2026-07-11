#!/usr/bin/env bash
# Package binary + geo into a neutral-named zip.
# Usage: package.sh <bin-path> <geo-dir> <asset-name> [license-path] [out-dir]
# Example: package.sh dist/app geo linux-64 core/LICENSE dist
set -euo pipefail

BIN="${1:?binary path required}"
GEO_DIR="${2:?geo dir required}"
ASSET="${3:?asset name required (e.g. linux-64)}"
LICENSE="${4:-}"
OUT_DIR="${5:-.}"

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

[[ -f "$BIN" ]] || { echo "ERROR: binary not found: $BIN" >&2; exit 1; }
[[ -s "$GEO_DIR/geoip.dat" && -s "$GEO_DIR/geosite.dat" ]] || {
  echo "ERROR: geo files missing in $GEO_DIR" >&2
  exit 1
}

cp -f "$BIN" "$STAGE/"
# normalize binary name inside zip
base="$(basename "$BIN")"
if [[ "$base" != "app" && "$base" != "app.exe" ]]; then
  if [[ "$base" == *.exe ]]; then
    mv -f "$STAGE/$base" "$STAGE/app.exe"
  else
    mv -f "$STAGE/$base" "$STAGE/app"
  fi
fi
cp -f "$GEO_DIR/geoip.dat" "$GEO_DIR/geosite.dat" "$STAGE/"
if [[ -n "$LICENSE" && -f "$LICENSE" ]]; then
  cp -f "$LICENSE" "$STAGE/LICENSE"
fi

ZIP_NAME="app-${ASSET}.zip"
ZIP_PATH="${OUT_DIR}/${ZIP_NAME}"
rm -f "$ZIP_PATH"

if command -v zip >/dev/null 2>&1; then
  (
    cd "$STAGE"
    zip -9 -X "$ZIP_PATH" ./*
  )
else
  # Fallback when zip CLI is missing (e.g. minimal local env)
  python3 - "$STAGE" "$ZIP_PATH" <<'PY'
import pathlib, sys, zipfile
stage, out = map(pathlib.Path, sys.argv[1:3])
with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
    for p in sorted(stage.iterdir()):
        if p.is_file():
            zf.write(p, arcname=p.name)
print(f"wrote {out}")
PY
fi

DGST="${ZIP_PATH}.dgst"
: >"$DGST"
if command -v openssl >/dev/null 2>&1; then
  openssl dgst -md5 "$ZIP_PATH" >>"$DGST"
  openssl dgst -sha256 "$ZIP_PATH" >>"$DGST"
elif command -v sha256sum >/dev/null 2>&1; then
  md5sum "$ZIP_PATH" >>"$DGST" 2>/dev/null || true
  sha256sum "$ZIP_PATH" >>"$DGST"
else
  python3 - "$ZIP_PATH" "$DGST" <<'PY'
import hashlib, pathlib, sys
p = pathlib.Path(sys.argv[1])
out = pathlib.Path(sys.argv[2])
data = p.read_bytes()
lines = [
    f"MD5({p}) = {hashlib.md5(data).hexdigest()}",
    f"SHA256({p}) = {hashlib.sha256(data).hexdigest()}",
]
out.write_text("\n".join(lines) + "\n")
PY
fi

echo "OK: $ZIP_PATH"
ls -lh "$ZIP_PATH" "$DGST"
