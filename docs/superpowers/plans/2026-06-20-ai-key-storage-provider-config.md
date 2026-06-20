# Secure API-Key Storage + Multi-Provider Config — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A ⚙ Settings pane to choose the active AI provider, pick a model, and store each provider's API key in the macOS Keychain; non-secret config persists via localStorage; keys are never shown in full.

**Architecture:** Rust commands (`security` CLI) store/delete keys in the Keychain. A pure `AiConfig` Elm module holds the non-secret config (active provider, per-provider model, per-provider last-4 hint) with encode/decode. Config persists through the existing Flags + `saveX` port + localStorage pattern. A settings pane in `View` edits it; key Set/Delete ride the existing FS bridge.

**Tech Stack:** Rust/Tauri 2 (`security` CLI, no new dep), Elm 0.19.1 (`elm-explorations/test`).

Spec: `docs/superpowers/specs/2026-06-20-ai-key-storage-provider-config-design.md`

---

## File Structure

- **Modify** `src-tauri/src/fs_commands.rs` + `lib.rs` — `set_api_key`/`delete_api_key` (Keychain) + tests.
- **Create** `frontend/src/AiConfig.elm` + `frontend/tests/AiConfigTest.elm` — config type, provider/model data, `last4`, encode/decoder, mutators.
- **Modify** `frontend/src/Flags.elm` + `frontend/tests/FlagsTest.elm` — decode `aiConfig`.
- **Modify** `frontend/src/FileOps.elm` — `saveAiConfig` port.
- **Modify** `frontend/index.html` — read `aiConfig` into flags + subscribe `saveAiConfig`.
- **Modify** `frontend/src/Types.elm` — Model fields, `Msg`, `PendingOp`.
- **Modify** `frontend/src/Main.elm` — init from flags, message handlers, `handleResponse`.
- **Modify** `frontend/src/View.elm` — ⚙ button + settings pane.

---

## Task 1: Rust — Keychain commands (TDD)

**Files:** Modify `src-tauri/src/fs_commands.rs`, `src-tauri/src/lib.rs`

- [ ] **Step 1: Write the failing tests**

Add to the `#[cfg(test)] mod tests { … }` block in `src-tauri/src/fs_commands.rs` (uses a throwaway service so it never touches the real one):

```rust
    #[test]
    fn keychain_set_get_delete_round_trip() {
        let service = "MacScriptaViewer-AI-test-rt";
        // clean any leftover, ignore result
        let _ = delete_api_key_impl(service, "anthropic");
        set_api_key_impl(service, "anthropic", "sk-test-1234").unwrap();
        assert_eq!(read_api_key_impl(service, "anthropic").unwrap(), "sk-test-1234");
        // -U updates in place
        set_api_key_impl(service, "anthropic", "sk-test-5678").unwrap();
        assert_eq!(read_api_key_impl(service, "anthropic").unwrap(), "sk-test-5678");
        delete_api_key_impl(service, "anthropic").unwrap();
        // deleting an absent key is a no-op success
        delete_api_key_impl(service, "anthropic").unwrap();
        assert!(read_api_key_impl(service, "anthropic").is_err());
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo test keychain 2>&1 | tail -20`
Expected: compile error — `set_api_key_impl`/`read_api_key_impl`/`delete_api_key_impl` not found.

- [ ] **Step 3: Implement**

Add to `src-tauri/src/fs_commands.rs`:

