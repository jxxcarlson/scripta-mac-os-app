# Mac Scripta Viewer — Design

**Date:** 2026-06-15
**Status:** Approved (design); implementation plan pending

## Goal

A macOS desktop app with full local filesystem access for creating, reading,
editing, and deleting the user's `.scripta` documents. It reuses the Scripta
compiler for rendering. It is designed so that support for MiniLaTeX (`.tex`)
and extended Markdown (`.md`) can be added later with minimal change.

## Reference codebases

- **`/Users/carlson/dev/elm-work/scripta/scripta-app-v4`** — existing Elm web
  app implementing these features against a *remote* Haskell/PostgreSQL API +
  WebSocket. Source of pieces to port: CodeMirror editor integration,
  render plumbing (`Render.elm`), `FileSystem`/`Node`/`Format` types,
  debounced-save state machine (`SaveState.elm`). Not carried over: JWT auth,
  WebSocket "baton" ownership, version-number optimistic concurrency,
  Cloudflare image upload, collections/notebooks.
- **`/Users/carlson/dev/elm-work/scripta/scripta-compiler-v3`** — library-like
  Elm compiler. Public `Scripta` module exposes `parse` / `reparse` / `render`
  / `compile` / `exportHtml`, returning `Html msg` and an `Event` type. Needs
  KaTeX for math. **Today it parses Scripta input only**; `.tex`/`.md` require
  a `Language` dispatch layer added upstream before they will actually render.

## Key decisions

| Decision | Choice |
|---|---|
| Desktop shell | **Tauri 2 (Rust)** |
| Frontend strategy | **Fresh lean Elm app**, porting selected pieces from v4 |
| Storage model | **Workspace folder ("vault")** of real files on disk |
| Editor | **Port v4's CodeMirror** custom-element integration |
| v1 scope | KaTeX math, live split-pane preview, HTML/LaTeX export, watch-for-external-edits, change-the-vault at runtime |

## Architecture

### Stack & process model

- **Tauri 2 (Rust)** shell owns the disk: workspace listing, read/write/create/
  rename/delete, folder picker, file watching, export "Save As", native menus,
  opening external links.
- **Webview** hosts the compiled Elm app (`elm.js`) plus three JS glue pieces:
  the CodeMirror custom element (ported from v4), KaTeX bundled locally (no
  CDN), and a thin Tauri bridge shim.
- **Elm** holds all UI and state and stays pure — it never touches the
  filesystem and speaks to Rust only through ports.

### Port ↔ command bridge

Tauri `invoke` is Promise-based; Elm ports are fire-and-forget. Every FS
request carries a **`requestId`**; the JS shim awaits the `invoke` and returns
`{requestId, result|error}` on one inbound port. Elm keeps a
`Dict requestId PendingOp` to match responses to requests. File-watcher events
arrive on a separate inbound port (no correlation needed).

```
Elm  --(port fsRequest {requestId, op, args})-->  JS shim  --invoke-->  Rust handler
Elm  <--(port fsResponse {requestId, result})--  JS shim  <--Promise--  Rust handler
Elm  <--(port fileChanged {path, mtime})------  JS shim  <--event-----  Rust watcher
```

### Rust commands (`src-tauri/`)

- `list_workspace(root)` — recursive, extension-filtered (`.scripta`, `.tex`, `.md`)
- `read_file(path)` → `{content, mtime}`
- `write_file(path, content)` → `{mtime}`
- `create_file(path, content)` / `create_dir(path)`
- `rename(path, newPath)`
- `delete(path)` → **OS trash, not hard delete** (recoverable)
- `pick_workspace()` — folder dialog
- `export_save(defaultName, content)` — save dialog
- file watcher emits `file-changed {path, mtime}`

All commands return `Result`; failures surface to Elm as errors, never crashes.

### Elm modules

