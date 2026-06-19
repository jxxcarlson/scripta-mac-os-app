# New-File Creation: Verbatim Name + Inbox Placement — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New files use the typed name verbatim (no auto-capitalize, no forced `.scripta`) and are placed in `kbase/Inbox` when the vault is kbase or a descendant, otherwise in the open document's folder.

**Architecture:** A new `PathUtil.kbaseRoot` locates the kbase root from the vault path; `Main.ClickedNewFile` routes there (`Inbox/<name>` relative to the kbase root) or falls back to the sibling path. `ensureScriptaExt` is removed (it was also used by rename, which becomes verbatim too). The name `Html.input` gets `autocapitalize`/`autocorrect`/`spellcheck` off.

**Tech Stack:** Elm 0.19.1 (`elm-explorations/test`). No Rust changes (`create_file` already creates parent dirs).

Spec: `docs/superpowers/specs/2026-06-19-new-file-placement-design.md`

---

## File Structure

- **Modify** `frontend/src/PathUtil.elm` + `frontend/tests/PathUtilTest.elm` — add `kbaseRoot`.
- **Modify** `frontend/src/View.elm` — disable OS auto-capitalize/correct on the name input.
- **Modify** `frontend/src/Main.elm` — verbatim names + Inbox placement; remove `ensureScriptaExt` (updating both `ClickedNewFile` and `ClickedRename`).

---

## Task 1: `PathUtil.kbaseRoot` (TDD)

**Files:** Modify `frontend/src/PathUtil.elm`, `frontend/tests/PathUtilTest.elm`

- [ ] **Step 1: Write the failing tests**

Add to the `describe "PathUtil"` list in `frontend/tests/PathUtilTest.elm`:

```elm
        , test "kbaseRoot returns the vault path when it ends in kbase" <|
            \_ ->
                Expect.equal (Just "/Users/c/CloudDocs/kbase")
                    (PathUtil.kbaseRoot "/Users/c/CloudDocs/kbase")
        , test "kbaseRoot truncates a kbase descendant to the kbase root" <|
            \_ ->
                Expect.equal (Just "/Users/c/CloudDocs/kbase")
                    (PathUtil.kbaseRoot "/Users/c/CloudDocs/kbase/Subjects/Physics")
        , test "kbaseRoot is Nothing when there is no kbase segment" <|
            \_ ->
                Expect.equal Nothing (PathUtil.kbaseRoot "/Users/c/projects/notes")
        , test "kbaseRoot requires an exact segment match (not a prefix)" <|
            \_ ->
                Expect.equal Nothing (PathUtil.kbaseRoot "/Users/c/kbase-backup/x")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/PathUtilTest.elm`
Expected: compile error — `PathUtil.kbaseRoot` not found.

- [ ] **Step 3: Implement**

In `frontend/src/PathUtil.elm`, add `kbaseRoot` to the module's `exposing (…)` list (alongside `basename`, `parentDir`, `siblingPath`) and add:

```elm
{-| If `path` contains a directory segment named "kbase", return the path
truncated to and including that segment (the kbase root); otherwise Nothing.
So `…/kbase` and `…/kbase/sub` both yield `Just "…/kbase"`. Matches whole
segments only, so `kbase-backup` does not qualify. An absolute path's leading
"" segment is preserved by the rejoin.
-}
kbaseRoot : String -> Maybe String
kbaseRoot path =
    let
        go acc remaining =
            case remaining of
                [] ->
                    Nothing

                seg :: rest ->
                    if seg == "kbase" then
                        Just (String.join "/" (List.reverse (seg :: acc)))

                    else
                        go (seg :: acc) rest
    in
    go [] (String.split "/" path)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/PathUtilTest.elm`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/PathUtil.elm frontend/tests/PathUtilTest.elm
git commit -m "feat: PathUtil.kbaseRoot locates the kbase root in a vault path"
```

---

## Task 2: Disable OS auto-capitalize/correct on the name input

**Files:** Modify `frontend/src/View.elm`

- [ ] **Step 1: Add the attributes**

In `frontend/src/View.elm`, the new-file-name `Html.input` (around line 29-33) currently has
`Html.Attributes.placeholder "new-file-name"`, `Html.Attributes.value model.newName`,
`onInput SetNewName`, and a `style`. Add three attributes to that list:

```elm
                        , Html.Attributes.attribute "autocapitalize" "off"
                        , Html.Attributes.attribute "autocorrect" "off"
                        , Html.Attributes.spellcheck False
