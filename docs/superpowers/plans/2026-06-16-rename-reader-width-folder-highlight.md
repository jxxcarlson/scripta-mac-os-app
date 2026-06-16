# Rename to "Scripta", Reader Width 5.5″, Current-Folder Highlight — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the app to "Scripta", widen reader-mode text to 5.5″, and highlight the folder a new document will land in.

**Architecture:** Rename is config-only (`tauri.conf.json` `productName`/title + `index.html` title). Reader width is one CSS value. The folder highlight bundles the tree's highlight inputs into a small `Highlights` record threaded through `fileTree → treeView → nodeView`, where the `FolderNode` matching `parentDir(selectedPath)` gets a lighter-blue fill.

**Tech Stack:** Elm 0.19.1, Tauri 2 bundle config, view-only CSS.

---

## Reference (current state — verified)

- `src-tauri/tauri.conf.json`: line 3 `  "productName": "Mac Scripta Viewer",`; line 13 `      { "title": "Mac Scripta Viewer", "width": 1200, "height": 800 }`. `productName` drives the bundled `.app` name. Identifier `io.scripta.viewer` and Cargo binary `mac-scripta-viewer` are unchanged by this work.
- `frontend/index.html`: line 6 `    <title>Mac Scripta Viewer</title>`.
- `frontend/src/View.elm`:
  - Imports (lines 3–15) include `Language`, `Render`, `Set exposing (Set)`, `Types exposing (Model, Msg(..))`, `Workspace exposing (Node(..))` — but NOT `PathUtil`.
  - `readerView` inner content div (lines 131–135) has `style "max-width" "4.5in"`.
  - `fileTree` (235–245), `treeView` (248–255), `nodeView` (258–305) currently thread `model.selectedPath : Maybe String` (the `FileNode` highlight). The `FolderNode` header `div` (289–298) has `onClick (ToggledFolder r.path)` and is NOT currently highlightable.
- `frontend/src/PathUtil.elm`: `parentDir : String -> String` (tested) returns the folder part of a `/`-separated path, `""` when there is no `/`. Workspace node paths are relative (e.g. `Physics`, `Physics/notes.scripta`).

**Path note:** repo root has a space — always quote. End commit messages with:
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File structure

```
src-tauri/tauri.conf.json   # productName + window title → "Scripta"
frontend/index.html         # <title> → Scripta
frontend/src/View.elm       # reader max-width 5.5in; Highlights record; folder highlight
```

---

### Task 1: Rename the app to "Scripta"

**Files:**
- Modify: `src-tauri/tauri.conf.json`
- Modify: `frontend/index.html`

- [ ] **Step 1: tauri.conf.json — productName**

Change line 3 from:
```json
  "productName": "Mac Scripta Viewer",
```
to:
```json
  "productName": "Scripta",
```

- [ ] **Step 2: tauri.conf.json — window title**

Change the window entry (line 13) from:
```json
      { "title": "Mac Scripta Viewer", "width": 1200, "height": 800 }
```
to:
```json
      { "title": "Scripta", "width": 1200, "height": 800 }
```

- [ ] **Step 3: index.html — document title**

Change line 6 from:
```html
    <title>Mac Scripta Viewer</title>
```
to:
```html
    <title>Scripta</title>
```

- [ ] **Step 4: Verify**

Run: `grep -n "Mac Scripta Viewer" src-tauri/tauri.conf.json frontend/index.html`
Expected: NO matches (the product name is fully renamed).
Run: `python3 -c "import json;print(json.load(open('src-tauri/tauri.conf.json'))['productName'])"`
Expected: `Scripta`.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/tauri.conf.json frontend/index.html
git commit -m "feat: rename app to Scripta (productName, window + document title)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Reader max-width 5.5″

**Files:**
- Modify: `frontend/src/View.elm`

- [ ] **Step 1: Widen the reader content pane**

In `readerView`, change the inner content div's max-width (line 133) from:
```elm
                        , style "max-width" "4.5in"
```
to:
```elm
                        , style "max-width" "5.5in"
```

- [ ] **Step 2: Verify build + tests**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -5` → `Success!`.
Run: `cd frontend && elm-test 2>&1 | tail -6` → 42 pass.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/View.elm
git commit -m "feat: widen reader-mode text max-width to 5.5in

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Highlight the current folder

**Files:**
- Modify: `frontend/src/View.elm`

- [ ] **Step 1: Import PathUtil**

Add `import PathUtil` to the import block (alphabetically, between `import Language` and `import Render`):
```elm
import Language
import PathUtil
import Render
```

- [ ] **Step 2: Add the `Highlights` record alias**

Add this top-level type alias immediately above `fileTree`:
```elm
{-| Tree highlight inputs: the open document (pale-blue pill) and the folder a
new document will land in (lighter-blue fill). `currentFolder` is "" at the
vault root, which matches no folder node.
-}
type alias Highlights =
    { selectedDoc : Maybe String
    , currentFolder : String
    }
