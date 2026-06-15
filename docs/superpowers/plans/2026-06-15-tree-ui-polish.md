# File-tree & Editor UI Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consistent dark-grey/white buttons (incl. the CodeMirror search panel), abstract filled/outline folder icons, collapsible folders (default closed, remembered per vault via localStorage), and a slightly smaller file-tree font.

**Architecture:** Frontend-only (no Rust). A small tested `OpenFolders` module holds the toggle + decode logic; `Model` gains `openFolders : Set String`; `View` renders folders collapsibly with inline-SVG icons; three localStorage ports persist the open set per vault; button styling is global CSS in `index.html`.

**Tech Stack:** Elm 0.19.1 (+`elm/svg`), `elm-test`, localStorage via ports, CSS.

---

## Reference (current state — verified)

- `frontend/src/Types.elm` `Model` fields (in order): `vaultRoot, tree, selectedPath, nextRequestId, pending, error, content, loadedContent, loadedMtime, externalConflict, parsedDoc, language, isLight, contentWidth, saveState, newName`. `Msg` includes `ClickedTreeNode String`, `GotFsResponse`, etc. `PendingOp` includes `PListWorkspace`, `PNoop`, `PReadFile String`, `PPickWorkspace`, `PLaunchFile`.
- `frontend/src/Main.elm`: `init` builds the full model record inside `request PLaunchFile "take_launch_file" [] {...}`. `request : PendingOp -> String -> List (String, E.Value) -> Model -> (Model, Cmd Msg)`. `openExternalFile abs model` sets `vaultRoot`/`selectedPath`/`language` on `m0` then batches list_workspace + watch_workspace + read_file. `handleResponse` `PPickWorkspace` `Ok (Just root)` branch sets `vaultRoot = Just root` and batches list_workspace + watch_workspace. `subscriptions` batches `FileOps.fsResponse`, `FileOps.fileChanged`, `FileOps.openFile`.
- `frontend/src/View.elm`: `treeView : List Node -> Html Msg` and `nodeView : Node -> Html Msg`; `FolderNode r ->` currently renders `text ("📁 " ++ r.name)` then `treeView r.children` (always). `FileNode r ->` is clickable (`ClickedTreeNode r.path`). The left pane has many `button [...]` elements.
- `frontend/src/FileOps.elm`: `port module FileOps exposing (FsResponse, fsRequest, fsResponse, fileChanged, openFile, scrollToElement, encodeRequest, responseDecoder, resultOf, send)`. Imports `Json.Decode as D`, `Json.Encode as E`.
- `frontend/index.html`: `<style>` block exists; inline boot script obtains `const { listen } = window.__TAURI__.event;` and wires `app.ports.*`.
- `frontend/elm.json`: does NOT list `elm/svg`.
- Workspace `Node`: `FolderNode { path : String, name : String, children : List Node }`, `FileNode { path, name, mtime }`. Folder `path` is workspace-relative, '/'-separated.

**Path note:** repo root has a space — always quote. End commit messages with:
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File structure

```
frontend/
├── src/
│   ├── OpenFolders.elm     # NEW: toggle + decode (pure, tested)
│   ├── Types.elm           # + openFolders field, ToggledFolder/GotOpenFolders msgs
│   ├── Main.elm            # + init field, toggle/decode handlers, load/save wiring, subs
│   ├── FileOps.elm         # + 3 localStorage ports
│   └── View.elm            # collapsible rendering, SVG folder icons, 13px tree font
├── tests/OpenFoldersTest.elm  # NEW
├── elm.json                # + elm/svg
└── index.html              # button CSS + localStorage port handlers
```

---

### Task 1: `OpenFolders` module — toggle + decode (TDD)

**Files:**
- Create: `frontend/src/OpenFolders.elm`
- Create: `frontend/tests/OpenFoldersTest.elm`

- [ ] **Step 1: Write the failing test** — `frontend/tests/OpenFoldersTest.elm`:

