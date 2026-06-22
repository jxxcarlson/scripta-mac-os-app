# File-tree icon + `<Vault>` agent shell — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Swap the file-tree `-` prefix for a solid dark-blue file icon, and make Shell 1 show the vault name and auto-run a configurable CLI agent (`cd '<vault>' && <agent>`) when it first opens.

**Architecture:** Feature 1 is a self-contained `View` change (new `fileIcon` SVG + one swap). Feature 2 adds an overridable agent command to the persisted `AiConfig`, surfaces it in Settings, renames the Shell 1 tab to the vault basename, and threads an `init-cmd` from the `terminal-pane` element into a new `init_cmd` parameter on the Rust `terminal_open`, which writes it to the pty after spawning the shell.

**Tech Stack:** Elm 0.19 (`Browser.element`), elm-test, Tauri 2 (Rust, `portable-pty`), xterm.js.

## Global Constraints

- Run Elm tests from `frontend/`: `npx elm-test`. Type-check: `npx elm make src/Main.elm --output=/dev/null`. Rust: `cd src-tauri && cargo test` / `cargo build`.
- elm-format and rustfmt conventions apply; keep code clean.
- Provider→CLI agent map (verbatim): `anthropic → claude`, `openai → codex`, `gemini → gemini`, fallback `claude`.
- Agent command setting is a single overridable string; empty/whitespace means "use the active provider's default".
- Only **Shell 1** is renamed (to the vault folder basename) and auto-runs the agent; Shell 2 and Scratch are unchanged. With no vault open, Shell 1's tab label is `Shell 1` and there is no auto-run.
- Auto-run command: `cd '<vault>' && <agent>` (single-quoted vault path; spaces expected, embedded single quotes out of scope). Runs once, when the pty first opens; not re-run on in-app Reload.
- File icon: solid dark-blue (`#3b6ea5`) file glyph, sized like `folderIcon` (`13×13`, `viewBox "0 0 16 16"`), kept at the current child indent. Long titles already hang-indent via the existing flex layout — do not change positioning.
- Tauri v2 maps camelCase JS argument keys to snake_case Rust parameters, so the Rust `init_cmd` parameter is passed from JS as `initCmd`.

---

### Task 1: `AiConfig` agent command (model + logic)

Add the overridable agent command to the persisted config, with the provider-default mapping. Pure module — fully unit-tested.

**Files:**
- Modify: `frontend/src/AiConfig.elm` (exposing `:1-7`, type alias `:20-24`, `init` `:27-29`, `encode` `:139-145`, `decoder` `:148-153`)
- Test: `frontend/tests/AiConfigTest.elm`

**Interfaces:**
- Produces (consumed by Tasks 2 and 5):
  - `AiConfig` record gains `agentCommand : String`
  - `AiConfig.agentDefault : String -> String`
  - `AiConfig.effectiveAgentCommand : AiConfig -> String`
  - `AiConfig.setAgentCommand : String -> AiConfig -> AiConfig`

- [ ] **Step 1: Write the failing tests**

Open `frontend/tests/AiConfigTest.elm`. Ensure these imports exist at the top (add any missing):

```elm
import Json.Decode as D
import Json.Encode as E
```

Add these cases inside the existing top-level `describe` list (e.g. at the end, before the closing `]`):

