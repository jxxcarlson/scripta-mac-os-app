# Move File Controls into the Header — Design Spec

**Date:** 2026-06-20
**Status:** Approved (pending spec review)

## Goal

Move the file-management controls out of the sidebar and into the top toolbar (header), after the
Dark/Light button. The Export buttons and the file tree stay in the sidebar. This is a pure
layout rearrangement — no behavior, message, or model changes.

## Context

In `frontend/src/View.elm`:
- **`toolbar`** (in `view`) is a single flex row (`display flex; align-items center; gap 8px;
  padding 6px 8px; border-bottom 1px solid var(--border)`) currently holding four buttons:
  **← Back**, **Reader**, **Parse: Full/Incremental**, **Dark/Light**.
- **`treeColumn`** holds, top to bottom: the **Open Vault** button, `searchBox`, `fileTree`, the
  **Saved** status label (`div [...] [ text (saveLabel model.saveState.saveStatus) ]`), a row with
  the **new-file-name** `Html.input` + **New** + **Rename**, a row with **Delete** + **Change
  Vault**, and a row with **Export HTML** / **Export LaTeX** / **Export PDF**.
- All the relevant messages already exist: `SetNewName`, `ClickedNewFile`, `ClickedRename`,
  `ClickedDeleteSelected`, `ClickedChangeVault`; the new-file input already carries the
  `autocapitalize`/`autocorrect`/`spellcheck` attributes; `saveLabel`/`model.saveState` provide
  the status text.

## Design

### Toolbar (header) — append after the Dark/Light button, in this order
1. the **new-file-name** `Html.input` (verbatim, keeping its `placeholder`, `value`,
   `onInput SetNewName`, `width 150px`, and the autocapitalize/autocorrect/spellcheck attributes)
2. **New** button (`onClick ClickedNewFile`)
3. **Rename** button (`onClick ClickedRename`)
4. **Delete** button (`onClick ClickedDeleteSelected`)
5. **Change Vault** button (`onClick ClickedChangeVault`)
6. the **Saved** status label (`div [ style "font-size" "12px", style "color" "var(--muted)" ]
   [ text (saveLabel model.saveState.saveStatus) ]`)

Resulting header order: `← Back · Reader · Parse · Dark · [new-file-name] · New · Rename · Delete ·
Change Vault · Saved`.

Add **`style "flex-wrap" "wrap"`** to the `toolbar` div so the row wraps to a second line on a
narrow window rather than clipping. (Keep the existing flex/gap/padding/border styles.)

### Sidebar (`treeColumn`) — what remains
- **Open Vault** button, `searchBox`, `fileTree`, and the **Export HTML / Export LaTeX / Export
  PDF** row.
- **Removed** (moved to the header): the Saved label div, the new-file input + New + Rename row,
  and the Delete + Change Vault row.

The previously inter-row `margin-top`/`display flex` wrapper `div`s that only existed to lay out
the moved controls in the sidebar are removed along with them; the moved controls sit directly in
the toolbar's flex row (each as a sibling, relying on the toolbar's `gap`). The input keeps its
explicit `width 150px`.

## Data Flow / Behavior

Unchanged. The controls dispatch the same messages from their new location; `update`,
`PendingOp`, the FS bridge, and the model are untouched.

## Error Handling

Unchanged (no new failure modes; this is markup relocation).

## Testing

- `cd frontend && elm make src/Main.elm --output=/dev/null` → `Success!` (purely structural; no
  logic changes).
- `elm-test` → existing suites still pass (no test depends on control placement).
- **Manual (GUI):** the header shows the moved controls after Dark/Light and they work (create a
  file, rename, delete, change vault, and the Saved indicator updates); the sidebar now shows only
  Open Vault, search, the tree, and the three Export buttons; on a narrow window the header wraps
  instead of clipping.

## Out of Scope (YAGNI)

- Restyling the buttons, icons, grouping/separators, or responsive breakpoints beyond
  `flex-wrap`.
- Moving the Export buttons or the search box.
- Any change to what the controls do.
