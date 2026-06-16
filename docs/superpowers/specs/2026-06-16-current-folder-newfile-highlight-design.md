# New-File-In-Current-Folder, Current-Document Highlight, Search-Box Gap — Design Spec

**Date:** 2026-06-16

## Goal

1. **Create new documents in the current folder.** A new file should land in the folder of the
   currently open document (e.g. with `Physics/notes.scripta` open, "intro" → `Physics/intro.scripta`),
   instead of always at the vault root.
2. **Highlight the current document** in the file tree so the user can see which file is open.
3. **Make the gap above the file-tree search box visibly larger** (the existing 1 mm is imperceptible).

## Current state (verified)

- `frontend/src/Main.elm` `ClickedNewFile` (lines 263–280): builds the create path as
  `ensureScriptaExt model.newName` — a bare name relative to the vault root, ignoring any open
  document. Issues `create_file` with `{ root, path, content="" }`, then (`PCreateFile _` →
  `relist model`) re-lists the workspace.
- `Main.elm` `ClickedRename` (lines 293–316): ALREADY preserves the folder — it computes
  `dir = PathUtil.parentDir path` and rebuilds `newPath = (if dir == "" then "" else dir ++ "/") ++ ensureScriptaExt model.newName`.
  No change needed here; the new-file helper mirrors this logic.
- `frontend/src/PathUtil.elm`: exposes `parentDir : String -> String` (returns `""` for a
  root-level/relative file with no separator). Tested in `frontend/tests/PathUtilTest.elm`.
- `Model.selectedPath : Maybe String` holds the workspace-relative path of the open document
  (e.g. `Physics/notes.scripta`; bare basename when opened as an external file). It is the source
  of truth for both "current folder" and "current document."
- `frontend/src/View.elm`: `fileTree model` → `treeView : Bool -> Set String -> List Node -> Html Msg`
  → `nodeView : Bool -> Set String -> Node -> Html Msg`. `nodeView` does NOT currently receive
  `selectedPath`, so it cannot highlight the open file. The `FileNode` branch renders an `li`
  with `onClick (ClickedTreeNode r.path)`. `searchBox` (lines 218–229) has
  `style "margin-bottom" "8px"` and `style "margin-top" "1mm"`.
- `Workspace.Node = FileNode { path, name, mtime } | FolderNode { path, name, children }`; node
  paths are workspace-relative (e.g. `Physics/notes.scripta`).

## Design

### 1. New file in the current folder

Add a pure, tested helper to `PathUtil.elm`:

```elm
{-| Path of a file named `fileName` placed in the same folder as `reference`
(the open document, if any). No reference, or a reference at the vault root,
yields `fileName` itself; a nested reference yields `<folder>/<fileName>`.
-}
siblingPath : Maybe String -> String -> String
siblingPath reference fileName =
    case reference of
        Nothing ->
            fileName

        Just ref ->
            case parentDir ref of
                "" ->
                    fileName

                dir ->
                    dir ++ "/" ++ fileName
```

`Main.ClickedNewFile` changes its `path` binding to:
```elm
        path =
            PathUtil.siblingPath model.selectedPath (ensureScriptaExt model.newName)
```
Everything else in `ClickedNewFile` (empty-name guard, `create_file` request, `relist`) is unchanged.
`Rename` is left as-is (already correct).

**Behavior:** open doc in `Physics/` → new file in `Physics/`; open doc at root → root; no doc open
→ root. In the folder cases the folder is already expanded (the user navigated into it), so the new
file appears in place after the relist.

### 2. Highlight the current document

Thread the open document's path into the tree render so the matching `FileNode` is highlighted:

- `fileTree` passes `model.selectedPath` down.
- `treeView` and `nodeView` gain a `Maybe String` parameter (the selected path).
- In the `FileNode` branch, when `Just r.path == selectedPath`, apply a persistent highlight to the
  `li`: `background-color: #cfe6fb` (the app's pale-blue palette), plus `border-radius: 3px` and a
  small horizontal padding so the tint reads as a pill rather than a full-width bar. Non-selected
  files and all folders render exactly as today.

Signature change (threaded, not global state):
```elm
treeView : Bool -> Maybe String -> Set String -> List Node -> Html Msg
nodeView : Bool -> Maybe String -> Set String -> Node -> Html Msg
```
(The recursive `treeView` call inside the `FolderNode` branch forwards the same `selectedPath`.)

### 3. Search-box gap

In `searchBox`, change `style "margin-top" "1mm"` to `style "margin-top" "8px"` — a clearly visible
gap consistent with the `8px` spacing rhythm already used in the tree column.

## Files touched

- `frontend/src/PathUtil.elm` — add `siblingPath` (+ export).
- `frontend/tests/PathUtilTest.elm` — tests for `siblingPath`.
- `frontend/src/Main.elm` — `ClickedNewFile` uses `PathUtil.siblingPath`.
- `frontend/src/View.elm` — thread `selectedPath` through `fileTree`/`treeView`/`nodeView`; highlight
  the open file; search-box `margin-top: 8px`.

## Testing

- **TDD** for `PathUtil.siblingPath` in `PathUtilTest.elm`:
  - `siblingPath Nothing "intro.scripta" == "intro.scripta"`
  - `siblingPath (Just "notes.scripta") "intro.scripta" == "intro.scripta"` (root-level doc)
  - `siblingPath (Just "Physics/notes.scripta") "intro.scripta" == "Physics/intro.scripta"`
  - `siblingPath (Just "A/B/c.scripta") "d.scripta" == "A/B/d.scripta"` (nested)
- Highlight + search gap are view-only → `elm make` build + manual GUI check.
- `elm-test` (current baseline 38, will rise by the new `siblingPath` cases) and `cargo test` (13)
  stay green.
- **Manual checklist:**
  1. With a doc open in a subfolder, create a new file → it appears in that subfolder.
  2. With no doc open, create a new file → it appears at the vault root.
  3. The open document is visibly highlighted (pale blue) in the tree; clicking another file moves
     the highlight.
  4. A clearly visible gap sits above the search box.

## Decisions / out of scope

- "Current folder" is derived from `selectedPath` (no new model state, no click-to-select folder).
- Rename keeps its existing (already-correct) folder-preserving behavior; not refactored to share
  `siblingPath`.
- Not auto-opening/selecting the newly created file (unchanged from current behavior).
- Folder highlighting / a separate "current folder" indicator is out of scope.
