# Reload Button + Button Styling + New-Doc-Becomes-Current Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sidebar Reload button, give all buttons a new background + press feedback, and make a newly-created document open as the current document (loaded for editing, highlighted, revealed).

**Architecture:** Three Elm changes (a `PathUtil.ancestorDirs` helper, a `ClickedReload` Msg wired to the existing `relist`, and a richer `PCreateFile` response that opens the new file) plus a pure-CSS change to `index.html`.

**Tech Stack:** Elm 0.19.1 (`elm-test`), static `index.html` CSS.

**Spec:** `docs/superpowers/specs/2026-06-21-reload-button-press-feedback-new-doc-design.md`

---

## File Structure

- `frontend/src/PathUtil.elm` — new `ancestorDirs` helper (+ exposing) [Task 1].
- `frontend/tests/PathUtilTest.elm` — tests for `ancestorDirs` [Task 1].
- `frontend/src/Types.elm` — new `Msg` variant `ClickedReload` [Task 2].
- `frontend/src/Main.elm` — `ClickedReload` handler [Task 2]; richer `PCreateFile` handler [Task 3].
- `frontend/src/View.elm` — `Reload` button in `treeColumn` [Task 2].
- `frontend/index.html` — button background + `:active`/hover CSS [Task 4].

Note on testing scope: `update`/`relist` and the `PCreateFile` Cmd path can't be unit-tested without constructing the ~40-field `Model` (no builder exists, and `Main` isn't import-exposed for tests). So Tasks 2–4 are verified by `make elm` + manual check; Task 1's pure helper carries the automated tests.

---

### Task 1: `PathUtil.ancestorDirs` helper

**Files:**
- Modify: `frontend/src/PathUtil.elm`
- Test: `frontend/tests/PathUtilTest.elm`

- [ ] **Step 1: Write the failing tests**

In `frontend/tests/PathUtilTest.elm`, add these tests inside the `describe "PathUtil"` list (before its closing `]`):

```elm
        , test "ancestorDirs of a nested path lists each ancestor folder" <|
            \_ -> Expect.equal [ "a", "a/b" ] (PathUtil.ancestorDirs "a/b/c.md")
        , test "ancestorDirs of a single-folder path" <|
            \_ -> Expect.equal [ "Inbox" ] (PathUtil.ancestorDirs "Inbox/foo.md")
        , test "ancestorDirs of a root-level file is empty" <|
            \_ -> Expect.equal [] (PathUtil.ancestorDirs "foo.md")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd frontend && elm-test`
Expected: FAIL — compile error, `PathUtil.ancestorDirs` does not exist.

- [ ] **Step 3: Implement `ancestorDirs`**

In `frontend/src/PathUtil.elm`, add `ancestorDirs` to the exposing list (alphabetical):

```elm
module PathUtil exposing (ancestorDirs, basename, kbaseRoot, parentDir, siblingPath)
```

Then add this definition (place it after `parentDir`, before `kbaseRoot`):

```elm
{-| Every ancestor folder of a '/'-separated path, outermost first. The final
segment (the file name) is dropped. So `"a/b/c.md"` yields `["a", "a/b"]`,
`"Inbox/foo.md"` yields `["Inbox"]`, and a bare `"foo.md"` yields `[]`.
-}
ancestorDirs : String -> List String
ancestorDirs path =
    let
        folders =
            path |> String.split "/" |> List.reverse |> List.drop 1 |> List.reverse
    in
    folders
        |> List.foldl
            (\seg acc ->
                case acc of
                    prev :: _ ->
                        (prev ++ "/" ++ seg) :: acc

                    [] ->
                        [ seg ]
            )
            []
        |> List.reverse
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd frontend && elm-test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/PathUtil.elm frontend/tests/PathUtilTest.elm
git commit -m "feat: add PathUtil.ancestorDirs helper"
```

---

### Task 2: Reload button

**Files:**
- Modify: `frontend/src/Types.elm`, `frontend/src/Main.elm`, `frontend/src/View.elm`

- [ ] **Step 1: Add the `ClickedReload` Msg variant**

In `frontend/src/Types.elm`, in `type Msg`, add the variant immediately after `CopyReply String` (around line 118):

```elm
    | CopyReply String
    | ClickedReload
```

- [ ] **Step 2: Handle `ClickedReload` in `update`**

In `frontend/src/Main.elm`, add a branch immediately before the `ClickedNewFile ->` branch (around line 344):

```elm
        ClickedReload ->
            relist model

```

(`relist` already returns `( model, Cmd.none )` when there is no vault, so this is a safe no-op then; otherwise it re-lists the tree at the current root without touching `selectedPath`, the open document, or `openFolders`.)

- [ ] **Step 3: Add the Reload button to the sidebar**

In `frontend/src/View.elm`, in `treeColumn`, replace the leading element of the list — currently:

```elm
        (button [ onClick ClickedOpenVault ] [ text "Open Vault" ]
            :: [ searchBox model
```

with a row holding both buttons:

```elm
        (div [ style "display" "flex", style "gap" "4px" ]
            [ button [ onClick ClickedOpenVault ] [ text "Open Vault" ]
            , button
                [ onClick ClickedReload
                , Html.Attributes.disabled (model.vaultRoot == Nothing)
                ]
                [ text "Reload" ]
            ]
            :: [ searchBox model
```