```elm
module OpenFoldersTest exposing (suite)

import Expect
import Json.Encode as E
import OpenFolders
import Set
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "OpenFolders"
        [ test "toggle adds a path when absent" <|
            \_ ->
                OpenFolders.toggle "a/b" Set.empty
                    |> Set.member "a/b"
                    |> Expect.equal True
        , test "toggle removes a path when present" <|
            \_ ->
                Set.singleton "a/b"
                    |> OpenFolders.toggle "a/b"
                    |> Set.member "a/b"
                    |> Expect.equal False
        , test "toggle twice returns the original set" <|
            \_ ->
                let
                    start =
                        Set.fromList [ "x", "y" ]
                in
                start
                    |> OpenFolders.toggle "z"
                    |> OpenFolders.toggle "z"
                    |> Expect.equal start
        , test "fromValue decodes a JSON array of strings" <|
            \_ ->
                E.list E.string [ "a", "b/c" ]
                    |> OpenFolders.fromValue
                    |> Expect.equal (Set.fromList [ "a", "b/c" ])
        , test "fromValue of a malformed value is the empty set" <|
            \_ ->
                E.int 42
                    |> OpenFolders.fromValue
                    |> Expect.equal Set.empty
        ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd frontend && elm-test tests/OpenFoldersTest.elm 2>&1 | tail -10`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement** — `frontend/src/OpenFolders.elm`:

```elm
module OpenFolders exposing (fromValue, toggle)

{-| Pure helpers for the set of open (expanded) folder paths in the file tree.
-}

import Json.Decode as D
import Set exposing (Set)


{-| Flip a folder path's membership: remove it if present, otherwise add it.
-}
toggle : String -> Set String -> Set String
toggle path set =
    if Set.member path set then
        Set.remove path set

    else
        Set.insert path set


{-| Decode a persisted JSON array of folder paths into a Set. Any malformed
value yields the empty set (all folders closed).
-}
fromValue : D.Value -> Set String
fromValue value =
    case D.decodeValue (D.list D.string) value of
        Ok xs ->
            Set.fromList xs

        Err _ ->
            Set.empty
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd frontend && elm-test tests/OpenFoldersTest.elm 2>&1 | tail -10`
Expected: 5 pass. Then `cd frontend && elm-test 2>&1 | tail -6` → 28 total (23 prior + 5).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/OpenFolders.elm frontend/tests/OpenFoldersTest.elm
git commit -m "feat: OpenFolders toggle/decode helpers with tests"
```

---

### Task 2: Model state, ports, and load/save wiring

**Files:**
- Modify: `frontend/src/Types.elm`
- Modify: `frontend/src/FileOps.elm`
- Modify: `frontend/src/Main.elm`

- [ ] **Step 1: Types.elm — Model field + imports + Msgs**

Add `import Set exposing (Set)` to Types.elm. Add to `Model` (after `newName`):
```elm
    , openFolders : Set String
```
Add to `Msg`:
```elm
    | ToggledFolder String
    | GotOpenFolders D.Value
```
(`Json.Decode as D` is already imported in Types.elm.)

- [ ] **Step 2: FileOps.elm — add three localStorage ports**

Add `saveOpenFolders`, `requestOpenFolders`, `gotOpenFolders` to the `exposing ( ... )` list, and declare (place after `scrollToElement`):
```elm
port saveOpenFolders : E.Value -> Cmd msg


port requestOpenFolders : String -> Cmd msg


port gotOpenFolders : (E.Value -> msg) -> Sub msg
```

- [ ] **Step 3: Main.elm — imports + init field**

Add `import Set` and `import OpenFolders` to Main.elm. In `init`'s model record (inside the `request PLaunchFile ...` call), add:
```elm
        , openFolders = Set.empty
```

- [ ] **Step 4: Main.elm — a save-command helper**

Add a top-level helper:
```elm
saveOpenFoldersCmd : Maybe String -> Set.Set String -> Cmd Msg
saveOpenFoldersCmd maybeVault folders =
    case maybeVault of
        Just vault ->
            FileOps.saveOpenFolders
                (E.object
                    [ ( "vault", E.string vault )
                    , ( "folders", E.list E.string (Set.toList folders) )
                    ]
                )

        Nothing ->
            Cmd.none
```

- [ ] **Step 5: Main.elm — handle the two new Msgs**

Add update branches:
```elm
        ToggledFolder path ->
            let
                folders =
                    OpenFolders.toggle path model.openFolders
            in
            ( { model | openFolders = folders }
            , saveOpenFoldersCmd model.vaultRoot folders
            )

        GotOpenFolders value ->
            ( { model | openFolders = OpenFolders.fromValue value }, Cmd.none )
