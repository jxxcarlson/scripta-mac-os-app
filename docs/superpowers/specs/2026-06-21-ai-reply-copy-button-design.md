# AI Reply "Copy" Button — Design

**Date:** 2026-06-21
**Status:** Approved — ready for implementation plan.

## Goal

Add a small `Copy` button to each **assistant** reply in the AI chat (Tab/left pane)
that copies the **raw markdown source** the model returned to the system clipboard.

## Decisions

- **Assistant replies only** — user messages get no copy button.
- **Copies the raw markdown source** (`ChatMessage.content` — the text the model
  returned), not the rendered HTML or a plain-text projection.
- **No transient "Copied!" feedback** — would require per-message state; YAGNI. The
  button copies silently.

## Components

- **`frontend/src/FileOps.elm`** — new outbound port:
  ```elm
  port copyToClipboard : String -> Cmd msg
  ```
  Add `copyToClipboard` to the `port module FileOps exposing (...)` list.

- **`frontend/src/Types.elm`** — new `Msg` variant `CopyReply String`.

- **`frontend/src/Main.elm`** — handle it in `update`:
  ```elm
  CopyReply text ->
      ( model, FileOps.copyToClipboard text )
  ```

- **`frontend/src/View.elm`** — in `chatMessageView`, for assistant messages only,
  render a small muted `Copy` button in the bubble header next to the "Assistant"
  label: `button [ onClick (CopyReply m.content), <small/muted styles> ] [ text "Copy" ]`.
  Expose `chatMessageView` from the module for testing.

- **`frontend/index.html`** — subscribe to the port using the existing guarded
  `subscribePort` helper:
  ```js
  subscribePort('copyToClipboard', (text) => {
    navigator.clipboard.writeText(text).catch(() => {});
  });
  ```

## Data flow

User clicks `Copy` on an assistant bubble → `CopyReply m.content` → `update` issues
`FileOps.copyToClipboard text` → JS port handler calls `navigator.clipboard.writeText`.
One-way; no model state added.

## Error handling

`navigator.clipboard.writeText` returns a promise; `.catch(() => {})` swallows failures
(e.g. clipboard permission denied) so a failed copy is a silent no-op rather than an
unhandled rejection. Matches the app's existing best-effort port style.

## Testing

- **Elm (`Test.Html`):** expose `chatMessageView`. Test that an assistant message
  (`role == "assistant"`) renders a `button` with text `Copy` whose click emits
  `CopyReply <content>`; and that a user message (`role == "user"`) renders no such
  button.
- **JS (clipboard write):** no JS test harness in this repo — verified manually after
  `make build` (click Copy on a reply, paste elsewhere, confirm raw markdown).
- **Regression:** full `elm-test` stays green.
