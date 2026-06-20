# AI Reply "Copy" Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a small `Copy` button to each assistant reply in the AI chat that copies the reply's raw markdown source to the clipboard.

**Architecture:** A new outbound Elm port `copyToClipboard` carries the text to a JS handler that calls `navigator.clipboard.writeText`. The assistant bubble header renders a `Copy` button emitting `CopyReply content`; `update` issues the port command. No model state is added.

**Tech Stack:** Elm 0.19.1 ports + `Test.Html`, Tauri WKWebView `navigator.clipboard`.

**Spec:** `docs/superpowers/specs/2026-06-21-ai-reply-copy-button-design.md`

---

## File Structure

- `frontend/src/FileOps.elm` — new outbound port `copyToClipboard : String -> Cmd msg` (+ exposing).
- `frontend/src/Types.elm` — new `Msg` variant `CopyReply String`.
- `frontend/src/Main.elm` — `update` handler for `CopyReply`.
- `frontend/src/View.elm` — expose `chatMessageView`; add the `Copy` button to assistant bubbles.
- `frontend/index.html` — `subscribePort('copyToClipboard', ...)`.
- `frontend/tests/ChatViewTest.elm` (new) — assistant bubble has the Copy button (emits `CopyReply content`); user bubble does not.

This is a single coupled task: the view references the new `Msg`, which references the new port, so the pieces compile only together. Implement as one TDD task.

---

### Task 1: AI reply Copy button

**Files:**
- Create: `frontend/tests/ChatViewTest.elm`
- Modify: `frontend/src/Types.elm`, `frontend/src/FileOps.elm`, `frontend/src/Main.elm`, `frontend/src/View.elm:1` + `chatMessageView`, `frontend/index.html`

- [ ] **Step 1: Write the failing test**

Create `frontend/tests/ChatViewTest.elm`:

```elm
module ChatViewTest exposing (suite)

import Chat
import Expect
import Test exposing (Test, describe, test)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Types exposing (Msg(..))
import View


suite : Test
suite =
    describe "View.chatMessageView"
        [ test "assistant reply has a Copy button that emits CopyReply with the raw content" <|
            \_ ->
                View.chatMessageView (Chat.assistant "# Hi\n\nsource")
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "button", Selector.containing [ Selector.text "Copy" ] ]
                    |> Event.simulate Event.click
                    |> Event.expect (CopyReply "# Hi\n\nsource")
        , test "user message has no Copy button" <|
            \_ ->
                View.chatMessageView (Chat.user "hello")
                    |> Query.fromHtml
                    |> Query.findAll [ Selector.tag "button", Selector.containing [ Selector.text "Copy" ] ]
                    |> Query.count (Expect.equal 0)
        ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd frontend && elm-test`
Expected: FAIL — compile error (`View.chatMessageView` not exposed; `CopyReply` unknown).

- [ ] **Step 3: Add the `CopyReply` Msg variant**

In `frontend/src/Types.elm`, add a new variant to the `type Msg` union. Add it immediately after the existing `SelectTerminalTab String` variant (around line 116):

```elm
    | SelectTerminalTab String
    | CopyReply String
```

- [ ] **Step 4: Add the `copyToClipboard` port**

In `frontend/src/FileOps.elm`, add `copyToClipboard` to the module exposing list — append it to the `scrollAndHighlight` line so that line reads:

```elm
    , scrollAndHighlight, copyToClipboard
```

Then add the port declaration next to the other `save*`/`scrollAndHighlight` ports (after `port scrollAndHighlight : String -> Cmd msg` near line 59):

```elm
port copyToClipboard : String -> Cmd msg
```

- [ ] **Step 5: Handle `CopyReply` in `update`**

In `frontend/src/Main.elm`, add a branch to the `update` `case` (place it next to the `SelectTerminalTab` branch, around line 495):

```elm
        CopyReply text ->
            ( model, FileOps.copyToClipboard text )
```

(`FileOps` is already imported in `Main.elm`.)

- [ ] **Step 6: Expose `chatMessageView` and add the Copy button**

In `frontend/src/View.elm`, add `chatMessageView` to the module exposing list (alphabetical position):

```elm
module View exposing (chatMessageView, imagePane, plainTextPreview, rightTabs, themeName, view)
```

Then replace the header `div` in `chatMessageView` (the block that renders the "You"/"Assistant" label, currently:

```elm
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
```

) with:

```elm
        (div
            [ style "display" "flex"
            , style "align-items" "center"
            , style "gap" "8px"
            , style "font-size" "11px"
            , style "font-weight" "700"
            , style "color" "var(--muted)"
            , style "margin-bottom" "4px"
            ]
            (text
                (if isUser then
                    "You"

                 else
                    "Assistant"
                )
                :: (if isUser then
                        []

                    else
                        [ button
                            [ onClick (CopyReply m.content)
                            , style "font-size" "10px"
                            , style "font-weight" "400"
                            , style "padding" "0 6px"
                            ]
                            [ text "Copy" ]
                        ]
                   )
            )
            :: body
        )
```

(`button`, `text`, `style`, and `onClick` are already imported in `View.elm`.)

- [ ] **Step 7: Run the test to verify it passes**

Run: `cd frontend && elm-test`
Expected: PASS (all tests green, count now 99).

- [ ] **Step 8: Wire the JS clipboard handler**

In `frontend/index.html`, next to the other `subscribePort(...)` calls (e.g. after the `subscribePort('saveAiConfig', ...)` block around line 432), add:

```js
      subscribePort('copyToClipboard', (text) => {
        navigator.clipboard.writeText(text).catch(() => {});
      });
```

- [ ] **Step 9: Build and commit**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make elm && (cd frontend && elm-test)`
Expected: `Success!` and `TEST RUN PASSED` (99 tests).

```bash
git add frontend/src/Types.elm frontend/src/FileOps.elm frontend/src/Main.elm frontend/src/View.elm frontend/index.html frontend/tests/ChatViewTest.elm
git commit -m "feat: add Copy button to AI replies (copies raw markdown source)"
```

---

## Self-Review

**1. Spec coverage:**
- Copy button on assistant replies only → Step 6 (`if isUser then [] else [button ...]`) + Step 1 user-message test.
- Copies raw markdown source → Step 6 (`CopyReply m.content`) + Step 5 (`FileOps.copyToClipboard text`) + Step 8 (`navigator.clipboard.writeText`).
- No transient feedback / no model state → no `Model` changes anywhere. ✔
- Error handling (`.catch(() => {})`) → Step 8. ✔
- Expose `chatMessageView` + Test.Html tests → Steps 1, 6. ✔

**2. Placeholder scan:** No TBD/TODO; every code step has full code and exact commands. ✔

**3. Type/name consistency:** `CopyReply String` defined in Types (Step 3), emitted in View (Step 6), matched in update (Step 5); `copyToClipboard : String -> Cmd msg` exposed + declared (Step 4), called in update (Step 5), subscribed in JS (Step 8); `chatMessageView` exposed (Step 6) and used by tests (Step 1). All consistent. ✔
