# Secure API-Key Storage + Multi-Provider Config — Design Spec

**Date:** 2026-06-20
**Status:** Approved (pending spec review)

**Sub-project #1 of 4** in the "AI terminal" effort. The others (terminal panel + tabs; AI chat
in tab 1; AI-administers-kbase with shell access) are separate specs and **out of scope here**.
This one is the foundation: configure AI providers and store their keys securely.

## Goal

A Settings pane (opened from a ⚙ button in the header) where the user picks the **active AI
provider** (Anthropic / OpenAI / Gemini), chooses a **model** per provider, and stores each
provider's **API key** in the **macOS Keychain**. Config persists across launches; the full key
is never displayed or returned to the frontend (only a last-4 hint). No network calls yet.

Reference UX: the v4 Scripta app's "AI Provider API Keys" panel
(`scripta-app-v4/frontend/src/ViewHelper/Settings.elm`) — provider `<select>` + password key
field + a list showing only a masked hint + Delete. We mirror that UX; storage differs (Keychain,
not a server DB).

## Context

- The Mac app is local Tauri 2 + Elm; no server, no existing AI/terminal/key code (confirmed).
- It already shells out from Rust via `std::process::Command` (`open`, `latexmk`) — so the macOS
  `security` CLI is a natural, dependency-free way to reach the Keychain.
- Non-secret prefs already persist via `Flags` (decoded from JS) + `saveX` ports + `localStorage`
  (e.g. `readerMode`, `isLight`). AI config (active provider, per-provider model, per-provider
  key hint) follows that exact pattern.
- Commands are `#[tauri::command]`s registered in `lib.rs`, invoked from Elm via the FS bridge
  (`FileOps.send`/`request`/`handleResponse`).

## Architecture

Secrets live in the Keychain (Rust ↔ `security` CLI). Non-secret config (active provider, models,
last-4 hints) lives in `localStorage` via the Flags pattern. A Settings pane in `View` edits both.

### 1. Rust — Keychain commands (`fs_commands.rs` or a new `keychain.rs`)

Service constant: `"MacScriptaViewer-AI"`. Account = provider id (`"anthropic"`/`"openai"`/`"gemini"`).

- `set_api_key(provider: String, key: String) -> Result<(), String>`
  → `security add-generic-password -U -s "MacScriptaViewer-AI" -a <provider> -w <key>`
  (`-U` updates if present). Args passed as separate argv (no shell), so no injection.
- `delete_api_key(provider: String) -> Result<(), String>`
  → `security delete-generic-password -s "MacScriptaViewer-AI" -a <provider>`
  (treat "item not found" as success — deleting an absent key is a no-op).

Register both in `lib.rs`. **The full key is never read back to the frontend.** (`get_api_key`
for internal backend use, and `has_api_key`, are deferred to sub-project #3, where the chat
backend reads the key in Rust and calls the provider — the secret never crosses into JS.)

### 2. Elm — config model + persistence

- `Types.Model` gains AI config (exact field shapes finalized in the plan; intent):
  - `aiActiveProvider : String` (default `"anthropic"`)
  - `aiModels : Dict String String` (provider → chosen model)
  - `aiKeyHints : Dict String String` (provider → last-4 hint; key present in this dict ⇔ a key
    is stored for that provider)
  - transient form state: `aiKeyInput : Dict String String` (provider → current password-field
    text), `showSettings : Bool`.
- `Flags` gains the persisted non-secret config (`aiActiveProvider`, `aiModels`, `aiKeyHints`),
  decoded tolerantly with defaults (mirroring `readerMode`/`fullParse`).
- A `saveAiConfig : Json.Encode.Value -> Cmd msg` port (mirrors `saveReaderMode`) writes the
  non-secret config to `localStorage`; `index.html` reads it back into `flags` at boot and
  subscribes the save handler.

### 3. Elm — Settings pane (`View`) + messages (`Main`)

