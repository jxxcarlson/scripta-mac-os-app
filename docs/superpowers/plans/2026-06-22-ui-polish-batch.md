# UI polish batch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five small, independent UI improvements: light-gray prompt bubbles, inline `_index.md` on folder rows, a draggable source/preview divider, an Export dropdown in the toolbar, and a relocated "Saved" indicator.

**Architecture:** Each feature is a self-contained Elm `View` change (plus, for two of them, a CSS var / JS drag-handler in `index.html`, and one new `Workspace` helper + `Types`/`Main` wiring). They share no state and can land in any order; each task leaves the repo compiling.

**Tech Stack:** Elm 0.19 (`Browser.element`), elm-test, plain JS/CSS in `index.html`, xterm/CodeMirror custom elements.

## Global Constraints

- Run Elm tests from `frontend/`: `npx elm-test`. Type-check: `npx elm make src/Main.elm --output=/dev/null`.
- elm-format conventions apply; keep code clean.
- `--chat-prompt-bg`: `#eeeeee` (light `:root`) / `#2e2e2e` (`[data-theme="dark"]`).
- The source/preview divider clamps to ≥200px from each side and persists to `localStorage` key `editorSplit`, mirroring the existing `terminalSplit` handler.
- `_index.md` match is an immediate child that is a `FileNode` named exactly `_index.md` (a folder named `_index.md` does not match); it is shown inline after the folder name and removed from the folder's child list.
- The Export dropdown is a native `Html.select` whose `value` is pinned to `""` (always shows "Export"); selections reuse the existing `ClickedExportHtml/Latex/Pdf` handlers via a new `ExportSelected String` Msg — no duplicated export logic.
- Final toolbar order: `… ⌘ Terminal`, new-file-name input, Saved div, New, Rename, Delete, Export dropdown.
- `View.elm` already imports `Workspace exposing (Node(..))`, `Html.Events exposing (onClick, onInput)`, `Json.Decode as D`, `Html exposing (Html, button, div, li, span, text, ul)`. Use `Html.select`/`Html.option`/`Html.Events.on`/`Html.Events.targetValue`/`Html.Events.stopPropagationOn` qualified.

---

### Task 1: Light-gray prompt bubbles

**Files:**
- Modify: `frontend/index.html` (`:root` ~`:42`, `[data-theme="dark"]` ~`:89`)
- Modify: `frontend/src/View.elm` (`chatMessageView` background ~`:750-756`)

**Interfaces:** none shared.

- [ ] **Step 1: Add the CSS variable (light + dark)**

In `frontend/index.html`, in the `:root { … }` palette block, add a line after `--tree-folder-bg: #e8f2fc;`:

```css
        --chat-prompt-bg: #eeeeee;
```

In the `[data-theme="dark"] { … }` block, add a line after `--tree-folder-bg: #243c54;`:

```css
        --chat-prompt-bg: #2e2e2e;
```

- [ ] **Step 2: Use it for the user bubble**

In `frontend/src/View.elm` `chatMessageView`, change the user-bubble background. Replace:

```elm
        , style "background"
            (if isUser then
                "var(--tree-selected-bg)"

             else
                "var(--panel-bg)"
            )
```

with:

```elm
        , style "background"
            (if isUser then
                "var(--chat-prompt-bg)"

             else
                "var(--panel-bg)"
            )
```

- [ ] **Step 3: Verify it compiles + tests pass**

