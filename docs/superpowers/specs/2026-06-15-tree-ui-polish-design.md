# File-tree & Editor UI Polish — Design

**Date:** 2026-06-15
**Status:** Approved (design); implementation plan pending

## Goal

Four UI improvements to Mac Scripta Viewer:
1. A consistent button style (white on dark grey), fixing the black-on-black
   CodeMirror search-panel buttons.
2. Abstract folder icons in the file tree: filled for closed, outline for open.
3. Collapsible folders — all closed by default, click to toggle, open/closed
   state remembered per vault.
4. A slightly smaller file-tree font.

## Decisions

| Topic | Choice |
|---|---|
| Button palette | `#3a3a3a` bg, white text, `#555` border, `#4a4a4a` hover; applied to `button, .cm-button` |
| Folder icons | inline SVG (~12px): closed = filled, open = outline (stroke only); needs `elm/svg` |
| Default folder state | all folders closed (including nested) |
| Persistence | localStorage, key `openFolders:<vault-abs-path>`, value = JSON array of open folder paths |
| Tree font size | ~13px on the tree container only |

## 1. Consistent button style

In `frontend/index.html` `<style>`:
```css
button, .cm-button {
  background: #3a3a3a;
  color: #fff;
  border: 1px solid #555;
  border-radius: 4px;
  padding: 3px 10px;
  font: inherit;
  cursor: pointer;
  background-image: none;
}
button:hover, .cm-button:hover { background: #4a4a4a; }
```
CodeMirror's search buttons are `<button class="cm-button">`, so this single rule
styles both the app's own buttons (Open Vault, New, Delete, etc.) and the search
panel's (next, previous, all, replace, replace all). `background-image: none`
overrides CodeMirror's default gradient. No Elm changes.

## 2. Abstract folder icons

A `folderIcon : Bool -> Html msg` helper in `View.elm` (argument = isOpen),
rendering a ~12px inline SVG folder:
- **closed:** `fill="#000"` (solid black folder)
- **open:** `fill="none" stroke="#000" stroke-width="1.5"` (outline only)

Requires adding `elm/svg` as a direct dependency (`import Svg`,
`Svg.Attributes`). Files keep plain text with no icon. The icon sits left of the
folder name on the folder row.

## 3. Collapsible folders, default closed, per-vault persistence

### Model & messages
- `Model` gains `openFolders : Set String` — the set of folder paths (workspace-
  relative, '/'-separated, matching `Workspace` `FolderNode.path`) that are open.
- `Msg` gains `ToggledFolder String` and `GotOpenFolders D.Value`.
- `openFolders` initializes to `Set.empty` → every folder closed.

### Rendering (`View.elm`)
- A `FolderNode` renders a clickable row (icon + name); `onClick (ToggledFolder
  path)`. Its children `treeView` is rendered only when `Set.member path
  model.openFolders`. Nested folders are likewise closed until individually
  opened.
- `nodeView`/`treeView` take `openFolders` so they can decide per folder.

### Toggle
`ToggledFolder path` flips membership: if present, remove; else insert. After
updating, persist via the save port (only when `vaultRoot` is `Just`).

### Persistence (localStorage, three ports in `FileOps.elm`)
- `saveOpenFolders : E.Value -> Cmd msg` — payload `{ vault : String, folders :
  List String }`; JS writes `localStorage['openFolders:'+vault] =
  JSON.stringify(folders)`.
- `requestOpenFolders : String -> Cmd msg` — JS reads that key (defaulting to
  `[]` on miss or parse error) and replies on the next port.
- `gotOpenFolders : (E.Value -> msg) -> Sub msg` — payload = JSON array of folder
  path strings → `GotOpenFolders`.

### Load/save lifecycle
- When the vault **changes** (after `pick_workspace` success, and in
  `openExternalFile`/`PLaunchFile` where the parent becomes the vault), set
  `openFolders = Set.empty` and fire `requestOpenFolders <vault>`. The
  `GotOpenFolders` response replaces `openFolders` with the saved set.
- On every `ToggledFolder`, fire `saveOpenFolders { vault, folders =
  Set.toList openFolders }`.
- CRUD `relist` (create/rename/delete) does NOT reload `openFolders` — it keeps
  the current set, since the vault hasn't changed.

### index.html port handlers
```javascript
app.ports.saveOpenFolders.subscribe(({ vault, folders }) => {
  try { localStorage.setItem('openFolders:' + vault, JSON.stringify(folders)); } catch (e) {}
});
app.ports.requestOpenFolders.subscribe((vault) => {
  let folders = [];
  try {
    const raw = localStorage.getItem('openFolders:' + vault);
    folders = raw ? JSON.parse(raw) : [];
  } catch (e) { folders = []; }
  app.ports.gotOpenFolders.send(folders);
});
```

## 4. Tree font size

Set `font-size: 13px` on the tree's root container (the top-level `ul` produced
by `treeView`), leaving the editor and preview panes unchanged.

## Error handling

- `requestOpenFolders` on a missing/corrupt localStorage entry → `[]` (all
  closed). No crash.
- `GotOpenFolders` decode failure → leave `openFolders` unchanged (no crash).
- A persisted folder path that no longer exists in the tree is harmless: it
  simply matches no `FolderNode` and is ignored on render. (It remains in
  localStorage; acceptable for v1.)

## Testing

- **Elm unit tests:**
  - Toggle logic: a pure `toggleFolder : String -> Set String -> Set String`
    (insert if absent, remove if present) — toggling twice returns the original
    set.
  - Decoding the saved list: `D.list D.string` on a JSON array yields the
    expected `List String` (and a malformed value is handled by the caller).
- **Manual / visual:** button colors (app + search panel), folder icons
  (filled vs outline), default-all-closed, click-to-toggle, persistence across
  an app restart (reopen same vault → same folders open), and the smaller tree
  font.

## Build / install impact

These are frontend-only changes (no Rust). After merging, rebuild with
`make build` and re-copy the `.app` to `/Applications` to see them in the
installed app; `make dev` shows them immediately during development.

## Out of scope

- Pruning stale folder paths from localStorage.
- File-type icons (only folder icons are specified).
- Expand-all / collapse-all controls.
