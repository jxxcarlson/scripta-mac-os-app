# AI Chat in Tab 1 (Anthropic, non-streaming) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The terminal dock's AI tab becomes a working multi-turn chat with Anthropic, using the Keychain-stored key, with replies rendered as Markdown.

**Architecture:** A Rust async `ai_chat` command reads the key (Keychain, internal), POSTs the Anthropic Messages API, and returns the reply text (pure body-builder/parser helpers are unit-tested). A testable `Chat` Elm module holds the message type/encoding; `Main` owns the conversation; `View` renders the chat (assistant = Markdown) in the AI tab.

**Tech Stack:** Rust/Tauri 2 + new `reqwest` crate (async); Elm 0.19.1 (`elm-explorations/test`).

Spec: `docs/superpowers/specs/2026-06-20-ai-chat-anthropic-design.md`

---

## File Structure

- **Modify** `src-tauri/Cargo.toml` (+`reqwest`), `src-tauri/src/fs_commands.rs` (+`read_provider_key`), `src-tauri/src/lib.rs`; **create** `src-tauri/src/ai.rs`.
- **Create** `frontend/src/Chat.elm` + `frontend/tests/ChatTest.elm`.
- **Modify** `frontend/src/Types.elm`, `frontend/src/Main.elm`, `frontend/src/View.elm`.

---

## Task 1: Rust — `ai_chat` command (TDD on the pure helpers)

**Files:** Modify `src-tauri/Cargo.toml`, `src-tauri/src/fs_commands.rs`, `src-tauri/src/lib.rs`; create `src-tauri/src/ai.rs`.

- [ ] **Step 1: Add reqwest + a key-reader helper**

In `src-tauri/Cargo.toml` `[dependencies]`: `reqwest = { version = "0.12", features = ["json"] }`.
In `src-tauri/src/fs_commands.rs`, add a small public helper (so `ai.rs` need not see the private
service const):
```rust
/// Read the stored API key for `provider` from the AI Keychain service.
pub fn read_provider_key(provider: &str) -> Result<String, String> {
    read_api_key_impl(AI_KEYCHAIN_SERVICE, provider)
}
```

- [ ] **Step 2: Write the failing tests (pure helpers)**

Create `src-tauri/src/ai.rs` test module first by writing the file with the helpers' signatures
absent — i.e. add this test module and the `use`s, then run to see it fail. Put in `ai.rs`:
```rust
#[cfg(test)]
mod tests {
    use super::{build_anthropic_body, parse_anthropic_reply, ChatMessage};
    use serde_json::json;

    #[test]
    fn body_has_model_max_tokens_and_messages() {
        let msgs = vec![ChatMessage { role: "user".into(), content: "hi".into() }];
        let b = build_anthropic_body("claude-sonnet-4-6", &msgs);
        assert_eq!(b["model"], "claude-sonnet-4-6");
        assert_eq!(b["max_tokens"], 4096);
        assert_eq!(b["messages"][0]["role"], "user");
        assert_eq!(b["messages"][0]["content"], "hi");
    }

    #[test]
    fn parse_reply_extracts_text() {
        let body = json!({ "content": [ { "type": "text", "text": "hello there" } ] });
        assert_eq!(parse_anthropic_reply(&body).unwrap(), "hello there");
    }

    #[test]
    fn parse_reply_surfaces_error_message() {
        let body = json!({ "type": "error", "error": { "type": "x", "message": "bad key" } });
        assert_eq!(parse_anthropic_reply(&body), Err("bad key".to_string()));
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo test ai:: 2>&1 | tail -20`
Expected: compile error — `build_anthropic_body`/`parse_anthropic_reply`/`ChatMessage` not found.
(You may need `mod ai;` in `lib.rs` first for the test module to be compiled — add it in Step 5; or temporarily run `cargo test` after Step 4+5.)

- [ ] **Step 4: Implement `ai.rs`**