Run: `cd frontend && npx elm make src/Main.elm --output=/dev/null` → "Success!".
Run: `cd frontend && npx elm-test` → all existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add frontend/index.html frontend/src/View.elm
git commit -m "style: light-gray background on AI chat prompt bubbles"
```

Note: visual change; verified by compile + manual (You-bubbles read light gray in both themes).

---

### Task 2: Inline `_index.md` on folder rows

**Files:**
- Modify: `frontend/src/Workspace.elm` (exposing `:1-5`; new helper)
- Test: `frontend/tests/WorkspaceTest.elm`
- Modify: `frontend/src/View.elm` (`nodeView` `FolderNode` branch ~`:439-452`)

**Interfaces:**
- Produces: `Workspace.splitIndexFile : List Node -> ( Maybe Node, List Node )` (consumed by `View.nodeView`).

- [ ] **Step 1: Write the failing tests**

In `frontend/tests/WorkspaceTest.elm`, add these cases inside the top-level `describe` list (the file already imports `Workspace exposing (Entry, Node(..))`):

```elm
        , test "splitIndexFile extracts the _index.md file and removes it from the list" <|
            \_ ->
                let
                    idx =
                        FileNode { path = "Physics/_index.md", name = "_index.md", mtime = 1 }

                    a =
                        FileNode { path = "Physics/a.scripta", name = "a.scripta", mtime = 2 }

                    b =
                        FileNode { path = "Physics/b.scripta", name = "b.scripta", mtime = 3 }
                in
                Expect.equal ( Just idx, [ a, b ] ) (Workspace.splitIndexFile [ a, idx, b ])
        , test "splitIndexFile returns Nothing and the list unchanged when there is no _index.md" <|
            \_ ->
                let
                    a =
                        FileNode { path = "Physics/a.scripta", name = "a.scripta", mtime = 2 }

                    b =
                        FileNode { path = "Physics/b.scripta", name = "b.scripta", mtime = 3 }
                in
                Expect.equal ( Nothing, [ a, b ] ) (Workspace.splitIndexFile [ a, b ])
        , test "splitIndexFile ignores a folder named _index.md (must be a file)" <|
            \_ ->
                let
                    folder =
                        FolderNode { path = "Physics/_index.md", name = "_index.md", children = [] }

                    a =
                        FileNode { path = "Physics/a.scripta", name = "a.scripta", mtime = 2 }
                in
                Expect.equal ( Nothing, [ folder, a ] ) (Workspace.splitIndexFile [ folder, a ])
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd frontend && npx elm-test`
Expected: FAIL — `Workspace.splitIndexFile` does not exist.

- [ ] **Step 3: Implement `splitIndexFile`**

In `frontend/src/Workspace.elm`, add `splitIndexFile` to the exposing list. Change:

```elm
module Workspace exposing
    ( Entry, Node(..)
    , entryDecoder, toTree, filter
    , nodeName, nodePath, folderChildren
    )
```

to:

```elm
module Workspace exposing
    ( Entry, Node(..)
    , entryDecoder, toTree, filter
    , nodeName, nodePath, folderChildren, splitIndexFile
    )
```

Add this function at the end of `frontend/src/Workspace.elm`:

```elm


{-| Split a folder's immediate children into its `_index.md` file (if any) and
the remaining children. Only a `FileNode` named exactly `_index.md` matches; a
folder of that name does not. The remaining children keep their order.
-}
splitIndexFile : List Node -> ( Maybe Node, List Node )
splitIndexFile children =
    let
        isIndex n =
            case n of
                FileNode r ->
                    r.name == "_index.md"

                FolderNode _ ->
                    False
    in
    case List.filter isIndex children of
        idx :: _ ->
            ( Just idx, List.filter (\n -> not (isIndex n)) children )

        [] ->
            ( Nothing, children )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd frontend && npx elm-test`
Expected: PASS (the three new cases + existing).

- [ ] **Step 5: Render the inline link in `FolderNode`**

In `frontend/src/View.elm`, the `FolderNode r ->` branch currently is:

```elm
        FolderNode r ->
            let
                isOpen =
                    forceOpen || Set.member r.path openFolders
            in
            li []
                (div
                    ([ onClick (ToggledFolder r.path)
                     , style "cursor" "pointer"
                     , style "margin-bottom" "4px"
                     , style "display" "flex"
                     , style "align-items" "flex-start"
                     ]
                        ++ (if r.path == highlights.currentFolder then
                                [ style "background-color" "var(--tree-folder-bg)"
                                , style "border-radius" "3px"
                                , style "padding" "0 4px"
                                ]

                            else
                                []
                           )
                    )
                    [ span [ style "flex" "0 0 auto", style "margin-right" "5px" ] [ folderIcon isOpen ]
                    , span [ style "flex" "1 1 auto" ] [ text r.name ]
                    ]
                    :: (if isOpen then
                            [ treeView forceOpen highlights openFolders r.children ]

                        else
                            []
                       )
                )
