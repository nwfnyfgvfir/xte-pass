#!/usr/bin/env bash
# Apply source-level log silence + branding strip to an upstream core tree.
# Usage: patch-nolog.sh <core-src-dir>
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
) = map(pathlib.Path, sys.argv[1:])


def must_sub(pattern: str, repl: str, text: str, path: pathlib.Path, flags=0, count=1) -> str:
    new, n = re.subn(pattern, repl, text, count=count, flags=flags)
    if n == 0:
        raise SystemExit(f"pattern not found in {path}: {pattern[:80]!r}")
    return new


# --- common/log/log.go ---
s = log_go.read_text()
if "func Record(msg Message)" not in s:
    raise SystemExit("Record not found — upstream API changed")
s = must_sub(
    r"func Record\(msg Message\) \{\n\tlogHandler\.Handle\(msg\)\n\}",
    "func Record(msg Message) {\n\t// nolog-patch: swallow all log records\n}",
    s,
    log_go,
)
s = must_sub(
    r"func RegisterHandler\(handler Handler\) \{\n\tif handler == nil \{\n\t\tpanic\(\"Log handler is nil\"\)\n\t\}\n\tlogHandler\.Set\(handler\)\n\}",
    """func RegisterHandler(handler Handler) {
\t// nolog-patch: always install no-op; ignore caller-provided handler
\tlogHandler.Set(nologNoopHandler{})
}

type nologNoopHandler struct{}

func (nologNoopHandler) Handle(msg Message) {}
""",
    s,
    log_go,
)
log_go.write_text(s)

# --- common/log/logger.go ---
s = logger_go.read_text()
s = must_sub(
    r"func \(l \*serverityLogger\) Handle\(msg Message\) \{\n\tswitch msg := msg\.\(type\) \{\n\tcase \*GeneralMessage:\n\t\tif msg\.Severity <= l\.logLevel \{\n\t\t\tl\.inner\.Handle\(msg\)\n\t\t\}\n\tdefault:\n\t\tl\.inner\.Handle\(msg\)\n\t\}\n\}",
    "func (l *serverityLogger) Handle(msg Message) {\n\t// nolog-patch\n}",
    s,
    logger_go,
)
s = must_sub(
    r"func \(l \*generalLogger\) Handle\(msg Message\) \{\n\tselect \{\n\tcase l\.buffer <- msg:\n\tdefault:\n\t\}\n\n\tselect \{\n\tcase <-l\.access\.Wait\(\):\n\t\tgo l\.run\(\)\n\tdefault:\n\t\}\n\}",
    "func (l *generalLogger) Handle(msg Message) {\n\t// nolog-patch\n}",
    s,
    logger_go,
)
s = must_sub(
    r"func CreateStdoutLogWriter\(\) WriterCreator \{\n\treturn func\(\) Writer \{\n\t\treturn &consoleLogWriter\{\n\t\t\tlogger: log\.New\(os\.Stdout, \"\", log\.Ldate\|log\.Ltime\|log\.Lmicroseconds\),\n\t\t\}\n\t\}\n\}",
    "func CreateStdoutLogWriter() WriterCreator {\n\t// nolog-patch\n\treturn func() Writer { return nil }\n}",
    s,
    logger_go,
)
s = must_sub(
    r"func CreateStderrLogWriter\(\) WriterCreator \{\n\treturn func\(\) Writer \{\n\t\treturn &consoleLogWriter\{\n\t\t\tlogger: log\.New\(os\.Stderr, \"\", log\.Ldate\|log\.Ltime\|log\.Lmicroseconds\),\n\t\t\}\n\t\}\n\}",
    "func CreateStderrLogWriter() WriterCreator {\n\t// nolog-patch\n\treturn func() Writer { return nil }\n}",
    s,
    logger_go,
)
s = must_sub(
    r"func init\(\) \{\n\tRegisterHandler\(NewLogger\(CreateStdoutLogWriter\(\)\)\)\n\}",
    "func init() {\n\t// nolog-patch\n\tRegisterHandler(nologNoopHandler{})\n}",
    s,
    logger_go,
)
logger_go.write_text(s)

# --- app/log/log.go ---
s = app_log.read_text()
s = must_sub(
    r"func \(g \*Instance\) Handle\(msg log\.Message\) \{\n\tg\.RLock\(\)\n\tdefer g\.RUnlock\(\)\n\n\tif !g\.active \{\n\t\treturn\n\t\}\n\n\tvar Msg log\.Message\n\tif g\.config\.MaskAddress != \"\" \{\n\t\tMsg = &MaskedMsgWrapper\{\n\t\t\tMessage: msg,\n\t\t\tMask4:   g\.mask4,\n\t\t\tMask6:   g\.mask6,\n\t\t\}\n\t\} else \{\n\t\tMsg = msg\n\t\}\n\n\tswitch msg := msg\.\(type\) \{\n\tcase \*log\.AccessMessage:\n\t\tif g\.accessLogger != nil \{\n\t\t\tg\.accessLogger\.Handle\(Msg\)\n\t\t\}\n\tcase \*log\.DNSLog:\n\t\tif g\.dns && g\.accessLogger != nil \{\n\t\t\tg\.accessLogger\.Handle\(Msg\)\n\t\t\}\n\tcase \*log\.GeneralMessage:\n\t\tif g\.errorLogger != nil && msg\.Severity <= g\.config\.ErrorLogLevel \{\n\t\t\tg\.errorLogger\.Handle\(Msg\)\n\t\t\}\n\tdefault:\n\t\t// Swallow\n\t\}\n\}",
    "func (g *Instance) Handle(msg log.Message) {\n\t// nolog-patch: discard access/error/dns logs\n}",
    s,
    app_log,
)
app_log.write_text(s)