Prepend to `src-tauri/src/ai.rs` (above the test module):
```rust
use serde_json::{json, Value};

#[derive(serde::Deserialize)]
pub struct ChatMessage {
    pub role: String,
    pub content: String,
}

pub fn build_anthropic_body(model: &str, messages: &[ChatMessage]) -> Value {
    let msgs: Vec<Value> = messages
        .iter()
        .map(|m| json!({ "role": m.role, "content": m.content }))
        .collect();
    json!({ "model": model, "max_tokens": 4096, "messages": msgs })
}

pub fn parse_anthropic_reply(body: &Value) -> Result<String, String> {
    if let Some(msg) = body.get("error").and_then(|e| e.get("message")).and_then(|m| m.as_str()) {
        return Err(msg.to_string());
    }
    body.get("content")
        .and_then(|c| c.get(0))
        .and_then(|c0| c0.get("text"))
        .and_then(|t| t.as_str())
        .map(|s| s.to_string())
        .ok_or_else(|| "unexpected response shape".to_string())
}

#[tauri::command]
pub async fn ai_chat(provider: String, model: String, messages: Vec<ChatMessage>) -> Result<String, String> {
    if provider != "anthropic" {
        return Err(format!("{} chat is not supported yet", provider));
    }
    let key = crate::fs_commands::read_provider_key(&provider)?;
    let body = build_anthropic_body(&model, &messages);
    let client = reqwest::Client::new();
    let resp = client
        .post("https://api.anthropic.com/v1/messages")
        .header("x-api-key", key)
        .header("anthropic-version", "2023-06-01")
        .header("content-type", "application/json")
        .json(&body)
        .send()
        .await
        .map_err(|e| e.to_string())?;
    let json: Value = resp.json().await.map_err(|e| e.to_string())?;
    parse_anthropic_reply(&json)
}
```

- [ ] **Step 5: Register**

In `src-tauri/src/lib.rs`: add `mod ai;` at the top; add `ai::ai_chat,` to `generate_handler![ … ]`.

- [ ] **Step 6: Build + tests**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo test 2>&1 | tail -20`
Expected: compiles (reqwest resolves; if its TLS backend fails to build on this macOS, switch the
feature to `features = ["json", "rustls-tls"], default-features = false` and retry); the 3 `ai::`
tests pass; existing tests pass. The live HTTP call is verified manually.

- [ ] **Step 7: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add src-tauri/Cargo.toml src-tauri/Cargo.lock src-tauri/src/ai.rs src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: ai_chat command (Anthropic Messages API)"
```

---

## Task 2: Elm — `Chat` module + conversation state/handlers (TDD)

**Files:** Create `frontend/src/Chat.elm`, `frontend/tests/ChatTest.elm`; modify `frontend/src/Types.elm`, `frontend/src/Main.elm`.

- [ ] **Step 1: Write the failing tests**

Create `frontend/tests/ChatTest.elm`:
```elm
module ChatTest exposing (suite)

import Chat
import Expect
import Json.Decode as D
import Json.Encode as E
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Chat"
        [ test "user / assistant build messages with the right role" <|
            \_ ->
                Expect.equal ( "user", "hi", "assistant" )
                    ( (Chat.user "hi").role, (Chat.user "hi").content, (Chat.assistant "ok").role )
        , test "encode produces {role, content}" <|
            \_ ->
                let
                    v = Chat.encode (Chat.user "hello")
                    role = D.decodeValue (D.field "role" D.string) v
                    content = D.decodeValue (D.field "content" D.string) v
                in
                Expect.equal ( Ok "user", Ok "hello" ) ( role, content )
        ]
```

Run `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/ChatTest.elm` → fails (no `Chat`).

- [ ] **Step 2: Implement `Chat.elm`**

Create `frontend/src/Chat.elm`:
```elm
module Chat exposing (ChatMessage, user, assistant, encode)

import Json.Encode as E


type alias ChatMessage =
    { role : String, content : String }


user : String -> ChatMessage
user content =
    { role = "user", content = content }


assistant : String -> ChatMessage
assistant content =
    { role = "assistant", content = content }


encode : ChatMessage -> E.Value
encode m =
    E.object [ ( "role", E.string m.role ), ( "content", E.string m.content ) ]
```
Run the test → PASS.