```

Replace it with (adds `( maybeIndex, restChildren )`, an `indexLink`, and uses `restChildren`):

```elm
        FolderNode r ->
            let
                isOpen =
                    forceOpen || Set.member r.path openFolders

                ( maybeIndex, restChildren ) =
                    Workspace.splitIndexFile r.children

                indexLink =
                    case maybeIndex of
                        Just (FileNode ir) ->
                            [ span
                                [ Html.Events.stopPropagationOn "click" (D.succeed ( ClickedTreeNode ir.path, True ))
                                , style "flex" "0 0 auto"
                                , style "margin-left" "6px"
                                , style "color" "var(--muted)"
                                , style "cursor" "pointer"
                                , style "font-size" "12px"
                                ]
                                [ text "_index.md" ]
                            ]

                        _ ->
                            []
            in
            li []
                (div
                    ([ onClick (ToggledFolder r.path)
                     , style "cursor" "pointer"
                     , style "margin-bottom" "4px"
                     , style "display" "flex"
                     , style "align-items" "flex-start"
                     ]
                        ++ (if r.path == highlights.currentFolder then
                                [ style "background-color" "var(--tree-folder-bg)"
                                , style "border-radius" "3px"
                                , style "padding" "0 4px"
                                ]

                            else
                                []
                           )
                    )
                    ([ span [ style "flex" "0 0 auto", style "margin-right" "5px" ] [ folderIcon isOpen ]
                     , span [ style "flex" "1 1 auto" ] [ text r.name ]
                     ]
                        ++ indexLink
                    )
                    :: (if isOpen then
                            [ treeView forceOpen highlights openFolders restChildren ]

                        else
                            []
                       )
                )
```

- [ ] **Step 6: Verify it compiles + full suite**

Run: `cd frontend && npx elm make src/Main.elm --output=/dev/null` → "Success!".
Run: `cd frontend && npx elm-test` → all pass.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/Workspace.elm frontend/tests/WorkspaceTest.elm frontend/src/View.elm
git commit -m "feat: show a folder's _index.md inline on the folder row"
```

---

### Task 3: Draggable source/preview divider

**Files:**
- Modify: `frontend/src/View.elm` (`threePaneRow` ~`:62-80`)
- Modify: `frontend/index.html` (`:root` ~`:74`; new IIFE after the terminal-split IIFE ~`:362`)

**Interfaces:** the handle element id `editor-split-handle` and CSS var `--editor-split` connect the Elm view and the JS handler.

- [ ] **Step 1: Update `threePaneRow` layout**

In `frontend/src/View.elm`, replace the `threePaneRow` definition:

```elm
        threePaneRow =
            div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
                [ treeColumn model
                , Html.node "codemirror-editor"
                    [ Html.Attributes.attribute "text" model.loadedContent
                    , Html.Attributes.attribute "fill-parent" ""
                    , Html.Events.on "text-change" (D.map EditorChanged Editor.textChangeDecoder)
                    , style "flex" "1"
                    , style "border-right" "1px solid var(--border)"
                    ]
                    []
                , div
                    [ Html.Attributes.id Editor.renderedTextId
                    , style "flex" "1"
                    , style "padding" "16px"
                    , style "overflow" "auto"
                    ]
                    (previewBody model)
                ]
```

with:

```elm
        threePaneRow =
            div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
                [ treeColumn model
                , Html.node "codemirror-editor"
                    [ Html.Attributes.attribute "text" model.loadedContent
                    , Html.Attributes.attribute "fill-parent" ""
                    , Html.Events.on "text-change" (D.map EditorChanged Editor.textChangeDecoder)
                    , style "flex" "0 0 auto"
                    , style "width" "var(--editor-split, 50%)"
                    , style "border-right" "1px solid var(--border)"
                    ]
                    []
                , div
                    [ Html.Attributes.id "editor-split-handle"
                    , style "flex" "0 0 auto"
                    , style "width" "6px"
                    , style "cursor" "col-resize"
                    , style "background" "var(--border)"
                    ]
                    []
                , div
                    [ Html.Attributes.id Editor.renderedTextId
                    , style "flex" "1"
                    , style "padding" "16px"
                    , style "overflow" "auto"
                    ]
                    (previewBody model)
                ]
```

- [ ] **Step 2: Add the CSS var**

In `frontend/index.html`, change:

```css
      :root { --terminal-height: 280px; --terminal-split: 50%; }
```

to:

```css
      :root { --terminal-height: 280px; --terminal-split: 50%; --editor-split: 50%; }
```

- [ ] **Step 3: Add the drag handler**

