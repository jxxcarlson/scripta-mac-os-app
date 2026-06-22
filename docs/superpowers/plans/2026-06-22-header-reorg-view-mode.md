# Header reorg + View-mode dropdown — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "Reader" toggle with a Reader/Editor/Both View dropdown and reorganize the header into two rows.

**Architecture:** Add a `ViewMode` type + pure `viewModeFromString` (unit-tested), swap the Model's `readerMode : Bool` for `viewMode : ViewMode`, branch `body` on it (adding an editor-only view), and restructure the single toolbar row into two `toolbarRow`s with a `viewModeDropdown` and the buttons regrouped.

**Tech Stack:** Elm 0.19, elm-test.

## Global Constraints

- Run from `frontend/`: `npx elm make src/Main.elm --output=/dev/null`, `npx elm-test`. Existing 131 tests must stay green (plus new ViewMode tests).
- elm-format conventions apply.
- View mode is session-only: `viewMode` defaults to `ViewBoth` each launch; the old persisted `flags.readerMode` is no longer read; the `FileOps.saveReaderMode` port is left defined but uncalled (vestigial, not cleaned up this iteration).
- Row 1 order: Prev, Next, group-separator, Hide/Show Tree, View dropdown, Hide/Show TOC, Hide/Show Terminal.
- Row 2 order: new-file-name input, Saved, New, Rename, Delete, Export dropdown, group-separator, Parse, Dark/Light, ⚙ Settings.
- View dropdown options: `both`→"Both", `editor`→"Editor", `reader`→"Reader"; the option matching `model.viewMode` is `selected`.

---

### Task 1: `ViewMode` type + `viewModeFromString`

**Files:**
- Modify: `frontend/src/Types.elm` (module exposing line `:1`; add type + function)
- Test: `frontend/tests/ViewModeTest.elm`

**Interfaces:**
- Produces: `Types.ViewMode = ViewReader | ViewEditor | ViewBoth`; `Types.viewModeFromString : String -> ViewMode` (consumed by Task 2).

- [ ] **Step 1: Write the failing test**

Create `frontend/tests/ViewModeTest.elm`:

```elm
module ViewModeTest exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import Types exposing (ViewMode(..), viewModeFromString)


suite : Test
suite =
    describe "Types.viewModeFromString"
        [ test "reader" <|
            \_ -> Expect.equal ViewReader (viewModeFromString "reader")
        , test "editor" <|
            \_ -> Expect.equal ViewEditor (viewModeFromString "editor")
        , test "both" <|
            \_ -> Expect.equal ViewBoth (viewModeFromString "both")
        , test "unknown falls back to Both" <|
            \_ -> Expect.equal ViewBoth (viewModeFromString "whatever")
        ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd frontend && npx elm-test`
Expected: FAIL — `Types.ViewMode` / `viewModeFromString` do not exist.

- [ ] **Step 3: Add the type and function**

In `frontend/src/Types.elm`, add `ViewMode(..)` and `viewModeFromString` to the module exposing list. The current line:

```elm
module Types exposing (Model, Msg(..), PendingOp(..), Pane(..))
```

becomes:

```elm
module Types exposing (Model, Msg(..), PendingOp(..), Pane(..), ViewMode(..), viewModeFromString)
```

Then add this type and function to `Types.elm` (e.g. just above the `Pane` type):

```elm
type ViewMode
    = ViewReader
    | ViewEditor
    | ViewBoth


viewModeFromString : String -> ViewMode
viewModeFromString s =
    case s of
        "reader" ->
            ViewReader

        "editor" ->
            ViewEditor

        _ ->
            ViewBoth
```

- [ ] **Step 4: Run the tests**

Run: `cd frontend && npx elm-test`
Expected: PASS (4 new ViewMode tests + existing 131). The repo still compiles — `readerMode` is untouched and `ViewMode` is not yet used elsewhere.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Types.elm frontend/tests/ViewModeTest.elm
git commit -m "feat: add ViewMode type and viewModeFromString"
```

---

### Task 2: Wire viewMode + two-row toolbar

Swap `readerMode`→`viewMode` across Model/init/update/body, add the editor-only view and the View dropdown, and restructure the toolbar into two rows. This all lands together because removing `readerMode` touches the toolbar's old Reader button.

**Files:**
- Modify: `frontend/src/Types.elm` (Model field; Msg)
- Modify: `frontend/src/Main.elm` (Types import; `init`; `update`)
- Modify: `frontend/src/View.elm` (Types import; `body`; new `editorOnlyView`, `viewModeDropdown`, `toolbarRow`, `groupSep`; toolbar rewrite)

**Interfaces:**
- Consumes: `ViewMode(..)`, `viewModeFromString` (Task 1); existing `treeCols`, `renderTocColumns`, `exportDropdown`, `imageView`, `threePaneRow`, `readerView`.

- [ ] **Step 1: Model field + Msg (`Types.elm`)**

Change the Model field — replace:

```elm
    , readerMode : Bool
