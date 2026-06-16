# New-File-In-Current-Folder, Current-Document Highlight, Search-Box Gap — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New documents are created in the open document's folder, the open document is highlighted in the file tree, and the gap above the search box is made clearly visible.

**Architecture:** A pure, tested `PathUtil.siblingPath` derives the target path from `model.selectedPath` (no new model state). `Main.ClickedNewFile` uses it. The View threads `selectedPath` down through `fileTree → treeView → nodeView` to highlight the open file, and bumps the search-box top margin.

**Tech Stack:** Elm 0.19.1, `elm-test`, view-only CSS via `Html.Attributes.style`.

---

## Reference (current state — verified)

- `frontend/src/PathUtil.elm`: `module PathUtil exposing (basename, parentDir)`. `parentDir "c.scripta" == ""`; `parentDir "sub/c.scripta" == "sub"`; `parentDir "/a/b/c.scripta" == "/a/b"`.
- `frontend/tests/PathUtilTest.elm`: a single `suite = describe "PathUtil" [ ... ]` with 5 tests. (Whole-suite baseline across the project is 38 tests.)
- `frontend/src/Main.elm` `ClickedNewFile` (lines 263–280):
  ```elm
        ClickedNewFile ->
            case model.vaultRoot of
                Just root ->
                    let
                        path =
                            ensureScriptaExt model.newName
                    in
                    if String.isEmpty (String.trim model.newName) then
                        ( model, Cmd.none )

                    else
                        request (PCreateFile path)
                            "create_file"
                            [ ( "root", E.string root ), ( "path", E.string path ), ( "content", E.string "" ) ]
                            { model | newName = "" }

                Nothing ->
                    ( model, Cmd.none )
  ```
  `Main` already imports `PathUtil` (used by `Rename`/`openExternalFile`). `Model.selectedPath : Maybe String`.
- `frontend/src/View.elm`:
  - `fileTree` (lines 235–245): `if String.isEmpty q then treeView False model.openFolders model.tree else treeView True model.openFolders (Workspace.filter q model.tree)`.
  - `treeView : Bool -> Set String -> List Node -> Html Msg` (248–255): `ul [...] (List.map (nodeView forceOpen openFolders) nodes)`.
  - `nodeView : Bool -> Set String -> Node -> Html Msg` (258–295): `FileNode r ->` renders an `li` with `onClick (ClickedTreeNode r.path)` and styles `cursor/margin-bottom/display/align-items`; `FolderNode r ->` recurses via `treeView forceOpen openFolders r.children`.
  - `searchBox` (218–229): input has `style "margin-bottom" "8px"` and `style "margin-top" "1mm"`.
  - `Set` is imported as `import Set exposing (Set)`; `Html.Attributes exposing (style)` (qualified `Html.Attributes.*` also works).

**Path note:** repo root has a space — always quote. End commit messages with:
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File structure

```
frontend/
├── src/
│   ├── PathUtil.elm     # + siblingPath (exposed)
│   ├── Main.elm         # ClickedNewFile uses PathUtil.siblingPath
│   └── View.elm         # thread selectedPath; highlight open file; search gap 8px
└── tests/PathUtilTest.elm  # + siblingPath cases
```

---

### Task 1: `PathUtil.siblingPath` (TDD)

**Files:**
- Modify: `frontend/tests/PathUtilTest.elm`
- Modify: `frontend/src/PathUtil.elm`

- [ ] **Step 1: Write the failing tests** — add these four `test` entries to the END of the list inside `describe "PathUtil"` in `frontend/tests/PathUtilTest.elm` (insert them right before the closing `]`, each preceded by a `,`):

```elm
        , test "siblingPath with no reference returns the bare name" <|
            \_ -> Expect.equal "intro.scripta" (PathUtil.siblingPath Nothing "intro.scripta")
        , test "siblingPath beside a root-level doc returns the bare name" <|
            \_ -> Expect.equal "intro.scripta" (PathUtil.siblingPath (Just "notes.scripta") "intro.scripta")
        , test "siblingPath beside a nested doc keeps the folder" <|
            \_ -> Expect.equal "Physics/intro.scripta" (PathUtil.siblingPath (Just "Physics/notes.scripta") "intro.scripta")
        , test "siblingPath beside a deeply nested doc keeps the full folder" <|
            \_ -> Expect.equal "A/B/d.scripta" (PathUtil.siblingPath (Just "A/B/c.scripta") "d.scripta")
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd frontend && elm-test tests/PathUtilTest.elm 2>&1 | tail -10`
Expected: FAIL — `PathUtil.siblingPath` is not exposed / does not exist (compile error naming `siblingPath`).

- [ ] **Step 3: Implement** — in `frontend/src/PathUtil.elm`, change the module line to expose `siblingPath`:
```elm
module PathUtil exposing (basename, parentDir, siblingPath)
```
and add this function at the end of the file:
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

- [ ] **Step 4: Run to verify it passes; full suite**

Run: `cd frontend && elm-test tests/PathUtilTest.elm 2>&1 | tail -10` (9 pass: 5 prior + 4 new).
Then: `cd frontend && elm-test 2>&1 | tail -6` (42 total: 38 prior + 4).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/PathUtil.elm frontend/tests/PathUtilTest.elm
git commit -m "feat: PathUtil.siblingPath — path of a file beside a reference doc

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: New file lands in the current folder

**Files:**
- Modify: `frontend/src/Main.elm`

- [ ] **Step 1: Use `siblingPath` in `ClickedNewFile`**

