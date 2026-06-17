# Full/Incremental Parse Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted **Full / Incremental** toolbar toggle: Full (default) uses `Render.parse` on each edit, Incremental uses `Scripta.reparse`; file load always uses `Render.parse`.

**Architecture:** A persisted `fullParse : Bool` mirroring the existing `readerMode` toggle (flag from localStorage + `saveFullParse` port). `EditorChanged` branches on it; the toolbar gets a toggle button.

**Tech Stack:** Elm 0.19.1, `elm-test`, localStorage flag+port via `index.html`.

---

## Reference (current state — verified)

- `frontend/src/Flags.elm`: `type alias Flags = { lastVault : Maybe String, readerMode : Bool }`; `decode` builds it with `D.field … |> Result.withDefault …`.
- `frontend/tests/FlagsTest.elm`: `suite = describe "Flags.decode" [ … ]` (5 tests), imports `Expect`, `Flags`, `Json.Encode as E`, `Test (Test, describe, test)`.
- `frontend/src/Types.elm`: `Model` has `… , searchQuery : String` (31), `, readerMode : Bool` (32), `, initialLastVault : Maybe String` (33). `Msg` has `| ToggledReaderMode` (85). Exposed `Model`, `Msg(..)`.
- `frontend/src/Main.elm`: `init` record has `, readerMode = flags.readerMode` (61), `, initialLastVault = flags.lastVault` (62). `EditorChanged` (229–241):
  ```elm
        EditorChanged newText ->
            let
                ( ss, action ) =
                    SaveState.textChanged 1000 model.saveState

                reparsed =
                    if model.language == Just Language.Scripta then
                        Maybe.map (\d -> Scripta.reparse (Render.options model.isLight model.contentWidth) d newText) model.parsedDoc

                    else
                        model.parsedDoc
            in
            applySaveAction action { model | content = newText, parsedDoc = reparsed, saveState = ss }
  ```
  `ToggledReaderMode` handler (375–380): `let rm = not model.readerMode in ( { model | readerMode = rm }, FileOps.saveReaderMode rm )`. `Render.parse : Bool -> Int -> String -> Scripta.Document`.
- `frontend/src/FileOps.elm`: exposing line 6 `, saveReaderMode, saveLastVault`; `port saveReaderMode : Bool -> Cmd msg` (41); `port saveLastVault : String -> Cmd msg` (44).
- `frontend/src/View.elm` `toolbar` (73–90): a flex `div` whose children list is `[ button [ onClick ToggledReaderMode ] [ text (if model.readerMode then "Exit Reader" else "Reader") ] ]`.
- `frontend/index.html`: flags object (159–162) `{ lastVault: lastVault, readerMode: lsGet('readerMode') === 'true' }`; `saveReaderMode` handler (213–215) via `subscribePort`.

**Path note:** repo root has a space — always quote. End commit messages with:
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File structure

```
frontend/src/Flags.elm        # + fullParse (default True)
frontend/tests/FlagsTest.elm  # + fullParse decode tests
frontend/src/Types.elm        # + Model.fullParse, Msg.ToggledParseMode
frontend/src/FileOps.elm      # + saveFullParse port
frontend/src/Main.elm         # init field; EditorChanged branch; ToggledParseMode handler
frontend/src/View.elm         # toolbar toggle button
frontend/index.html           # fullParse flag + saveFullParse handler
```

---

### Task 1: `Flags.fullParse` decoder (TDD)

**Files:**
- Modify: `frontend/tests/FlagsTest.elm`
- Modify: `frontend/src/Flags.elm`

- [ ] **Step 1: Write failing tests** — add these three to the END of the list in `describe "Flags.decode"` in `FlagsTest.elm` (before the closing `]`, each preceded by `,`):
```elm
        , test "missing fullParse defaults to True" <|
            \_ ->
                Expect.equal True (Flags.decode (E.object [ ( "readerMode", E.bool False ) ])).fullParse
        , test "fullParse false decodes to False" <|
            \_ ->
                Expect.equal False (Flags.decode (E.object [ ( "fullParse", E.bool False ) ])).fullParse
        , test "fullParse true decodes to True" <|
            \_ ->
                Expect.equal True (Flags.decode (E.object [ ( "fullParse", E.bool True ) ])).fullParse
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd frontend && elm-test tests/FlagsTest.elm 2>&1 | tail -10`
Expected: FAIL — `Flags` record has no field `fullParse`.

- [ ] **Step 3: Implement** — in `Flags.elm`, add `fullParse` to the record and `decode`:
```elm
type alias Flags =
    { lastVault : Maybe String
    , readerMode : Bool
    , fullParse : Bool
    }


decode : D.Value -> Flags
decode value =
    { lastVault =
        D.decodeValue (D.field "lastVault" (D.nullable D.string)) value
            |> Result.withDefault Nothing
    , readerMode =
        D.decodeValue (D.field "readerMode" D.bool) value
            |> Result.withDefault False
    , fullParse =
        D.decodeValue (D.field "fullParse" D.bool) value
            |> Result.withDefault True
    }
```

- [ ] **Step 4: Run to verify it passes; full suite**

Run: `cd frontend && elm-test tests/FlagsTest.elm 2>&1 | tail -8` (8 pass: 5 prior + 3 new).
Then: `cd frontend && elm-test 2>&1 | tail -6` (45 total: 42 prior + 3).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Flags.elm frontend/tests/FlagsTest.elm
git commit -m "feat: Flags.fullParse (default Full=True)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Wire the toggle (state, behavior, persistence, UI)

