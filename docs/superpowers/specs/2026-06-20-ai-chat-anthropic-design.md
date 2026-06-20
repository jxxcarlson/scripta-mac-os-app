# AI Chat in Tab 1 (Anthropic, non-streaming) — Design Spec

**Date:** 2026-06-20
**Status:** Approved (pending spec review)

**Sub-project #3 of the "AI terminal" effort.** Turns the terminal panel's AI tab (a placeholder
from #2) into a working chat with Anthropic, using the API key stored in #1. Plain chat only —
tools / vault access / shell is **#4**. OpenAI & Gemini and streaming are later.

## Goal

In the terminal dock's **AI** tab: a multi-turn chat. The user types a message; the app sends the
conversation to **Anthropic** (Messages API) via the stored key and renders the reply as Markdown.
Non-streaming (a "thinking…" indicator until the full reply arrives).

## Context

- #1 stores per-provider keys in the macOS Keychain; `read_api_key_impl(AI_KEYCHAIN_SERVICE, provider)`
  (`fs_commands.rs`, internal — no command wrapper) returns the key or an `Err`. `AiConfig` (Elm)
  provides `activeProvider`, `modelFor provider`, `keyHint provider`.
- #2 added the dock with an **AI** tab currently showing `aiPlaceholder` (in `View.elm`).
- The app has a markdown renderer: `MarkdownRender.render : String -> Render.RenderOutput`
  (`.body : List (Html Render.RenderMsg)`).
- Rust commands ride the FS bridge (`request`/`handleResponse`/`PendingOp` in `Main.elm`;
  `FileOps.send`). **No HTTP client dependency exists yet.** Tauri supports `async` commands.

## Architecture

A Rust `ai_chat` command does the provider HTTP call (key never leaves Rust); Elm holds the
conversation and renders it.

### A. Rust `src-tauri/src/ai.rs` (new) + `reqwest`

- Add `reqwest = { version = "0.12", features = ["json"] }` to `Cargo.toml` (default features bring a
  TLS backend; confirm it builds on macOS).
- `#[derive(serde::Deserialize)] struct ChatMessage { role: String, content: String }`.
- **Pure, unit-testable helpers** (no I/O):
  - `build_anthropic_body(model: &str, messages: &[ChatMessage]) -> serde_json::Value` →
    `{ "model": model, "max_tokens": 4096, "messages": [ {"role","content"}, … ] }`.
  - `parse_anthropic_reply(body: &serde_json::Value) -> Result<String, String>` → the text at
    `content[0].text`; if the body has an `error.message`, return that as `Err`; otherwise a generic
    parse error.
- `#[tauri::command] async fn ai_chat(provider: String, model: String, messages: Vec<ChatMessage>) -> Result<String, String>`:
  - If `provider != "anthropic"` → `Err(format!("{provider} chat is not supported yet"))`.
  - `key = read_api_key_impl(AI_KEYCHAIN_SERVICE, &provider)?` (Err → "no key…").
  - `reqwest::Client` POST `https://api.anthropic.com/v1/messages` with headers
    `x-api-key: <key>`, `anthropic-version: 2023-06-01`, `content-type: application/json`,
    body = `build_anthropic_body(&model, &messages)`; `.send().await`; read JSON; on a non-success
    status, still parse the body for `error.message`; `parse_anthropic_reply(&json)`.
  - Map network/reqwest errors to `Err(e.to_string())`.
- Register `ai_chat` in `lib.rs`. (Provider dispatch is a `match` so OpenAI/Gemini add later.)

### B. Elm — chat state + flow (`Types`, `Main`)

- `type alias ChatMessage = { role : String, content : String }` (e.g. in `Types` or a small
  `Chat`/`AiConfig`-adjacent module; keep it simple — `Types`).
- `Model` gains: `chatMessages : List ChatMessage` (oldest→newest), `chatInput : String`,
  `chatPending : Bool`. In-memory only (resets on relaunch).