```rust
const AI_KEYCHAIN_SERVICE: &str = "MacScriptaViewer-AI";

/// Store (or update) `key` for `account` under `service` in the login Keychain.
pub fn set_api_key_impl(service: &str, account: &str, key: &str) -> Result<(), String> {
    let out = std::process::Command::new("security")
        .args(["add-generic-password", "-U", "-s", service, "-a", account, "-w", key])
        .output()
        .map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).trim().to_string())
    }
}

/// Read the key for `account`. Errors if not found.
pub fn read_api_key_impl(service: &str, account: &str) -> Result<String, String> {
    let out = std::process::Command::new("security")
        .args(["find-generic-password", "-s", service, "-a", account, "-w"])
        .output()
        .map_err(|e| e.to_string())?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).trim_end_matches('\n').to_string())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).trim().to_string())
    }
}

/// Delete the key for `account`. Treats "not found" as success.
pub fn delete_api_key_impl(service: &str, account: &str) -> Result<(), String> {
    let out = std::process::Command::new("security")
        .args(["delete-generic-password", "-s", service, "-a", account])
        .output()
        .map_err(|e| e.to_string())?;
    if out.status.success() {
        return Ok(());
    }
    let stderr = String::from_utf8_lossy(&out.stderr);
    if stderr.contains("could not be found") {
        Ok(())
    } else {
        Err(stderr.trim().to_string())
    }
}

#[tauri::command]
pub fn set_api_key(provider: String, key: String) -> Result<(), String> {
    set_api_key_impl(AI_KEYCHAIN_SERVICE, &provider, &key)
}

#[tauri::command]
pub fn delete_api_key(provider: String) -> Result<(), String> {
    delete_api_key_impl(AI_KEYCHAIN_SERVICE, &provider)
}
```