```

- [ ] **Step 2: Verify it compiles**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null`
Expected: `Success!`. (No unit test — this is an OS-input attribute, verified manually in the GUI.)

- [ ] **Step 3: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/View.elm
git commit -m "fix: disable auto-capitalize/correct on the new-file name field"
```

---

## Task 3: Verbatim names + Inbox placement (Main.elm)

**Files:** Modify `frontend/src/Main.elm`

- [ ] **Step 1: Rewrite `ClickedNewFile`**

Replace the `ClickedNewFile ->` branch with (routes to `kbase/Inbox` or the open doc's folder; uses the trimmed name verbatim):

```elm
        ClickedNewFile ->
            case model.vaultRoot of
                Just root ->
                    let
                        name =
                            String.trim model.newName
                    in
                    if String.isEmpty name then
                        ( model, Cmd.none )

                    else
                        case PathUtil.kbaseRoot root of
                            Just kroot ->
                                let
                                    path =
                                        "Inbox/" ++ name
                                in
                                request (PCreateFile path)
                                    "create_file"
                                    [ ( "root", E.string kroot ), ( "path", E.string path ), ( "content", E.string "" ) ]
                                    { model | newName = "" }

                            Nothing ->
                                let
                                    path =
                                        PathUtil.siblingPath model.selectedPath name
                                in
                                request (PCreateFile path)
                                    "create_file"
                                    [ ( "root", E.string root ), ( "path", E.string path ), ( "content", E.string "" ) ]
                                    { model | newName = "" }

                Nothing ->
                    ( model, Cmd.none )
```

- [ ] **Step 2: Make `ClickedRename` use the verbatim name**

In the `ClickedRename ->` branch, the `newPath` currently ends with `++ ensureScriptaExt model.newName`. Change that to use the trimmed name verbatim:

```elm
                            newPath =
                                (if dir == "" then
                                    ""

                                 else
                                    dir ++ "/"
                                )
                                    ++ String.trim model.newName
```

- [ ] **Step 3: Remove `ensureScriptaExt`**

Delete the now-unused `ensureScriptaExt` function definition from `frontend/src/Main.elm`:

```elm
ensureScriptaExt : String -> String
ensureScriptaExt name =
    if String.endsWith ".scripta" name then
        name

    else
        name ++ ".scripta"
```

- [ ] **Step 4: Build + full test suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test`
Expected: `Success!` (no unused-function/import errors — `ensureScriptaExt` is fully removed) and all suites pass.

- [ ] **Step 5: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/Main.elm
git commit -m "feat: new files use verbatim name + kbase/Inbox placement"
```

---

## After All Tasks

- Final code review over the whole diff.
- **Manual verification (human, GUI):** open the **kbase** vault → New `black-hole-study-notes.md` → it is created as `kbase/Inbox/black-hole-study-notes.md`, **lowercase preserved, no `.scripta`**, and appears in the sidebar. Open a **subfolder of kbase** as the vault → New a file → it's created in `kbase/Inbox` (won't show in the sidebar until you open kbase — expected). Open a **non-kbase** folder, open a document, New a file → created beside that document. Rename a file → name used verbatim (no `.scripta` added).
- Then use superpowers:finishing-a-development-branch.

## Notes

- No Rust change: `create_file` writes `root.join(path)` and creates parent directories, so
  `Inbox/<name>` auto-creates `Inbox/`. Passing the **kbase root** as the command's `root`
  (not the opened vault) makes the file land in the real `kbase/Inbox` even when the opened
  vault is a subfolder.
- Subfolder caveat (accepted, per spec): when the opened vault is a descendant of kbase, the
  relist (which lists only the opened vault) won't show the new Inbox file until kbase is opened.
- `ensureScriptaExt` was shared by create and rename; both become verbatim for consistency.