| Module | Purpose |
|---|---|
| `Main.elm` | wiring: init, update, subscriptions |
| `Types.elm` | `Model`, `Msg`, shared records |
| `Workspace.elm` | file-tree model; **node id = path relative to vault root** (no UUIDs/humanIds) |
| `FileOps.elm` | encode/decode FS port messages + `requestId` correlation |
| `Editor.elm` | CodeMirror integration — DOM ids + `text-change` CustomEvent decoder (ported from v4); the `<codemirror-editor>` element is prebuilt JS copied as-is |
| `Render.elm` | wraps `Scripta.parse/reparse/render`; maps `Event` → `Msg` (ported/trimmed from v4) |
| `SaveState.elm` | debounced-save state machine (trimmed from v4) |
| `Language.elm` | `Scripta \| MiniLaTeX \| Markdown` from file extension (the `.tex`/`.md` seam) |
| `Export.elm` | HTML / LaTeX export wiring |
| `View.elm` | three-pane layout: tree │ editor │ live preview |
| `scripta-compiler/` | vendored copy of compiler-v3 `src/`, used as-is |

## Behavior

### Save model

Single local writer — no version numbers or baton. On keystroke: mark dirty →
debounce **~1s** → `write_file`. Each loaded file's **`mtime`** is recorded.
Before writing, if the watcher reported a newer `mtime` than the one loaded, it
is an **external-edit conflict** → banner offering **Reload** / **Keep mine
(overwrite)**. This is the only concurrency case.

### Render model

Debounced **incremental reparse ~150ms**: keep `parsedDoc` in the model, call
`Scripta.reparse`, then `render` (the v4 pattern). `Event` mapping:

- internal `ilink` / `ClickedId` → scroll/navigate within the preview
- external `ClickedLink` → Rust `shell.open`
- `ClickedImage` / TOC clicks → scroll via a `scrollToElement` port

Parse errors need no special handling — the compiler renders error blocks inline.

### Math (KaTeX, offline)

KaTeX is **vendored into the repo** — `katex.min.css`, `katex.min.js`, the
`mhchem` extension, and the KaTeX fonts are committed as app assets (e.g.
`frontend/vendor/katex/`) and bundled by Tauri. Nothing is fetched from a CDN
at build time or run time, so the app renders math with **no internet
connection**. The Scripta compiler emits `<math-text>` elements; a
**`math-text` custom element** (ported from v4's `index.html`) renders each one
via `katex.renderToString` in its `connectedCallback` — so no `typesetMath`
port is needed; math self-renders when the DOM updates.

Note: KaTeX ships web fonts (`.woff2` etc.); these must be vendored alongside
the CSS and the CSS `@font-face` URLs must resolve to the local copies, or math
glyphs will fall back to system fonts.

### `.tex` / `.md` seam (designed now, wired later)

`Language.elm` maps extension → `Scripta | MiniLaTeX | Markdown`, and
`Render.elm` takes a `Language` argument. **v1 wires Scripta only**; `.tex` /
`.md` files are listed and openable but render a clear "language not yet
supported" placeholder, because the compiler cannot parse them until a
`Language` dispatch layer is added upstream in compiler-v3. The vault's
extension filter already includes all three.

## Error handling

- Rust returns `Result`; failures (permissions, missing file, disk full)
  surface as a **non-blocking toast/banner** in Elm — never a crash.
- Delete confirms, then moves to **OS trash** (recoverable).
- Switching the vault mid-session re-runs `list_workspace` and resets
  editor/preview state.
- External-edit conflict → Reload / Keep-mine banner (see Save model).

## Testing

- **Elm (`elm-test`):** `Workspace` tree-building & decode; `FileOps` port
  encode/decode + requestId correlation; `SaveState` debounce/conflict
  transitions; `Language` extension mapping; `Render` event → msg mapping.
- **Rust:** FS command handlers against a temp dir (create/read/write/rename/
  delete/list; trash-on-delete).
- **Manual smoke checklist:** open vault → edit → autosave → external edit →
  reload → export.
- The vendored compiler retains its own tests; not re-tested here.

## Build & run

`src-tauri/` (Rust) plus a frontend dir with Elm.
`elm make src/Main.elm --output=dist/elm.js`, driven by `tauri dev` /
`tauri build`. A `Makefile` (or npm scripts) chains the Elm build into Tauri.

## Milestones

1. **Skeleton** — Tauri+Elm boot, requestId bridge, pick vault, render file tree.
2. **Read + render** — open a `.scripta` file, live preview with KaTeX.
3. **Edit + save** — CodeMirror, debounced autosave, dirty state.
4. **Full CRUD** — create / rename / delete (trash), change vault.
5. **Watcher + conflict** banner; **export** HTML / LaTeX.