(`read_api_key_impl` has no command wrapper yet — it's the internal reader the chat backend will
use in sub-project #3; it's exercised by the test now.)

- [ ] **Step 4: Register the commands**

In `src-tauri/src/lib.rs` `tauri::generate_handler![ … ]`, add:
```rust
            fs_commands::set_api_key,
            fs_commands::delete_api_key,
```

- [ ] **Step 5: Run the tests + build**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo test 2>&1 | tail -15`
Expected: all pass (incl. `keychain_set_get_delete_round_trip`). Handler list compiles.
(If the sandbox blocks Keychain access and the test errors on `security`, report it — the commands
are still correct and will work in the real app; we'd then mark that one test `#[ignore]`.)

- [ ] **Step 6: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: Keychain set/delete API-key commands (security CLI)"
```

---

## Task 2: Elm — `AiConfig` module (TDD)

**Files:** Create `frontend/src/AiConfig.elm`, `frontend/tests/AiConfigTest.elm`. Modify `frontend/elm.json`? No — `src` is already a source dir.

- [ ] **Step 1: Write the failing tests**

Create `frontend/tests/AiConfigTest.elm`:
```elm
module AiConfigTest exposing (suite)

import AiConfig
import Dict
import Expect
import Json.Decode as D
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "AiConfig"
        [ test "providers are anthropic, openai, gemini" <|
            \_ -> Expect.equal [ "anthropic", "openai", "gemini" ] AiConfig.providers
        , test "defaultModel per provider" <|
            \_ ->
                Expect.equal [ "claude-sonnet-4-6", "gpt-4o", "gemini-1.5-pro" ]
                    (List.map AiConfig.defaultModel [ "anthropic", "openai", "gemini" ])
        , test "last4 takes the last four chars" <|
            \_ -> Expect.equal "1234" (AiConfig.last4 "sk-abc1234")
        , test "last4 of a short string is the whole string" <|
            \_ -> Expect.equal "ab" (AiConfig.last4 "ab")
        , test "modelFor falls back to the provider default" <|
            \_ -> Expect.equal "gpt-4o" (AiConfig.modelFor "openai" AiConfig.init)
        , test "setModel then modelFor returns the set model" <|
            \_ ->
                Expect.equal "gpt-4o-mini"
                    (AiConfig.modelFor "openai" (AiConfig.setModel "openai" "gpt-4o-mini" AiConfig.init))
        , test "setHint / keyHint / clearHint" <|
            \_ ->
                let
                    c1 = AiConfig.setHint "anthropic" "1234" AiConfig.init
                    c2 = AiConfig.clearHint "anthropic" c1
                in
                Expect.equal ( Just "1234", Nothing )
                    ( AiConfig.keyHint "anthropic" c1, AiConfig.keyHint "anthropic" c2 )
        , test "encode then decode round-trips" <|
            \_ ->
                let
                    cfg =
                        AiConfig.init
                            |> AiConfig.setActiveProvider "gemini"
                            |> AiConfig.setModel "gemini" "gemini-2.0-flash"
                            |> AiConfig.setHint "gemini" "9999"
                in
                Expect.equal (Ok cfg) (D.decodeValue AiConfig.decoder (AiConfig.encode cfg))
        ]
```

- [ ] **Step 2: Run to verify fail**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/AiConfigTest.elm`
Expected: compile error — `AiConfig` module not found.

- [ ] **Step 3: Implement**

Create `frontend/src/AiConfig.elm`:
```elm
module AiConfig exposing
    ( AiConfig
    , init, providers, providerLabel, modelsFor, defaultModel, last4
    , activeProvider, modelFor, keyHint
    , setActiveProvider, setModel, setHint, clearHint
    , encode, decoder
    )

{-| Non-secret AI provider configuration: which provider is active, the chosen
model per provider, and a last-4 hint per provider (presence ⇔ a key is stored
in the Keychain). The secret keys themselves live in the macOS Keychain and are
never represented here.
-}

import Dict exposing (Dict)
import Json.Decode as D
import Json.Encode as E


type alias AiConfig =
    { activeProvider : String
    , models : Dict String String
    , keyHints : Dict String String
    }


init : AiConfig
init =
    { activeProvider = "anthropic", models = Dict.empty, keyHints = Dict.empty }


providers : List String
providers =
    [ "anthropic", "openai", "gemini" ]


providerLabel : String -> String
providerLabel p =
    case p of
        "anthropic" -> "Anthropic"
        "openai" -> "OpenAI"
        "gemini" -> "Gemini"
        _ -> p


modelsFor : String -> List String
modelsFor p =
    case p of
        "anthropic" -> [ "claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5" ]
        "openai" -> [ "gpt-4o", "gpt-4o-mini", "gpt-4.1" ]
        "gemini" -> [ "gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash" ]
        _ -> []


defaultModel : String -> String
defaultModel p =
    case p of
        "anthropic" -> "claude-sonnet-4-6"
        "openai" -> "gpt-4o"
        "gemini" -> "gemini-1.5-pro"
        _ -> ""


last4 : String -> String
last4 =
    String.right 4


activeProvider : AiConfig -> String
activeProvider cfg =
    cfg.activeProvider


modelFor : String -> AiConfig -> String
modelFor p cfg =
    Dict.get p cfg.models |> Maybe.withDefault (defaultModel p)


keyHint : String -> AiConfig -> Maybe String
keyHint p cfg =
    Dict.get p cfg.keyHints


setActiveProvider : String -> AiConfig -> AiConfig
setActiveProvider p cfg =
    { cfg | activeProvider = p }


setModel : String -> String -> AiConfig -> AiConfig
setModel p m cfg =
    { cfg | models = Dict.insert p m cfg.models }


setHint : String -> String -> AiConfig -> AiConfig
setHint p h cfg =
    { cfg | keyHints = Dict.insert p h cfg.keyHints }


clearHint : String -> AiConfig -> AiConfig
clearHint p cfg =
    { cfg | keyHints = Dict.remove p cfg.keyHints }


encode : AiConfig -> E.Value
encode cfg =
    E.object
        [ ( "activeProvider", E.string cfg.activeProvider )
        , ( "models", E.dict identity E.string cfg.models )
        , ( "keyHints", E.dict identity E.string cfg.keyHints )
        ]


decoder : D.Decoder AiConfig
decoder =
    D.map3 AiConfig
        (D.oneOf [ D.field "activeProvider" D.string, D.succeed "anthropic" ])
        (D.oneOf [ D.field "models" (D.dict D.string), D.succeed Dict.empty ])
        (D.oneOf [ D.field "keyHints" (D.dict D.string), D.succeed Dict.empty ])
```

- [ ] **Step 4: Run to verify pass**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/AiConfigTest.elm`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/AiConfig.elm frontend/tests/AiConfigTest.elm
git commit -m "feat: AiConfig module (providers, models, hints, encode/decode)"
```

---

## Task 3: Persistence wiring (Flags, port, index.html, Model init)

**Files:** Modify `frontend/src/Flags.elm`, `frontend/tests/FlagsTest.elm`, `frontend/src/FileOps.elm`, `frontend/index.html`, `frontend/src/Types.elm`, `frontend/src/Main.elm`

- [ ] **Step 1: Flags — add `aiConfig` (with a failing test)**

In `frontend/tests/FlagsTest.elm`, add:
```elm
        , test "missing aiConfig decodes to AiConfig.init" <|
            \_ ->
                Expect.equal AiConfig.init (Flags.decode (E.object [])).aiConfig
        , test "aiConfig is decoded when present" <|
            \_ ->
                let
                    cfg = AiConfig.setActiveProvider "gemini" AiConfig.init
                    v = E.object [ ( "aiConfig", AiConfig.encode cfg ) ]
                in
                Expect.equal "gemini" (Flags.decode v).aiConfig.activeProvider
```
(Add `import AiConfig` and ensure `Json.Encode as E` is imported in the test.)

Run `cd frontend && elm-test tests/FlagsTest.elm` → fails (`Flags` has no `aiConfig`).

In `frontend/src/Flags.elm`: add `import AiConfig`; add `, aiConfig : AiConfig.AiConfig` to the
`Flags` alias; add to `decode`:
```elm
    , aiConfig =
        D.decodeValue (D.field "aiConfig" AiConfig.decoder) value
            |> Result.withDefault AiConfig.init
    }
```
Run the test again → PASS.

- [ ] **Step 2: FileOps — `saveAiConfig` port**

In `frontend/src/FileOps.elm`, add `saveAiConfig` to the `exposing (…)` list and declare:
```elm
port saveAiConfig : E.Value -> Cmd msg
```
(`Json.Encode as E` is already imported in FileOps.)

- [ ] **Step 3: index.html — read + persist aiConfig**

In `frontend/index.html`, add to the `flags` object (after `isLight`):
```javascript
        ,
        aiConfig: JSON.parse(lsGet('aiConfig') || 'null')   // object | null
```
(Adjust the trailing comma so the object stays valid — `isLight` line gets a comma, then this line.)
And add a save subscription alongside the other `saveX` handlers:
```javascript
      subscribePort('saveAiConfig', (cfg) => {
        try { localStorage.setItem('aiConfig', JSON.stringify(cfg)); } catch (e) {}
      });
```

- [ ] **Step 4: Types — Model fields**

In `frontend/src/Types.elm`: add `import AiConfig` and `import Dict exposing (Dict)` (if not
already imported — `Dict` is already used by `pending`). Add to `Model`:
```elm
    , aiConfig : AiConfig.AiConfig
    , aiKeyInput : Dict String String
    , showSettings : Bool
```

- [ ] **Step 5: Main — initialize from flags**

In `frontend/src/Main.elm`'s initial model record, add:
```elm
        , aiConfig = flags.aiConfig
        , aiKeyInput = Dict.empty
        , showSettings = False
```
(`Dict` and `AiConfig`/`flags` are in scope — `flags` is the decoded Flags used to build the model.)

- [ ] **Step 6: Build + tests**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test`
Expected: `Success!` and all suites pass. (No UI/handlers yet — that's Tasks 4–5 — but it compiles and persists nothing until then.)

- [ ] **Step 7: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/Flags.elm frontend/tests/FlagsTest.elm frontend/src/FileOps.elm frontend/index.html frontend/src/Types.elm frontend/src/Main.elm
git commit -m "feat: persist AI config via flags + saveAiConfig port"
```

---

## Task 4: Main — messages + handlers + handleResponse

**Files:** Modify `frontend/src/Types.elm`, `frontend/src/Main.elm`

- [ ] **Step 1: Types — Msg + PendingOp**

In `frontend/src/Types.elm`:
- Add to `type Msg`:
```elm
    | ToggledSettings
    | SetActiveProvider String
    | SetProviderModel String String
    | AiKeyInput String String
    | SubmitApiKey String
    | DeleteApiKey String
```
- Add to `type PendingOp`:
```elm
    | PSetApiKey String String
    | PDeleteApiKey String
```

- [ ] **Step 2: Main — update branches**

Add these branches to `update` (e.g. near `ToggledTheme`). `AiConfig`, `Dict`, `E`, `FileOps`,
`request` are in scope:
```elm
        ToggledSettings ->
            ( { model | showSettings = not model.showSettings }, Cmd.none )

        SetActiveProvider provider ->
            let
                cfg =
                    AiConfig.setActiveProvider provider model.aiConfig
            in
            ( { model | aiConfig = cfg }, FileOps.saveAiConfig (AiConfig.encode cfg) )

        SetProviderModel provider modelName ->
            let
                cfg =
                    AiConfig.setModel provider modelName model.aiConfig
            in
            ( { model | aiConfig = cfg }, FileOps.saveAiConfig (AiConfig.encode cfg) )

        AiKeyInput provider text ->
            ( { model | aiKeyInput = Dict.insert provider text model.aiKeyInput }, Cmd.none )

        SubmitApiKey provider ->
            let
                key =
                    Dict.get provider model.aiKeyInput |> Maybe.withDefault ""
            in
            if String.isEmpty (String.trim key) then
                ( model, Cmd.none )

            else
                request (PSetApiKey provider (AiConfig.last4 key))
                    "set_api_key"
                    [ ( "provider", E.string provider ), ( "key", E.string key ) ]
                    model

        DeleteApiKey provider ->
            request (PDeleteApiKey provider)
                "delete_api_key"
                [ ( "provider", E.string provider ) ]
                model
```

- [ ] **Step 3: Main — handleResponse branches**

In `handleResponse`'s `Ok result -> case op of`, add (the `Err` arm already shows errors via the
banner, which is the right behavior on a failed Keychain write):
```elm
                PSetApiKey provider hint ->
                    let
                        cfg =
                            AiConfig.setHint provider hint model.aiConfig
                    in
                    ( { model | aiConfig = cfg, aiKeyInput = Dict.remove provider model.aiKeyInput }
                    , FileOps.saveAiConfig (AiConfig.encode cfg)
                    )

                PDeleteApiKey provider ->
                    let
                        cfg =
                            AiConfig.clearHint provider model.aiConfig
                    in
                    ( { model | aiConfig = cfg }, FileOps.saveAiConfig (AiConfig.encode cfg) )
```