```

with:

```elm
    , viewMode : ViewMode
```

In the `Msg` type, remove the variant `| ToggledReaderMode` and add `| SetViewMode String` (e.g. where `ToggledReaderMode` was).

- [ ] **Step 2: Main.elm — import, init, update**

Update the Types import in `frontend/src/Main.elm`:

```elm
import Types exposing (Model, Msg(..), PendingOp(..))
```

becomes:

```elm
import Types exposing (Model, Msg(..), PendingOp(..), ViewMode(..), viewModeFromString)
```

In `init`, replace `, readerMode = flags.readerMode` with:

```elm
        , viewMode = ViewBoth
```

In `update`, remove the entire `ToggledReaderMode ->` branch and add:

```elm
        SetViewMode v ->
            ( { model | viewMode = viewModeFromString v }, Cmd.none )
```

- [ ] **Step 3: View.elm — Types import + body branch**

Update the Types import in `frontend/src/View.elm`:

```elm
import Types exposing (Model, Msg(..))
```

becomes:

```elm
import Types exposing (Model, Msg(..), ViewMode(..))
```

Replace the `body` let-binding:

```elm
        body =
            if model.language == Just Language.Image then
                imageView model

            else if model.readerMode then
                readerView

            else
                threePaneRow
```

with:

```elm
        body =
            if model.language == Just Language.Image then
                imageView model

            else
                case model.viewMode of
                    ViewBoth ->
                        threePaneRow

                    ViewReader ->
                        readerView

                    ViewEditor ->
                        editorOnlyView model
```

- [ ] **Step 4: View.elm — new top-level helpers**

Add these four top-level functions (e.g. just above `imageView`):

```elm
editorOnlyView : Model -> Html Msg
editorOnlyView model =
    div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
        (treeCols model
            ++ [ Html.node "codemirror-editor"
                    [ Html.Attributes.attribute "text" model.loadedContent
                    , Html.Attributes.attribute "fill-parent" ""
                    , Html.Events.on "text-change" (D.map EditorChanged Editor.textChangeDecoder)
                    , style "flex" "1"
                    ]
                    []
               ]
        )


viewModeDropdown : Model -> Html Msg
viewModeDropdown model =
    Html.select [ Html.Events.on "change" (D.map SetViewMode Html.Events.targetValue) ]
        [ Html.option [ Html.Attributes.value "both", Html.Attributes.selected (model.viewMode == ViewBoth) ] [ text "Both" ]
        , Html.option [ Html.Attributes.value "editor", Html.Attributes.selected (model.viewMode == ViewEditor) ] [ text "Editor" ]
        , Html.option [ Html.Attributes.value "reader", Html.Attributes.selected (model.viewMode == ViewReader) ] [ text "Reader" ]
        ]


toolbarRow : List (Html Msg) -> Html Msg
toolbarRow children =
    div
        [ style "display" "flex"
        , style "align-items" "center"
        , style "gap" "8px"
        , style "padding" "6px 8px"
        , style "flex-wrap" "wrap"
        ]
        children


groupSep : Html msg
groupSep =
    div
        [ style "width" "1px"
        , style "align-self" "stretch"
        , style "background" "var(--border)"
        , style "margin" "0 4px"
        ]
        []
