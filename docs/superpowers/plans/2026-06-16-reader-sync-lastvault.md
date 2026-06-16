# Reader Mode, Ctrl-S Sync, Remember-Last-Vault Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted reader-mode toggle (preview only), Ctrl-S/Cmd-S left-to-right sync (cursor → rendered text, scroll + highlight), and auto-reopen of the last vault on a plain launch.

**Architecture:** Initial prefs (`lastVault`, `readerMode`) come in as Elm flags read from localStorage in `index.html`; saving uses ports. Reader mode is Elm view/state. The Ctrl-S sync is pure `index.html` JS + CSS that reverses the existing line-encoding `id` scheme on rendered Scripta elements. A shared `openVault` helper unifies the picker / CLI-open / last-vault paths.

**Tech Stack:** Elm 0.19.1, `elm-test`, localStorage via flags + ports, CSS/JS in `index.html`.

---

## Reference (current state — verified)

- `frontend/src/Main.elm`: `main : Program () Model Msg`; `init : () -> ( Model, Cmd Msg )` builds the full model record inside `request PLaunchFile "take_launch_file" [] { ... }`. `request : PendingOp -> String -> List (String, E.Value) -> Model -> ( Model, Cmd Msg )`. `openExternalFile abs model` sets `vaultRoot`/`selectedPath`/`language`/`openFolders=Set.empty` on `m0`, then batches list_workspace + watch_workspace (PNoop) + read_file + `FileOps.requestOpenFolders parent`. `handleResponse` `PPickWorkspace` `Ok (Just root)` sets `vaultRoot`, `openFolders = Set.empty`, batches list + watch + `FileOps.requestOpenFolders root`. `handleResponse` `PLaunchFile` handles `Ok (Just abs) -> openExternalFile`, `_ -> (model, Cmd.none)`. `update` has `GotOpenFolders`, `SetSearchQuery`, etc. No `_ ->` wildcard in the `Msg` `case` — a new Msg needs a branch.
- `frontend/src/Types.elm`: `Model` ends `..., openFolders : Set String, searchQuery : String`. `Msg` includes `SetSearchQuery String` etc. `PendingOp` includes `PNoop`, `PListWorkspace`, `PReadFile String`, `PLaunchFile`.
- `frontend/src/FileOps.elm`: `port module FileOps exposing ( FsResponse, fsRequest, fsResponse, fileChanged, openFile, scrollToElement, saveOpenFolders, requestOpenFolders, gotOpenFolders, encodeRequest, responseDecoder, resultOf, send )`. Imports `Json.Decode as D`, `Json.Encode as E`.
- `frontend/src/View.elm`: `view` builds `threePaneRow` (tree | editor | preview) and returns `div [column] (conflictBanner model ++ [ threePaneRow ])`. `previewBody : Model -> List (Html Msg)` exists. `Editor.renderedTextId` is the preview container id. Imports include `Html exposing (Html, button, div, li, span, text, ul)`, `Html.Attributes`, `Html.Events exposing (onClick, onInput)`.
- `frontend/index.html`: `const app = Elm.Main.init({ node: document.getElementById('app') });` (line ~144). Has `window.__TAURI__` wiring, `listen('file-changed')`, `listen('open-file')`, `scrollToElement`, and the `saveOpenFolders`/`requestOpenFolders` localStorage handlers. `<style>` block has the `--cm-*` palette + button rules.

**Path note:** repo root has a space — always quote. End commit messages with:
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File structure

```
frontend/
├── src/
│   ├── Flags.elm        # NEW: Flags type + tolerant decode (tested)
│   ├── Types.elm        # + readerMode, initialLastVault fields; ToggledReaderMode Msg
│   ├── Main.elm         # Program D.Value; init from flags; openVault helper; reader + last-vault wiring
│   ├── FileOps.elm      # + saveReaderMode, saveLastVault ports
│   └── View.elm         # top toolbar + Reader button; reader-mode layout
├── tests/FlagsTest.elm  # NEW
└── index.html           # pass flags; save ports; Ctrl/Cmd-S sync JS + .lr-sync-highlight CSS
```

