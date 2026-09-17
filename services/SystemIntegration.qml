pragma Singleton

// Status + apply/remove for external Hyprland config Celeste's own features
// depend on (shortcuts, gestures -- see docs/EXTERNAL-CONFIG.md's "Required"
// and "Recommended" sections, which this is the live, in-panel counterpart
// of) plus config Celeste offers to manage on the user's behalf even though
// nothing in Celeste itself needs it (pip -- see below).
//
// IMPORTANT LIMITATION, read before extending this file: Omarchy's plugin
// enable/disable/remove (omarchy-plugin-enable/-disable/-remove) has NO
// lifecycle hooks at all -- confirmed by reading those scripts directly, not
// assumed. Enabling/disabling a plugin is pure data: it flips an entry in
// shell.json's disabledPlugins[] (or moves a bar-kind plugin's id into
// bar.id) and nothing else. There is no "run this when the user disables
// me" mechanism, and once Celeste itself is disabled or removed, none of
// its QML -- this file included -- is running any more to react to that.
//
// So this can only ever be a Celeste-owned settings panel the user drives
// themselves (Celeste Settings -> System), not something that actually
// fires off Omarchy's own enable/disable/remove commands. The practical
// consequence, and the thing the System settings page tells the user
// directly: turn an item off HERE before disabling or removing Celeste
// through Omarchy, since nothing will do it afterwards.
//
// Every write this file makes is scoped to a marker block it owns (`-- BEGIN
// noodlesploder.celeste (<tag>)` / `-- END ...`) and never touches
// unmarked content, even content that does the same thing -- see
// `shortcutsStatus`/`gesturesStatus` below. That matters concretely on the
// machine this was built on: bindings.lua and input.lua already carry this
// exact configuration, hand-written before this feature existed, with no
// marker at all. Treating that as "already managed" and offering to
// "remove" it would delete hand-authored content Celeste never wrote.
// Reported as "external" instead -- present and correct, just not something
// this panel can safely offer to undo.
//
// Deliberately NOT covered here, and why (matches docs/EXTERNAL-CONFIG.md):
//   - Selecting Celeste as the active bar (omarchy shell.json bar.id) --
//     already handled by `omarchy plugin enable` itself for a bar-kind
//     plugin (confirmed by reading omarchy-plugin-enable: it sets bar.id
//     automatically and prints "Now using <id> as the bar"). Nothing for
//     Celeste to add.
//   - Per-monitor workspace blocks / SUPER+1..6 rebinding -- a personal
//     Hyprland workspace-numbering scheme, not a Celeste dependency. Celeste
//     works fine on plain global workspaces; wiring this into Celeste's own
//     lifecycle would silently reach into config that has nothing to do
//     with which bar is active.
//   - The dock hotplug recovery workaround -- EXTERNAL-CONFIG.md files this
//     under "This machine only" for a reason: it is a fix for a kernel bug
//     on this specific hardware, unrelated to Celeste. Bundling it into
//     Celeste's lifecycle would be scope creep the doc itself argues
//     against.
//   - Required CLI tools (brightnessctl, inotify-tools) -- reported as a
//     status check only. Installing packages can require an interactive
//     sudo password prompt, which a headless Process launched from a
//     settings toggle cannot supply (see the Omarchy skill's own privilege
//     rule: an interactive command needs a visible terminal). The panel
//     shows what is missing and the exact command to run, not a button that
//     silently runs one.
//
// pip/applyPip(): Omarchy already floats+pins+corner-docks browser
// Picture-in-Picture windows by default (default/hypr/apps/pip.lua) -- this
// toggle only removes the fixed 600x338 size + forced aspect ratio it also
// applies, so a popped-out video can be freely resized. Two things asked for
// alongside this were deliberately NOT built here:
//   - Guaranteed always-on-top-of-every-window, not just above the tiled
//     layout: Hyprland has no static declarative "stay on top of all other
//     floating windows" rule (confirmed via the compiled binary's own
//     symbol strings -- only a one-shot `alter_zorder` dispatcher exists,
//     which would need a running watcher re-raising the window on every
//     focus/open event to hold permanently, a materially different feature
//     from a window rule toggle).
//   - Hide/unhide the pip window -- explicitly scoped as future work when
//     this was requested, not part of this pass.
// A third ask, an in-page icon/glyph on web video players indicating the
// pop-out is available, is out of Celeste's reach entirely -- a Hyprland/
// Quickshell bar plugin has no access to a browser tab's page content; that
// would need a separate browser extension project. Browsers already surface
// their own native PiP affordance on hover, independent of any of this.

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string bindingsPath: root.home + "/.config/hypr/bindings.lua"
    readonly property string inputPath: root.home + "/.config/hypr/input.lua"
    readonly property string autostartPath: root.home + "/.config/hypr/autostart.lua"
    readonly property string hyprlandPath: root.home + "/.config/hypr/hyprland.lua"

    readonly property string shortcutsBegin: "-- BEGIN noodlesploder.celeste (shortcuts)"
    readonly property string shortcutsEnd: "-- END noodlesploder.celeste (shortcuts)"
    readonly property string gesturesBegin: "-- BEGIN noodlesploder.celeste (gestures)"
    readonly property string gesturesEnd: "-- END noodlesploder.celeste (gestures)"
    readonly property string pipBegin: "-- BEGIN noodlesploder.celeste (pip)"
    readonly property string pipEnd: "-- END noodlesploder.celeste (pip)"

    // "managed"  -- our own marker block is present (we can safely remove it)
    // "external" -- the content Celeste needs is present, but not inside our
    //               marker (hand-written, or added before this feature
    //               existed) -- present and correct, but not ours to remove
    // "absent"   -- neither; the feature will not work until this is added
    function statusFor(text, beginMarker, needleRe) {
        if (text.indexOf(beginMarker) !== -1)
            return "managed";
        if (needleRe.test(text))
            return "external";
        return "absent";
    }

    // Mutable, not `readonly property string x: fileView.text()` -- that
    // shape was tried first and silently never populates inside a
    // pragma Singleton: isolated with a minimal reproduction (a singleton
    // QtObject with exactly this binding stayed permanently empty, while the
    // identical binding in a plain, non-singleton QtObject loaded correctly
    // straight away). Matches why Config.qml and OmarchyMenu.qml never use
    // this shape either -- both assign into a mutable property from
    // onLoaded/onFileChanged instead, which is what these three now do too.
    property string bindingsText: ""
    property string inputText: ""
    property string autostartText: ""
    property string hyprlandText: ""

    readonly property string shortcutsStatus: root.statusFor(
        root.bindingsText, root.shortcutsBegin, /celeste:menu|celeste:overview\b/)
    readonly property string gesturesStatus: root.statusFor(
        root.inputText, root.gesturesBegin, /celeste:overviewShow|celeste:overviewHide/)
    // externalPattern here is necessarily fuzzier than shortcuts/gestures' --
    // there's no unique dispatcher string to key off, so it looks for the
    // one property this block actually changes (the aspect-ratio unlock)
    // sitting near Omarchy's own PiP title match, not an exact phrase.
    readonly property string pipStatus: root.statusFor(
        root.hyprlandText, root.pipBegin, /Picture[\s\S]{0,300}keep_aspect_ratio\s*=\s*false/)

    // The exact diagnostic CLAUDE.md documents for this: a stray, uncommented
    // exec_on_start line starting a second full Omarchy shell.
    readonly property bool autostartHasStrayLine: {
        const lines = root.autostartText.split("\n");
        for (const line of lines) {
            const t = line.trim();
            if (t.indexOf("quickshell") !== -1
                && t.indexOf("/usr/share/omarchy/shell") !== -1
                && t.indexOf("--") !== 0)
                return true;
        }
        return false;
    }

    property int duplicateShellCount: 1
    property string lastAction: ""
    property string lastResult: ""

    function refreshDuplicateCheck() {
        duplicateCheck.running = true;
    }

    Component.onCompleted: root.refreshDuplicateCheck()

    // ------------------------------------------------------------- writers
    //
    // Every write: back up first, use awk (not sed) for the marker-range
    // delete so the marker text is matched as a literal substring, never as
    // a regex -- bindings.lua's own name has a "." in it, which sed would
    // treat as "any character". Reload Hyprland and check for config errors
    // afterward; a broken write rolls itself back from the backup it just
    // made, so a bad apply cannot leave the user's Hyprland unusable.
    //
    // THE SCRIPT BELOW IS A FIXED CONSTANT. Nothing is interpolated into it.
    // Paths, markers, Lua bodies and patterns all arrive as real argv
    // elements ($1..$6) via Process.command, so there is no shell-quoting
    // layer to get wrong and no way for a body's own quotes or newlines to
    // change the script's meaning. That replaces the old _q() helper (and
    // the _applyScript/_removeScript string builders) outright -- the
    // "one escaping layer, applied once" problem is gone because there is
    // now zero escaping to do.
    //
    // Hardening, all of it against a same-user process racing these paths:
    //   - Traversal is anchored: every target must resolve (realpath -e)
    //     inside the verified, owned $HOME/.config/hypr, whose own
    //     descriptor is opened once and checked (dev:inode + uid) so the
    //     directory itself cannot be swapped underneath the transaction.
    //   - A target that IS a symlink, or whose canonical path differs from
    //     the path we were handed (a symlinked parent, a ".." component),
    //     is refused rather than followed.
    //   - Each file is opened ONCE. What the descriptor actually reached is
    //     compared against a fresh stat of the pathname (dev:inode), which
    //     catches a swap that landed between the check and the open; owner
    //     and size are checked on the descriptor, not the name. Every later
    //     read is a bounded `head -c` from /proc/self/fd/N -- the pathname
    //     is never reopened, so there is no second window to race, and a
    //     FIFO or an endless file cannot block or exhaust the shell.
    //   - Writes go to an exclusively-created mktemp file in the target's
    //     own directory, are fsynced, then renamed over the target.
    //     rename(2) replaces the directory entry itself and never follows
    //     it, so the final swap is safe even if the name was replaced with
    //     a symlink after we started.
    //   - The backup path is computed once per transaction and that exact
    //     path is what a rollback restores. The old `ls -t "${F}".bak.*`
    //     pick is gone: it chose rollback data by glob and mtime, which an
    //     attacker could seed.
    //   - hyprctl runs under a deadline with its output capped in memory.
    //     The old predictable /tmp/celeste-hypr-reload.log target is gone
    //     too -- it was a symlink-plant waiting to happen.
    //
    // Two behaviours carried over from the string-builders this replaces,
    // both load-bearing:
    //
    //   `apply` refuses when the equivalent hand-written content is already
    //   present (the external_re check). That is defence in depth, not the
    //   only guard -- the settings page only offers "Apply" when the status
    //   already reads "absent" -- but the write path should never trust a
    //   caller for something this consequential: appending our own marked
    //   block on top of unmarked content doing the same thing would leave
    //   two conflicting hl.unbind/o.bind (or hl.gesture) calls for the same
    //   key, so it reports "external" instead, same as the UI's status read.
    //
    //   `remove` deletes the marker range with awk's index() (a plain
    //   substring search), never a regex -- the marker text contains "."
    //   and "(", both regex metacharacters a sed pattern would have to
    //   escape. It also buffers one line behind rather than printing
    //   immediately, so the blank line `apply` inserts just before BEGIN is
    //   dropped retroactively once BEGIN is seen. Confirmed by testing an
    //   apply/remove cycle in isolation: without that, every toggle off left
    //   one more blank line at the same spot than the last, growing without
    //   bound.
    readonly property string _safeIoScript: [
        "set -euo pipefail",
        "MAX_BYTES=$((2*1024*1024))",
        "DEADLINE=8",
        "fail() { echo \"$1\"; exit 1; }",
        "ALLOWED_DIR=$(realpath -e -- \"$HOME/.config/hypr\") || fail anchor-resolve-failed",
        "if [[ ! -d \"$ALLOWED_DIR\" || -L \"$ALLOWED_DIR\" ]]; then fail anchor-invalid; fi",
        "exec {DFD}<\"$ALLOWED_DIR\" || fail anchor-open-failed",
        "dir_by_path=$(stat -c '%d:%i' -- \"$ALLOWED_DIR\") || fail anchor-stat-failed",
        "dir_by_fd=$(stat -L -c '%d:%i' -- \"/proc/self/fd/$DFD\") || fail anchor-stat-fd-failed",
        "if [[ \"$dir_by_path\" != \"$dir_by_fd\" ]]; then fail anchor-race; fi",
        "dir_owner=$(stat -L -c '%u' -- \"/proc/self/fd/$DFD\") || fail anchor-owner-failed",
        "if [[ \"$dir_owner\" != \"$(id -u)\" ]]; then fail anchor-not-owned; fi",
        "dir_mode=$(stat -L -c '%a' -- \"/proc/self/fd/$DFD\") || fail anchor-mode-failed",
        "if (( 0$dir_mode & 0022 )); then fail \"anchor-writable-by-others:$dir_mode\"; fi",
        "TMP_FILE=",
        "cleanup() { if [[ -n ${TMP_FILE:-} ]]; then rm -f -- \"$TMP_FILE\"; fi; }",
        "trap cleanup EXIT",
        "RESOLVED_PATH=",
        "resolve_anchored() {",
        "  local raw=\"$1\" real",
        "  if [[ -L \"$raw\" ]]; then fail \"refuse-symlink:$raw\"; fi",
        "  real=$(realpath -e -- \"$raw\") || fail \"resolve-failed:$raw\"",
        "  case \"$real\" in \"$ALLOWED_DIR\"/*) ;; *) fail \"outside-anchor:$real\" ;; esac",
        "  if [[ \"$real\" != \"$raw\" ]]; then fail \"path-not-canonical:$raw\"; fi",
        "  RESOLVED_PATH=\"$real\"",
        "}",
        "OPEN_FD=",
        "open_verified() {",
        "  local path=\"$1\" a b owner size mode",
        "  if [[ -L \"$path\" ]]; then fail \"refuse-symlink:$path\"; fi",
        "  if [[ ! -f \"$path\" ]]; then fail \"refuse-nonregular:$path\"; fi",
        "  exec {OPEN_FD}<\"$path\" || fail \"open-failed:$path\"",
        "  a=$(stat -c '%d:%i' -- \"$path\") || fail \"stat-failed:$path\"",
        "  b=$(stat -L -c '%d:%i' -- \"/proc/self/fd/$OPEN_FD\") || fail \"stat-fd-failed:$path\"",
        "  if [[ \"$a\" != \"$b\" ]]; then fail \"race-detected:$path\"; fi",
        "  owner=$(stat -L -c '%u' -- \"/proc/self/fd/$OPEN_FD\") || fail \"stat-owner-failed:$path\"",
        "  if [[ \"$owner\" != \"$(id -u)\" ]]; then fail \"not-owned:$path\"; fi",
        "  size=$(stat -L -c '%s' -- \"/proc/self/fd/$OPEN_FD\") || fail \"stat-size-failed:$path\"",
        "  if [ \"$size\" -gt \"$MAX_BYTES\" ]; then fail \"too-large:$path\"; fi",
        "  mode=$(stat -L -c '%a' -- \"/proc/self/fd/$OPEN_FD\") || fail \"stat-mode-failed:$path\"",
        "  if (( 0$mode & 0022 )); then fail \"writable-by-others:$path ($mode)\"; fi",
        "}",
        "read_verified() { head -c \"$MAX_BYTES\" \"/proc/self/fd/$1\"; }",
        "atomic_write() {",
        "  local path=\"$1\" dir tmp",
        "  dir=$(dirname -- \"$path\")",
        "  tmp=$(mktemp -- \"$dir/.celeste-tmp.XXXXXXXX\") || fail \"mktemp-failed:$path\"",
        "  TMP_FILE=\"$tmp\"",
        "  cat > \"$tmp\"",
        "  sync -- \"$tmp\" || fail \"fsync-failed:$path\"",
        "  mv -f -- \"$tmp\" \"$path\"",
        "  TMP_FILE=",
        "  sync -- \"$dir\" 2>/dev/null || true",
        "}",
        "make_backup() { head -c \"$MAX_BYTES\" \"/proc/self/fd/$1\" | atomic_write \"$2\"; }",
        "restore_backup() {",
        "  if [[ ! -f \"$1\" || -L \"$1\" ]]; then fail \"backup-missing:$1\"; fi",
        "  cat -- \"$1\" | atomic_write \"$2\"",
        "}",
        "run_capped() {",
        "  local out status",
        "  set +e",
        "  out=$(timeout \"$DEADLINE\" \"$@\" 2>&1 | head -c 65536)",
        "  status=$?",
        "  set -e",
        "  printf '%s' \"$out\"",
        "  return \"$status\"",
        "}",
        "verb=\"$1\"",
        "resolve_anchored \"$2\"; path=$RESOLVED_PATH",
        "case \"$verb\" in",
        "apply)",
        "  begin=\"$3\"; end=\"$4\"; body=\"$5\"; external_re=\"$6\"",
        "  open_verified \"$path\"; fd=$OPEN_FD",
        "  content=$(read_verified \"$fd\")",
        "  if grep -qF -- \"$begin\" <<<\"$content\"; then echo already-managed; exit 0; fi",
        "  if grep -qE -- \"$external_re\" <<<\"$content\"; then echo external; exit 0; fi",
        "  backup=\"$path.bak.$(date -u +%Y%m%d%H%M%S).$$\"",
        "  make_backup \"$fd\" \"$backup\"",
        "  { printf '%s\\n' \"$content\"; printf '\\n%s\\n%s\\n%s\\n' \"$begin\" \"$body\" \"$end\"; } | atomic_write \"$path\"",
        "  exec {fd}<&-",
        "  if ! reload_out=$(run_capped hyprctl reload); then",
        "    restore_backup \"$backup\" \"$path\"",
        "    echo reload-failed; printf '%s\\n' \"$reload_out\"; exit 1",
        "  fi",
        "  errors=$(run_capped hyprctl configerrors || true)",
        "  if [[ -n \"$errors\" && \"$errors\" != \"no errors\"* ]]; then",
        "    restore_backup \"$backup\" \"$path\"",
        "    run_capped hyprctl reload >/dev/null || true",
        "    echo config-errors; printf '%s\\n' \"$errors\"; exit 1",
        "  fi",
        "  echo applied",
        "  ;;",
        "remove)",
        "  begin=\"$3\"; end=\"$4\"",
        "  open_verified \"$path\"; fd=$OPEN_FD",
        "  content=$(read_verified \"$fd\")",
        "  if ! grep -qF -- \"$begin\" <<<\"$content\"; then echo not-managed; exit 0; fi",
        "  backup=\"$path.bak.$(date -u +%Y%m%d%H%M%S).$$\"",
        "  make_backup \"$fd\" \"$backup\"",
        "  new_content=$(awk -v b=\"$begin\" -v e=\"$end\" '" +
            "index($0,b)==1{skip=1; if (have && prev==\"\") have=0; next} " +
            "index($0,e)==1{skip=0; next} " +
            "skip{next} " +
            "{if (have) print prev; prev=$0; have=1} " +
            "END{if (have) print prev}" +
            "' <<<\"$content\")",
        "  printf '%s\\n' \"$new_content\" | atomic_write \"$path\"",
        "  exec {fd}<&-",
        "  if ! reload_out=$(run_capped hyprctl reload); then",
        "    restore_backup \"$backup\" \"$path\"",
        "    echo reload-failed; printf '%s\\n' \"$reload_out\"; exit 1",
        "  fi",
        "  echo removed",
        "  ;;",
        "fix-autostart)",
        "  open_verified \"$path\"; fd=$OPEN_FD",
        "  content=$(read_verified \"$fd\")",
        "  if ! grep -qE '^[^-].*quickshell.*/usr/share/omarchy/shell' <<<\"$content\"; then echo clean; exit 0; fi",
        "  backup=\"$path.bak.$(date -u +%Y%m%d%H%M%S).$$\"",
        "  make_backup \"$fd\" \"$backup\"",
        "  new_content=$(sed -E 's#^([[:space:]]*)(o\\.exec_on_start\\(\"quickshell[^\"]*/usr/share/omarchy/shell\"\\).*)#\\1-- \\2  -- disabled by Celeste (starts a duplicate shell)#' <<<\"$content\")",
        "  printf '%s\\n' \"$new_content\" | atomic_write \"$path\"",
        "  exec {fd}<&-",
        "  echo fixed",
        "  ;;",
        "*) fail \"unknown-verb:$verb\" ;;",
        "esac"
    ].join("\n")

    // luaBody strings below use plain, real newlines and real quotes, and
    // are handed over as argv elements -- nothing parses them as shell, so
    // they need no escaping at all.
    function applyShortcuts() {
        root.lastAction = "shortcuts";
        writer.command = ["bash", "-c", root._safeIoScript, "celeste-safe-io", "apply",
            root.bindingsPath, root.shortcutsBegin, root.shortcutsEnd,
            "hl.unbind(\"SUPER + SPACE\")\n" +
            "o.bind(\"SUPER + SPACE\", \"Omarchy menu\", hl.dsp.global(\"celeste:menu\"))\n" +
            "hl.unbind(\"CTRL + TAB\")\n" +
            "o.bind(\"CTRL + TAB\", \"Workspace overview\", hl.dsp.global(\"celeste:overview\"))",
            "celeste:menu|celeste:overview"];
        writer.running = true;
    }

    function removeShortcuts() {
        root.lastAction = "shortcuts";
        writer.command = ["bash", "-c", root._safeIoScript, "celeste-safe-io", "remove",
            root.bindingsPath, root.shortcutsBegin, root.shortcutsEnd];
        writer.running = true;
    }

    function applyGestures() {
        root.lastAction = "gestures";
        writer.command = ["bash", "-c", root._safeIoScript, "celeste-safe-io", "apply",
            root.inputPath, root.gesturesBegin, root.gesturesEnd,
            "hl.gesture({ fingers = 4, direction = \"horizontal\", action = \"workspace\" })\n" +
            "hl.gesture({ fingers = 4, direction = \"up\", action = function() hl.dispatch(hl.dsp.global(\"celeste:overviewShow\")) end })\n" +
            "hl.gesture({ fingers = 4, direction = \"down\", action = function() hl.dispatch(hl.dsp.global(\"celeste:overviewHide\")) end })",
            "celeste:overviewShow|celeste:overviewHide"];
        writer.running = true;
    }

    function removeGestures() {
        root.lastAction = "gestures";
        writer.command = ["bash", "-c", root._safeIoScript, "celeste-safe-io", "remove",
            root.inputPath, root.gesturesBegin, root.gesturesEnd];
        writer.running = true;
    }

    // Omarchy's own default (default/hypr/apps/pip.lua, loaded before this
    // file's own requires -- see hyprland.lua) already floats, pins, and
    // corner-docks any window whose title matches this exact pattern, plus
    // Google Meet's chromium PiP. It also forces a fixed 600x338 size with
    // keep_aspect_ratio, which is the one thing this overrides: reusing
    // Omarchy's own title match (not re-deriving it) so this stays in sync
    // with whatever Omarchy already tags as PiP, rather than drifting from
    // it. float/pin/opacity/border are re-asserted rather than left implicit
    // so this block still works even if Omarchy's own default ever changes.
    function applyPip() {
        root.lastAction = "pip";
        writer.command = ["bash", "-c", root._safeIoScript, "celeste-safe-io", "apply",
            root.hyprlandPath, root.pipBegin, root.pipEnd,
            "o.window({ title = \"(Picture.?in.?[Pp]icture)\" }, {\n" +
            "  float = true,\n" +
            "  pin = true,\n" +
            "  keep_aspect_ratio = false,\n" +
            "  border_size = 0,\n" +
            "  opacity = \"1 1\",\n" +
            "})\n" +
            "o.window({ tag = \"chromium-based-browser\", title = \"^Meet - .+\" }, {\n" +
            "  float = true,\n" +
            "  pin = true,\n" +
            "  keep_aspect_ratio = false,\n" +
            "  border_size = 0,\n" +
            "  opacity = \"1 1\",\n" +
            "})",
            "keep_aspect_ratio\\s*=\\s*false"];
        writer.running = true;
    }

    function removePip() {
        root.lastAction = "pip";
        writer.command = ["bash", "-c", root._safeIoScript, "celeste-safe-io", "remove",
            root.hyprlandPath, root.pipBegin, root.pipEnd];
        writer.running = true;
    }

    // Comments out the stray autostart line rather than deleting it, so the
    // reason it is inert stays visible in the file if anyone looks. Backs up
    // first; no-ops (reports "clean") if the line is already gone or already
    // commented -- safe to click more than once.
    function fixAutostart() {
        root.lastAction = "autostart";
        writer.command = ["bash", "-c", root._safeIoScript, "celeste-safe-io",
            "fix-autostart", root.autostartPath];
        writer.running = true;
    }

    property FileView bindingsFile: FileView {
        path: root.bindingsPath
        watchChanges: true
        printErrors: false
        onLoaded: root.bindingsText = text()
        onFileChanged: reload()
    }

    property FileView inputFile: FileView {
        path: root.inputPath
        watchChanges: true
        printErrors: false
        onLoaded: root.inputText = text()
        onFileChanged: reload()
    }

    property FileView autostartFile: FileView {
        path: root.autostartPath
        watchChanges: true
        printErrors: false
        onLoaded: root.autostartText = text()
        onFileChanged: reload()
    }

    property FileView hyprlandFile: FileView {
        path: root.hyprlandPath
        watchChanges: true
        printErrors: false
        onLoaded: root.hyprlandText = text()
        onFileChanged: reload()
    }

    property Process writer: Process {
        id: writer
        stdout: StdioCollector {
            id: writerOut
            waitForEnd: true
            onStreamFinished: {
                root.lastResult = writerOut.text.trim();
                bindingsFile.reload();
                inputFile.reload();
                autostartFile.reload();
                hyprlandFile.reload();
                root.refreshDuplicateCheck();
            }
        }
    }

    // CLAUDE.md's own documented diagnostic, run literally: "There must be
    // exactly one." pgrep -c -f alone miscounts (it also matches the wrapper
    // command line), so this greps the full command lines instead and counts
    // rows, the same as the manual check.
    property Process duplicateCheck: Process {
        id: duplicateCheck
        command: ["bash", "-c", "ps -eo cmd | grep quickshell | grep -v grep | grep -c '/usr/share/omarchy/shell' || true"]
        stdout: StdioCollector {
            id: dupOut
            waitForEnd: true
            onStreamFinished: {
                const n = parseInt(dupOut.text.trim(), 10);
                root.duplicateShellCount = isNaN(n) ? 1 : n;
            }
        }
    }

    property bool hasBrightnessctl: true
    property bool hasInotifywait: true

    property Process toolCheck: Process {
        id: toolCheck
        command: ["bash", "-c", "command -v brightnessctl >/dev/null && echo b:1 || echo b:0; command -v inotifywait >/dev/null && echo i:1 || echo i:0"]
        stdout: StdioCollector {
            id: toolOut
            waitForEnd: true
            onStreamFinished: {
                const text = toolOut.text;
                root.hasBrightnessctl = text.indexOf("b:1") !== -1;
                root.hasInotifywait = text.indexOf("i:1") !== -1;
            }
        }
    }

    function refreshToolCheck() {
        toolCheck.running = true;
    }
}