```elm
        , test "agentDefault maps anthropic to claude" <|
            \_ -> Expect.equal "claude" (AiConfig.agentDefault "anthropic")
        , test "agentDefault maps openai to codex" <|
            \_ -> Expect.equal "codex" (AiConfig.agentDefault "openai")
        , test "agentDefault maps gemini to gemini" <|
            \_ -> Expect.equal "gemini" (AiConfig.agentDefault "gemini")
        , test "agentDefault falls back to claude for unknown" <|
            \_ -> Expect.equal "claude" (AiConfig.agentDefault "whatever")
        , test "effectiveAgentCommand uses the active provider default when unset" <|
            \_ -> Expect.equal "claude" (AiConfig.effectiveAgentCommand AiConfig.init)
        , test "effectiveAgentCommand uses a non-empty override" <|
            \_ -> Expect.equal "my-agent" (AiConfig.effectiveAgentCommand (AiConfig.setAgentCommand "my-agent" AiConfig.init))
        , test "effectiveAgentCommand trims the override" <|
            \_ -> Expect.equal "my-agent" (AiConfig.effectiveAgentCommand (AiConfig.setAgentCommand "  my-agent  " AiConfig.init))
        , test "effectiveAgentCommand falls back to default for whitespace override" <|
            \_ -> Expect.equal "claude" (AiConfig.effectiveAgentCommand (AiConfig.setAgentCommand "   " AiConfig.init))
        , test "encode/decode round-trips agentCommand" <|
            \_ ->
                AiConfig.setAgentCommand "codex" AiConfig.init
                    |> AiConfig.encode
                    |> D.decodeValue AiConfig.decoder
                    |> Result.map .agentCommand
                    |> Expect.equal (Ok "codex")
        , test "decoding without agentCommand yields empty string" <|
            \_ ->
                E.object [ ( "activeProvider", E.string "openai" ) ]
                    |> D.decodeValue AiConfig.decoder
                    |> Result.map .agentCommand
                    |> Expect.equal (Ok "")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd frontend && npx elm-test`
Expected: FAIL — `agentDefault` / `effectiveAgentCommand` / `setAgentCommand` not found, and `.agentCommand` field does not exist.

- [ ] **Step 3: Implement the AiConfig changes**

In `frontend/src/AiConfig.elm`:

(a) Update the module exposing line (`:1-7`) to add the new functions — change the second exposing group and add the setter group. The full exposing block should read:

```elm
module AiConfig exposing
    ( AiConfig
    , init, providers, providerLabel, modelsFor, defaultModel, last4
    , activeProvider, modelFor, keyHint, agentDefault, effectiveAgentCommand
    , setActiveProvider, setModel, setHint, clearHint, setAgentCommand
    , encode, decoder
    )
```

(b) Add `agentCommand` as the last field of the record (`:20-24`):

```elm
type alias AiConfig =
    { activeProvider : String
    , models : Dict String String
    , keyHints : Dict String String
    , agentCommand : String
    }
```

(c) Update `init` (`:27-29`):

```elm
init : AiConfig
init =
    { activeProvider = "anthropic", models = Dict.empty, keyHints = Dict.empty, agentCommand = "" }
```

(d) Add these functions (place near `keyHint`, e.g. after it):

```elm
{-| The default CLI agent command for a provider. -}
agentDefault : String -> String
agentDefault p =
    case p of
        "anthropic" ->
            "claude"

        "openai" ->
            "codex"

        "gemini" ->
            "gemini"

        _ ->
            "claude"


{-| The agent command to run: the explicit override when set (trimmed),
otherwise the active provider's default. -}
effectiveAgentCommand : AiConfig -> String
effectiveAgentCommand cfg =
    let
        trimmed =
            String.trim cfg.agentCommand
    in
    if trimmed == "" then
        agentDefault cfg.activeProvider

    else
        trimmed


setAgentCommand : String -> AiConfig -> AiConfig
setAgentCommand cmd cfg =
    { cfg | agentCommand = cmd }
```

(e) Update `encode` (`:139-145`) to add the field:

```elm
encode : AiConfig -> E.Value
encode cfg =
    E.object
        [ ( "activeProvider", E.string cfg.activeProvider )
        , ( "models", E.dict identity E.string cfg.models )
        , ( "keyHints", E.dict identity E.string cfg.keyHints )
        , ( "agentCommand", E.string cfg.agentCommand )
        ]
```

(f) Update `decoder` (`:148-153`) from `map3` to `map4`, adding the backward-compatible field last (matching the record field order):