```

- [ ] **Step 5: View.elm — rewrite the toolbar into two rows**

Replace the entire `toolbar` let-binding (the `div` with `display:flex … border-bottom … flex-wrap` holding every toolbar child, from `toolbar =` through its closing `]`) with:

```elm
        toolbar =
            div [ style "border-bottom" "1px solid var(--border)" ]
                [ toolbarRow
                    [ button
                        [ onClick ClickedPrev
                        , Html.Attributes.disabled (List.isEmpty model.history)
                        ]
                        [ text "← Prev" ]
                    , button
                        [ onClick ClickedNext
                        , Html.Attributes.disabled (List.isEmpty model.future)
                        ]
                        [ text "Next →" ]
                    , groupSep
                    , button [ onClick ToggledTree ]
                        [ text
                            (if model.treeVisible then
                                "Hide Tree"

                             else
                                "Show Tree"
                            )
                        ]
                    , viewModeDropdown model
                    , button [ onClick ToggledToc ]
                        [ text
                            (if model.tocVisible then
                                "Hide TOC"

                             else
                                "Show TOC"
                            )
                        ]
                    , button [ onClick ToggledTerminal ]
                        [ text
                            (if model.terminalVisible then
                                "Hide Terminal"

                             else
                                "Show Terminal"
                            )
                        ]
                    ]
                , toolbarRow
                    [ Html.input
                        [ Html.Attributes.placeholder "new-file-name"
                        , Html.Attributes.value model.newName
                        , onInput SetNewName
                        , style "width" "300px"
                        , style "min-width" "150px"
                        , Html.Attributes.attribute "autocapitalize" "off"
                        , Html.Attributes.attribute "autocorrect" "off"
                        , Html.Attributes.attribute "autocomplete" "off"
                        , Html.Attributes.spellcheck False
                        ]
                        []
                    , div [ style "font-size" "12px", style "color" "var(--muted)" ]
                        [ text (saveLabel model.saveState.saveStatus) ]
                    , button [ onClick ClickedNewFile ] [ text "New" ]
                    , button [ onClick ClickedRename ] [ text "Rename" ]
                    , button [ onClick ClickedDeleteSelected ] [ text "Delete" ]
                    , exportDropdown
                    , groupSep
                    , button [ onClick ToggledParseMode ]
                        [ text
                            (if model.fullParse then
                                "Parse: Full"

                             else
                                "Parse: Incremental"
                            )
                        ]
                    , button [ onClick ToggledTheme ]
                        [ text
                            (if model.isLight then
                                "Dark"

                             else
                                "Light"
                            )
                        ]
                    , button [ onClick ToggledSettings ] [ text "⚙ Settings" ]
                    ]
                ]
```

- [ ] **Step 6: Verify compiles + tests**

Run: `cd frontend && npx elm make src/Main.elm --output=/dev/null` → "Success!".
Run: `cd frontend && npx elm-test` → all pass (135 = 131 + 4).

(If the compiler reports a leftover `model.readerMode` or `ToggledReaderMode` reference, fix that reference — the only legitimate uses were the body branch and the toolbar Reader button, both replaced above.)

- [ ] **Step 7: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm
git commit -m "feat: View-mode dropdown (Reader/Editor/Both) + two-row header"
```

---

## Manual verification (after both tasks — `make install`)

1. Header is two rows:
   - Row 1: `← Prev`, `Next →`, separator, `Hide/Show Tree`, `[View ▾]`, `Hide/Show TOC`, `Hide/Show Terminal`.
   - Row 2: new-file-name field, `Saved`, `New`, `Rename`, `Delete`, `Export ▾`, separator, `Parse: …`, `Dark/Light`, `⚙ Settings`.
2. The View dropdown switches **Both** (editor + rendered), **Editor** (editor full-width, no rendered pane), **Reader** (rendered only). Image files still show the image view. The old "Reader" button is gone.
3. Tree/TOC/Terminal toggles, Parse, Dark/Light, and Settings all still work from their new positions.

---

## Self-Review notes

- **Spec coverage:** ViewMode type + helper → Task 1; Model/Msg/init/update swap, body branch + editor-only view, View dropdown, two-row toolbar with the specified ordering and relabeled Terminal button → Task 2. All spec sections mapped.
- **Type consistency:** `ViewMode(..)` (`ViewReader`/`ViewEditor`/`ViewBoth`), `viewModeFromString`, `SetViewMode String`, `viewMode : ViewMode`, helpers `editorOnlyView`/`viewModeDropdown`/`toolbarRow`/`groupSep` are used identically across both tasks.
- **Each task compiles:** Task 1 only adds an unused type/function (repo still builds); Task 2 swaps `readerMode`→`viewMode` and updates every reference (body + toolbar) in one commit.
- **Vestigial:** `flags.readerMode` and `FileOps.saveReaderMode` are left in place but unused (per the spec's session-only decision); no error since Elm permits unused exposed ports/fields.
