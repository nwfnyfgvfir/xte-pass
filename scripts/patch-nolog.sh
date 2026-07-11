#!/usr/bin/env bash
# Apply source-level log silence + branding strip to an upstream core tree.
# Usage: patch-nolog.sh <core-src-dir>
# Robust against minor whitespace differences across tags.
set -euo pipefail

ROOT="${1:?core source root required}"

die() { echo "ERROR: $*" >&2; exit 1; }
need() { [[ -f "$1" ]] || die "missing $1"; }

LOG_GO="$ROOT/common/log/log.go"
LOGGER_GO="$ROOT/common/log/logger.go"
APP_LOG="$ROOT/app/log/log.go"
CORE_GO="$ROOT/core/core.go"
VERSION_GO="$ROOT/main/version.go"
RUN_GO="$ROOT/main/run.go"
MAIN_GO="$ROOT/main/main.go"
ENV_GO="$ROOT/main/commands/base/env.go"
HELP_GO="$ROOT/main/commands/base/help.go"
CMD_GO="$ROOT/main/commands/base/command.go"

need "$LOG_GO"
need "$LOGGER_GO"
need "$APP_LOG"
need "$CORE_GO"
need "$VERSION_GO"
need "$RUN_GO"
need "$MAIN_GO"
need "$ENV_GO"

python3 - "$LOG_GO" "$LOGGER_GO" "$APP_LOG" "$CORE_GO" "$VERSION_GO" "$RUN_GO" "$MAIN_GO" "$ENV_GO" "$HELP_GO" "$CMD_GO" <<'PY'
import pathlib
import re
import sys

paths = list(map(pathlib.Path, sys.argv[1:]))
(
    log_go,
    logger_go,
    app_log,
    core_go,
    version_go,
    run_go,
    main_go,
    env_go,
    help_go,
    cmd_go,
) = paths


def replace_func(text: str, sig_re: str, new_func: str, path: pathlib.Path) -> str:
    """Replace a top-level Go function whose signature matches sig_re (full line).

    Uses brace matching so internal whitespace/newlines do not matter.
    """
    m = re.search(sig_re, text, flags=re.M)
    if not m:
        raise SystemExit(f"signature not found in {path}: {sig_re}")
    start = m.start()
    # find opening brace of function body
    brace = text.find("{", m.end() - 1)
    if brace < 0:
        raise SystemExit(f"opening brace not found for {sig_re} in {path}")
    depth = 0
    i = brace
    while i < len(text):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                # swallow trailing newline
                if end < len(text) and text[end] == "\n":
                    end += 1
                return text[:start] + new_func.rstrip() + "\n" + text[end:]
        i += 1
    raise SystemExit(f"unbalanced braces for {sig_re} in {path}")


def replace_const_string(text: str, name: str, new_value: str = "") -> str:
    """Replace `name = "...."` assignments (single line). Idempotent."""
    # already patched to empty string
    if re.search(rf'^\s*{re.escape(name)}\s*=\s*""', text, flags=re.M):
        return text
    pat = rf'^(\s*{re.escape(name)}\s*=\s*)"[^"]*"([^\n]*)'
    new, n = re.subn(pat, rf'\1"{new_value}" // nolog-patch', text, count=1, flags=re.M)
    if n == 0:
        raise SystemExit(f"assignment not found: {name}")
    return new


# --- common/log/log.go ---
s = log_go.read_text()
if "func Record(msg Message)" not in s:
    raise SystemExit("Record not found — upstream API changed")
if "nolog-patch: swallow all log records" not in s:
    s = replace_func(
        s,
        r"^func Record\(msg Message\)\s*\{",
        "func Record(msg Message) {\n\t// nolog-patch: swallow all log records\n}\n",
        log_go,
    )
