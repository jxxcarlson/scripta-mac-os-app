# Terminal Panel + Working Shells — Design Spec

**Date:** 2026-06-20
**Status:** Approved (pending spec review)

**Sub-project #2 of the "AI terminal" effort.** Delivers the dockable, tabbed terminal panel
**and** real shell sessions in tabs 2 & 3. Tab 1 is reserved for the AI chat (built in #3) — a
placeholder here. The AI agent / vault access is #4.

## Goal

A bottom, drag-resizable, toggle-able terminal panel with three tabs:
- **AI** (tab 1) — placeholder pane ("AI chat — coming in the next step").
- **Shell 1** and **Shell 2** (tabs 2 & 3) — real interactive shells (`$SHELL`) running with their
  working directory set to the open vault, rendered with a full terminal emulator (keys, colors,
  Ctrl-C, arrows, etc.).

The panel starts hidden, is toggled from a toolbar button (state persisted), and its height is
adjustable by dragging its top edge (height persisted).

## Context

- Tauri 2 + Elm desktop app. It already vendors front-end libraries offline (KaTeX under
  `frontend/vendor/`, `vendor/codemirror-element.js`) and uses **custom elements** for non-Elm UI
  (`<codemirror-editor>`, `<math-text>`) wired in `index.html` via `window.__TAURI__` `invoke`/`listen`.
- Rust commands live in `src-tauri/src/` (`fs_commands.rs`), registered in `lib.rs`
  `generate_handler![…]`; managed state is added with `.manage(...)` (e.g. `WatcherState`).
- Non-secret prefs persist via `Flags` + `saveX` ports + `localStorage` (`readerMode`, `isLight`, …).
- `View.view` = root `div` → `toolbar` + `body` (+ settings overlay). `body` is the editor/preview
  region. The terminal dock is a new region below `body`.
- No PTY/terminal code exists yet. `portable-pty` (the wezterm PTY crate) is **not** a dependency.

## Architecture

Three layers, deliberately decoupled (the terminal I/O bypasses Elm, exactly like CodeMirror):

### A. Rust PTY backend (`src-tauri/src/terminal.rs`, new)

- Add the `portable-pty` crate.
- `TerminalState` (managed via `.manage(...)`): a `Mutex<HashMap<String, Session>>` keyed by tab id
  (`"shell1"`, `"shell2"`). A `Session` owns the PTY master writer, the child process handle, and a
  reader-thread join handle.
- Commands (registered in `lib.rs`):
  - `terminal_open(app, state, id, cwd, cols, rows) -> Result<(), String>`: open a PTY pair of size
    `cols×rows`; build a command for `$SHELL` (fallback `/bin/zsh`) with `cwd` set to `cwd` if
    non-empty else `$HOME`; spawn it into the PTY slave; take the master reader and spawn a thread
    that loops reading bytes and emits a Tauri event `terminal-output` with payload
    `{ id, data }` where `data` is **base64** of the raw bytes (preserves escape sequences /
    non-UTF-8); on EOF emit `terminal-exit { id }`. Store the writer + child + thread in state under
    `id` (replacing/closing any existing session with that id first).
  - `terminal_input(state, id, data) -> Result<(), String>`: write `data` (UTF-8 string from the
    emulator) to that session's PTY writer.
  - `terminal_resize(state, id, cols, rows) -> Result<(), String>`: resize that session's PTY.
  - `terminal_close(state, id) -> Result<(), String>`: kill the child, drop the PTY (ends the reader
    thread), remove from the map. Idempotent (closing an absent id is a no-op success).

### B. Terminal emulator — vendored xterm.js + `terminal-pane` custom element (`index.html`)

- Vendor **xterm.js** + **@xterm/addon-fit** (JS + CSS) under `frontend/vendor/xterm/` (offline,
  like KaTeX). Link the CSS and scripts in `index.html`'s `<head>`.
- Define a `terminal-pane` custom element (in the existing boot `<script type="module">`, which has
  `invoke`/`listen` in scope) with attributes `term-id` and `cwd`. Lifecycle:
  - `connectedCallback`: create an `xterm` `Terminal` (+ `FitAddon`), `open()` it into the element,
    `fit()`, then `invoke('terminal_open', { id, cwd, cols, rows })`; wire
    `term.onData(d => invoke('terminal_input', { id, data: d }))`; `listen('terminal-output', e => { if (e.payload.id === id) term.write(base64ToBytes(e.payload.data)); })` (store the unlisten fn);
    on `terminal-exit` for this id, `term.write('\r\n[process exited]\r\n')`.
  - A `ResizeObserver` on the element re-`fit()`s and `invoke('terminal_resize', …)` when its size
    changes (panel resize / window resize / tab shown). **Skip the fit/resize when the element is
    0×0** (i.e. while the dock is hidden via `display:none`) so a hidden pane isn't resized to zero;
    refit when it becomes visible again.
  - `disconnectedCallback`: unlisten, `invoke('terminal_close', { id })`, dispose the `Terminal`.
- Terminal theme follows the app: read the current `--app-bg`/`--app-fg` (or pass light/dark via an
  attribute) so it matches dark mode. (Acceptable to start with xterm's default dark theme and
  refine; not blocking.)

### C. Elm panel UI (`View`, `Types`, `Main`, `Flags`, `FileOps`, `index.html` flags)

- **Model** gains `terminalVisible : Bool`, `terminalEverOpened : Bool` (session-only, not
  persisted), `terminalTab : String` (`"ai"`/`"shell1"`/`"shell2"`, default `"ai"`),
  `terminalHeight : Int` (px, default e.g. 280, clamped to a sane min/max).
- **Toolbar:** a `button [ onClick ToggledTerminal ] [ text "⌘ Terminal" ]` flips `terminalVisible`
  and persists it (`saveTerminalVisible` port, mirroring `saveReaderMode`). The first time it
  becomes visible this session it also sets `terminalEverOpened = True`.
- **Dock (mounted persistently so shells survive hide/show):** render the dock whenever
  `terminalEverOpened` is `True` — i.e. it is mounted lazily on first open and then stays in the
  DOM for the rest of the session — and control visibility with
  `style "display" (if terminalVisible then "flex" else "none")` (NOT by unmounting). Because the
  dock and its `terminal-pane` elements stay connected when hidden, **the shells keep running while
  the panel is hidden**, and you return to them on re-show. The dock contains:
  - a **drag handle** strip on its top edge (see resize below),
  - a **tab bar**: AI · Shell 1 · Shell 2 (clicking sets `terminalTab` via `SelectTerminalTab`),
  - a **content area** mounting **both** shell panes
    (`Html.node "terminal-pane" [ attribute "term-id" "shell1", attribute "cwd" (vaultRoot or "") ] []`
    and `…"shell2"…`) plus the AI placeholder, showing only the active tab (others
    `style "display" "none"`). Both shell panes stay mounted, so **switching tabs preserves each
    shell's session** too.
  - Use `Html.Keyed` (or fixed stable `id`s) for the dock and the `terminal-pane` nodes so Elm's
    vdom never recreates them on tab change / re-render (which would kill the shell).
  - Shells end only when the app quits (or a shell exits on its own). There is no per-tab close
    control in this sub-project.
- **Resize:** the drag handle has a JS pointer-drag (small handler in `index.html`) that adjusts the
  dock's height live and, on pointer-up, sends the final height to Elm via `saveTerminalHeight`
  (persisted) — Elm holds `terminalHeight` and renders the dock at that height. (Same split-of-labor
  as the existing CodeMirror/JS interop: Elm owns the value, JS handles the live drag.)
- **Flags + persistence:** `terminalVisible` (default `False`) and `terminalHeight` (default 280)
  added to `Flags`/`index.html`/`localStorage`, decoded tolerantly. `terminalTab` need not persist.

## Data Flow

```
Toggle:   ⌘ Terminal → ToggledTerminal → terminalVisible := not; saveTerminalVisible
Open:     panel shown → terminal-pane connected → invoke terminal_open(id, cwd, cols, rows)
                                                  → Rust spawns $SHELL in PTY (cwd = vault)
Output:   PTY → reader thread → emit terminal-output {id, data=base64} → pane (id match) → term.write
Input:    keystrokes → xterm onData → invoke terminal_input {id, data}  → PTY writer
Resize:   ResizeObserver / panel drag → fit (skip if 0×0) → invoke terminal_resize {id, cols, rows}
Hide/show: ToggledTerminal → CSS display toggles; panes stay connected → shells keep running
Close:    app quit (or shell self-exits) → disconnected/Drop → terminal_close → kill child
Tabs:     SelectTerminalTab → terminalTab := id (both shell panes stay mounted; CSS shows active)
```

Elm controls only visibility, active tab, and dock height; all terminal I/O is the custom element
↔ Rust, like CodeMirror.

## Error Handling

- `terminal_open` failure (shell missing, PTY error) → `Err` returned to the `invoke` caller; the
  pane writes the error into the terminal view (`term.write('\r\n[failed to start shell: …]\r\n')`).
- `terminal_input`/`resize`/`close` on an unknown id → no-op `Ok` (the session may have exited).
- Shell exits (you type `exit`) → reader thread hits EOF → `terminal-exit` → pane shows
  `[process exited]`. The session is removed from state; the tab stays (reopen the panel to respawn).
- App quit: `TerminalState` dropping closes PTYs/children; no orphan shells.

## Testing

- **Rust:** the PTY lifecycle spawns a real shell — verified manually. A small pure helper if any
  (e.g., resolving the cwd: empty → `$HOME`, else passthrough) gets a unit test; the spawn/read
  loop is integration/manual.
- **Elm:** pure panel-state helpers — `terminalVisible` toggle, `terminalTab` selection,
  `terminalHeight` clamp (min/max) — unit-tested; `Flags` decode of `terminalVisible`/`terminalHeight`
  (present / missing → defaults).
- **Manual (GUI):** open the vault → click ⌘ Terminal → dock appears → Shell 1 runs `$SHELL` with
  `pwd` = the vault → run `ls`, an interactive command, Ctrl-C, arrow-key history → switch to
  Shell 2 (independent session) → switch back (Shell 1 state preserved) → drag the top edge to
  resize → **toggle the panel off then on → the same shell sessions are still there (history
  intact)** → relaunch (visibility + height persist; shells start fresh) → AI tab shows the
  placeholder.

## Out of Scope (later sub-projects / YAGNI)

- AI chat in tab 1 (#3); the AI agent + vault access (#4).
- Restoring shells/scrollback across app launches (shells persist across hide/show within a
  session, but a relaunch starts fresh).
- Terminal splits, more than two shells, configurable shell/font, copy-paste menus beyond xterm
  defaults, search.
- A real keyboard shortcut for toggling (toolbar button only for now).
