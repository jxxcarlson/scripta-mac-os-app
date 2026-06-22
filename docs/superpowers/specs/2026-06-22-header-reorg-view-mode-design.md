# Header reorg + View-mode dropdown — Design (iteration 1)

Date: 2026-06-22

Reorganize the header toolbar into two rows and replace the "Reader" toggle with
a View dropdown that cycles Reader / Editor / Both. The user expects to iterate
on exact positions, so this is a deliberately light first pass.

## Target layout

```
Row 1:  [← Prev] [Next →]   ‖   [Hide Tree]  [View: Both ▾]  [Hide TOC]  [Hide Terminal]
Row 2:  [ new-filename ] [Saved] [New] [Rename] [Delete] [Export ▾]   [Parse: Incremental] [Dark] [⚙ Settings]
```

- Row 1 = navigation + view/visibility controls.
- Row 2 = the file-name input, save indicator, file ops, export, then the
  remaining utilities (Parse, Dark/Light, Settings) appended after Export.
- The file-tree column is unchanged (search field, then the tree).

## View mode (replaces Reader button + readerMode)

A new `ViewMode` with three states, chosen via a native `<select>` (same control
style as the Export dropdown) whose value reflects the current mode:

- **Both** — tree (if shown) + editor + rendered text (today's 3-pane default).
- **Editor** — tree (if shown) + editor only, full width (no rendered pane).
- **Reader** — tree (if shown) + rendered text only (today's reader view).

The image view still takes precedence when the open file is an image. The Tree
and TOC show/hide toggles continue to apply within whichever mode shows the tree
/ rendered text.

### State / messages
- `Types.elm`: add `type ViewMode = ViewReader | ViewEditor | ViewBoth` (exported);
  add a pure `viewModeFromString : String -> ViewMode` (`"reader"`→`ViewReader`,
  `"editor"`→`ViewEditor`, anything else→`ViewBoth`) for the dropdown decoder and
  unit testing.
- `Types.elm` Model: replace `readerMode : Bool` with `viewMode : ViewMode`.
- `Types.elm` Msg: remove `ToggledReaderMode`; add `SetViewMode String`.
- `Main.elm` init: `viewMode = ViewBoth` (session-only; the old persisted
  `flags.readerMode` is no longer read).
- `Main.elm` update: remove the `ToggledReaderMode` branch; add
  `SetViewMode v -> ( { model | viewMode = viewModeFromString v }, Cmd.none )`.
- The `flags.readerMode` field and the `FileOps.saveReaderMode` port become
  vestigial (left defined but unused); cleaning them up is out of scope for this
  iteration.

### View
- `View.elm` `body`: replace `if model.readerMode then readerView else threePaneRow`
  with, after the image check:
  ```elm
  case model.viewMode of
      ViewBoth -> threePaneRow
      ViewReader -> readerView
      ViewEditor -> editorOnlyView model
  ```
- Add `editorOnlyView : Model -> Html Msg`: `treeCols model ++ [ <editor node, flex 1> ]`
  — the codemirror editor at `flex 1` with no editor-split handle and no border
  (nothing to its right). `threePaneRow` and `readerView` are unchanged from the
  previous batch.
- Add `viewModeDropdown : Model -> Html Msg`: a `Html.select` with
  `Html.Events.on "change" (D.map SetViewMode Html.Events.targetValue)` and three
  options (`both`→"Both", `editor`→"Editor", `reader`→"Reader"), each marked
  `selected` when it matches `model.viewMode`.

## Toolbar restructure (two rows)

`View.elm` `toolbar` becomes a container holding two flex rows:

- `toolbarRow : List (Html Msg) -> Html Msg` — `div` with
  `display:flex; align-items:center; gap:8px; padding:6px 8px; flex-wrap:wrap`.
- A light group separator `groupSep : Html msg` — a thin vertical rule
  (`div` `width:1px; align-self:stretch; background:var(--border); margin:0 4px`)
  used between the parenthesized groups.
- `toolbar = div [ style "border-bottom" "1px solid var(--border)" ] [ row1, row2 ]`
  (the border-bottom moves from the old single row to the container).

**Row 1 children (in order):** Prev button, Next button, `groupSep`, Hide/Show
Tree button, `viewModeDropdown model`, Hide/Show TOC button, Hide/Show Terminal
button.

**Row 2 children (in order):** the new-file-name input, the Saved `div`, New,
Rename, Delete, `exportDropdown`, `groupSep`, Parse button, Dark/Light button,
⚙ Settings button.

**Button relabels:** the Terminal toggle (currently `⌘ Terminal`,
`onClick ToggledTerminal`) becomes Hide/Show form:
`text (if model.terminalVisible then "Hide Terminal" else "Show Terminal")`.
The existing Hide/Show Tree, Hide/Show TOC, Parse (`Parse: Full`/`Parse: Incremental`),
and Dark/Light (`Dark`/`Light`) buttons keep their current dynamic labels. The
`⚙ Settings` button is unchanged. The old "Reader"/"Exit Reader" button is removed.

## Testing
- Unit test `Types.viewModeFromString` (`"reader"`/`"editor"`/`"both"`/unknown).
- The toolbar/layout and dropdown wiring are view-typed → verified by compile +
  the manual checklist.

## Manual checklist
- Two header rows with the specified order.
- View dropdown switches Both / Editor / Reader; "Editor" shows the editor full
  width with no rendered pane; "Reader" shows rendered text only; "Both" is the
  3-pane view. Image files still show the image view.
- Tree / TOC / Terminal toggles work; Parse, Dark/Light, Settings function from
  Row 2.

## Out of scope (this iteration)
- Persisting `viewMode` across launches (session-only for now).
- Removing the vestigial `readerMode` flag / `saveReaderMode` port.
- Final visual polish of the two rows (we will iterate on spacing/grouping).