**Files:**
- Modify: `frontend/src/Types.elm`, `frontend/src/FileOps.elm`, `frontend/src/Main.elm`, `frontend/src/View.elm`, `frontend/index.html`

- [ ] **Step 1: Types.elm — Model field + Msg**

In `Model`, add `fullParse` after `readerMode`:
```elm
    , readerMode : Bool
    , fullParse : Bool
    , initialLastVault : Maybe String
```
In `Msg`, add after `| ToggledReaderMode`:
```elm
    | ToggledReaderMode
    | ToggledParseMode
```

- [ ] **Step 2: FileOps.elm — port**

Change the exposing line `    , saveReaderMode, saveLastVault` to:
```elm
    , saveReaderMode, saveLastVault, saveFullParse
```
Add the port declaration after `port saveLastVault : String -> Cmd msg`:
```elm


port saveFullParse : Bool -> Cmd msg
```

- [ ] **Step 3: Main.elm — init field**

In the `init` model record, add `fullParse` after `readerMode`:
```elm
        , readerMode = flags.readerMode
        , fullParse = flags.fullParse
        , initialLastVault = flags.lastVault
```

- [ ] **Step 4: Main.elm — `EditorChanged` branch**

Replace the `reparsed` binding in `EditorChanged`:
```elm
                reparsed =
                    if model.language == Just Language.Scripta then
                        Maybe.map (\d -> Scripta.reparse (Render.options model.isLight model.contentWidth) d newText) model.parsedDoc

                    else
                        model.parsedDoc
```
with:
```elm
                reparsed =
                    if model.language == Just Language.Scripta then
                        if model.fullParse then
                            Just (Render.parse model.isLight model.contentWidth newText)

                        else
                            Maybe.map (\d -> Scripta.reparse (Render.options model.isLight model.contentWidth) d newText) model.parsedDoc

                    else
                        model.parsedDoc
```

- [ ] **Step 5: Main.elm — `ToggledParseMode` handler**

Add immediately after the `ToggledReaderMode -> …` branch:
```elm
        ToggledParseMode ->
            let
                fp =
                    not model.fullParse
            in
            ( { model | fullParse = fp }, FileOps.saveFullParse fp )
```

- [ ] **Step 6: View.elm — toolbar toggle button**

In `toolbar`, change the children list (currently a single Reader button) to add a second button:
```elm
                [ button [ onClick ToggledReaderMode ]
                    [ text
                        (if model.readerMode then
                            "Exit Reader"

                         else
                            "Reader"
                        )
                    ]
                , button [ onClick ToggledParseMode ]
                    [ text
                        (if model.fullParse then
                            "Parse: Full"

                         else
                            "Parse: Incremental"
                        )
                    ]
                ]
```

- [ ] **Step 7: index.html — flag + save handler**

Change the flags object:
```javascript
      const flags = {
        lastVault: lastVault,                        // string | null (from Rust)
        readerMode: lsGet('readerMode') === 'true'   // bool
      };
```
to:
```javascript
      const flags = {
        lastVault: lastVault,                        // string | null (from Rust)
        readerMode: lsGet('readerMode') === 'true',  // bool
        fullParse: lsGet('fullParse') !== 'false'    // bool (unset → Full)
      };
```
Add a save handler after the `saveReaderMode` one:
```javascript
      subscribePort('saveFullParse', (on) => {
        try { localStorage.setItem('fullParse', on ? 'true' : 'false'); } catch (e) {}
      });
```

- [ ] **Step 8: Verify build + tests**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -20` → `Success!`.
Run: `cd frontend && elm-test 2>&1 | tail -6` → 45 pass.
Run: `grep -n "fullParse\|saveFullParse" frontend/index.html` → flag + handler present.

- [ ] **Step 9: Commit**

```bash
git add frontend/src/Types.elm frontend/src/FileOps.elm frontend/src/Main.elm frontend/src/View.elm frontend/index.html
git commit -m "feat: Full/Incremental parse toggle (toolbar button, persisted)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Build, reinstall, manual verification

**Files:** none (build + manual).

- [ ] **Step 1: Full automated suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make test 2>&1 | tail -15`
Expected: elm-test (45) and cargo test (26) pass.

- [ ] **Step 2: Build + reinstall**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
make build 2>&1 | tail -6
SRC="src-tauri/target/release/bundle/macos/Scripta.app"
rm -rf "/Applications/Scripta.app" && ditto "$SRC" "/Applications/Scripta.app"
```

- [ ] **Step 3: Manual verification (GUI — user runs these)**

1. Fresh launch → toolbar shows **Parse: Full**; edit a Scripta doc → preview updates (full reparse).
2. Click → **Parse: Incremental**; edit → preview updates via incremental reparse; quit + relaunch → still **Parse: Incremental** (persisted).
3. Click back → **Parse: Full**; quit + relaunch → still Full.
4. Opening any file parses correctly in either mode (load always uses `Render.parse`).

- [ ] **Step 4: Commit any fixes** found during manual testing (none if all good).

---

## Self-review notes (coverage map)

- Persisted `fullParse` default Full → Task 1 (`Flags`, tested), Task 2 Steps 1/3/7 (Model, init, flag+handler).
- Full uses `Render.parse` on edit; Incremental uses `Scripta.reparse` → Task 2 Step 4 (`EditorChanged`).
- Toggle + persistence → Task 2 Steps 2/5/6 (`saveFullParse` port, `ToggledParseMode`, toolbar button).
- Load always `Render.parse` → unchanged (`Main.elm:447`).

## Out of scope

- Keyboard shortcut; per-document setting.
