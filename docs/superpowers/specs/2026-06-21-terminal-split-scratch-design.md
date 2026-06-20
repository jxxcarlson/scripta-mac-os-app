# Terminal Dock: AI/Terminal Split + Scratch Editor — Design

**Date:** 2026-06-21
**Status:** Approved — ready for implementation plan.

## Goal

Restructure the bottom terminal dock into two side-by-side halves separated by a
draggable vertical divider:

- **Left half:** the AI chat (always visible when the dock is open — no longer a tab).
- **Right half:** a tabbed pane with `Shell 1 | Shell 2 | Scratch`.
- **Scratch** is a new tab to the right of `Shell 2`. Pressing it raises a CodeMirror
  editor occupying the right half. Its content is debounce-saved to `localStorage` in
  real time and restored on launch.
- A thin draggable separator between the halves resizes the division. It cannot be
  dragged closer than **150 px** to the left or right edge of the app.
- The split position is remembered across restarts.

## Decisions (settled during brainstorming)

- **Scratch editor:** reuse the already-vendored `codemirror-editor` custom element
  (a second instance), not a plain textarea.
- **Scratch scope:** a single global buffer — one `localStorage` key, same content
  regardless of which vault is open.
- **Split position:** persisted to `localStorage`.
- **Persistence style:** JS-owned (bypassing Elm), consistent with the existing
  terminal I/O and panel-height-resize code. Elm does not see Scratch keystrokes.

## Current structure (before)

`View.elm` `terminalDock` (≈535–567) is a vertical column:

```
column:
  #terminal-resize-handle (row-resize → height drag)
  tab bar  [AI | Shell 1 | Shell 2]
  keyed content (flex:1, position:relative):
    ai / shell1 / shell2   (each absolute inset:0; active=block else none)
```

The `codemirror-editor` (`frontend/vendor/codemirror-element.js`) is a heavyweight
custom element used for the main document. It exposes a `text` attribute for seeding
content and emits a bubbling, composed `text-change` CustomEvent whose
`detail.source` is the full document string (see `sendText`, ≈26196).

Panel height is a CSS var `--terminal-height` driven by JS drag handlers in
`index.html` (clamp on load/drag/resize + persist to `localStorage['terminalHeight']`).

## Target structure (after)

`terminalDock` becomes:

```
column:
  #terminal-resize-handle (row-resize → height drag)            ← unchanged
  body (display:flex; flex-direction:row; flex:1; min-height:0):
    LEFT  = AI chat        width: var(--terminal-split, 50%); flex:0 0 auto; min-width:0; overflow:hidden
    SEP   = #terminal-split-handle   flex:0 0 6px; cursor:col-resize; background:var(--border)
    RIGHT = column (flex:1; min-width:0):
              tab bar  [Shell 1 | Shell 2 | Scratch]
              keyed content (flex:1; position:relative):
                shell1 / shell2 / scratch  (each absolute inset:0; active=block else none)
```

All three right-pane panels stay mounted (display toggled), so shells keep running and
Scratch keeps its content across tab switches. The AI chat is rendered once in the left
pane and is always visible while the dock is open.

## Components

### 1. Layout (`frontend/src/View.elm`)

- Split `terminalDock`'s content into the `body` row described above.
- New helper for the right pane (tab bar + keyed content). Keep functions small and
  focused; reuse existing `terminalTabButton`, `terminalTabContent`, `terminalPane`,
  `aiChatView`.
- Tab bar list changes from `[("ai","AI"),("shell1","Shell 1"),("shell2","Shell 2")]`
  to `[("shell1","Shell 1"),("shell2","Shell 2"),("scratch","Scratch")]`.
- Left pane wraps `aiChatView model` with `width: var(--terminal-split, 50%)`,
  `flex:0 0 auto`, `min-width:0`, `overflow:hidden`.
- Scratch pane content: `node "codemirror-editor"
  [ id "scratch-editor", attribute "text" model.scratchContent
  , style "display" "block", style "height" "100%", style "width" "100%" ] []`.

### 2. Split var default (`frontend/index.html` CSS)

- Add `--terminal-split: 50%;` to the existing `:root { ... }` rule (alongside
  `--terminal-height`).

### 3. Separator drag (`frontend/index.html` boot script)

Mirror the height-drag block (same clamp/persist/resize discipline). To avoid ever
`parseInt`-ing the `"50%"` default into `50` px, the split works exclusively in px and
reads its current value from `localStorage` (which is only ever written in px) — never
from the computed CSS var:

- `clampSplit(px)` → `Math.max(150, Math.min(window.innerWidth - 150, px))`.
- `applySplit(px, persist)` → `h = clampSplit(px)`; set `--terminal-split` to `h + 'px'`;
  if `persist`, `localStorage.setItem('terminalSplit', h)`. Returns `h`.
- On load: `const s = parseInt(lsGet('terminalSplit'), 10); if (!isNaN(s)) applySplit(s, true);`
  (if unset, the CSS `50%` default stands — the divider sits centered).