---

### Task 1: `Flags` decoder (TDD)

**Files:**
- Create: `frontend/src/Flags.elm`
- Create: `frontend/tests/FlagsTest.elm`

- [ ] **Step 1: Write the failing test** — `frontend/tests/FlagsTest.elm`:

```elm
module FlagsTest exposing (suite)

import Expect
import Flags
import Json.Encode as E
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Flags.decode"
        [ test "decodes a full flags object" <|
            \_ ->
                let
                    v =
                        E.object [ ( "lastVault", E.string "/Users/me/vault" ), ( "readerMode", E.bool True ) ]

                    f =
                        Flags.decode v
                in
                Expect.equal ( Just "/Users/me/vault", True ) ( f.lastVault, f.readerMode )
        , test "missing lastVault decodes to Nothing" <|
            \_ ->
                let
                    f =
                        Flags.decode (E.object [ ( "readerMode", E.bool False ) ])
                in
                Expect.equal Nothing f.lastVault
        , test "null lastVault decodes to Nothing" <|
            \_ ->
                let
                    f =
                        Flags.decode (E.object [ ( "lastVault", E.null ), ( "readerMode", E.bool False ) ])
                in
                Expect.equal Nothing f.lastVault
        , test "missing/garbage readerMode defaults to False" <|
            \_ ->
                let
                    f =
                        Flags.decode (E.object [ ( "readerMode", E.string "yes" ) ])
                in
                Expect.equal False f.readerMode
        , test "a non-object value yields defaults" <|
            \_ ->
                let
                    f =
                        Flags.decode (E.int 5)
                in
                Expect.equal ( Nothing, False ) ( f.lastVault, f.readerMode )
        ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd frontend && elm-test tests/FlagsTest.elm 2>&1 | tail -10`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement** — `frontend/src/Flags.elm`:

```elm
module Flags exposing (Flags, decode)

{-| App-launch preferences read from localStorage (via JS) as a JSON value.
Decoding is tolerant: any missing or malformed field falls back to a default.
-}

import Json.Decode as D


type alias Flags =
    { lastVault : Maybe String
    , readerMode : Bool
    }


decode : D.Value -> Flags
decode value =
    { lastVault =
        D.decodeValue (D.field "lastVault" (D.nullable D.string)) value
            |> Result.withDefault Nothing
    , readerMode =
        D.decodeValue (D.field "readerMode" D.bool) value
            |> Result.withDefault False
    }
```

- [ ] **Step 4: Run to verify it passes; full suite**

Run: `cd frontend && elm-test tests/FlagsTest.elm 2>&1 | tail -10` (5 pass), then `cd frontend && elm-test 2>&1 | tail -6` (38 total: 33 prior + 5).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Flags.elm frontend/tests/FlagsTest.elm
git commit -m "feat: Flags decoder for launch prefs (lastVault, readerMode)"
```

---

### Task 2: Elm wiring — flags, ports, reader state, openVault, last-vault

**Files:**
- Modify: `frontend/src/Types.elm`
- Modify: `frontend/src/FileOps.elm`
- Modify: `frontend/src/Main.elm`

- [ ] **Step 1: Types.elm — Model fields + Msg**

Add to `Model` (after `searchQuery`):
```elm
    , readerMode : Bool
    , initialLastVault : Maybe String
```
Add to `Msg`:
```elm
    | ToggledReaderMode
```

- [ ] **Step 2: FileOps.elm — two save ports**

Add `saveReaderMode` and `saveLastVault` to the `exposing ( ... )` list, and declare (after `gotOpenFolders`):
```elm
port saveReaderMode : Bool -> Cmd msg


port saveLastVault : String -> Cmd msg
```

- [ ] **Step 3: Main.elm — Program + init from flags**

Add `import Flags`. Change the signatures and init:
```elm
main : Program D.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = View.view
        }


