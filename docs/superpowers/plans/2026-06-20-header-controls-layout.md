# Move File Controls into the Header — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Relocate the file-management controls from the sidebar into the top toolbar (after Dark/Light); keep Export buttons + tree + search + Open Vault in the sidebar. Pure layout — no logic/message/model changes.

**Architecture:** A single `frontend/src/View.elm` edit: move the new-file input, New, Rename, Delete, Change Vault, and the Saved label into the `toolbar` flex row (add `flex-wrap: wrap`), and delete them from `treeColumn`.

**Tech Stack:** Elm 0.19.1 (`elm-test`).

Spec: `docs/superpowers/specs/2026-06-20-header-controls-layout-design.md`

---

## Task 1: Relocate the controls (View.elm)

**Files:** Modify `frontend/src/View.elm`

- [ ] **Step 1: Add the controls to the toolbar**

In `view`'s `toolbar` definition, (a) add `, style "flex-wrap" "wrap"` to the wrapping `div`'s
attribute list (keep the existing `display`/`align-items`/`gap`/`padding`/`border-bottom`
styles), and (b) append these elements to the toolbar's child list, immediately AFTER the
existing Dark/Light button (`button [ onClick ToggledTheme ] [ text (…) ]`):

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
                , button [ onClick ClickedChangeVault ] [ text "Change Vault" ]
                , div [ style "font-size" "12px", style "color" "var(--muted)" ]
                    [ text (saveLabel model.saveState.saveStatus) ]
```

- [ ] **Step 2: Remove the moved controls from `treeColumn`**

In `treeColumn`, delete three list items: the **Saved** label `div`
(`div [ style "font-size" "12px", style "color" "var(--muted)", style "margin-top" "6px" ] [ text (saveLabel …) ]`),
the **new-file row** `div` (the one containing `Html.input … new-file-name`, the **New** button,
and the **Rename** button), and the **Delete / Change Vault row** `div`. Leave the **Open Vault**
button, `searchBox model`, `fileTree model`, and the **Export** row untouched. The remaining
`treeColumn` child list should read:

```elm
        (button [ onClick ClickedOpenVault ] [ text "Open Vault" ]
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

- [ ] **Step 3: Build + tests**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test`
Expected: `Success!` and all suites pass (no test depends on control placement). Also confirm
there are no "unused" warnings — every moved `onClick`/`Msg` is still referenced (just from the
toolbar now), and `saveLabel`/`searchBox`/`fileTree` remain used.

- [ ] **Step 4: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/View.elm
git commit -m "feat: move file controls (new/rename/delete/change-vault/save) into the header"
```

---

## After All Tasks

- **Manual verification (GUI):** the header shows, after Dark/Light: `[new-file-name] New ·
  Rename · Delete · Change Vault · Saved`, and each works (create, rename, delete, change vault;
  Saved updates on edit/save). The sidebar now shows only Open Vault, search, the tree, and the
  three Export buttons. On a narrow window the header wraps to a second line instead of clipping.
- Then use superpowers:finishing-a-development-branch.

## Notes

- No new messages/model/ports — the controls already exist and keep their handlers; this only
  changes where they render.
- The inter-row wrapper `div`s in the sidebar are removed with their controls; the controls sit
  directly in the toolbar's flex row and rely on the toolbar's `gap`. The input keeps `width 150px`.