- [ ] **Step 4: Build + tests**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test`
Expected: `Success!` (exhaustive `Msg`/`PendingOp`) and all suites pass. (Buttons that send these
messages are added in Task 5; until then they're handled but unreachable — compiles fine.)

- [ ] **Step 5: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/Types.elm frontend/src/Main.elm
git commit -m "feat: AI settings message handlers (set/delete key, provider/model)"
```

---

## Task 5: View — ⚙ button + settings pane

**Files:** Modify `frontend/src/View.elm`

- [ ] **Step 1: Add the ⚙ Settings button to the toolbar**

In `view`'s `toolbar` button list, add (e.g. right after the Dark/Light button):
```elm
                , button [ onClick ToggledSettings ] [ text "\u{2699} Settings" ]
```

- [ ] **Step 2: Render the settings overlay when `showSettings`**

In `view`, where the root element is assembled (`div [ data-theme … ] (conflictBanner … ++ errorBanner … ++ [ toolbar, body ])`), append the settings overlay conditionally:
```elm
    div
        [ ... existing root attrs ... ]
        (conflictBanner model
            ++ errorBanner model
            ++ [ toolbar, body ]
            ++ (if model.showSettings then [ settingsOverlay model ] else [])
        )
```

- [ ] **Step 3: Add the settings pane**