- [ ] **Step 3: Types — Model + Msg + PendingOp**

In `frontend/src/Types.elm`: add `import Chat`. Add to `Model`:
```elm
    , chatMessages : List Chat.ChatMessage
    , chatInput : String
    , chatPending : Bool
```
Add to `Msg`: `| ChatInput String` and `| SendChat`. Add to `PendingOp`: `| PChatReply`.

- [ ] **Step 4: Main — init + handlers**

In the initial model record add `, chatMessages = [] , chatInput = "" , chatPending = False`.
Add `import Chat` if not present. Add to `update`:
```elm
        ChatInput t ->
            ( { model | chatInput = t }, Cmd.none )

        SendChat ->
            let
                text =
                    String.trim model.chatInput
            in
            if model.chatPending || String.isEmpty text then
                ( model, Cmd.none )

            else
                let
                    provider =
                        AiConfig.activeProvider model.aiConfig

                    msgs =
                        model.chatMessages ++ [ Chat.user text ]
                in
                request PChatReply
                    "ai_chat"
                    [ ( "provider", E.string provider )
                    , ( "model", E.string (AiConfig.modelFor provider model.aiConfig) )
                    , ( "messages", E.list Chat.encode msgs )
                    ]
                    { model | chatMessages = msgs, chatInput = "", chatPending = True }
```

- [ ] **Step 5: Main — handleResponse (Ok + special-cased Err)**

In `handleResponse`'s `Ok result -> case op of`, add:
```elm
                PChatReply ->
                    case D.decodeValue D.string result of
                        Ok reply ->
                            ( { model | chatMessages = model.chatMessages ++ [ Chat.assistant reply ], chatPending = False }, Cmd.none )

                        Err e ->
                            ( { model | chatMessages = model.chatMessages ++ [ Chat.assistant ("\u{26A0} " ++ D.errorToString e) ], chatPending = False }, Cmd.none )
```
In the `Err e ->` arm of `handleResponse`, special-case `PChatReply` so chat errors become an
assistant bubble (not the global banner). Change that arm to:
```elm
        Err e ->
            case op of
                PChatReply ->
                    ( { model | chatMessages = model.chatMessages ++ [ Chat.assistant ("\u{26A0} " ++ e) ], chatPending = False }, Cmd.none )

                _ ->
                    let
                        newSaveState =
                            case op of
                                PWriteFile _ ->
                                    Tuple.first (SaveState.saveFailed model.saveState)

                                _ ->
                                    model.saveState
                    in
                    ( { model | error = Just e, saveState = newSaveState }, Cmd.none )
```
(Keep the existing `newSaveState`/`PWriteFile` logic exactly as it is today in the `_` branch.)

- [ ] **Step 6: Build + tests**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test`
Expected: `Success!`; all suites pass (incl. ChatTest). (No chat UI yet — Task 3.)

- [ ] **Step 7: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/Chat.elm frontend/tests/ChatTest.elm frontend/src/Types.elm frontend/src/Main.elm
git commit -m "feat: chat conversation state + ai_chat request/response wiring"
```

---

## Task 3: Elm — chat UI in the AI tab

**Files:** Modify `frontend/src/View.elm`.

- [ ] **Step 1: Replace the AI placeholder with the chat view**