if "nologNoopHandler" not in s:
    s = replace_func(
        s,
        r"^func RegisterHandler\(handler Handler\)\s*\{",
        """func RegisterHandler(handler Handler) {
\t// nolog-patch: always install no-op; ignore caller-provided handler
\tlogHandler.Set(nologNoopHandler{})
}

type nologNoopHandler struct{}

func (nologNoopHandler) Handle(msg Message) {}
""",
        log_go,
    )
log_go.write_text(s)

# --- common/log/logger.go ---
s = logger_go.read_text()
s = replace_func(
    s,
    r"^func \(l \*serverityLogger\) Handle\(msg Message\)\s*\{",
    "func (l *serverityLogger) Handle(msg Message) {\n\t// nolog-patch\n}\n",
    logger_go,
)
s = replace_func(
    s,
    r"^func \(l \*generalLogger\) Handle\(msg Message\)\s*\{",
    "func (l *generalLogger) Handle(msg Message) {\n\t// nolog-patch\n}\n",
    logger_go,
)
s = replace_func(
    s,
    r"^func CreateStdoutLogWriter\(\) WriterCreator\s*\{",
    "func CreateStdoutLogWriter() WriterCreator {\n\t// nolog-patch\n\treturn func() Writer { return nil }\n}\n",
    logger_go,
)
s = replace_func(
    s,
    r"^func CreateStderrLogWriter\(\) WriterCreator\s*\{",
    "func CreateStderrLogWriter() WriterCreator {\n\t// nolog-patch\n\treturn func() Writer { return nil }\n}\n",
    logger_go,
)
s = replace_func(
    s,
    r"^func init\(\)\s*\{",
    "func init() {\n\t// nolog-patch\n\tRegisterHandler(nologNoopHandler{})\n}\n",
    logger_go,
)
logger_go.write_text(s)

# --- app/log/log.go ---
s = app_log.read_text()
s = replace_func(
    s,
    r"^func \(g \*Instance\) Handle\(msg log\.Message\)\s*\{",
    "func (g *Instance) Handle(msg log.Message) {\n\t// nolog-patch: discard access/error/dns logs\n}\n",
    app_log,
)
app_log.write_text(s)

# --- core/core.go ---
s = core_go.read_text()
s = replace_const_string(s, "codename", "")
s = replace_const_string(s, "intro", "")
s = replace_func(
    s,
    r"^func VersionStatement\(\) \[\]string\s*\{",
    """func VersionStatement() []string {
\t// nolog-patch: pure version only
\t_, _, _ = codename, intro, build
\treturn []string{Version()}
}
""",
    core_go,
)
# Drop imports only used by old VersionStatement
if "serial." not in s:
    s = s.replace('\n\t"github.com/xtls/xray-core/common/serial"\n', "\n")
    s = s.replace('\r\n\t"github.com/xtls/xray-core/common/serial"\r\n', "\r\n")
if "runtime." not in s:
    s = re.sub(r'\n\t"runtime"\n', "\n", s)
core_go.write_text(s)

# --- main/version.go ---
s = version_go.read_text()
s = s.replace("Show current version of Xray", "Show current version")
s = re.sub(
    r"Long:\s*`Version prints the build information for Xray executables\.\s*`",
    'Long:      `Show current version.`',
    s,
    count=1,
)
s = replace_func(
    s,
    r"^func printVersion\(\)\s*\{",
    "func printVersion() {\n\t// nolog-patch: pure version only\n\tfmt.Println(core.Version())\n}\n",
    version_go,
)
version_go.write_text(s)

# --- main/run.go: silent start + soften help strings ---
s = run_go.read_text()
if "nolog-patch: silent start" not in s:
    if "printVersion()" not in s:
        raise SystemExit(f"printVersion() call not found in {run_go}")
    s = s.replace(
        "\tprintVersion()\n\tserver, err := startXray()",
        "\t// nolog-patch: silent start\n\tserver, err := startXray()",
        1,
    )
    if "nolog-patch: silent start" not in s:
        # whitespace-tolerant
        s2, n = re.subn(
            r"[ \t]*printVersion\(\)[ \t]*\n[ \t]*server, err := startXray\(\)",
            "\t// nolog-patch: silent start\n\tserver, err := startXray()",
            s,
            count=1,
        )
        if n == 0:
            raise SystemExit("failed to remove printVersion() from run")
        s = s2