(`button`, `text`, `style`, `onClick` and `Html.Attributes.disabled` are all already imported/used in `View.elm`.)

- [ ] **Step 4: Verify build + tests**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make elm && (cd frontend && elm-test)`
Expected: `Success!` and `TEST RUN PASSED`.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm
git commit -m "feat: add Reload button to refresh the vault tree"
```

---

### Task 3: New document becomes the current document

**Files:**
- Modify: `frontend/src/Main.elm` (the `PCreateFile` response branch, around line 707)

- [ ] **Step 1: Replace the `PCreateFile` response branch**

In `frontend/src/Main.elm`, the response handler currently reads:

```elm
                PCreateFile _ ->
                    relist model
```

Replace it with:

```elm
                PCreateFile path ->
                    let
                        expanded =
                            { model
                                | openFolders =
                                    List.foldl Set.insert model.openFolders (PathUtil.ancestorDirs path)
                            }

                        ( opened, openCmd ) =
                            openDoc path expanded

                        ( relisted, relistCmd ) =
                            relist opened
                    in
                    ( relisted
                    , Cmd.batch
                        [ openCmd
                        , relistCmd
                        , saveOpenFoldersCmd relisted.vaultRoot relisted.openFolders
                        ]
                    )
```

(`Set`, `PathUtil`, `openDoc`, `relist`, and `saveOpenFoldersCmd` are all already in scope in `Main.elm`. `openDoc` sets `selectedPath = Just path` — the sidebar highlight — and issues the `PReadFile` that loads the new file's empty content for editing; `ancestorDirs` expands its folders so it is revealed; `relist` refreshes the tree to include it.)

- [ ] **Step 2: Verify build + tests**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make elm && (cd frontend && elm-test)`
Expected: `Success!` and `TEST RUN PASSED` (no test count change — this path is manually verified).

- [ ] **Step 3: Commit**

```bash
git add frontend/src/Main.elm
git commit -m "feat: newly created document opens, highlights, and reveals itself"
```

---

### Task 4: Button background color + press feedback

**Files:**
- Modify: `frontend/index.html` (CSS, around lines 121-160)

- [ ] **Step 1: Update the base button rule + hover**

In `frontend/index.html`, replace the base button rule and its hover (around lines 121-132):

```css
      button, .cm-button {
        background: #3b3f45;
        color: #fff;
        border: 1px solid #555;
        border-radius: 4px;
        padding: 2px 8px;
        font: inherit;
        font-size: 12px;
        cursor: pointer;
        background-image: none;
      }
      button:hover, .cm-button:hover { background: #4a4e55; }
```

with:

```css
      button, .cm-button {
        background: #2b2c40;
        color: #fff;
        border: 1px solid #555;
        border-radius: 4px;
        padding: 2px 8px;
        font: inherit;
        font-size: 12px;
        cursor: pointer;
        background-image: none;
        transition: background 0.08s ease, transform 0.05s ease;
      }
      button:hover, .cm-button:hover { background: #3a3c55; }
      button:active, .cm-button:active { background: #1f2030 !important; transform: translateY(1px); }
```

- [ ] **Step 2: Update the `.cm-button` !important overrides**

In `frontend/index.html`, replace the `.cm-button` override block and its hover (around lines 154-160):

```css
      .cm-button {
        color: #fff !important;
        background: #3b3f45 !important;
        background-image: none !important;
        border: 1px solid #555 !important;
      }
      .cm-button:hover { background: #4a4e55 !important; }
```

with:

```css
      .cm-button {
        color: #fff !important;
        background: #2b2c40 !important;
        background-image: none !important;
        border: 1px solid #555 !important;
      }
      .cm-button:hover { background: #3a3c55 !important; }
```

- [ ] **Step 3: Build**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make elm`
Expected: `Success! Compiled 1 module.` (CSS is not compiled; verified manually after `make build`.)

- [ ] **Step 4: Commit**

```bash
git add frontend/index.html
git commit -m "style: button background #2b2c40 + momentary press feedback"
```

---

## Self-Review

**1. Spec coverage:**
- Reload button → Task 2 (Msg + `relist` handler + sidebar button, disabled when no vault).
- Button background `#2b2c40` → Task 4 (base rule + `.cm-button` override).
- Momentary press feedback → Task 4 (`:active` rule + transition).
- New doc becomes current (open + highlight + reveal + tree refresh) → Task 3 (`openDoc` + `ancestorDirs` + `relist`), built on Task 1.
- `ancestorDirs` helper + tests → Task 1.
- Edge case (vault is kbase subfolder) — documented in spec; no code path needed (normal use opens kbase root).

**2. Placeholder scan:** No TBD/TODO; every code step has full code + exact commands. The only intentional testing deviation (no `ClickedReload`/`PCreateFile` unit test) is justified in the File Structure note — Model construction isn't feasible without a builder; those paths are manually verified. ✔

**3. Type/name consistency:** `ancestorDirs : String -> List String` defined Task 1, used Task 3; `ClickedReload` defined Task 2 (Types), handled Task 2 (update), emitted Task 2 (View); `openDoc`/`relist`/`saveOpenFoldersCmd`/`Set`/`PathUtil` confirmed in scope in `Main.elm`. Colors consistent across both CSS blocks (`#2b2c40` base, `#3a3c55` hover, `#1f2030` active). ✔