# --- core/core.go ---
s = core_go.read_text()
s = must_sub(
    r'codename = "Xray, Penetrates Everything\."\n\tintro    = "A unified platform for anti-censorship\."',
    'codename = "" // nolog-patch\n\tintro    = "" // nolog-patch',
    s,
    core_go,
)
# Replace entire VersionStatement body (spacing-tolerant)
s = must_sub(
    r"func VersionStatement\(\) \[\]string \{.*?\n\}",
    "func VersionStatement() []string {\n\t// nolog-patch: pure version only\n\t_, _, _ = codename, intro, build\n\treturn []string{Version()}\n}",
    s,
    core_go,
    flags=re.S,
)
# Drop imports only used by old VersionStatement
if "serial." not in s:
    s = s.replace('\n\t"github.com/xtls/xray-core/common/serial"\n', "\n")
if "runtime." not in s:
    s = s.replace('\n\t"runtime"\n', "\n")
core_go.write_text(s)

# --- main/version.go ---
s = version_go.read_text()
s = must_sub(
    r'var cmdVersion = &base\.Command\{\n\tUsageLine: "\{\{\.Exec\}\} version",\n\tShort:     "Show current version of Xray",\n\tLong: `Version prints the build information for Xray executables\.\n\t`,\n\tRun: executeVersion,\n\}',
    '''var cmdVersion = &base.Command{
\tUsageLine: "{{.Exec}} version",
\tShort:     "Show current version",
\tLong:      `Show current version.`,
\tRun:       executeVersion,
}''',
    s,
    version_go,
)
s = must_sub(
    r"func printVersion\(\) \{\n\tversion := core\.VersionStatement\(\)\n\tfor _, s := range version \{\n\t\tfmt\.Println\(s\)\n\t\}\n\}",
    "func printVersion() {\n\t// nolog-patch: pure version only\n\tfmt.Println(core.Version())\n}",
    s,
    version_go,
)
version_go.write_text(s)

# --- main/run.go: do not print version on start; neutralize help text ---
s = run_go.read_text()
s = must_sub(
    r"\tprintVersion\(\)\n\tserver, err := startXray\(\)",
    "\t// nolog-patch: silent start\n\tserver, err := startXray()",
    s,
    run_go,
)
# Soften user-facing Short/Long that contain branding (help text only)
s = s.replace("Run Xray with config, the default command", "Run with config, the default command")
s = s.replace("without launching Xray server.", "without launching the server.")
s = s.replace("Config path for Xray.", "Config path.")
s = s.replace("before Xray starts.", "before the process starts.")
s = s.replace("\nXray. Multiple assign is accepted.", "\nMultiple assign is accepted.")
s = s.replace("set the config files for\nXray.", "set the config files.")
s = s.replace("tells Xray to test config files only,", "tests config files only,")
s = s.replace("tells Xray to print the merged config.", "prints the merged config.")
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
s = must_sub(
    r'CommandEnv\.Exec = "xray"',
    'CommandEnv.Exec = "app" // nolog-patch',
    s,
    env_go,
)
env_go.write_text(s)

# --- help.go / command.go: replace hardcoded help brand if present ---
if help_go.exists():
    s = help_go.read_text()
    s2 = s.replace("xray help", "app help").replace("'xray help", "'app help")
    if s2 != s:
        help_go.write_text(s2)
if cmd_go.exists():
    s = cmd_go.read_text()
    s2 = s.replace("Run 'xray help", "Run 'app help").replace("a xray command", "a command").replace(
        "like xray run or xray version", "like app run or app version"
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
# Runtime branding only (package comments may still mention upstream names)
if grep -nE 'serial\.Concat\("Xray |"Xray, Penetrates|"Show current version of Xray' "$CORE_GO" "$VERSION_GO"; then
  die "runtime branding still present in core/version"
fi
if grep -n 'codename = "Xray' "$CORE_GO"; then
  die "codename still branded"
fi
if ! grep -q 'return \[\]string{Version()}' "$CORE_GO" && ! grep -q 'return []string{Version()}' "$CORE_GO"; then
  die "VersionStatement does not return pure Version()"
fi

echo "OK: nolog patches verified under $ROOT"