# Soften user-facing strings (best-effort; help only)
for a, b in [
    ("Run Xray with config, the default command", "Run with config, the default command"),
    ("without launching Xray server.", "without launching the server."),
    ("Config path for Xray.", "Config path."),
    ("before Xray starts.", "before the process starts."),
    ("\nXray. Multiple assign is accepted.", "\nMultiple assign is accepted."),
    ("set the config files for\nXray.", "set the config files."),
    ("tells Xray to test config files only,", "tests config files only,"),
    ("tells Xray to print the merged config.", "prints the merged config."),
    ("Dump merged config only, without launching Xray server.", "Dump merged config only, without launching the server."),
    ("Test config file only, without launching Xray server.", "Test config file only, without launching the server."),
]:
    s = s.replace(a, b)
run_go.write_text(s)

# --- main/main.go ---
s = main_go.read_text()
s = s.replace(
    'base.RootCommand.Long = "Xray is a platform for building proxies."',
    'base.RootCommand.Long = "A network proxy platform." // nolog-patch',
)
main_go.write_text(s)

# --- main/commands/base/env.go ---
s = env_go.read_text()
if 'CommandEnv.Exec = "app"' not in s:
    s2, n = re.subn(
        r'CommandEnv\.Exec\s*=\s*"xray"',
        'CommandEnv.Exec = "app" // nolog-patch',
        s,
        count=1,
    )
    if n == 0:
        raise SystemExit("CommandEnv.Exec assignment not found")
    s = s2
env_go.write_text(s)

# --- help.go / command.go: replace hardcoded help brand if present ---
if help_go.exists():
    s = help_go.read_text()
    s2 = s.replace("xray help", "app help").replace("'xray help", "'app help")
    if s2 != s:
        help_go.write_text(s2)
if cmd_go.exists():
    s = cmd_go.read_text()
    s2 = (
        s.replace("Run 'xray help", "Run 'app help")
        .replace("a xray command", "a command")
        .replace("like xray run or xray version", "like app run or app version")
    )
    if s2 != s:
        cmd_go.write_text(s2)

print("patches applied")
PY

# --- Verification ---
grep -q 'nolog-patch: swallow all log records' "$LOG_GO" || die "Record patch missing"
grep -q 'nolog-patch: always install no-op' "$LOG_GO" || die "RegisterHandler patch missing"
grep -q 'nologNoopHandler' "$LOG_GO" || die "noop handler missing"
grep -q 'nolog-patch' "$LOGGER_GO" || die "logger.go patch missing"
grep -q 'nolog-patch: discard' "$APP_LOG" || die "Instance.Handle patch missing"
grep -q 'nolog-patch: pure version only' "$CORE_GO" || die "VersionStatement patch missing"
grep -q 'nolog-patch: pure version only' "$VERSION_GO" || die "printVersion patch missing"
grep -q 'nolog-patch: silent start' "$RUN_GO" || die "run silent start patch missing"
grep -q 'CommandEnv.Exec = "app"' "$ENV_GO" || die "Exec rename missing"

if grep -n 'RegisterHandler(NewLogger(CreateStdoutLogWriter()))' "$LOGGER_GO"; then
  die "stdout logger still registered in init"
fi
if grep -nE 'serial\.Concat\("Xray |"Xray, Penetrates|"Show current version of Xray' "$CORE_GO" "$VERSION_GO"; then
  die "runtime branding still present in core/version"
fi
if grep -n 'codename = "Xray' "$CORE_GO"; then
  die "codename still branded"
fi
if ! grep -Fq 'return []string{Version()}' "$CORE_GO"; then
  die "VersionStatement does not return pure Version()"
fi

echo "OK: nolog patches verified under $ROOT"