In `Main.elm` `ClickedNewFile`, replace the `path` binding:
```elm
                    let
                        path =
                            ensureScriptaExt model.newName
                    in
```
with:
```elm
                    let
                        path =
                            PathUtil.siblingPath model.selectedPath (ensureScriptaExt model.newName)
                    in
```
(Leave the rest of `ClickedNewFile` — the empty-name guard, the `create_file` request, `{ model | newName = "" }` — unchanged.)

- [ ] **Step 2: Verify build + tests**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -20` → `Success!`.
Run: `cd frontend && elm-test 2>&1 | tail -6` → 42 pass.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/Main.elm
git commit -m "feat: create new documents in the open document's folder

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Highlight the open document + visible search-box gap

**Files:**
- Modify: `frontend/src/View.elm`

- [ ] **Step 1: Pass `selectedPath` from `fileTree`**

Replace the body of `fileTree` so both `treeView` calls take `model.selectedPath` as a new second argument:
```elm
fileTree : Model -> Html Msg
fileTree model =
    let
        q =
            String.trim model.searchQuery
    in
    if String.isEmpty q then
        treeView False model.selectedPath model.openFolders model.tree

    else
        treeView True model.selectedPath model.openFolders (Workspace.filter q model.tree)
```

- [ ] **Step 2: Add the `selectedPath` parameter to `treeView`**

Replace the whole `treeView` function with:
```elm
treeView : Bool -> Maybe String -> Set String -> List Node -> Html Msg
treeView forceOpen selectedPath openFolders nodes =
    ul
        [ style "list-style" "none"
        , style "padding-left" "12px"
        , style "font-size" "13px"
        ]
        (List.map (nodeView forceOpen selectedPath openFolders) nodes)
```

- [ ] **Step 3: Add the `selectedPath` parameter to `nodeView` and highlight the open file**

Replace the whole `nodeView` function with:
```elm
nodeView : Bool -> Maybe String -> Set String -> Node -> Html Msg
nodeView forceOpen selectedPath openFolders node =
    case node of
        FileNode r ->
            li
                ([ onClick (ClickedTreeNode r.path)
                 , style "cursor" "pointer"
                 , style "margin-bottom" "4px"
                 , style "display" "flex"
                 , style "align-items" "flex-start"
                 ]
                    ++ (if Just r.path == selectedPath then
                            [ style "background-color" "#cfe6fb"
                            , style "border-radius" "3px"
                            , style "padding" "0 4px"
                            ]

                        else
                            []
                       )
                )
                [ span [ style "flex" "0 0 auto", style "margin-right" "5px" ] [ text "-" ]
                , span [ style "flex" "1 1 auto" ] [ text r.name ]
                ]

        FolderNode r ->
            let
                isOpen =
                    forceOpen || Set.member r.path openFolders
            in
            li []
                (div
                    [ onClick (ToggledFolder r.path)
                    , style "cursor" "pointer"
                    , style "margin-bottom" "4px"
                    , style "display" "flex"
                    , style "align-items" "flex-start"
                    ]
                    [ span [ style "flex" "0 0 auto", style "margin-right" "5px" ] [ folderIcon isOpen ]
                    , span [ style "flex" "1 1 auto" ] [ text r.name ]
                    ]
                    :: (if isOpen then
                            [ treeView forceOpen selectedPath openFolders r.children ]

                        else
                            []
                       )
                )
```

- [ ] **Step 4: Make the search-box gap visible**

In `searchBox`, change:
```elm
        , style "margin-top" "1mm"
```
to:
```elm
        , style "margin-top" "8px"
```

- [ ] **Step 5: Verify build + tests**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -20` → `Success!`.
Run: `cd frontend && elm-test 2>&1 | tail -6` → 42 pass.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/View.elm
git commit -m "feat: highlight the open document in the tree; visible search-box gap

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Build, reinstall, manual verification

**Files:** none (build + manual).

- [ ] **Step 1: Full automated suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make test 2>&1 | tail -15`
Expected: elm-test (42) and cargo test (13) pass.

- [ ] **Step 2: Build + reinstall**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
make build 2>&1 | tail -6
SRC="src-tauri/target/release/bundle/macos/Mac Scripta Viewer.app"
DEST="/Applications/Mac Scripta Viewer.app"
rm -rf "$DEST" && ditto "$SRC" "$DEST"
```

- [ ] **Step 3: Manual verification (GUI — user runs these)**

1. **New file in current folder:** open a document inside a subfolder (e.g. `Physics/notes.scripta`), type a name, click **New** → the new file appears inside that subfolder.
2. **New file at root:** with no document open (fresh vault), create a new file → it appears at the vault root.
3. **Highlight:** the open document shows a pale-blue highlight in the tree; clicking a different file moves the highlight to it.
4. **Search gap:** a clearly visible gap sits above the search box.

- [ ] **Step 4: Commit any fixes** found during manual testing (none if all good).

---

## Self-review notes (coverage map)

- New file in current folder → Task 1 (`siblingPath`, tested), Task 2 (`ClickedNewFile` uses it).
- Highlight current document → Task 3 Steps 1–3 (thread `selectedPath`, pale-blue `#cfe6fb` on the matching `FileNode`).
- Visible search-box gap → Task 3 Step 4 (`margin-top: 8px`).

## Out of scope

- Click-to-select a folder as the target (current folder is derived from `selectedPath`).
- Refactoring `Rename` to share `siblingPath` (it already preserves the folder correctly).
- Auto-opening/selecting the newly created file.
- Folder highlighting / a separate current-folder indicator.
