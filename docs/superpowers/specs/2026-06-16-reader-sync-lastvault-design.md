# Reader Mode, Ctrl-S Sync, Remember-Last-Vault — Design

**Date:** 2026-06-16
**Status:** Approved (design); implementation plan pending

## Goal

Three features for Mac Scripta Viewer:
1. **Reader mode** — a persisted toggle that shows only the rendered preview
   (hides the file tree and editor).
2. **Ctrl-S / Cmd-S left-to-right sync** — jump from the editor cursor to the
   corresponding rendered text, scroll it into view, and highlight it.
3. **Remember last vault** — on a plain launch (no CLI file argument), reopen the
   vault that was last used.

## Decisions

| Topic | Choice |
|---|---|
| Reader mode persistence | Persisted across restarts (localStorage), restored via an Elm flag |
| Reader exit | Same toggle button, kept in an always-visible top toolbar |
| Sync key(s) | Both Ctrl-S and Cmd-S (both `preventDefault`) |
| Last vault | Auto-open last vault on plain launch; a CLI file argument wins |
| Initial prefs load | Elm **flags** (read from localStorage in `index.html` before init) |

## 1. Reader mode

- `Model` gains `readerMode : Bool`; `Msg` gains `ToggledReaderMode`.
- `View` renders a thin **top toolbar** (always visible) containing a **Reader**
  toggle button. Below the toolbar:
  - normal: the existing three-pane row (tree | editor | preview);
  - reader: only the rendered preview, full width.
- The conflict banner continues to render above this content when active.
- `ToggledReaderMode` flips the flag and fires `FileOps.saveReaderMode` (port →
  localStorage key `readerMode`).
- Initial value comes from the `readerMode` flag (default `False`).

## 2. Ctrl-S / Cmd-S left-to-right sync

Implemented entirely in `index.html` JS + CSS (no Elm, no compiler change),
because the rendered Scripta output already carries the line-encoding `id`s the
rendered→editor jump uses; we reverse that mapping.

- A `keydown` listener (on `window`, capture phase) for
  `(e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S')`:
  `e.preventDefault()`, then run the sync.
- Sync steps:
  1. `ed = document.querySelector('codemirror-editor')?.editor`; bail if none.
  2. `pos = ed.state.selection.main.head`; `line0 = ed.state.doc.lineAt(pos).number - 1` (0-indexed).
  3. `rendered = document.getElementById('__RENDERED_TEXT__')`; bail if none.
  4. Scan `rendered.querySelectorAll('[id]')`; parse each `id` to a 0-indexed
     source line with a local `parseLineNumber` (mirrors the bundle's:
     `e-N.T` → `N`; block `N-I` → `N`). Choose the element whose parsed line
     equals `line0`; if none, the element with the greatest parsed line `<= line0`
     (nearest preceding). Bail if none.
  5. `el.scrollIntoView({ block: 'center', behavior: 'smooth' })`.
  6. Clear any existing `.lr-sync-highlight`, then add it to `el`.
- CSS: define `.lr-sync-highlight { background-color: #fff2a8; }` (soft yellow,
  with a brief transition) in `index.html`. The bundle already adds this class
  for MiniLaTeX; defining the style makes it visible for Scripta too.

This new handler is independent of the bundle's `setupLRSync` (which only fires
on an editor `selection`-attribute change that this app never sets), so there is
no conflict.

## 3. Remember last vault

- `FileOps.saveLastVault : String -> Cmd msg` (port → localStorage key
  `lastVault`).
- A shared `openVault : String -> Model -> ( Model, Cmd Msg )` helper in `Main`
  sets `vaultRoot`, clears `selectedPath`/`content`/`loadedContent`/`parsedDoc`
  and `openFolders`, and batches: `list_workspace`, `watch_workspace` (tagged
  `PNoop`), `requestOpenFolders`, and `saveLastVault`. Used by:
  - the folder picker success path (`PPickWorkspace`),
  - `openExternalFile` (which additionally reads the file; it opens the file's
    parent as the vault, so it also calls `saveLastVault parent`),
  - the auto-reopen path.
- **Launch precedence:** `init` still fires `take_launch_file` first. In
  `handleResponse` `PLaunchFile`:
  - `Ok (Just abs)` → `openExternalFile abs` (CLI file wins),
  - otherwise → if the `lastVault` flag is present, `openVault lastVault`; else
    leave the app empty.
  The model keeps the flag's `lastVault` (e.g. `initialLastVault : Maybe String`)
  so the `PLaunchFile` handler can use it.

## Flags

`main : Program Flags Model Msg` where:
```elm
type alias Flags = { lastVault : Maybe String, readerMode : Bool }
```
`index.html` reads localStorage before `Elm.Main.init`:
```javascript
function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
const flags = {
  lastVault: lsGet('lastVault'),                 // string | null
  readerMode: lsGet('readerMode') === 'true'     // bool
};
const app = Elm.Main.init({ node: document.getElementById('app'), flags: flags });
```
A `flagsDecoder` (or `Json.Decode` via `Program`) maps this to `Flags`, tolerating
missing/garbage values (defaults: `lastVault = Nothing`, `readerMode = False`).

## Error handling

- All localStorage access is wrapped in try/catch in `index.html` (returns
  `null`/default on failure).
- A saved `lastVault` that no longer exists → `list_workspace` returns an error
  surfaced by the existing error banner; the app stays usable.
- Ctrl-S with no editor / no rendered output / no matching element → no-op.
- Flag decode failure → defaults (empty app, reader off).

## Testing

- **Elm unit test** for the flags decoder: a full object decodes to the record;
  missing `lastVault` → `Nothing`; missing/garbage `readerMode` → `False`.
- **Manual / GUI:** Reader toggle hides/show panes and persists across restart;
  Ctrl-S and Cmd-S scroll+highlight the rendered text for the cursor's line;
  launching with no CLI argument reopens the last vault (and a `scripta <file>`
  launch still wins); the per-vault folder expansion is restored.

## Build / install impact

Frontend-only. After merging, `make build` + re-`ditto` the `.app` to
`/Applications`.

## Out of scope

- Reader-mode keyboard shortcut (button only).
- Sync highlight fade-out timing beyond a simple CSS transition.
- Pruning a stale `lastVault` from localStorage.