In `terminalDock` (Task #2's code), the AI tab content is `aiPlaceholder`. Change that keyed entry
to use `aiChatView model`:
```elm
            [ ( "ai", terminalTabContent (model.terminalTab == "ai") (aiChatView model) )
```
(Leave the `shell1`/`shell2` entries unchanged.)

- [ ] **Step 2: Add the chat view functions**

Add `import Chat` and `import AiConfig` (AiConfig is already imported from the settings work; add
`Chat`). Add these top-level functions to `View.elm`:
```elm
aiChatView : Model -> Html Msg
aiChatView model =
    let
        provider =
            AiConfig.activeProvider model.aiConfig

        hasKey =
            AiConfig.keyHint provider model.aiConfig /= Nothing
    in
    div [ style "display" "flex", style "flex-direction" "column", style "height" "100%", style "min-height" "0" ]
        [ div [ style "flex" "1", style "overflow" "auto", style "padding" "12px" ]
            (List.map chatMessageView model.chatMessages
                ++ (if model.chatPending then
                        [ div [ style "color" "var(--muted)", style "font-style" "italic", style "padding" "4px 0" ] [ text "thinking\u{2026}" ] ]

                    else
                        []
                   )
            )
        , if hasKey then
            chatInputRow model

          else
            div [ style "padding" "12px", style "color" "var(--muted)", style "border-top" "1px solid var(--border)" ]
                [ text ("Set an API key for " ++ AiConfig.providerLabel provider ++ " in \u{2699} Settings to use chat.") ]
        ]


chatMessageView : Chat.ChatMessage -> Html Msg
chatMessageView m =
    let
        isUser =
            m.role == "user"

        body =
            if isUser then
                [ Html.pre [ style "white-space" "pre-wrap", style "margin" "0", style "font-family" "inherit" ] [ text m.content ] ]

            else
                MarkdownRender.render m.content |> .body |> List.map (Html.map (\_ -> NoOpFromRender))
    in
    div
        [ style "margin-bottom" "12px"
        , style "padding" "8px 10px"
        , style "border-radius" "6px"
        , style "background"
            (if isUser then
                "var(--tree-selected-bg)"

             else
                "var(--panel-bg)"
            )
        ]
        (div [ style "font-size" "11px", style "font-weight" "700", style "color" "var(--muted)", style "margin-bottom" "4px" ]
            [ text
                (if isUser then
                    "You"

                 else
                    "Assistant"
                )
            ]
            :: body
        )


chatInputRow : Model -> Html Msg
chatInputRow model =
    div [ style "display" "flex", style "gap" "8px", style "padding" "8px", style "border-top" "1px solid var(--border)" ]
        [ Html.input
            [ Html.Attributes.placeholder "Message the AI\u{2026}"
            , Html.Attributes.value model.chatInput
            , onInput ChatInput
            , Html.Events.on "keydown" (chatEnterDecoder)
            , style "flex" "1"
            ]
            []
        , button
            [ onClick SendChat
            , Html.Attributes.disabled (model.chatPending || String.isEmpty (String.trim model.chatInput))
            ]
            [ text "Send" ]
        ]


chatEnterDecoder : D.Decoder Msg
chatEnterDecoder =
    D.field "key" D.string
        |> D.andThen
            (\k ->
                if k == "Enter" then
                    D.succeed SendChat

                else
                    D.fail "not Enter"
            )
```
(`D` = `Json.Decode` — `View.elm` already imports `Json.Decode as D`. `Html.Events`/`Html.Attributes`/`MarkdownRender` are imported.)

- [ ] **Step 3: Build + full suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test`
Expected: `Success!` and all suites pass.

- [ ] **Step 4: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/View.elm
git commit -m "feat: AI chat UI in the terminal AI tab"
```

---

## After All Tasks

- Final code review over the whole diff.
- **Manual verification (GUI):** ⚙ Settings → set the Anthropic key + a model → open ⌘ Terminal →
  **AI** tab → type "hello" + Enter → a "thinking…" indicator, then a Markdown-rendered reply →
  ask a follow-up (history carries) → delete the key in Settings → the no-key notice shows → set a
  bad key → an "⚠️ …" assistant error bubble appears. Confirm the key never appears in the UI.
- Then use superpowers:finishing-a-development-branch.

## Notes

- The key is read inside Rust (`read_provider_key` → Keychain) and never returned to Elm; Elm sends
  only the conversation text + provider/model.
- Assistant replies render through `MarkdownRender` but are mapped to `NoOpFromRender`, so links in
  chat are inert (the renderer's relative-link resolution targets vault docs, not chat) — making web
  links clickable is a later tweak.
- `ai_chat` is `async`; if `reqwest`'s default TLS fails to build on this macOS, use
  `features = ["json", "rustls-tls"], default-features = false`.
- Chat is in-memory (resets on relaunch); system prompt omitted for now — both per the spec.