- `Msg`: `ChatInput String`, `SendChat`.
- `PendingOp`: `PChatReply`.
- `update`:
  - `ChatInput t` → `{ model | chatInput = t }`.
  - `SendChat` → if `chatPending` or the trimmed input is empty, no-op. Else build the user turn,
    `msgs = model.chatMessages ++ [ { role = "user", content = trimmedInput } ]`, then
    `request PChatReply "ai_chat" [ ("provider", E.string (AiConfig.activeProvider model.aiConfig)), ("model", E.string (AiConfig.modelFor (activeProvider) model.aiConfig)), ("messages", E.list encodeChatMessage msgs) ]` on
    `{ model | chatMessages = msgs, chatInput = "", chatPending = True }`.
  - `handleResponse PChatReply` → on `Ok` decode `D.string` → append `{ role="assistant", content=reply }`,
    `chatPending = False`; on the bridge's `Err` arm, append `{ role="assistant", content = "⚠️ " ++ error }`
    and clear `chatPending` (so errors appear in the conversation, not the global banner — note:
    this needs the `Err` arm to special-case `PChatReply`, or handle the append there).
- `encodeChatMessage m = E.object [ ("role", E.string m.role), ("content", E.string m.content) ]`.

### C. Elm — chat UI (replaces `aiPlaceholder`, `View`)

`aiChatView : Model -> Html Msg`:
- If `AiConfig.keyHint (activeProvider) model.aiConfig == Nothing`: show a notice "Set an API key for
  <provider> in ⚙ Settings to use chat." (and still allow typing, but Send is disabled / shows the
  notice).
- A scrollable message list (flex-1, overflow-auto): for each message, a row styled by role —
  **assistant** content via `MarkdownRender.render content |> .body |> List.map (Html.map (\_ -> NoOpFromRender))`
  (links in chat inert for now), **user** content as plain `text`. A "thinking…" line when
  `chatPending`.
- A bottom input row: a text input bound to `chatInput`/`ChatInput`, Enter → `SendChat`
  (`Html.Events.on "keydown"` Enter, as v4 does), and a **Send** button (disabled when pending or
  empty).

## Data Flow

```
type → ChatInput; Enter/Send → SendChat
  → append {user, text}; chatPending := True
  → ai_chat { provider, model, messages = full history }   [Rust: read key → POST Anthropic → text]
  → Ok: append {assistant, reply (Markdown)}; pending := False
  → Err: append {assistant, "⚠️ <error>"}; pending := False
```

The key is read inside Rust and never returned to Elm; Elm only sends the conversation text.

## Error Handling

- No key, network error, or Anthropic non-200 → `Err(String)` → shown as an assistant error bubble
  in the chat (keeps the conversation readable), `chatPending` cleared.
- Empty/whitespace input or a send while `chatPending` → no-op.

## Testing

- **Rust unit tests** (pure helpers, no network): `build_anthropic_body` produces the right shape
  (model, `max_tokens`, messages); `parse_anthropic_reply` extracts `content[0].text` from a sample
  success body and returns the `error.message` from a sample error body.
- **Elm:** `encodeChatMessage` round-trips; chat-state helper(s) (append user/assistant, pending
  toggle) if extracted; a `Test.Html` check that an assistant message renders a Markdown element
  (e.g. a `pre`/`p`) and a user message renders its text.
- **Manual:** set the Anthropic key (⚙) → open the AI tab → send "hello" → a rendered reply appears;
  ask a follow-up (history works); clear the key → the no-key notice shows; trigger an error (bad
  key) → an error bubble appears.

## Out of Scope (#4 / later / YAGNI)

- Tools / vault access / shell-from-AI (that is sub-project #4).
- OpenAI & Gemini providers; response streaming; persisting chat across launches.
- System-prompt customization (a minimal or empty system prompt for now), temperature/token UI,
  cost/usage display, stop/cancel mid-request, conversation management (multiple threads).
- Making links inside AI replies clickable (inert for now).