```

- [ ] **Step 3: Build the record in `fileTree` and pass it down**

Replace the whole `fileTree` function with:
```elm
fileTree : Model -> Html Msg
fileTree model =
    let
        q =
            String.trim model.searchQuery

        highlights =
            { selectedDoc = model.selectedPath
            , currentFolder =
                model.selectedPath
                    |> Maybe.map PathUtil.parentDir
                    |> Maybe.withDefault ""
            }
    in
    if String.isEmpty q then
        treeView False highlights model.openFolders model.tree

    else
        treeView True highlights model.openFolders (Workspace.filter q model.tree)
```

- [ ] **Step 4: Update `treeView` to carry the record**

Replace the whole `treeView` function with:
```elm
treeView : Bool -> Highlights -> Set String -> List Node -> Html Msg
treeView forceOpen highlights openFolders nodes =
    ul
        [ style "list-style" "none"
        , style "padding-left" "12px"
        , style "font-size" "13px"
        ]
        (List.map (nodeView forceOpen highlights openFolders) nodes)
```

- [ ] **Step 5: Update `nodeView` — record-sourced doc pill + folder highlight**

Replace the whole `nodeView` function with:
```elm
nodeView : Bool -> Highlights -> Set String -> Node -> Html Msg
nodeView forceOpen highlights openFolders node =
    case node of
        FileNode r ->
            li
                ([ onClick (ClickedTreeNode r.path)
                 , style "cursor" "pointer"
                 , style "margin-bottom" "4px"
                 , style "display" "flex"
                 , style "align-items" "flex-start"
                 ]
                    ++ (if Just r.path == highlights.selectedDoc then
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
                    ([ onClick (ToggledFolder r.path)
                     , style "cursor" "pointer"
                     , style "margin-bottom" "4px"
                     , style "display" "flex"
                     , style "align-items" "flex-start"
                     ]
                        ++ (if r.path == highlights.currentFolder then
                                [ style "background-color" "#e8f2fc"
                                , style "border-radius" "3px"
                                , style "padding" "0 4px"
                                ]

                            else
                                []
                           )
                    )
                    [ span [ style "flex" "0 0 auto", style "margin-right" "5px" ] [ folderIcon isOpen ]
                    , span [ style "flex" "1 1 auto" ] [ text r.name ]
                    ]
                    :: (if isOpen then
                            [ treeView forceOpen highlights openFolders r.children ]

                        else
                            []
                       )
                )
```

- [ ] **Step 6: Verify build + tests**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -20` → `Success!`.
Run: `cd frontend && elm-test 2>&1 | tail -6` → 42 pass.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/View.elm
git commit -m "feat: highlight the current folder (where a new doc will land)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Build, reinstall (replace old app), manual verification

**Files:** none (build + manual).

- [ ] **Step 1: Full automated suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make test 2>&1 | tail -15`
Expected: elm-test (42) and cargo test (13) pass.

- [ ] **Step 2: Build + reinstall (remove the old app)**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
make build 2>&1 | tail -6
SRC="src-tauri/target/release/bundle/macos/Scripta.app"
rm -rf "/Applications/Mac Scripta Viewer.app" "/Applications/Scripta.app"
ditto "$SRC" "/Applications/Scripta.app"
ls -d "/Applications/Scripta.app"
```
Expected: `make build` bundles `Scripta.app`; only `/Applications/Scripta.app` remains.

- [ ] **Step 3: Manual verification (GUI — user runs these)**

1. **Name:** the app shows as **Scripta** in the window title bar, the Dock, and Finder; `/Applications` has only `Scripta.app`.
2. **Reader width:** in reader mode the rendered text column is visibly wider (≈5.5″).
3. **Current folder:** open a document inside a subfolder → that folder shows the lighter-blue highlight while the open document keeps its stronger pale-blue pill; open a document in a different folder → the folder highlight moves.
4. **Root case:** with a root-level document open (or none open), no folder is highlighted.

- [ ] **Step 4: Commit any fixes** found during manual testing (none if all good).

---

## Self-review notes (coverage map)

- Rename to "Scripta" → Task 1 (productName + window title + HTML title); bundle becomes `Scripta.app` and old app removed in Task 4 Step 2.
- Reader max-width 5.5″ → Task 2.
- Current-folder highlight → Task 3 (`Highlights` record, `parentDir`-derived `currentFolder`, lighter-blue `#e8f2fc` on the matching `FolderNode`; document pill `#cfe6fb` preserved).

## Out of scope

- Changing the bundle identifier or Cargo binary name.
- Updating any external `scripta` shell command that opens files by app name (not in this repo).
- Click-to-select folder targeting (current folder stays derived from the open document).