init : D.Value -> ( Model, Cmd Msg )
init flagsValue =
    let
        flags =
            Flags.decode flagsValue
    in
    request PLaunchFile
        "take_launch_file"
        []
        { vaultRoot = Nothing
        , tree = []
        , selectedPath = Nothing
        , nextRequestId = 0
        , pending = Dict.empty
        , error = Nothing
        , content = ""
        , loadedContent = ""
        , loadedMtime = 0
        , externalConflict = False
        , parsedDoc = Nothing
        , language = Nothing
        , isLight = True
        , contentWidth = 500
        , saveState = SaveState.init
        , newName = ""
        , openFolders = Set.empty
        , searchQuery = ""
        , readerMode = flags.readerMode
        , initialLastVault = flags.lastVault
        }
```
(Use the EXACT existing field set plus the two new fields; only the wrapping/flag use changes.)

- [ ] **Step 4: Main.elm — `openVault` helper**

Add a top-level helper:
```elm
{-| Open a folder as the vault: list + watch it, restore its remembered open
folders, and persist it as the last-used vault. Clears any open document.
-}
openVault : String -> Model -> ( Model, Cmd Msg )
openVault root model =
    let
        m0 =
            { model
                | vaultRoot = Just root
                , selectedPath = Nothing
                , content = ""
                , loadedContent = ""
                , parsedDoc = Nothing
                , openFolders = Set.empty
            }

        ( m1, c1 ) =
            request PListWorkspace "list_workspace" [ ( "root", E.string root ) ] m0

        ( m2, c2 ) =
            request PNoop "watch_workspace" [ ( "root", E.string root ) ] m1
    in
    ( m2, Cmd.batch [ c1, c2, FileOps.requestOpenFolders root, FileOps.saveLastVault root ] )
```

- [ ] **Step 5: Main.elm — use `openVault` in the picker path**

Replace the `PPickWorkspace` `Ok (Just root) ->` body with:
```elm
                        Ok (Just root) ->
                            openVault root model
```

- [ ] **Step 6: Main.elm — refactor `openExternalFile` to reuse `openVault`**

Replace `openExternalFile` with:
```elm
openExternalFile : String -> Model -> ( Model, Cmd Msg )
openExternalFile abs model =
    let
        parent =
            PathUtil.parentDir abs

        name =
            PathUtil.basename abs

        ( m1, c1 ) =
            openVault parent model

        m2 =
            { m1 | selectedPath = Just name, language = Language.fromPath name }

        ( m3, c3 ) =
            request (PReadFile name) "read_file" [ ( "root", E.string parent ), ( "path", E.string name ) ] m2
    in
    ( m3, Cmd.batch [ c1, c3 ] )
```

- [ ] **Step 7: Main.elm — last-vault on plain launch (PLaunchFile)**

Replace the `PLaunchFile` branch with:
```elm
                PLaunchFile ->
                    case D.decodeValue (D.nullable D.string) result of
                        Ok (Just abs) ->
                            openExternalFile abs model

                        _ ->
                            case model.initialLastVault of
                                Just vault ->
                                    openVault vault model

                                Nothing ->
                                    ( model, Cmd.none )
```

- [ ] **Step 8: Main.elm — reader-mode toggle handler**

Add an `update` branch:
```elm
        ToggledReaderMode ->
            let
                rm =
                    not model.readerMode
            in
            ( { model | readerMode = rm }, FileOps.saveReaderMode rm )
```

- [ ] **Step 9: Verify**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -20` → Success. (View doesn't use `readerMode` yet; `ToggledReaderMode` isn't produced yet — both fine.) `cd frontend && elm-test 2>&1 | tail -6` → 38 pass.

- [ ] **Step 10: Commit**

```bash
git add frontend/src/Types.elm frontend/src/FileOps.elm frontend/src/Main.elm
git commit -m "feat: flags-based init, openVault helper, reader-mode + last-vault state"
```

---

### Task 3: index.html — pass flags + save-port handlers

**Files:**
- Modify: `frontend/index.html`

- [ ] **Step 1: Read flags from localStorage and pass to Elm**

Replace the init line `const app = Elm.Main.init({ node: document.getElementById('app') });` with:
```javascript
      function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
      const flags = {
        lastVault: lsGet('lastVault'),               // string | null
        readerMode: lsGet('readerMode') === 'true'   // bool
      };
      const app = Elm.Main.init({ node: document.getElementById('app'), flags: flags });
```

