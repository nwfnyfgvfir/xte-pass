# Patches

This repo does **not** vendor the upstream core tree. At CI time we clone a tag and apply `scripts/patch-nolog.sh`.

## What the script changes

| Area | Files | Effect |
|------|--------|--------|
| Log silence | `common/log/log.go`, `common/log/logger.go`, `app/log/log.go` | `Record` / handlers become no-op |
| Version output | `core/core.go`, `main/version.go` | `version` prints pure `x.y.z` only |
| Silent start | `main/run.go` | No version banner on `run` |
| CLI exec name | `main/commands/base/env.go` | Help uses `app` |

## When upstream breaks the patch

1. CI fails on `patch-nolog.sh` verification greps.
2. Clone the failing tag locally, run the script, inspect the error.
3. Update regexes in `scripts/patch-nolog.sh` to match the new source shape.
4. Optionally save `git diff` of a successful patch here as `nolog-<tag>.diff` for reference.

## Out of scope

- Renaming Go module path
- Rewriting LICENSE legal text
- Stripping every occurrence of upstream names in comments
