# UI polish batch — Design

Date: 2026-06-22

Five independent UI changes in the Elm + Tauri app (`frontend/`):

1. Light-gray background on the user's prompt bubbles in the AI chat transcript.
2. Show a folder's `_index.md` as an inline clickable link on the folder row
   (hidden from the folder's child list).
3. Make the divider between the source editor and the rendered preview draggable.
4. Replace the three sidebar Export buttons with a native "Export" dropdown in
   the toolbar, placed after New/Rename/Delete.
5. Move the "Saved" indicator to immediately after the new-file-name input.

All five are presentational and independent; they share no state.

---

## Feature 1 — Light-gray prompt bubbles

### Current
`chatMessageView` (`frontend/src/View.elm`, the `isUser` background ~`:751-755`)
sets the "You" bubble background to `var(--tree-selected-bg)` and the assistant
bubble to `var(--panel-bg)`.

### Design
- Add a theme-aware CSS variable `--chat-prompt-bg` in `frontend/index.html`:
  - `:root` (light): `#eeeeee`
  - `[data-theme="dark"]`: `#2e2e2e`
- In `chatMessageView`, change the user-bubble background from
  `var(--tree-selected-bg)` to `var(--chat-prompt-bg)`. Assistant bubble
  unchanged (`var(--panel-bg)`).

---

## Feature 2 — `_index.md` inline on the folder row

### Current
`nodeView` `FolderNode` branch (`frontend/src/View.elm` ~`:439-452`) renders the
folder row (`folderIcon` + name) and, when open, a nested
`treeView … r.children`. `Workspace.Node` is
`FileNode { path, name, mtime } | FolderNode { path, name, children }`.

### Design
- Add a pure helper that splits a child list into the `_index.md` file node (if
  any) and the remaining children. Put it in `Workspace.elm` (exported) so it is
  unit-testable:

  ```elm
  splitIndexFile : List Node -> ( Maybe Node, List Node )
  ```

  It returns `( Just node, rest )` where `node` is the first child that is a
  `FileNode` whose `name == "_index.md"`, and `rest` is the child list with that
  node removed; `( Nothing, children )` when there is no such file. Only the
  immediate children are considered (not recursive). Folders named `_index.md`
  are ignored (must be a `FileNode`).

- In `FolderNode`, compute `( maybeIndex, restChildren ) = Workspace.splitIndexFile r.children`.
  - After the folder-name `span`, when `maybeIndex` is `Just (FileNode ir)`,
    render an inline clickable link `span` showing `_index.md`. It must open the
    file without also toggling the folder, so it uses
    `Html.Events.stopPropagationOn "click" (D.succeed ( ClickedTreeNode ir.path, True ))`
    instead of plain `onClick` (the folder row's `div` has `onClick (ToggledFolder r.path)`).
    Style it muted/clickable (e.g. `color var(--muted)`, `margin-left 6px`,
    `cursor pointer`, smaller font); a highlight when it is the selected doc is
    optional and out of scope.
  - Pass `restChildren` (not `r.children`) to the nested `treeView`, so
    `_index.md` is not also listed below.

- The inline link shows regardless of whether the folder is open or closed.

### Testing
- Unit tests for `Workspace.splitIndexFile` (`frontend/tests/`): a child list with
  an `_index.md` FileNode → `( Just thatNode, others )`; without one →
  `( Nothing, sameList )`; a *folder* named `_index.md` is not matched; order of
  the remaining children is preserved.

---

## Feature 3 — Movable source/render divider

### Current
`threePaneRow` (`frontend/src/View.elm` ~`:62-80`) is a flex row:
`treeColumn` | `codemirror-editor` (`flex 1`, `border-right`) | preview `div`
(`flex 1`). `index.html` already implements an analogous draggable split for the
terminal's left/right panes via a `#terminal-split-handle` element, a
`--terminal-split` CSS var, pointer-event handlers, and `localStorage`
persistence (`index.html` ~`:331-360`). This feature mirrors that pattern.

### Design
- **CSS var:** add `--editor-split: 50%` to the existing `:root { --terminal-height …; --terminal-split … }`
  rule in `index.html`.
- **`threePaneRow` layout** (`View.elm`):
  - Editor element: replace `style "flex" "1"` with
    `style "flex" "0 0 auto"` and `style "width" "var(--editor-split, 50%)"`.
    Keep the `border-right`.
  - Insert a handle `div` between the editor and the preview:
    `Html.div [ Html.Attributes.id "editor-split-handle" ] []` styled
    `flex 0 0 auto; width 6px; cursor col-resize; background var(--border)`.
  - Preview `div`: keep `flex 1`.
- **Drag logic** (`index.html`, a new IIFE mirroring the terminal-split one):
  - Maintain a `dragging` flag and the editor's left edge.
  - On `pointerdown` where `e.target.id === 'editor-split-handle'`: set
    `dragging = true`, record `editorLeft = document.querySelector('codemirror-editor').getBoundingClientRect().left`,
    `e.preventDefault()`.
  - On `pointermove` while dragging: `applyEditorSplit(e.clientX - editorLeft, false)`.
  - On `pointerup` while dragging: `dragging = false; applyEditorSplit(e.clientX - editorLeft, true)`.
  - `applyEditorSplit(px, persist)`: clamp to
    `Math.max(200, Math.min(window.innerWidth - 200, px))`, set
    `--editor-split` to `<clamped>px`, and when `persist` write
    `localStorage.editorSplit`.
  - On load: read `localStorage.editorSplit`; if a valid number, apply it
    (persist). Re-clamp on `window.resize` like the terminal split does.
- Only `threePaneRow` (the source|render view) is affected; `readerView` and the
  image view are unchanged.

### Testing
- Manual: drag the divider; the editor/preview resize, the position survives a
  relaunch, and it can't be dragged within 200px of either side.

---

## Feature 4 — Export dropdown in the toolbar

### Current
Three buttons — `Export HTML` / `Export LaTeX` / `Export PDF` — live in
`treeColumn` (the sidebar, `frontend/src/View.elm` ~`:39-41`) wired to
`ClickedExportHtml` / `ClickedExportLatex` / `ClickedExportPdf`.

### Design
- **Remove** the sidebar export `div` (the three buttons) from `treeColumn`.
- **Add** a native dropdown in the toolbar, placed after the Delete button
  (see Feature 5 for the final order). It is built by a helper:

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

  Pinning `value` to `""` keeps the control showing "Export"; after a selection
  it reverts to the placeholder rather than sticking on the chosen item.
- **New Msg** `ExportSelected String` (`Types.elm`). **Update branch** (`Main.elm`)
  reuses the existing export handlers (no duplicated export logic):

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

### Testing
- Compile + manual: the dropdown shows "Export", each option triggers the
  corresponding export, and the control returns to "Export" afterward.

---

## Feature 5 — Move the "Saved" indicator

### Current
The save-status `div` (`div [ … ] [ text (saveLabel model.saveState.saveStatus) ]`)
is the **last** item in the toolbar, after the Delete button
(`frontend/src/View.elm` ~`:143-144`).

### Design
- Move that `div` to immediately **after** the new-file-name `Html.input` and
  **before** the New button.
- Final toolbar item order:
  `… ⌘ Terminal`, `new-file-name input`, `Saved div`, `New`, `Rename`,
  `Delete`, `exportDropdown`.

### Testing
- Compile + manual: "Saved/Unsaved…/Saving…" appears right after the input field;
  Export dropdown appears at the far end.

---

## Out of scope
- Restyling the chat input box (Feature 1 targets the prompt bubbles only).
- Recursive `_index.md` handling or selected-doc highlight on the inline link.
- A custom (non-native) Export menu panel.
- Any change to `readerView` / image view for the divider.

## Global notes
- Grays for `--chat-prompt-bg`: `#eeeeee` (light) / `#2e2e2e` (dark) — adjustable.
- The divider persists its position in `localStorage` (`editorSplit`), mirroring
  the terminal split.