- [ ] **Step 2: Add the save-port handlers**

Near the other `app.ports.*` subscriptions (e.g. after the `requestOpenFolders` handler), add:
```javascript
      app.ports.saveReaderMode.subscribe((on) => {
        try { localStorage.setItem('readerMode', on ? 'true' : 'false'); } catch (e) {}
      });
      app.ports.saveLastVault.subscribe((vault) => {
        try { localStorage.setItem('lastVault', vault); } catch (e) {}
      });
```

- [ ] **Step 3: Verify wiring**

Run: `grep -n "flags:\|saveReaderMode\|saveLastVault\|lsGet" frontend/index.html`
Expected: the flags object/init and both port handlers present.

- [ ] **Step 4: Build sanity**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -3` → Success.

- [ ] **Step 5: Commit**

```bash
git add frontend/index.html
git commit -m "feat: pass launch flags + persist readerMode/lastVault to localStorage"
```

---

### Task 4: View — top toolbar + Reader button + reader-mode layout

**Files:**
- Modify: `frontend/src/View.elm`

- [ ] **Step 1: Add the toolbar + reader layout and switch on `readerMode`**

Change the end of `view` so the page is: optional conflict banner, a toolbar, then either the three-pane row or the reader (preview-only) view. Replace the final `in ... div [...] (conflictBanner model ++ [ threePaneRow ])` with a version that includes a toolbar and branches on `model.readerMode`:
```elm
        toolbar =
            div
                [ style "display" "flex"
                , style "align-items" "center"
                , style "gap" "8px"
                , style "padding" "6px 8px"
                , style "border-bottom" "1px solid #ddd"
                ]
                [ button [ onClick ToggledReaderMode ]
                    [ text
                        (if model.readerMode then
                            "Exit Reader"

                         else
                            "Reader"
                        )
                    ]
                ]

        readerView =
            div
                [ Html.Attributes.id Editor.renderedTextId
                , style "flex" "1"
                , style "padding" "16px"
                , style "overflow" "auto"
                ]
                (previewBody model)

        body =
            if model.readerMode then
                readerView

            else
                threePaneRow
    in
    div [ style "display" "flex", style "flex-direction" "column", style "height" "100vh", style "font-family" "system-ui" ]
        (conflictBanner model ++ [ toolbar, body ])
```
NOTE: `readerView` and the existing preview pane both use `Editor.renderedTextId`, but only one is in the DOM at a time (reader XOR three-pane), so there is never a duplicate id. `button`, `div`, `text`, `onClick`, `Html.Attributes`, `Editor`, `previewBody` are all already imported/in-scope.

- [ ] **Step 2: Verify**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -15` → Success. `cd frontend && elm-test 2>&1 | tail -6` → 38 pass.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/View.elm
git commit -m "feat: reader-mode toggle toolbar + preview-only layout"
```

---

### Task 5: index.html — Ctrl-S / Cmd-S left-to-right sync

**Files:**
- Modify: `frontend/index.html`

- [ ] **Step 1: Add the `.lr-sync-highlight` CSS**

In the `<style>` block, add:
```css
      .lr-sync-highlight {
        background-color: #fff2a8;
        transition: background-color 0.2s ease;
        border-radius: 2px;
      }