```elm
decoder : D.Decoder AiConfig
decoder =
    D.map4 AiConfig
        (D.oneOf [ D.field "activeProvider" D.string, D.succeed "anthropic" ])
        (D.oneOf [ D.field "models" (D.dict D.string), D.succeed Dict.empty ])
        (D.oneOf [ D.field "keyHints" (D.dict D.string), D.succeed Dict.empty ])
        (D.oneOf [ D.field "agentCommand" D.string, D.succeed "" ])
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd frontend && npx elm-test`
Expected: PASS (all AiConfig tests, including the new ones).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/AiConfig.elm frontend/tests/AiConfigTest.elm
git commit -m "feat: add overridable agent command to AiConfig"
```

---

### Task 2: Settings UI for the agent command

Surface the agent command in the Settings overlay and persist edits.

**Files:**
- Modify: `frontend/src/Types.elm` (Msg list — add near `SetProviderModel` `:112`)
- Modify: `frontend/src/View.elm` (`settingsOverlay` `:516`, add a row after `activeProviderRow` `:542`; new helper near `activeProviderRow` `:831`)
- Modify: `frontend/src/Main.elm` (`update`, near `SetProviderModel` `:566-569`)

**Interfaces:**
- Consumes: `AiConfig.effectiveAgentCommand`, `AiConfig.setAgentCommand` (Task 1); `FileOps.saveAiConfig`, `AiConfig.encode` (existing).
- Produces: `Msg` variant `SetAgentCommand String`.

- [ ] **Step 1: Add the `SetAgentCommand` message**

In `frontend/src/Types.elm`, add the variant after `SetProviderModel String String` (`:112`):

```elm
    | SetProviderModel String String
    | SetAgentCommand String
```

- [ ] **Step 2: Handle it in `update`**

In `frontend/src/Main.elm`, add a branch right after the `SetProviderModel` branch (`:566-569`):

```elm
        SetAgentCommand cmd ->
            let
                cfg =
                    AiConfig.setAgentCommand cmd model.aiConfig
            in
            ( { model | aiConfig = cfg }, FileOps.saveAiConfig (AiConfig.encode cfg) )
```

- [ ] **Step 3: Add the Settings row**

In `frontend/src/View.elm`, add a new helper next to `activeProviderRow` (after it, around `:846`):

```elm
agentCommandRow : Model -> Html Msg
agentCommandRow model =
    div [ style "display" "flex", style "align-items" "center", style "gap" "8px", style "margin-bottom" "8px" ]
        [ Html.label [ style "font-weight" "600", style "font-size" "13px" ] [ text "Agent command:" ]
        , Html.input
            [ Html.Attributes.value (AiConfig.effectiveAgentCommand model.aiConfig)
            , onInput SetAgentCommand
            , Html.Attributes.attribute "autocapitalize" "off"
            , Html.Attributes.attribute "autocorrect" "off"
            , Html.Attributes.spellcheck False
            , style "flex" "1"
            ]
            []
        ]
```

Then render it in `settingsOverlay`: immediately after the `activeProviderRow model` line (`:542`), insert:

```elm
            , agentCommandRow model
```

- [ ] **Step 4: Verify it compiles**

Run: `cd frontend && npx elm make src/Main.elm --output=/dev/null`
Expected: Success ("Success!"). `SetAgentCommand` is handled; the new row renders.

- [ ] **Step 5: Run the suite (no regressions)**

Run: `cd frontend && npx elm-test`
Expected: PASS — all suites still green.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm
git commit -m "feat: Agent command field in Settings"
```

Note: no new unit test here — the pure setter is tested in Task 1, and the overlay (`settingsOverlay`) is not exported; this wiring is verified by compilation and the final manual check.

---

### Task 3: File icon in the tree

Replace the `-` prefix with a solid dark-blue file glyph.

**Files:**
- Modify: `frontend/src/View.elm` (new `fileIcon` near `folderIcon` `:313`; `FileNode` branch `:416`)

