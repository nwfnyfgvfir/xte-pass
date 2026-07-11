# Packaging repo notes

- Purpose: GitHub Actions builds of upstream proxy core with source-level log silence and neutral naming (`app`).
- Stack: Bash + GitHub Actions + Go (version from cloned `go.mod`).
- Do **not** vendor the core tree; clone at CI time into `core-src/`.
- Patch entrypoint: `scripts/patch-nolog.sh`
- CI uses `actions/setup-go` (not conda).
- Local optional Go toolchain via conda:

```bash
conda create -n xray go -c conda-forge -y
conda run -n xray go version
# clone tag, patch, build host:
# conda run -n xray bash -lc 'cd core-src && go build -o ../app ./main'
```

## Forced command style (local)

Prefer `conda run -n xray <cmd>` when using a conda-managed Go. Never assume a global `go` without checking.