In `frontend/index.html`, immediately after the terminal-split IIFE (the `})();` that closes the "Vertical separator between the AI pane … and shells/scratch" block), insert:

```javascript

      // --- Vertical divider between the source editor (left) and rendered preview (right). ---
      (function () {
        var editorLeft = 0;
        function applyEditorSplit(px, persist) {
          var w = Math.max(200, Math.min(window.innerWidth - 200, px));
          document.documentElement.style.setProperty('--editor-split', w + 'px');
          if (persist) { try { localStorage.setItem('editorSplit', w); } catch (e) {} }
          return w;
        }
        var saved = parseInt(lsGet('editorSplit'), 10);
        if (!isNaN(saved)) applyEditorSplit(saved, true);
        var dragging = false;
        document.addEventListener('pointerdown', function (e) {
          if (e.target && e.target.id === 'editor-split-handle') {
            var ed = document.querySelector('codemirror-editor');
            editorLeft = ed ? ed.getBoundingClientRect().left : 0;
            dragging = true;
            e.preventDefault();
          }
        });
        document.addEventListener('pointermove', function (e) {
          if (!dragging) return;
          applyEditorSplit(e.clientX - editorLeft, false);
        });
        document.addEventListener('pointerup', function (e) {
          if (!dragging) return;
          dragging = false;
          applyEditorSplit(e.clientX - editorLeft, true);
        });
        window.addEventListener('resize', function () {
          var s = parseInt(lsGet('editorSplit'), 10);
          if (!isNaN(s)) applyEditorSplit(s, true);
        });
      })();
```

(`lsGet` is the existing localStorage helper defined earlier in `index.html`.)

- [ ] **Step 4: Verify it compiles + tests**

Run: `cd frontend && npx elm make src/Main.elm --output=/dev/null` → "Success!".
Run: `cd frontend && npx elm-test` → all pass.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/View.elm frontend/index.html
git commit -m "feat: draggable divider between source and rendered panes"
```

Note: verified by compile + manual (drag resizes the two panes, clamps at 200px each side, position persists across relaunch).

---

### Task 4: Export dropdown + relocate "Saved" indicator

**Files:**
- Modify: `frontend/src/Types.elm` (Msg list, after `ClickedExportPdf` `:103`)
- Modify: `frontend/src/Main.elm` (`update`, after the `ClickedExportPdf` branch `:449+`)
- Modify: `frontend/src/View.elm` (`treeColumn` export div `:38-43`; toolbar tail `:130-145`; new `exportDropdown` helper)

**Interfaces:**
- Consumes: existing `ClickedExportHtml` / `ClickedExportLatex` / `ClickedExportPdf` handlers.
- Produces: `Msg` variant `ExportSelected String`; `View.exportDropdown : Html Msg` (module-internal).

- [ ] **Step 1: Add the `ExportSelected` Msg**

In `frontend/src/Types.elm`, add the variant after `ClickedExportPdf` (`:103`):

```elm
    | ClickedExportPdf
    | ExportSelected String
```

- [ ] **Step 2: Handle it in `update`**

In `frontend/src/Main.elm`, add a branch immediately after the `ClickedExportPdf ->` branch (which ends around `:449+`). It reuses the existing handlers via recursive `update`:

```elm
        ExportSelected v ->
            case v of
                "html" ->
                    update ClickedExportHtml model

                "latex" ->
                    update ClickedExportLatex model

                "pdf" ->
                    update ClickedExportPdf model

                _ ->
                    ( model, Cmd.none )
```

- [ ] **Step 3: Remove the sidebar export buttons**

In `frontend/src/View.elm` `treeColumn`, replace:

```elm
            :: [ searchBox model
               , fileTree model
               , div [ style "margin-top" "4px", style "display" "flex", style "gap" "2mm" ]
                    [ button [ onClick ClickedExportHtml ] [ text "Export HTML" ]
                    , button [ onClick ClickedExportLatex ] [ text "Export LaTeX" ]
                    , button [ onClick ClickedExportPdf ] [ text "Export PDF" ]
                    ]
               ]
        )
```

with:

```elm
            :: [ searchBox model
               , fileTree model
               ]
        )