```

- [ ] **Step 2: Add the Ctrl/Cmd-S keydown sync handler**

In the inline boot script (after the other listeners), add:
```javascript
      // Ctrl-S / Cmd-S: left-to-right sync. Find the rendered element for the
      // editor's cursor line, scroll it into view, and highlight it.
      function lrParseLine(id) {
        if (!id) return null;
        if (id.indexOf('e-') === 0) {            // expression id "e-N.T" (0-indexed line)
          var n = parseInt(id.substring(2).split('.')[0], 10);
          return isNaN(n) ? null : n;
        }
        var parts = id.split('-');               // block id "N-I" (0-indexed line)
        if (parts.length >= 2) {
          var m = parseInt(parts[0], 10);
          return isNaN(m) ? null : m;
        }
        return null;
      }

      function lrSync() {
        var elc = document.querySelector('codemirror-editor');
        var ed = elc && elc.editor;
        if (!ed) return;
        var pos = ed.state.selection.main.head;
        var line0 = ed.state.doc.lineAt(pos).number - 1; // 0-indexed
        var rendered = document.getElementById('__RENDERED_TEXT__');
        if (!rendered) return;

        var nodes = rendered.querySelectorAll('[id]');
        var exact = null, best = null, bestLine = -1;
        for (var i = 0; i < nodes.length; i++) {
          var ln = lrParseLine(nodes[i].id);
          if (ln === null) continue;
          if (ln === line0) { exact = nodes[i]; break; }
          if (ln <= line0 && ln > bestLine) { best = nodes[i]; bestLine = ln; }
        }
        var target = exact || best;
        if (!target) return;

        target.scrollIntoView({ block: 'center', behavior: 'smooth' });
        document.querySelectorAll('.lr-sync-highlight').forEach(function (n) {
          n.classList.remove('lr-sync-highlight');
        });
        target.classList.add('lr-sync-highlight');
      }

      window.addEventListener('keydown', function (e) {
        if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S')) {
          e.preventDefault();
          lrSync();
        }
      }, true);
```

- [ ] **Step 3: Verify wiring**

Run: `grep -n "lr-sync-highlight\|lrSync\|keydown" frontend/index.html`
Expected: the CSS rule, `lrSync`, and the keydown listener present.

- [ ] **Step 4: Build sanity**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -3` → Success (no Elm change; confirms the app still builds).

- [ ] **Step 5: Commit**

```bash
git add frontend/index.html
git commit -m "feat: Ctrl-S/Cmd-S left-to-right sync (scroll + highlight rendered text)"
```

---

### Task 6: Build, reinstall, manual verification

**Files:** none (build + manual).

- [ ] **Step 1: Full automated suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make test 2>&1 | tail -15`
Expected: elm-test (38) and cargo test (13) pass.

- [ ] **Step 2: Build + reinstall**

Run:
```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
make build 2>&1 | tail -6
SRC="src-tauri/target/release/bundle/macos/Mac Scripta Viewer.app"
DEST="/Applications/Mac Scripta Viewer.app"
rm -rf "$DEST" && ditto "$SRC" "$DEST"
```

- [ ] **Step 3: Manual verification (GUI — user runs these)**

1. **Reader mode:** click **Reader** → only the rendered preview shows (tree + editor hidden); click **Exit Reader** → panes return. Toggle it on, quit, relaunch → it comes back in reader mode (persisted).
2. **Ctrl-S / Cmd-S:** open a `.scripta` file, put the cursor on a paragraph in the editor, press Ctrl-S (and Cmd-S) → the corresponding rendered text scrolls into view and is highlighted yellow; the browser "save" dialog does not appear.
3. **Last vault:** open a vault, quit, relaunch with no argument (Launchpad/`open -a`) → the same vault reopens with its folder expansion restored. Then `scripta <file>` → that file's folder opens instead (CLI wins).

- [ ] **Step 4: Commit any fixes** found during manual testing (none if all good).

---

## Self-review notes (coverage map)

- Reader mode (persisted, toolbar toggle, preview-only) → Task 2 (state + handler), Task 3 (save/flag), Task 4 (view).
- Ctrl-S/Cmd-S LR sync (cursor line → rendered element → scroll + highlight) → Task 5; `.lr-sync-highlight` CSS → Task 5 Step 1.
- Remember last vault (save on open, auto-reopen on plain launch, CLI wins) → Task 2 (openVault + PLaunchFile), Task 3 (flag + save port).
- Flags (tolerant decode, defaults) → Task 1; passed in Task 3.
- Tests: Flags decoder (Task 1); manual GUI (Task 6).

## Out of scope

- Reader-mode keyboard shortcut.
- Sync highlight auto-fade beyond the CSS transition.
- Pruning a stale `lastVault`.
