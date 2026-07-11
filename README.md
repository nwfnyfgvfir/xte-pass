# app (silent core builds)

Automated multi-platform builds of an upstream open-source proxy **core**, with:

- **Source-level log silence** — business logs are no-ops at compile time (not only config)
- **Neutral naming** — binary `app` / `app.exe`, assets `app-<platform>.zip`
- **Clean version** — `./app version` prints only `x.y.z`
- **Geo bundle** — each zip includes `geoip.dat` + `geosite.dat`
- **History kept** — one GitHub Release per upstream tag; old releases are never deleted

## Platforms

| Asset | GOOS/GOARCH |
|-------|-------------|
| `app-linux-64.zip` | linux/amd64 |
| `app-linux-arm64-v8a.zip` | linux/arm64 |
| `app-linux-arm32-v7a.zip` | linux/arm (GOARM=7) |
| `app-windows-64.zip` | windows/amd64 |
| `app-windows-arm64-v8a.zip` | windows/arm64 |
| `app-macos-64.zip` | darwin/amd64 |
| `app-macos-arm64-v8a.zip` | darwin/arm64 |

## Triggers

1. **Actions → Build and Release** (`workflow_dispatch`)
   - `version`: leave empty for upstream latest, or set e.g. `v26.6.27`
   - `force`: rebuild even if the tag already has a release
2. **Check upstream** (daily cron + manual): if upstream has a new tag and this repo has no matching release, dispatches the build workflow.

## Zip layout

```
app-linux-64.zip
├── app            # or app.exe on Windows
├── geoip.dat
├── geosite.dat
└── LICENSE        # upstream license (kept as required)
```

## Local patch / smoke (optional)

```bash
git clone --depth 1 --branch <tag> https://github.com/XTLS/Xray-core.git core-src
bash scripts/patch-nolog.sh core-src
# build with a Go toolchain matching core-src/go.mod
cd core-src && CGO_ENABLED=0 go build -o ../app -trimpath -ldflags="-s -w -buildid=" ./main
cd ..
./app version    # expect single line: x.y.z
```

## Notes

- Not an official upstream distribution; packaging and patches live in this repo.
- Module path inside the Go build may still reference upstream import paths (compile-time only).
- Windows TUN users need `wintun` separately (not bundled in v1).
- If upstream refactors its log package, update `scripts/patch-nolog.sh` (see `patches/README.md`).

## 中文摘要

基于上游核心的自动构建：源码级关闭业务日志、产物名 `app`、版本命令只输出纯版本号、附带 geo 数据。每个上游 tag 对应一个 Release 并保留历史。通过 GitHub Actions 手动或每日检测触发。