```

- [ ] **Step 4: Add the `exportDropdown` helper**

In `frontend/src/View.elm`, add this helper (e.g. just above or below `searchBox`):

```elm
exportDropdown : Html Msg
exportDropdown =
    Html.select
        [ Html.Attributes.value ""
        , Html.Events.on "change" (D.map ExportSelected Html.Events.targetValue)
        ]
        [ Html.option [ Html.Attributes.value "" ] [ text "Export" ]
        , Html.option [ Html.Attributes.value "html" ] [ text "Export HTML" ]
        , Html.option [ Html.Attributes.value "latex" ] [ text "Export LaTeX" ]
        , Html.option [ Html.Attributes.value "pdf" ] [ text "Export PDF" ]
        ]
```

- [ ] **Step 5: Reorder the toolbar tail (move Saved, add Export)**

In `frontend/src/View.elm`, the toolbar currently ends with the input, New/Rename/Delete, then the Saved div. Replace:

```elm
                , Html.input
                    [ Html.Attributes.placeholder "new-file-name"
                    , Html.Attributes.value model.newName
                    , onInput SetNewName
                    , style "width" "150px"
                    , Html.Attributes.attribute "autocapitalize" "off"
                    , Html.Attributes.attribute "autocorrect" "off"
                    , Html.Attributes.spellcheck False
                    ]
                    []
                , button [ onClick ClickedNewFile ] [ text "New" ]
                , button [ onClick ClickedRename ] [ text "Rename" ]
                , button [ onClick ClickedDeleteSelected ] [ text "Delete" ]
                , div [ style "font-size" "12px", style "color" "var(--muted)" ]
                    [ text (saveLabel model.saveState.saveStatus) ]
                ]
```

with (Saved moves up right after the input; Export added at the end):

```elm
                , Html.input
                    [ Html.Attributes.placeholder "new-file-name"
                    , Html.Attributes.value model.newName
                    , onInput SetNewName
                    , style "width" "150px"
                    , Html.Attributes.attribute "autocapitalize" "off"
                    , Html.Attributes.attribute "autocorrect" "off"
                    , Html.Attributes.spellcheck False
                    ]
                    []
                , div [ style "font-size" "12px", style "color" "var(--muted)" ]
                    [ text (saveLabel model.saveState.saveStatus) ]
                , button [ onClick ClickedNewFile ] [ text "New" ]
                , button [ onClick ClickedRename ] [ text "Rename" ]
                , button [ onClick ClickedDeleteSelected ] [ text "Delete" ]
                , exportDropdown
                ]
```

- [ ] **Step 6: Verify it compiles + full suite**

Run: `cd frontend && npx elm make src/Main.elm --output=/dev/null` → "Success!".
Run: `cd frontend && npx elm-test` → all pass.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm
git commit -m "feat: Export dropdown in toolbar; move Saved indicator after the name input"
```

---

## Manual verification (after all tasks — `make install`)

With a vault open:
1. AI chat: your "You" bubbles have a light-gray background (both light and dark themes).
2. A folder containing `_index.md` shows a muted, clickable `_index.md` to the right of the folder name; clicking it opens the file (without toggling the folder); it is not duplicated in the folder's expanded list.
3. The vertical bar between the source editor and the preview drags to resize both; it stops 200px from each edge and the position survives a relaunch.
4. The toolbar shows, in order: … ⌘ Terminal, new-file-name field, Saved indicator, New, Rename, Delete, and an "Export" dropdown whose HTML/LaTeX/PDF options each run the export and reset to "Export". The old sidebar export buttons are gone.

---

## Self-Review notes

- **Spec coverage:** Feature 1 → Task 1; Feature 2 → Task 2; Feature 3 → Task 3; Feature 4 + Feature 5 (same toolbar region) → Task 4. All spec sections mapped.
- **Type consistency:** `Workspace.splitIndexFile : List Node -> ( Maybe Node, List Node )`, `ExportSelected String`, `exportDropdown : Html Msg`, ids `editor-split-handle` / var `--editor-split` / key `editorSplit`, and `--chat-prompt-bg` are used identically across the defining and consuming steps.
- **Every task leaves the repo compiling:** the features are independent; Task 4 changes `Types`/`Main`/`View` together so the new Msg is always handled.
- **Tests where logic is pure:** Task 2 is TDD (`splitIndexFile`). Tasks 1, 3, 4 are CSS/JS/view-wiring verified by compilation + the manual checklist (the touched view helpers aren't exported and the dropdown/divider behavior is runtime DOM).