- `pointerdown` on `e.target.id === 'terminal-split-handle'` → `dragging = true; preventDefault()`.
- `pointermove` while dragging → `applySplit(e.clientX, false)` (left pane starts at
  x=0 since the dock spans the full app width, so left width = clientX).
- `pointerup` → `applySplit(e.clientX, true)` (persist the final px).
- `resize` listener → `const s = parseInt(lsGet('terminalSplit'), 10); if (!isNaN(s)) applySplit(s, true);`
  (re-clamp the stored px to the new viewport; do nothing if never dragged, so the
  `50%` default is preserved). This never touches the `%` value.

### 4. Scratch persistence (`frontend/index.html` boot script)

- Add flag `scratchContent: lsGet('scratch') || ''` to the `flags` object.
- Add a document-level listener:
  ```js
  let scratchSaveTimer = null;
  document.addEventListener('text-change', function (e) {
    if (!(e.target && e.target.closest && e.target.closest('#scratch-editor'))) return;
    const content = e.detail && e.detail.source != null ? e.detail.source : '';
    clearTimeout(scratchSaveTimer);
    scratchSaveTimer = setTimeout(function () {
      try { localStorage.setItem('scratch', content); } catch (e) {}
    }, 400);
  });
  ```
  (`text-change` bubbles and is composed, so it reaches `document`; `closest('#scratch-editor')`
  distinguishes it from the main document editor's events.)

### 5. Ctrl-S focus guard (`frontend/index.html`)

The existing global Ctrl-S handler runs the document editor's `lrSync()` regardless of
focus. Scratch has no rendered panel, so when focus is inside `#scratch-editor`, Ctrl-S
must do nothing meaningful (Scratch already auto-saves). Update the handler:

```js
window.addEventListener('keydown', function (e) {
  if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S')) {
    e.preventDefault();
    const ae = document.activeElement;
    if (ae && ae.closest && ae.closest('#scratch-editor')) return; // no doc-sync from Scratch
    lrSync();
  }
}, true);
```

### 6. Elm state (`frontend/src/Main.elm`, `Types.elm`)

- `Model`: add `scratchContent : String`. Set once from flags at `init`; never mutated
  (so Elm's virtual DOM never re-sets the `text` attribute and never clobbers the live
  buffer).
- Flags decoder: add a `scratchContent : String` field (default `""`).
- `terminalTab`: default `"shell1"`. Valid values `"shell1" | "shell2" | "scratch"`.
  Remove the `"ai"` case (AI is the always-on left pane). `SelectTerminalTab` unchanged.
- No Elm state for the split — it is a pure CSS var driven by JS, like `--terminal-height`.

## Data flow

- **Split:** drag → JS sets `--terminal-split` → CSS resizes left pane → `pointerup`
  persists px. Boot reads + clamps + re-persists. Window resize re-clamps. Elm uninvolved.
- **Scratch content:** boot reads `localStorage['scratch']` → flag → Elm seeds the
  editor's `text` once → user edits → editor emits `text-change` → JS debounces 400 ms →
  `localStorage['scratch']`. Elm never sees keystrokes; on next launch the flag reseeds.
- **Tab switching:** `SelectTerminalTab` toggles `model.terminalTab`; all panels stay
  mounted (display block/none).

## Error / edge handling

- All `localStorage` access wrapped in `try/catch` (matches existing code).
- Split clamp guarantees `150 ≤ leftWidth ≤ innerWidth − 150`; on a very narrow window
  (< 300 px) the `min`/`max` still produce a valid (possibly pinned) value.
- Oversized/garbage persisted split values are repaired on load by the clamp (same
  pattern as the height fix), so the divider can never get stuck off-screen.
- Scratch editor lives in a `display:none` container until its tab is shown; the
  vendored element already handles deferred measurement on becoming visible (same as
  the document editor). Verify on first `make build`.

## Singleton-editor note

Several `index.html` calls use `document.querySelector('codemirror-editor')` (Ctrl-S
sync, Esc clear). These must keep targeting the **document** editor. The document
editor precedes the Scratch editor in DOM order, so `querySelector` returns it. The
Ctrl-S focus guard (component 5) additionally prevents Scratch-focused Ctrl-S from
acting on the document editor.

## Testing

- **Elm (`frontend/tests`, `Test.Html`):**
  - Right tab bar renders buttons `Shell 1`, `Shell 2`, `Scratch` and does **not**
    render an `AI` tab button.
  - The dock renders a `codemirror-editor` element carrying `id="scratch-editor"`.
  - The AI chat view is present in the dock (left pane).
  - Default `terminalTab` is `"shell1"`.
- **JS (split clamp, debounce, scratch save, Ctrl-S guard):** no JS test harness exists
  in this repo; verified by `make elm` build success + manual check after `make build`,
  consistent with how the existing resize/terminal JS is verified.
- **Regression:** full `elm-test` suite stays green; `cargo test` unaffected (no Rust
  changes).