- A **⚙ Settings** button in the toolbar toggles `showSettings`.
- When `showSettings`, render a settings pane (modal overlay over the app) with an **AI Providers**
  panel mirroring v4:
  - An **active provider** selector (radio or `<select>`: Anthropic / OpenAI / Gemini).
  - One row per provider: a **model** `<select>` (curated list + default — see below), a
    **key** `input[type=password]` ("Paste your API key") with a **Set** button, and once a key
    is stored, a masked hint `key: ••••1234` + a **Delete** button.
  - A **Close** control.
- Messages (in `Types.Msg`, handled in `Main`): `ToggledSettings`, `SetActiveProvider String`,
  `SetProviderModel String String` (provider, model), `AiKeyInput String String`
  (provider, text), `SubmitApiKey String` (provider), `DeleteApiKey String` (provider).
- `SubmitApiKey provider`: compute `hint` = last 4 chars of the input; `request` `set_api_key`
  with `{ provider, key = input }`; update `aiKeyHints[provider] = hint`, clear `aiKeyInput[provider]`,
  and `saveAiConfig`. `DeleteApiKey provider`: `request` `delete_api_key`, drop the hint, `saveAiConfig`.
  `SetActiveProvider`/`SetProviderModel`: update state + `saveAiConfig`.

### Curated model lists (placeholders — trivially editable strings in the dropdown)

- **anthropic:** `claude-opus-4-8`, `claude-sonnet-4-6`, `claude-haiku-4-5` (default `claude-sonnet-4-6`)
- **openai:** `gpt-4o`, `gpt-4o-mini`, `gpt-4.1` (default `gpt-4o`)
- **gemini:** `gemini-2.0-flash`, `gemini-1.5-pro`, `gemini-1.5-flash` (default `gemini-1.5-pro`)

## Data Flow

```
Set key:  Settings input → SubmitApiKey provider
            → request set_api_key { provider, key }  → Rust → `security add-generic-password`
            → Elm: aiKeyHints[provider] := last4(input); clear input; saveAiConfig → localStorage
Delete:   DeleteApiKey provider → request delete_api_key → Rust → `security delete-generic-password`
            → drop hint; saveAiConfig
Config:   active provider / model selects → update state → saveAiConfig
Boot:     index.html reads localStorage → flags → Model (active provider, models, hints)
```

The Keychain holds the secrets; `localStorage` holds only non-secret config + last-4 hints.

## Error Handling

- `security` non-zero exit → `Err(stderr)` → surfaced via the existing error banner. Delete of an
  absent key is treated as success.
- A `set_api_key` failure leaves the hint unchanged (only update the hint after the command's `Ok`
  response, in `handleResponse`).

## Testing

- **Elm:** `Flags` decode of AI config (present / missing → defaults); a `last4` hint helper
  (`"sk-abc1234" → "1234"`, short strings handled); the config encoder used by `saveAiConfig`
  round-trips.
- **Rust:** Keychain commands verified **manually** (they touch the real login Keychain). Optional
  belt-and-suspenders: a Rust test using a throwaway service name (`"MacScriptaViewer-AI-test"`)
  that `set`s, then `delete`s and asserts success — guarded so it cleans up; skip if it proves
  flaky in the sandbox.
- **Manual:** open Settings → enter an Anthropic key → "key: ••••1234" appears → relaunch → hint
  persists, active provider/model remembered → Delete → hint clears; confirm via Keychain Access
  that an item `MacScriptaViewer-AI / anthropic` is created and removed.

## Out of Scope (later sub-projects / YAGNI)

- Any provider API call or key validation (needs the HTTP layer → sub-project #3 chat).
- `get_api_key`/`has_api_key` (added in #3, where the chat backend reads the key in Rust).
- The terminal panel, tabs, and shell sessions (#2); the AI agent + vault access (#4).
- Per-provider advanced params (temperature, max tokens), usage/billing, multiple keys per provider.
