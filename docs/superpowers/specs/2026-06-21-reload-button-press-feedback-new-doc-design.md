# Reload Button, Button Styling, New-Doc-Becomes-Current — Design

**Date:** 2026-06-21
**Status:** Approved — ready for implementation plan.

Four small, independent UI changes to the vault viewer.

## 1. Reload button

The inbox is processed by `claude` in the in-app terminal, so the app never loses
focus and can't auto-detect when the agent finishes. Provide an explicit reload.

- **`Types.elm`** — new `Msg` variant `ClickedReload`.
- **`Main.elm` update** — `ClickedReload -> relist model` (re-lists the workspace at the
  current `vaultRoot`; with no vault it is a no-op, which `relist` already handles by
  returning `( model, Cmd.none )`). `relist` only refreshes the tree — it does not touch
  `selectedPath`, the open document, or `openFolders`.
- **`View.elm` `treeColumn`** — add a **`Reload`** button next to the existing
  `Open Vault` button, wired to `onClick ClickedReload`, disabled when
  `model.vaultRoot == Nothing` (`Html.Attributes.disabled (model.vaultRoot == Nothing)`).

## 2 + 4. Button background color + press feedback (CSS only, `index.html`)

- **Background → `#2b2c40`** for all buttons. Update every place that sets a button
  background: the base `button, .cm-button` rule (line ~121), its `:hover`, and the
  `.cm-button { … !important }` block + its `:hover` (lines ~154-160). Hover may be a
  slightly lighter shade of the same (e.g. `#3a3c55`).
- **Press feedback** — add an `:active` rule so a pressed button momentarily changes
  appearance:
  ```css
  button, .cm-button { transition: background 0.08s ease, transform 0.05s ease; }
  button:active, .cm-button:active { background: #1f2030; transform: translateY(1px); }
  ```
  The `.cm-button:active` may need `!important` on background to beat CodeMirror's
  injected baseTheme, matching the existing `.cm-button` override pattern.

## 3. New document becomes the current document

Today `ClickedNewFile` creates the file, then the `PCreateFile path` response handler
runs `relist model` and discards `path`, so the new file is not opened or selected.

- **`Main.elm`** — change the `PCreateFile path` response branch to, in order:
  1. Expand the new file's ancestor folders so it is visible:
     `openFolders = List.foldl Set.insert model.openFolders (PathUtil.ancestorDirs path)`.
  2. `openDoc path` on that model — sets `selectedPath = Just path` (highlights it in the
     sidebar), sets `language`, and issues the `PReadFile` request that loads its content
     (empty for a freshly created file → editor ready).
  3. `relist` that model — refreshes the tree to include the new file.
  4. Return `( finalModel, Cmd.batch [ openCmd, relistCmd, saveOpenFoldersCmd finalModel.vaultRoot finalModel.openFolders ] )`.

  Thread the model through `openDoc` then `relist` so `nextRequestId`/`pending` stay
  consistent (both use `request`).

- **`PathUtil.elm`** — new helper `ancestorDirs : String -> List String` returning every
  ancestor folder of a vault-relative path, e.g. `ancestorDirs "a/b/c.md" == ["a", "a/b"]`,
  `ancestorDirs "Inbox/foo.md" == ["Inbox"]`, `ancestorDirs "foo.md" == []`. Add it to the
  module's exposing list.

- **Edge case (documented, not handled):** if the opened vault is a *subfolder* of kbase
  (so `vaultRoot /= kbaseRoot`), new Inbox files are created under `kbaseRoot/Inbox/` —
  outside the visible tree — and `openDoc` (which reads relative to `vaultRoot`) will not
  find them. This is a pre-existing quirk of the kbase new-file path; in normal use the
  vault opened *is* the kbase root, so `Inbox/<name>` is reachable and auto-open works.

## Testing

- **`PathUtil.ancestorDirs`** — unit tests for nested, single-level, and root-level paths
  (in `tests/PathUtilTest.elm`).
- **`ClickedReload`** — unit test: with `vaultRoot = Nothing`, `update ClickedReload model`
  returns the model unchanged with `Cmd.none` (no-op). (The with-vault path issues a
  `Cmd` that Elm can't easily introspect — covered by manual verification.)
- **CSS (#2/#4) and the create→open wiring (#3 with-vault)** — verified manually after
  `make build`: buttons are `#2b2c40` and depress on click; creating a file opens it in
  the editor, highlights it in the sidebar, and reveals its folder.
- Full `elm-test` suite stays green.