**Interfaces:**
- Produces: `fileIcon : Html msg` (module-internal; used only in `nodeView`).

- [ ] **Step 1: Add the `fileIcon` helper**

In `frontend/src/View.elm`, add directly after the `folderIcon` function (after its closing, around `:335`):

```elm
{-| A small solid file glyph (filled dark blue), sized to match folderIcon. -}
fileIcon : Html msg
fileIcon =
    Svg.svg
        [ SA.width "13"
        , SA.height "13"
        , SA.viewBox "0 0 16 16"
        , SA.style "vertical-align: middle; margin-right: 5px;"
        ]
        [ Svg.path
            [ SA.d "M3 1.5 H9 L13 5.5 V14.5 H3 Z M9 1.5 V5.5 H13"
            , SA.fill "#3b6ea5"
            , SA.stroke "#3b6ea5"
            , SA.strokeWidth "1"
            , SA.strokeLinejoin "round"
            ]
            []
        ]
```

- [ ] **Step 2: Use it in the `FileNode` row**

In `nodeView`'s `FileNode` branch, replace the prefix span (`:416`):

```elm
                [ span [ style "flex" "0 0 auto", style "margin-right" "5px" ] [ text "-" ]
```

with:

```elm
                [ span [ style "flex" "0 0 auto", style "margin-right" "5px" ] [ fileIcon ]
```

- [ ] **Step 3: Verify it compiles**

Run: `cd frontend && npx elm make src/Main.elm --output=/dev/null`
Expected: Success ("Success!").

- [ ] **Step 4: Run the suite (no regressions)**

Run: `cd frontend && npx elm-test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/View.elm
git commit -m "feat: solid file icon in the tree instead of '-'"
```

Note: visual change; `nodeView` is not exported, so this is verified by compilation here and by the final manual check (file rows show a blue file glyph; long names hang-indent).

---

### Task 4: Shell 1 tab shows the vault name

Rename Shell 1's tab to the vault folder basename.

**Files:**
- Modify: `frontend/src/View.elm` (`terminalTabBar` `:620-629`, `terminalTabButton` `:632-645`; new exported helper `vaultShellLabel`)
- Modify: `frontend/src/View.elm` exposing line (`:1`) to export `vaultShellLabel`
- Test: `frontend/tests/` — add `frontend/tests/VaultShellLabelTest.elm`

**Interfaces:**
- Consumes: `PathUtil.basename` (existing).
- Produces: `View.vaultShellLabel : Maybe String -> String`.

- [ ] **Step 1: Write the failing test**

Create `frontend/tests/VaultShellLabelTest.elm`:

```elm
module VaultShellLabelTest exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import View


suite : Test
suite =
    describe "View.vaultShellLabel"
        [ test "uses the vault folder basename when a vault is open" <|
            \_ -> Expect.equal "kbase" (View.vaultShellLabel (Just "/Users/c/CloudDocs/kbase"))
        , test "uses the basename for a nested-looking root too" <|
            \_ -> Expect.equal "MyVault" (View.vaultShellLabel (Just "/a/b/MyVault"))
        , test "falls back to 'Shell 1' when no vault is open" <|
            \_ -> Expect.equal "Shell 1" (View.vaultShellLabel Nothing)
        ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd frontend && npx elm-test tests/VaultShellLabelTest.elm`
Expected: FAIL — `View.vaultShellLabel` does not exist (not exported / not defined).

- [ ] **Step 3: Add and export `vaultShellLabel`**

In `frontend/src/View.elm`, update the module exposing line (`:1`) to add `vaultShellLabel`:

```elm
module View exposing (chatMessageView, imagePane, plainTextPreview, rightTabs, themeName, vaultShellLabel, view)
```

Add the helper near `rightTabs` (after it, around `:618`):

```elm
{-| Shell 1's tab label: the open vault's folder name, or "Shell 1" if none. -}
vaultShellLabel : Maybe String -> String
vaultShellLabel vaultRoot =
    case vaultRoot of
        Just root ->
            PathUtil.basename root

        Nothing ->
            "Shell 1"
```