```

- [ ] **Step 6: Main.elm — reload open-folders when the vault changes (PPickWorkspace)**

In `handleResponse`'s `PPickWorkspace` `Ok (Just root)` branch, (a) reset `openFolders` to empty on the model that starts the batch, and (b) add a `requestOpenFolders` command. Replace that branch's body with:
```elm
                        Ok (Just root) ->
                            let
                                ( m1, c1 ) =
                                    request PListWorkspace "list_workspace" [ ( "root", E.string root ) ] { model | vaultRoot = Just root, openFolders = Set.empty }

                                ( m2, c2 ) =
                                    request PNoop "watch_workspace" [ ( "root", E.string root ) ] m1
                            in
                            ( m2, Cmd.batch [ c1, c2, FileOps.requestOpenFolders root ] )
```

- [ ] **Step 7: Main.elm — reload open-folders in `openExternalFile`**

In `openExternalFile`, set `openFolders = Set.empty` on `m0` and add `FileOps.requestOpenFolders parent` to the final batch. The function becomes:
```elm
openExternalFile : String -> Model -> ( Model, Cmd Msg )
openExternalFile abs model =
    let
        parent =
            PathUtil.parentDir abs

        name =
            PathUtil.basename abs

        m0 =
            { model
                | vaultRoot = Just parent
                , selectedPath = Just name
                , language = Language.fromPath name
                , openFolders = Set.empty
            }

        ( m1, c1 ) =
            request PListWorkspace "list_workspace" [ ( "root", E.string parent ) ] m0

        ( m2, c2 ) =
            request PNoop "watch_workspace" [ ( "root", E.string parent ) ] m1

        ( m3, c3 ) =
            request (PReadFile name) "read_file" [ ( "root", E.string parent ), ( "path", E.string name ) ] m2
    in
    ( m3, Cmd.batch [ c1, c2, c3, FileOps.requestOpenFolders parent ] )
```

- [ ] **Step 8: Main.elm — subscribe to `gotOpenFolders`**

Add to `subscriptions`'s `Sub.batch` list:
```elm
        , FileOps.gotOpenFolders GotOpenFolders