Add `import AiConfig` and `import Dict` to `View.elm` (if absent), then add these top-level functions:
```elm
settingsOverlay : Model -> Html Msg
settingsOverlay model =
    div
        [ style "position" "fixed"
        , style "inset" "0"
        , style "background" "rgba(0,0,0,0.4)"
        , style "display" "flex"
        , style "align-items" "flex-start"
        , style "justify-content" "center"
        , style "padding" "40px"
        , style "overflow" "auto"
        , style "z-index" "100"
        ]
        [ div
            [ style "background" "var(--app-bg)"
            , style "color" "var(--app-fg)"
            , style "border" "1px solid var(--border)"
            , style "border-radius" "8px"
            , style "padding" "20px"
            , style "width" "560px"
            , style "max-width" "100%"
            ]
            [ div [ style "display" "flex", style "justify-content" "space-between", style "align-items" "center", style "margin-bottom" "12px" ]
                [ Html.h2 [ style "margin" "0", style "font-size" "18px" ] [ text "AI Providers" ]
                , button [ onClick ToggledSettings ] [ text "Close" ]
                ]
            , div [ style "color" "var(--muted)", style "font-size" "12px", style "margin-bottom" "16px" ]
                [ text "Keys are stored in your macOS Keychain. Only the last 4 characters are shown back." ]
            , activeProviderRow model
            , div [ style "height" "12px" ] []
            , div [] (List.map (providerRow model) AiConfig.providers)
            ]
        ]


activeProviderRow : Model -> Html Msg
activeProviderRow model =
    div [ style "display" "flex", style "align-items" "center", style "gap" "8px", style "margin-bottom" "8px" ]
        [ Html.label [ style "font-weight" "600", style "font-size" "13px" ] [ text "Active provider:" ]
        , Html.select [ Html.Events.onInput SetActiveProvider ]
            (List.map
                (\p ->
                    Html.option
                        [ Html.Attributes.value p, Html.Attributes.selected (p == AiConfig.activeProvider model.aiConfig) ]
                        [ text (AiConfig.providerLabel p) ]
                )
                AiConfig.providers
            )
        ]


providerRow : Model -> String -> Html Msg
providerRow model provider =
    let
        keyText =
            Dict.get provider model.aiKeyInput |> Maybe.withDefault ""
    in
    div
        [ style "border-top" "1px solid var(--border)"
        , style "padding" "12px 0"
        ]
        [ div [ style "display" "flex", style "align-items" "center", style "gap" "8px" ]
            [ div [ style "font-weight" "600", style "width" "90px" ] [ text (AiConfig.providerLabel provider) ]
            , Html.select [ Html.Events.onInput (SetProviderModel provider) ]
                (List.map
                    (\m ->
                        Html.option
                            [ Html.Attributes.value m, Html.Attributes.selected (m == AiConfig.modelFor provider model.aiConfig) ]
                            [ text m ]
                    )
                    (AiConfig.modelsFor provider)
                )
            ]
        , div [ style "display" "flex", style "align-items" "center", style "gap" "8px", style "margin-top" "8px" ]
            [ Html.input
                [ Html.Attributes.type_ "password"
                , Html.Attributes.placeholder "Paste your API key"
                , Html.Attributes.value keyText
                , Html.Events.onInput (AiKeyInput provider)
                , style "flex" "1"
                ]
                []
            , button [ onClick (SubmitApiKey provider) ] [ text "Set" ]
            , case AiConfig.keyHint provider model.aiConfig of
                Just hint ->
                    span [ style "display" "flex", style "align-items" "center", style "gap" "8px" ]
                        [ span [ style "color" "var(--muted)", style "font-family" "ui-monospace, monospace", style "font-size" "12px" ]
                            [ text ("key: \u{2022}\u{2022}\u{2022}\u{2022}" ++ hint) ]
                        , button [ onClick (DeleteApiKey provider) ] [ text "Delete" ]
                        ]

                Nothing ->
                    span [ style "color" "var(--muted)", style "font-size" "12px" ] [ text "no key" ]
            ]
        ]
```
(`span` is already imported in `View.elm`'s `Html exposing (…)`; `Html.h2`/`Html.label`/`Html.select`/`Html.option`/`Html.input` are qualified.)

- [ ] **Step 4: Build + full suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test`
Expected: `Success!` and all suites pass.

- [ ] **Step 5: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/View.elm
git commit -m "feat: AI providers settings pane (gear button + per-provider key/model)"
```

---

## After All Tasks

- Final code review over the whole diff.
- **Manual verification (GUI):** click ⚙ Settings → set the Anthropic active provider + a model →
  paste a key → Set → `key: ••••XXXX` appears → Close → relaunch the app → active provider, model,
  and hint persist → reopen Settings → Delete the key → hint clears. Verify in **Keychain Access**
  that a `MacScriptaViewer-AI / anthropic` generic-password item is created on Set and removed on
  Delete. Confirm the full key is never shown anywhere in the UI.
- Then use superpowers:finishing-a-development-branch.

## Notes

- The full key is sent to Rust once (on Set) and stored in the Keychain; the frontend keeps only
  the last-4 hint (in `aiConfig`, persisted to localStorage). `read_api_key_impl` (internal, no
  command wrapper) is the reader the chat backend will use in sub-project #3.
- `set_api_key`/`delete_api_key` ride the existing FS bridge (`request`/`handleResponse`); the
  hint/config update happens only on the command's `Ok`, so a failed Keychain write leaves the UI
  state unchanged and surfaces the error in the banner.
- Model dropdown lists are plain strings in `AiConfig.modelsFor`/`defaultModel` — edit there as
  providers release new models.