- [ ] **Step 4: Use it for the shell1 tab**

Change `terminalTabButton` (`:632-645`) to resolve the label — for `shell1`, use the vault label; otherwise the static tuple label. Replace the function with:

```elm
terminalTabButton : Model -> ( String, String ) -> Html Msg
terminalTabButton model ( tabId, label ) =
    let
        shownLabel =
            if tabId == "shell1" then
                vaultShellLabel model.vaultRoot

            else
                label
    in
    button
        [ onClick (SelectTerminalTab tabId)
        , style "font-weight"
            (if model.terminalTab == tabId then
                "700"

             else
                "400"
            )
        ]
        [ text shownLabel ]
```

(`terminalTabBar` already passes `model` into `terminalTabButton`, so no change there.)

- [ ] **Step 5: Run the test + full suite**

Run: `cd frontend && npx elm-test`
Expected: PASS — `VaultShellLabelTest` and all existing suites.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/View.elm frontend/tests/VaultShellLabelTest.elm
git commit -m "feat: Shell 1 tab shows the vault folder name"
```

---

### Task 5: Auto-run `cd '<vault>' && <agent>` on Shell 1 open

Thread an init command from the Shell 1 pane through to the pty.

**Files:**
- Modify: `src-tauri/src/terminal.rs` (`terminal_open` signature + post-spawn write)
- Modify: `frontend/index.html` (`terminal-pane` `_openOrResize`, the `terminal_open` invoke)
- Modify: `frontend/src/View.elm` (`terminalPane` `:806-815`)

**Interfaces:**
- Consumes: `AiConfig.effectiveAgentCommand` (Task 1).
- Produces: `terminal_open` Rust command now accepts `init_cmd: String` (JS key `initCmd`); the `terminal-pane` element reads an `init-cmd` attribute.

- [ ] **Step 1: Add `init_cmd` to the Rust `terminal_open`**

In `src-tauri/src/terminal.rs`, add the parameter to the signature:

```elm
pub fn terminal_open(
    app: tauri::AppHandle,
    state: tauri::State<'_, TerminalState>,
    id: String,
    cwd: String,
    cols: u16,
    rows: u16,
    init_cmd: String,
) -> Result<(), String> {
```

Then make the writer mutable and write the init command after the writer is obtained. Change the `let writer = ...` line to `let mut writer = ...` and, immediately after it, add the write:

```rust
    let mut writer = pair.master.take_writer().map_err(|e| e.to_string())?;
    if !init_cmd.is_empty() {
        let line = format!("{}\n", init_cmd);
        writer.write_all(line.as_bytes()).map_err(|e| e.to_string())?;
        writer.flush().map_err(|e| e.to_string())?;
    }
```

(The `reader`/`writer` bindings are just above the reader thread; `writer` is later moved into the `Session`. Writing here, before the move, sends the command to the freshly spawned shell.)

- [ ] **Step 2: Verify Rust builds**

Run: `cd src-tauri && cargo build 2>&1 | tail -5`
Expected: builds (the command now requires an extra arg; the frontend is updated next). Warnings OK; no errors.

- [ ] **Step 3: Pass `initCmd` from the terminal-pane element**

In `frontend/index.html`, in `_openOrResize`, update the open-branch invoke (the line that calls `terminal_open`) to read and pass the attribute:

Replace:

```javascript
            invoke('terminal_open', { id: this._id, cwd: this._cwd, cols: this._term.cols, rows: this._term.rows }).catch(function () {});
```

with:

```javascript
            invoke('terminal_open', { id: this._id, cwd: this._cwd, cols: this._term.cols, rows: this._term.rows, initCmd: this.getAttribute('init-cmd') || '' }).catch(function () {});
```

(Tauri v2 maps the camelCase `initCmd` to the Rust `init_cmd` parameter.)

- [ ] **Step 4: Set `init-cmd` for Shell 1 in `terminalPane`**

In `frontend/src/View.elm`, replace `terminalPane` (`:806-815`) with a version that adds the `init-cmd` attribute for `shell1` when a vault is open:

```elm
terminalPane : String -> Model -> Html Msg
terminalPane termId model =
    let
        initCmd =
            case ( termId, model.vaultRoot ) of
                ( "shell1", Just root ) ->
                    "cd '" ++ root ++ "' && " ++ AiConfig.effectiveAgentCommand model.aiConfig

                _ ->
                    ""
    in
    Html.node "terminal-pane"
        [ Html.Attributes.attribute "term-id" termId
        , Html.Attributes.attribute "cwd" (Maybe.withDefault "" model.vaultRoot)
        , Html.Attributes.attribute "init-cmd" initCmd
        , style "display" "block"
        , style "width" "100%"
        , style "height" "100%"
        ]
        []
```

(`AiConfig` is already imported in `View.elm`.)

- [ ] **Step 5: Verify the frontend compiles**

Run: `cd frontend && npx elm make src/Main.elm --output=/dev/null`
Expected: Success ("Success!").

- [ ] **Step 6: Run the full Elm suite + Rust tests**

Run: `cd frontend && npx elm-test` → PASS (all suites).
Run: `cd ../src-tauri && cargo test 2>&1 | tail -5` → existing tests pass (e.g. `resolve_cwd`).

- [ ] **Step 7: Commit**

```bash
git add src-tauri/src/terminal.rs frontend/index.html frontend/src/View.elm
git commit -m "feat: Shell 1 auto-runs 'cd <vault> && <agent>' on open"
```

---

## Manual verification (after all tasks — requires `make install`)

Run `make install`, then launch `/Applications/Scripta.app/Contents/MacOS/mac-scripta-viewer` (or open Scripta) with a vault open:

1. **File icon:** tree file rows show a small solid dark-blue file glyph (no `-`); a long file name wraps with a hanging indent under the title's first character.
2. **Settings → Agent command:** shows `claude` for the Anthropic provider; switching the active provider changes the shown default; typing an override persists across relaunch.
3. **Shell 1 tab:** labeled with the vault folder name (e.g. `kbase`).
4. **Auto-run:** opening the terminal with Shell 1 active runs `cd '<vault>' && claude` (or your override) once; typing is clean (no garbling — Shell 1 was already correct, and the lazy-open fix stands). Shell 2 stays a plain shell. In-app **Reload** does not relaunch the agent.

---

## Self-Review notes

- **Spec coverage:** Feature 1 (file icon, keep child indent, hanging indent) → Task 3. Feature 2A (AiConfig agent field/logic) → Task 1; 2B (Settings UI + SetAgentCommand) → Task 2; 2C (Shell 1 tab = vault name) → Task 4; 2D (auto-run via Rust `init_cmd` + JS `init-cmd` + Elm `terminalPane`) → Task 5. All spec sections mapped.
- **Type consistency:** `agentCommand : String`, `agentDefault : String -> String`, `effectiveAgentCommand : AiConfig -> String`, `setAgentCommand : String -> AiConfig -> AiConfig`, `SetAgentCommand String`, `vaultShellLabel : Maybe String -> String`, Rust `init_cmd: String` ↔ JS `initCmd`, attribute `init-cmd` — used identically across the defining and consuming tasks.
- **Every task leaves the repo compiling:** Task 5 changes the Rust signature and the two callers (JS invoke + Elm attribute) together; Step 2 notes the intermediate Rust build before the frontend catches up, but the task as a whole restores a consistent, runnable state.
- **Tests where logic is pure:** Tasks 1 and 4 are TDD with unit tests. Tasks 2, 3, 5 are wiring/visual/native-pty changes verified by compilation + the manual checklist (the relevant view helpers aren't exported and a pty can't be unit-tested); pure pieces they rely on are tested in Tasks 1 and 4.