```

- [ ] **Step 9: Verify**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -20` → Success. (View doesn't use `openFolders` yet — that's Task 3 — which is fine; Elm doesn't warn on an unused record field.) `cd frontend && elm-test 2>&1 | tail -6` → 28 pass.

- [ ] **Step 10: Commit**

```bash
git add frontend/src/Types.elm frontend/src/FileOps.elm frontend/src/Main.elm
git commit -m "feat: track + persist open-folder set per vault"
```

---

### Task 3: View — collapsible tree, SVG folder icons, smaller font

**Files:**
- Modify: `frontend/elm.json` (add `elm/svg`)
- Modify: `frontend/src/View.elm`

- [ ] **Step 1: Add the `elm/svg` dependency**

Run: `cd frontend && yes | elm install elm/svg 2>&1 | tail -5`
Expected: `elm/svg` added to `elm.json` `direct` deps. Verify: `grep elm/svg elm.json`.

- [ ] **Step 2: View.elm — imports**

Add to View.elm imports:
```elm
import Set exposing (Set)
import Svg
import Svg.Attributes as SA
```

- [ ] **Step 3: View.elm — folder icon helper**

Add:
```elm
{-| A small folder glyph: filled black when closed, outline-only when open.
-}
folderIcon : Bool -> Html msg
folderIcon isOpen =
    Svg.svg
        [ SA.width "13"
        , SA.height "13"
        , SA.viewBox "0 0 16 16"
        , SA.style "vertical-align: middle; margin-right: 5px;"
        ]
        [ Svg.path
            [ SA.d "M1.5 4 H6 L7.5 5.5 H14.5 V13 H1.5 Z"
            , SA.stroke "#000"
            , SA.strokeWidth "1"
            , SA.fill
                (if isOpen then
                    "none"

                 else
                    "#000"
                )
            ]
            []
        ]
```

- [ ] **Step 4: View.elm — thread `openFolders` through the tree and collapse**

Replace `treeView` and `nodeView` with versions that take the open set and render a folder's children only when it is open; the folder row toggles on click:
```elm
treeView : Set String -> List Node -> Html Msg
treeView openFolders nodes =
    ul
        [ style "list-style" "none"
        , style "padding-left" "12px"
        , style "font-size" "13px"
        ]
        (List.map (nodeView openFolders) nodes)


nodeView : Set String -> Node -> Html Msg
nodeView openFolders node =
    case node of
        FileNode r ->
            li [ onClick (ClickedTreeNode r.path), style "cursor" "pointer" ] [ text r.name ]

        FolderNode r ->
            let
                isOpen =
                    Set.member r.path openFolders
            in
            li []
                (div
                    [ onClick (ToggledFolder r.path), style "cursor" "pointer" ]
                    [ folderIcon isOpen, text r.name ]
                    :: (if isOpen then
                            [ treeView openFolders r.children ]

                        else
                            []
                       )
                )
```
NOTE: applying `font-size: 13px` on every nested `ul` is harmless (it re-sets the same size); the outer one establishes the smaller tree font. `div` is already imported in View.elm (`Html exposing (... div ...)`); confirm `div` is in the import list and add it if missing.

- [ ] **Step 5: View.elm — update the single `treeView` call site**

In `view` (the left pane), the tree is rendered as `treeView model.tree`. Change it to:
```elm
                           , treeView model.openFolders model.tree
```

- [ ] **Step 6: Verify**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -20` → Success. Fix compile errors (e.g., ensure `div` and `text` are imported; `onClick` already imported). `cd frontend && elm-test 2>&1 | tail -6` → 28 pass.

- [ ] **Step 7: Commit**

```bash
git add frontend/elm.json frontend/src/View.elm
git commit -m "feat: collapsible folders with SVG icons and smaller tree font"
```

---

### Task 4: index.html — button styling + localStorage port handlers

**Files:**
- Modify: `frontend/index.html`

- [ ] **Step 1: Add the button CSS**

In the `<style>` block in `index.html`, add:
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

- [ ] **Step 2: Add the localStorage port handlers**

In the inline boot script (after the existing `app.ports.*` wiring, e.g. near the `scrollToElement` subscription), add:
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

- [ ] **Step 3: Verify wiring present**

Run: `grep -n "cm-button\|saveOpenFolders\|requestOpenFolders\|gotOpenFolders" frontend/index.html`
Expected: the CSS rule and all three port handlers appear.

- [ ] **Step 4: Build the frontend (sanity)**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -3` → Success (no Elm change here, but confirms the app still builds with the ports referenced by JS).

- [ ] **Step 5: Commit**

```bash
git add frontend/index.html
git commit -m "feat: consistent button styling + localStorage open-folder ports"
```

---

### Task 5: Build, reinstall, manual verification

**Files:** none (build + manual).

- [ ] **Step 1: Full automated suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make test 2>&1 | tail -15`
Expected: elm-test (28) and cargo test (13) all pass.

- [ ] **Step 2: Build + reinstall the app**

Run:
```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
make build 2>&1 | tail -6
SRC="src-tauri/target/release/bundle/macos/Mac Scripta Viewer.app"
DEST="/Applications/Mac Scripta Viewer.app"
rm -rf "$DEST" && ditto "$SRC" "$DEST"
```
Expected: bundle built and copied.

- [ ] **Step 3: Manual verification (GUI — user runs these)**

1. Open a vault → all top-level folders are **closed** by default, each with a **filled** folder icon; tree font is a bit smaller.
2. Click a folder → it expands (icon becomes an **outline**), revealing its immediate children (themselves closed). Click again → collapses.
3. Open the editor search panel (Cmd-F) → the **next / previous / all / replace / replace all** buttons are white-on-dark-grey (legible), matching the app's other buttons.
4. Expand a few folders, quit the app, reopen the same vault → the **same folders are still open** (persisted per vault). Open a *different* vault → its own remembered state (independently).

- [ ] **Step 4: Commit any fixes** found during manual testing (none if all good).

---

## Self-review notes (coverage map)

- Consistent buttons (app + `.cm-button`) → Task 4 Step 1.
- SVG folder icons (filled closed / outline open) → Task 3 Steps 2–4.
- Collapsible, default-closed, click-to-toggle → Task 2 (state/msgs) + Task 3 (render).
- Persist open/closed per vault (localStorage) → Task 2 (ports + load/save wiring) + Task 4 Step 2 (JS handlers).
- Smaller tree font (13px) → Task 3 Step 4.
- Tests: `OpenFolders` toggle/decode (Task 1); manual visual (Task 5).
- Build/reinstall impact → Task 5.

## Out of scope

- Pruning stale folder paths from localStorage.
- File-type icons (folders only).
- Expand-all / collapse-all controls.
