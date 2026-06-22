# Chat "File" button + Prev/Next navigation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-reply "File" button (with a title field) that writes an AI chat reply into `<Vault>/Inbox`, and add Prev/Next document navigation with `Cmd+[` / `Cmd+]` shortcuts.

**Architecture:** Pure logic goes in small testable modules (`PathUtil.withDefaultExtension`, a new `Nav` module for back/forward stack transitions); `Main.elm` wires those into `update`/`subscriptions`, and `View.elm` adds the UI. The reply→file write reuses the existing `create_file` Tauri command and `PCreateFile` completion path (which already opens + reveals the new file). Navigation adds a `future` forward-stack alongside the existing `history` back-stack.

**Tech Stack:** Elm 0.19 (`Browser.element`), elm-test, Tauri 2 backend (unchanged — only the existing `create_file` command is used).

## Global Constraints

- elm-format format-on-save is enabled; keep code elm-format-clean.
- Run tests from the `frontend/` directory: `npx elm-test` (or `elm-test` if on PATH).
- New files for chat replies go under `Inbox/` when the vault is a kbase (via `PathUtil.kbaseRoot`); otherwise fall back to `PathUtil.siblingPath model.selectedPath name`, exactly mirroring the existing `ClickedNewFile` handler (`Main.elm:344-377`).
- Filename extension default for chat-reply files: `.md` (append only when the title's basename has no `.`).
- `Cmd+[` → Prev, `Cmd+]` → Next; both global (fire even when editor/chat is focused); both no-op when their stack is empty.
- Opening a document normally (`openDoc`) clears the `future` stack (standard browser semantics).

---

### Task 1: `PathUtil.withDefaultExtension` helper

Pure helper that appends a default extension when the filename's basename has no `.`.

**Files:**
- Modify: `frontend/src/PathUtil.elm` (module exposing line `:1`; add function at end of file `:91`)
- Test: `frontend/tests/PathUtilTest.elm` (add cases to existing `suite`)

**Interfaces:**
- Produces: `PathUtil.withDefaultExtension : String -> String -> String` — `withDefaultExtension ext name` returns `name` unchanged if its basename already contains `.`, otherwise `name ++ "." ++ ext`. (Consumed by Task 3.)

- [ ] **Step 1: Write the failing tests**

In `frontend/tests/PathUtilTest.elm`, add these to the list inside `describe "PathUtil"` (e.g. right after the `siblingPath` cases):

```elm
        , test "withDefaultExtension appends when there is no extension" <|
            \_ -> Expect.equal "notes.md" (PathUtil.withDefaultExtension "md" "notes")
        , test "withDefaultExtension keeps an existing extension" <|
            \_ -> Expect.equal "notes.scripta" (PathUtil.withDefaultExtension "md" "notes.scripta")
        , test "withDefaultExtension keeps a multi-dot name unchanged" <|
            \_ -> Expect.equal "a.b.md" (PathUtil.withDefaultExtension "md" "a.b.md")
        , test "withDefaultExtension only inspects the basename" <|
            \_ -> Expect.equal "Inbox/notes.md" (PathUtil.withDefaultExtension "md" "Inbox/notes")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd frontend && npx elm-test`
Expected: FAIL — compiler error / naming error that `PathUtil.withDefaultExtension` does not exist.

- [ ] **Step 3: Implement the helper**

In `frontend/src/PathUtil.elm`, change the module line `:1` to add the export:

```elm
module PathUtil exposing (ancestorDirs, basename, kbaseRoot, parentDir, siblingPath, withDefaultExtension)
```

Append at the end of the file:

```elm


{-| Ensure a file name has an extension. If the basename (final '/'-segment)
already contains a '.', `name` is returned unchanged; otherwise "." ++ ext is
appended. So `withDefaultExtension "md" "notes"` is `"notes.md"`, while
`withDefaultExtension "md" "notes.scripta"` is `"notes.scripta"`.
-}
withDefaultExtension : String -> String -> String
withDefaultExtension ext name =
    if String.contains "." (basename name) then
        name

    else
        name ++ "." ++ ext
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd frontend && npx elm-test`
Expected: PASS (all PathUtil tests, including the 4 new ones).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/PathUtil.elm frontend/tests/PathUtilTest.elm
git commit -m "feat: add PathUtil.withDefaultExtension helper"
```

---

### Task 2: `Nav` module — back/forward stack transitions

Pure module computing Prev/Next stack transitions, so navigation logic is unit-testable independent of Cmds.

**Files:**
- Create: `frontend/src/Nav.elm`
- Test: `frontend/tests/NavTest.elm`

**Interfaces:**
- Produces (consumed by Task 4):
  - `type alias Nav.Step = { target : String, history : List String, future : List String }`
  - `Nav.prev : Maybe String -> List String -> List String -> Maybe Nav.Step` — args are `current` selected path, `history`, `future`. Pops the head of `history` as `target`, pushes `current` (when `Just`) onto `future`. `Nothing` when `history` is empty.
  - `Nav.next : Maybe String -> List String -> List String -> Maybe Nav.Step` — pops the head of `future` as `target`, pushes `current` (when `Just`) onto `history`. `Nothing` when `future` is empty.

- [ ] **Step 1: Write the failing tests**

Create `frontend/tests/NavTest.elm`:

```elm
module NavTest exposing (suite)

import Expect
import Nav
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Nav"
        [ test "prev pops history head and pushes current onto future" <|
            \_ ->
                Expect.equal
                    (Just { target = "a", history = [], future = [ "b" ] })
                    (Nav.prev (Just "b") [ "a" ] [])
        , test "prev with empty history is Nothing" <|
            \_ -> Expect.equal Nothing (Nav.prev (Just "b") [] [])
        , test "prev with no current does not push onto future" <|
            \_ ->
                Expect.equal
                    (Just { target = "a", history = [], future = [] })
                    (Nav.prev Nothing [ "a" ] [])
        , test "next pops future head and pushes current onto history" <|
            \_ ->
                Expect.equal
                    (Just { target = "b", history = [ "a" ], future = [] })
                    (Nav.next (Just "a") [] [ "b" ])
        , test "next with empty future is Nothing" <|
            \_ -> Expect.equal Nothing (Nav.next (Just "a") [] [])
        , test "prev then next round-trips back to the starting document" <|
            \_ ->
                -- At B with history [A]: Prev -> target A, future [B]
                case Nav.prev (Just "B") [ "A" ] [] of
                    Just afterPrev ->
                        -- Now at A (target) with history [], future [B]: Next -> target B, history [A]
                        Expect.equal
                            (Just { target = "B", history = [ "A" ], future = [] })
                            (Nav.next (Just afterPrev.target) afterPrev.history afterPrev.future)

                    Nothing ->
                        Expect.fail "prev should have produced a step"
        ]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd frontend && npx elm-test`
Expected: FAIL — `Nav` module does not exist.

- [ ] **Step 3: Implement the `Nav` module**

Create `frontend/src/Nav.elm`:

```elm
module Nav exposing (Step, next, prev)

{-| Pure back/forward navigation stack transitions.

`history` is the back-stack (most-recent first); `future` is the forward-stack
(most-recent first). `current` is the currently open document, if any.
-}


type alias Step =
    { target : String, history : List String, future : List String }


{-| Go back: the most recent history entry becomes the target, and the current
document (if any) is pushed onto the future stack. Nothing when history is empty.
-}
prev : Maybe String -> List String -> List String -> Maybe Step
prev current history future =
    case history of
        p :: rest ->
            Just { target = p, history = rest, future = maybeCons current future }

        [] ->
            Nothing


{-| Go forward: the most recent future entry becomes the target, and the current
document (if any) is pushed onto the history stack. Nothing when future is empty.
-}
next : Maybe String -> List String -> List String -> Maybe Step
next current history future =
    case future of
        n :: rest ->
            Just { target = n, history = maybeCons current history, future = rest }

        [] ->
            Nothing


maybeCons : Maybe a -> List a -> List a
maybeCons m xs =
    case m of
        Just x ->
            x :: xs

        Nothing ->
            xs
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd frontend && npx elm-test`
Expected: PASS (all NavTest cases).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Nav.elm frontend/tests/NavTest.elm
git commit -m "feat: add Nav module for back/forward stack transitions"
```

---

### Task 3: Chat "File" — Model state, messages, and update wiring

Adds per-reply title drafts and the `File` action that writes the reply to `Inbox/`. (View comes in Task 5; this task is compiled/checked via the build, with the value logic resting on Task 1's tested helper.)

**Files:**
- Modify: `frontend/src/Types.elm` (Model `:46`, Msg list `:118-121`)
- Modify: `frontend/src/Main.elm` (init `:75-77`, update — add branches near `CopyReply` `:498`)

**Interfaces:**
- Consumes: `PathUtil.withDefaultExtension` (Task 1); existing `request`, `PCreateFile`, `PathUtil.kbaseRoot`, `PathUtil.siblingPath`.
- Produces (consumed by Task 5):
  - Model field `chatFileTitles : Dict Int String`
  - Msgs `ChatFileTitleInput Int String` and `ClickedChatFile Int String`

- [ ] **Step 1: Add Model field and Msgs**

In `frontend/src/Types.elm`, add the field to the `Model` record (after `chatPending : Bool` at `:48`):

```elm
    , chatPending : Bool
    , chatFileTitles : Dict Int String
    }
```

(`Dict` is already imported at `Types.elm:5`.)

Add two Msg variants after `SendChat` (`:121`):

```elm
    | SendChat
    | ChatFileTitleInput Int String
    | ClickedChatFile Int String
```

- [ ] **Step 2: Initialize the new field**

In `frontend/src/Main.elm` `init`, add after `chatPending = False` (`:77`):

```elm
        , chatPending = False
        , chatFileTitles = Dict.empty
        }
```

(`Dict` is already imported at `Main.elm:6`.)

- [ ] **Step 3: Add the update branches**

In `frontend/src/Main.elm`, add these two branches to `update` (place them right after the `CopyReply` branch at `:498-499`):

```elm
        ChatFileTitleInput n s ->
            ( { model | chatFileTitles = Dict.insert n s model.chatFileTitles }, Cmd.none )

        ClickedChatFile n content ->
            case model.vaultRoot of
                Just root ->
                    let
                        title =
                            String.trim (Dict.get n model.chatFileTitles |> Maybe.withDefault "")
                    in
                    if String.isEmpty title then
                        ( model, Cmd.none )

                    else
                        let
                            name =
                                PathUtil.withDefaultExtension "md" title

                            cleared =
                                { model | chatFileTitles = Dict.remove n model.chatFileTitles }
                        in
                        case PathUtil.kbaseRoot root of
                            Just kroot ->
                                let
                                    path =
                                        "Inbox/" ++ name
                                in
                                request (PCreateFile path)
                                    "create_file"
                                    [ ( "root", E.string kroot ), ( "path", E.string path ), ( "content", E.string content ) ]
                                    cleared

                            Nothing ->
                                let
                                    path =
                                        PathUtil.siblingPath model.selectedPath name
                                in
                                request (PCreateFile path)
                                    "create_file"
                                    [ ( "root", E.string root ), ( "path", E.string path ), ( "content", E.string content ) ]
                                    cleared

                Nothing ->
                    ( model, Cmd.none )
```

- [ ] **Step 4: Verify it compiles**

Run: `cd frontend && npx elm make src/Main.elm --output=/dev/null`
Expected: Success ("Success!" — no compiler errors). The new Msgs are now handled in `update`.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm
git commit -m "feat: chat File action writes a reply into the vault Inbox"
```

---

### Task 4: Prev/Next navigation — state, update, and buttons

Adds the `future` forward-stack, renames `ClickedBack` → `ClickedPrev`, adds `ClickedNext`, clears `future` on normal document opens, and updates the nav buttons (Back→Prev, add Next). This task leaves the repo compiling; Task 6 adds only the keyboard shortcuts.

**Files:**
- Modify: `frontend/src/Types.elm` (Model `:19`, Msg `:109`)
- Modify: `frontend/src/Main.elm` (init `:48`, `openVault` `:104`, `openDoc` `:147-158`, update `ClickedBack` `:544-550`)
- Modify: `frontend/src/View.elm` (nav button block `:91-95`)

**Interfaces:**
- Consumes: `Nav.prev`, `Nav.next`, `Nav.Step` (Task 2); existing `openDocNoPush`.
- Produces (consumed by Task 6): Model field `future : List String`; Msgs `ClickedPrev`, `ClickedNext`.

- [ ] **Step 1: Add Model field and rename/add Msgs**

In `frontend/src/Types.elm`, add `future` after `history` (`:19`):

```elm
    , history : List String
    , future : List String
```

Rename `ClickedBack` to `ClickedPrev` and add `ClickedNext` (`:109`):

```elm
    | ClickedPrev
    | ClickedNext
```

- [ ] **Step 2: Add `import Nav` to Main**

In `frontend/src/Main.elm`, add the import (keep alphabetical-ish ordering near the other local modules, e.g. after `import Language` at `:12`):

```elm
import Nav
```

- [ ] **Step 3: Initialize and reset `future`**

In `init` (`Main.elm:48`), add after `history = []`:

```elm
        , history = []
        , future = []
```

In `openVault` (`Main.elm:104`), add after `history = []` in the `m0` record:

```elm
                , history = []
                , future = []
```

- [ ] **Step 4: Clear `future` on normal opens**

In `openDoc` (`Main.elm:147-158`), change the final line so opening a new document clears the forward stack:

```elm
openDoc : String -> Model -> ( Model, Cmd Msg )
openDoc path model =
    let
        history =
            case model.selectedPath of
                Just current ->
                    current :: model.history

                Nothing ->
                    model.history
    in
    openDocNoPush path { model | history = history, future = [] }
```

- [ ] **Step 5: Replace the `ClickedBack` branch with `ClickedPrev` / `ClickedNext`**

In `frontend/src/Main.elm`, replace the `ClickedBack` branch (`:544-550`) with:

```elm
        ClickedPrev ->
            case Nav.prev model.selectedPath model.history model.future of
                Just step ->
                    openDocNoPush step.target { model | history = step.history, future = step.future }

                Nothing ->
                    ( model, Cmd.none )

        ClickedNext ->
            case Nav.next model.selectedPath model.history model.future of
                Just step ->
                    openDocNoPush step.target { model | history = step.history, future = step.future }

                Nothing ->
                    ( model, Cmd.none )
```

- [ ] **Step 6: Rename Back → Prev and add the Next button**

In `frontend/src/View.elm`, replace the existing Back button block (`:91-95`) with:

```elm
                [ button
                    [ onClick ClickedPrev
                    , Html.Attributes.disabled (List.isEmpty model.history)
                    ]
                    [ text "\u{2190} Prev" ]
                , button
                    [ onClick ClickedNext
                    , Html.Attributes.disabled (List.isEmpty model.future)
                    ]
                    [ text "Next \u{2192}" ]
```

- [ ] **Step 7: Verify it compiles**

Run: `cd frontend && npx elm make src/Main.elm --output=/dev/null`
Expected: Success ("Success!"). `ClickedBack` is fully replaced across `Types`, `Main`, and `View`; no references remain.

- [ ] **Step 8: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm
git commit -m "feat: add forward-nav future stack with Prev/Next buttons"
```

---

### Task 5: Chat "File" — view (title field + File button) and tests

Renders the per-reply title input and File button, threading the reply index and title draft into `chatMessageView`.

**Files:**
- Modify: `frontend/src/View.elm` (call site `:666`, `chatMessageView` `:683-739`)
- Test: `frontend/tests/ChatViewTest.elm` (update existing calls + add cases)

**Interfaces:**
- Consumes: Model field `chatFileTitles` and Msgs `ChatFileTitleInput`, `ClickedChatFile` (Task 3).
- Produces: new `chatMessageView : Int -> String -> Chat.ChatMessage -> Html Msg` (consumed by the `aiChatView` call site and the tests).

- [ ] **Step 1: Update the failing tests**

Replace the body of `frontend/tests/ChatViewTest.elm` `suite` with calls that match the new arity, and add coverage for the File button:

```elm
suite : Test
suite =
    describe "View.chatMessageView"
        [ test "assistant reply has a Copy button that emits CopyReply with the raw content" <|
            \_ ->
                View.chatMessageView 0 "" (Chat.assistant "# Hi\n\nsource")
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "button", Selector.containing [ Selector.text "Copy" ] ]
                    |> Event.simulate Event.click
                    |> Event.expect (CopyReply "# Hi\n\nsource")
        , test "assistant reply File button emits ClickedChatFile with index and content" <|
            \_ ->
                View.chatMessageView 2 "notes" (Chat.assistant "body text")
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "button", Selector.containing [ Selector.text "File" ] ]
                    |> Event.simulate Event.click
                    |> Event.expect (ClickedChatFile 2 "body text")
        , test "assistant title field emits ChatFileTitleInput with the reply index" <|
            \_ ->
                View.chatMessageView 3 "" (Chat.assistant "body")
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "input" ]
                    |> Event.simulate (Event.input "draft")
                    |> Event.expect (ChatFileTitleInput 3 "draft")
        , test "File button is disabled when the title draft is blank" <|
            \_ ->
                View.chatMessageView 0 "   " (Chat.assistant "body")
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "button", Selector.containing [ Selector.text "File" ] ]
                    |> Query.has [ Selector.disabled True ]
        , test "user message has no Copy button" <|
            \_ ->
                View.chatMessageView 0 "" (Chat.user "hello")
                    |> Query.fromHtml
                    |> Query.findAll [ Selector.tag "button", Selector.containing [ Selector.text "Copy" ] ]
                    |> Query.count (Expect.equal 0)
        ]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd frontend && npx elm-test tests/ChatViewTest.elm`
Expected: FAIL — `chatMessageView` is called with 3 args but currently takes 1 (compiler arity error).

- [ ] **Step 3: Update the call site**

In `frontend/src/View.elm` `aiChatView` (`:666`), replace `List.map chatMessageView model.chatMessages` with an indexed map that passes the per-reply title draft:

```elm
            (List.indexedMap
                (\i m -> chatMessageView i (Dict.get i model.chatFileTitles |> Maybe.withDefault "") m)
                model.chatMessages
```

(`Dict` is already imported at `View.elm:5`.)

- [ ] **Step 4: Update `chatMessageView`**

In `frontend/src/View.elm`, change the signature and add the index/draft params (`:683-684`):

```elm
chatMessageView : Int -> String -> Chat.ChatMessage -> Html Msg
chatMessageView idx titleDraft m =
```

Then, in the assistant-only header branch (`:727-735`), replace the single-element list holding the Copy button with Copy + title input + File button:

```elm
                    else
                        [ button
                            [ onClick (CopyReply m.content)
                            , style "font-size" "10px"
                            , style "font-weight" "400"
                            , style "padding" "0 6px"
                            ]
                            [ text "Copy" ]
                        , Html.input
                            [ Html.Attributes.placeholder "title\u{2026}"
                            , Html.Attributes.value titleDraft
                            , onInput (ChatFileTitleInput idx)
                            , style "font-size" "10px"
                            , style "width" "90px"
                            ]
                            []
                        , button
                            [ onClick (ClickedChatFile idx m.content)
                            , Html.Attributes.disabled (String.isEmpty (String.trim titleDraft))
                            , style "font-size" "10px"
                            , style "font-weight" "400"
                            , style "padding" "0 6px"
                            ]
                            [ text "File" ]
                        ]
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd frontend && npx elm-test tests/ChatViewTest.elm`
Expected: PASS (all five ChatViewTest cases).

- [ ] **Step 6: Commit**

```bash
git add frontend/src/View.elm frontend/tests/ChatViewTest.elm
git commit -m "feat: chat replies show a title field and File button"
```

---

### Task 6: Cmd+[ / Cmd+] keyboard shortcuts

Wires the global keyboard shortcuts to the Prev/Next messages added in Task 4.

**Files:**
- Modify: `frontend/src/Main.elm` (imports `:4`, `subscriptions` `:793-800`)

**Interfaces:**
- Consumes: Msgs `ClickedPrev`, `ClickedNext` (Task 4).

- [ ] **Step 1: Add `Browser.Events` import**

In `frontend/src/Main.elm`, add after `import Browser` (`:4`):

```elm
import Browser.Events
```

- [ ] **Step 2: Add the keyboard shortcut subscription**

In `frontend/src/Main.elm`, replace `subscriptions` (`:793-800`) with a version that adds `Browser.Events.onKeyDown`, plus a decoder:

```elm
subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ FileOps.fsResponse GotFsResponse
        , FileOps.fileChanged GotFileChanged
        , FileOps.openFile GotOpenFile
        , FileOps.gotOpenFolders GotOpenFolders
        , Browser.Events.onKeyDown navKeyDecoder
        ]


{-| Cmd+[ -> Prev, Cmd+] -> Next. Fails (no message) for anything else, so it
does not interfere with normal typing. The update handlers no-op when the
relevant nav stack is empty.
-}
navKeyDecoder : D.Decoder Msg
navKeyDecoder =
    D.map2 Tuple.pair (D.field "metaKey" D.bool) (D.field "key" D.string)
        |> D.andThen
            (\( meta, key ) ->
                if meta && key == "[" then
                    D.succeed ClickedPrev

                else if meta && key == "]" then
                    D.succeed ClickedNext

                else
                    D.fail "not a nav shortcut"
            )
```

- [ ] **Step 3: Verify the whole frontend compiles**

Run: `cd frontend && npx elm make src/Main.elm --output=/dev/null`
Expected: Success ("Success!").

- [ ] **Step 4: Run the full test suite**

Run: `cd frontend && npx elm-test`
Expected: PASS — all suites green (PathUtil, Nav, ChatView, and the pre-existing suites).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Main.elm
git commit -m "feat: Cmd+[ and Cmd+] navigate Prev/Next"
```

---

## Manual verification (after all tasks)

Run the app (`npm run tauri dev` or the project's run command) and confirm:

1. **Chat File button:** open the AI chat, get a reply, type a title (e.g. `idea`) in the reply's title field, click **File**. A file `Inbox/idea.md` is created with the reply text, opens in the editor, and is revealed/expanded in the tree. Typing `idea.scripta` instead produces `Inbox/idea.scripta`. Blank title → File button disabled.
2. **Prev/Next:** open doc A, then B, then C. **Prev** (button) goes C→B→A and disables at the end; **Next** goes A→B→C. `Cmd+[` and `Cmd+]` do the same. Opening a different doc from the tree after going Prev clears the Next button (disabled).

---

## Self-Review notes

- **Spec coverage:** Part 1 (title field per reply, File button, write to `<Vault>/Inbox`, `.md` default, open-on-create) → Tasks 1, 3, 5. Part 2 (Back→Prev rename, Cmd+[, Next button, Cmd+]) → Tasks 2, 4, 6. All spec sections map to tasks.
- **Type consistency:** `chatFileTitles : Dict Int String`, `ChatFileTitleInput Int String`, `ClickedChatFile Int String`, `future : List String`, `ClickedPrev`/`ClickedNext`, `Nav.Step { target, history, future }`, and `chatMessageView : Int -> String -> Chat.ChatMessage -> Html Msg` are used identically across the tasks that define and consume them.
- **Every task leaves the repo compiling:** Task 4 renames `ClickedBack` across `Types`, `Main`, and `View` together (and adds the Next button), so the build is green at each task boundary — important for per-task review gates.
