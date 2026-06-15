# `scripta` CLI — Design

**Date:** 2026-06-15
**Status:** Approved (design); implementation plan pending

## Goal

A `scripta <file>` shell command that opens the given `.scripta` (or `.tex` /
`.md`) file in Mac Scripta Viewer. If the app is already running, the file
opens in the existing window (single instance). The file's parent folder
becomes the app's vault, and the file is opened in the editor/preview.

## Decisions

| Decision | Choice |
|---|---|
| Vault behavior | The file's **parent folder becomes the vault**; the file opens |
| App already running | **Reuse the open window** (Tauri single-instance, forward argv) |
| Install location | **`/opt/homebrew/bin/scripta`** (on PATH, user-writable, no sudo) |

## Components

### 1. `scripta` shell script → `/opt/homebrew/bin/scripta`

Resolves the argument to an absolute path and launches the app with it:
```sh
#!/bin/sh
if [ -n "$1" ]; then
  abs="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  open -na "Mac Scripta Viewer" --args "$abs"
else
  open -a "Mac Scripta Viewer"
fi
```
`open -n --args` launches a new app process and delivers the path as the app's
`argv`, which is what the single-instance plugin forwards to the primary
instance. The no-argument form just launches/activates the app. The script is
installed by a committed `install-cli.sh` helper (and documented in the README /
CLAUDE.md) so it can be reinstalled after a rebuild.

### 2. Rust — single-instance + launch-file plumbing (`src-tauri`)

- Add dependency `tauri-plugin-single-instance` (v2), registered as the
  **first** plugin in the builder. Its callback receives the second
  invocation's `argv` (and cwd); it extracts the file path via the shared
  helper and emits an **`open-file`** event (payload `{ path : String }`) to the
  running window.
- On cold start, `setup` reads `std::env::args()` and stores any file path in
  Tauri-managed state `LaunchFile(Mutex<Option<String>>)`.
- New command `take_launch_file() -> Option<String>` returns and clears the
  stored path, for the frontend to pull during `init`.
- Shared pure helper `launch_file_from_args(args: &[String]) -> Option<String>`:
  returns the first argument that is an existing file OR has a recognized doc
  extension (scripta/tex/md), ignoring the program name and flags. Unit-tested.
  Used by both the cold-start path and the single-instance callback.

### 3. Elm — "open this absolute file"

- New `PendingOp` variant `PLaunchFile`; `init` fires a `take_launch_file`
  request through the existing FileOps bridge. The response (a nullable string)
  is handled: `Just abs` → open it; `Nothing` → no-op.
- New inbound port `openFile : (Value -> msg) -> Sub msg` in `FileOps`, wired in
  `index.html` via `listen('open-file', e => app.ports.openFile.send(e.payload))`.
  A new `Msg` `GotOpenFile Value` decodes `{ path }` and opens it.
- Single shared handler `openExternalFile : String -> Model -> ( Model, Cmd Msg )`:
  - `parent = parentDir abs`, `name = basename abs`
  - set `vaultRoot = Just parent`, `selectedPath = Just name`,
    `language = Language.fromPath name`
  - issue `list_workspace`(parent) [`PListWorkspace`], `watch_workspace`(parent)
    [`PNoop`], and `read_file`(root=parent, path=name) [`PReadFile name`],
    batched.
  Reuses the existing `parentDir`; add a `basename` helper. Because the vault is
  the file's parent, the file's workspace-relative path is just its basename, so
  the existing `read_file` and tree-selection logic work unchanged.

## Error handling

- Nonexistent / unreadable path → `read_file` returns an error → surfaced by the
  existing non-blocking error banner.
- No-argument launch → `take_launch_file` returns `Nothing` → normal empty app.
- App not installed in `/Applications` → `open` prints a clear error to the
  terminal (handled by macOS, not the app).
- A forwarded `open-file` event while a document is dirty: opening replaces the
  current document (same behavior as clicking another file in the tree). v1 does
  not prompt; autosave has typically already persisted edits.

## Testing

- **Rust unit test** for `launch_file_from_args`: (a) a real file path present →
  Some; (b) no path / only flags → None; (c) a non-doc argument → None.
- **Elm unit test** for the path math: `basename` and `parentDir` on
  `"/a/b/c.scripta"` → `"c.scripta"` / `"/a/b"`, and a bare filename → itself /
  `""`.
- **Manual:** `scripta f.scripta` on cold start (app opens with f loaded, vault =
  its folder) and with the app already running (file opens in the existing
  window). The shell script + `open` integration is verified manually.

## Build / install impact

The Rust changes require a **rebuild** (`make build`) and **re-copy** of the
`.app` to `/Applications`. The `scripta` script is installed once to
`/opt/homebrew/bin/scripta` (via `install-cli.sh`) and does not need
reinstalling on app rebuilds (it only references the app by name).
