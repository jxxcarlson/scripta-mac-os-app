# Rename to "Scripta", Reader Width 5.5″, Current-Folder Highlight — Design Spec

**Date:** 2026-06-16

## Goal

1. **Rename the app to "Scripta"** (window title, Dock/Finder name, HTML title; bundle becomes
   `Scripta.app`).
2. **Widen the reader-mode rendered text** max-width from 4.5″ to 5.5″.
3. **Highlight the current folder** in the file tree — the folder a new document will land in — so
   the user can see where "New" will create the file.

## Current state (verified)

- App name appears in exactly three places: `src-tauri/tauri.conf.json` `"productName": "Mac Scripta Viewer"`
  (line 3) and the window `"title": "Mac Scripta Viewer"` (line 13), and `frontend/index.html`
  `<title>Mac Scripta Viewer</title>` (line 6). `productName` drives the bundled `.app` name.
  The Cargo crate/binary name is `mac-scripta-viewer` (`src-tauri/Cargo.toml`); the bundle identifier
  is `io.scripta.viewer`. No Makefile/shell/install script references the product name.
- `frontend/src/View.elm`:
  - `readerView` inner content `div` has `style "max-width" "4.5in"` (line 133).
  - `fileTree` (lines 235–245) calls `treeView <forceOpen> model.selectedPath model.openFolders <nodes>`.
  - `treeView : Bool -> Maybe String -> Set String -> List Node -> Html Msg` forwards
    `(nodeView forceOpen selectedPath openFolders)`.
  - `nodeView : Bool -> Maybe String -> Set String -> Node -> Html Msg`: the `FileNode` branch
    appends a pale-blue (`#cfe6fb`) pill to the `li` when `Just r.path == selectedPath`; the
    `FolderNode` branch renders a clickable header `div` (`onClick (ToggledFolder r.path)`) and
    recurses via `treeView`.
  - `View` imports do NOT currently include `PathUtil`.
- `frontend/src/PathUtil.elm`: `parentDir : String -> String` (tested) returns the folder part of a
  `/`-separated workspace-relative path, `""` when there is no `/`. `Model.selectedPath : Maybe String`
  is the open document's workspace-relative path. Node paths are workspace-relative (e.g. `Physics`,
  `Physics/notes.scripta`).

## Design

### 1. Rename to "Scripta"

- `tauri.conf.json`: `productName` → `"Scripta"`; window `title` → `"Scripta"`.
- `index.html`: `<title>Scripta</title>`.
- Unchanged: Cargo binary name (`mac-scripta-viewer`, internal), bundle identifier
  (`io.scripta.viewer`, so saved prefs / last-vault carry over).
- Build produces `src-tauri/target/release/bundle/macos/Scripta.app`. Install step removes
  `/Applications/Mac Scripta Viewer.app` and any stale `/Applications/Scripta.app`, then `ditto`s the
  new `Scripta.app` in.

### 2. Reader max-width 5.5″

- `View.elm` `readerView`: change the inner content div's `style "max-width" "4.5in"` to
  `style "max-width" "5.5in"`. No other change.

### 3. Current-folder highlight

Bundle the tree's highlight inputs into a small record so the tree functions take one descriptive
argument instead of several adjacent positional ones (a light refactor of the `selectedPath`
threading added previously):

```elm
type alias Highlights =
    { selectedDoc : Maybe String   -- open document's workspace-relative path
    , currentFolder : String       -- folder a new doc lands in; "" = vault root
    }
```

- Add `import PathUtil` to `View.elm`.
- `fileTree` builds the record from the model and passes it down:
  ```elm
  highlights =
      { selectedDoc = model.selectedPath
      , currentFolder =
          model.selectedPath
              |> Maybe.map PathUtil.parentDir
              |> Maybe.withDefault ""
      }
  ```
  Both `treeView` calls take `highlights` in place of the current `model.selectedPath` argument.
- `treeView : Bool -> Highlights -> Set String -> List Node -> Html Msg` forwards the record to
  `nodeView`; the recursive `treeView` call in the `FolderNode` branch forwards it too.
- `nodeView : Bool -> Highlights -> Set String -> Node -> Html Msg`:
  - `FileNode`: pale-blue pill (`#cfe6fb`, `border-radius 3px`, `padding 0 4px`) when
    `Just r.path == h.selectedDoc` (same visual as today, sourced from the record).
  - `FolderNode`: the clickable header `div` gets a **lighter blue fill** (`#e8f2fc`,
    `border-radius 3px`, `padding 0 4px`) when `r.path == h.currentFolder`. Because real folder
    nodes always have a non-empty path, an empty `currentFolder` ("" — root-level or no open doc)
    matches nothing, so nothing is highlighted and files simply land at the top level.

With `Physics/notes.scripta` open: `Physics` shows the light-blue folder fill and `notes.scripta`
shows the stronger pill simultaneously.

## Files touched

- `src-tauri/tauri.conf.json` — `productName` + window `title` → "Scripta".
- `frontend/index.html` — `<title>` → "Scripta".
- `frontend/src/View.elm` — `import PathUtil`; `Highlights` record; thread it through
  `fileTree`/`treeView`/`nodeView`; folder highlight; reader `max-width: 5.5in`.

## Testing

- `PathUtil.parentDir` is already tested; no new pure logic. Rename + reader width + folder highlight
  are config/view → `elm make` build + manual GUI.
- `elm-test` (42) and `cargo test` (13) stay green.
- **Manual checklist:**
  1. App shows as **Scripta** in the title bar, Dock, and Finder; only one app in `/Applications`
     (`Scripta.app`).
  2. Reader-mode rendered text is wider (≈5.5″).
  3. With a doc open in a subfolder, that folder shows the lighter-blue highlight; the open doc shows
     the stronger pill; opening a doc in another folder moves the folder highlight.
  4. With a root-level doc or no doc open, no folder is highlighted.

## Decisions / out of scope

- Folder highlight is a **lighter blue fill** (`#e8f2fc`), distinct from the document pill (`#cfe6fb`).
- Bundle identifier and Cargo binary name unchanged; only the user-visible product name changes.
- A `scripta` shell command that opens files by app name (if any exists outside this repo) is the
  user's to update; not in scope.
- No click-to-select folder targeting (current folder remains derived from the open document).
