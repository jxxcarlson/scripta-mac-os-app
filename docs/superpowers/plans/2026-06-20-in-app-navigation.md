# In-App Navigation for Doc & Folder Links — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clicking a relative Markdown link to a `.md`/`.scripta` doc or a folder renders it inside the viewer (navigation), with a Back button; PDFs/images keep opening externally; relative links become robust to spaces/`%20`/`<…>`.

**Architecture:** A Rust `resolve_doc_link` cleans + resolves a clicked target against the current doc's directory (folder→`_index.md`, vault-confined) and returns a vault-relative path. Elm classifies links as navigate vs external; navigate round-trips through the resolver, then opens the path via a history-aware `openDoc` helper. A `clean_target` helper also hardens the existing external-open path.

**Tech Stack:** Rust/Tauri 2 (new `percent-encoding` dep), Elm 0.19.1 (`elm-explorations/test`, incl. `Test.Html`).

Spec: `docs/superpowers/specs/2026-06-19-in-app-navigation-design.md`

---

## File Structure

- **Modify** `src-tauri/Cargo.toml` — add `percent-encoding`.
- **Modify** `src-tauri/src/fs_commands.rs` — `clean_target`, `resolve_doc_link`; apply `clean_target` in `resolve_link_target`; tests.
- **Modify** `src-tauri/src/lib.rs` — register `resolve_doc_link`.
- **Modify** `frontend/src/Render.elm` — add `NavigateToFile String`.
- **Modify** `frontend/src/MarkdownRender.elm` + `frontend/tests/MarkdownRenderTest.elm` — `LinkKind` gains `Navigate`, `LocalFile`→`External`; classify + render.
- **Modify** `frontend/src/Types.elm` — `history` field, `PResolveDocLink`, `ClickedBack`.
- **Modify** `frontend/src/Main.elm` — `openDoc`/`openDocNoPush`, route navigation + Back + history reset.
- **Modify** `frontend/src/View.elm` — Back button.

---

## Task 1: Rust — clean_target + resolve_doc_link (TDD)

**Files:** Modify `src-tauri/Cargo.toml`, `src-tauri/src/fs_commands.rs`, `src-tauri/src/lib.rs`

- [ ] **Step 1: Add the dependency**

In `src-tauri/Cargo.toml` under `[dependencies]`, add:
```toml
percent-encoding = "2"
```

- [ ] **Step 2: Write the failing tests**

Add to the `#[cfg(test)] mod tests { … }` block in `src-tauri/src/fs_commands.rs`:
```rust
    #[test]
    fn clean_target_strips_and_decodes() {
        assert_eq!(clean_target("<a b.pdf>"), "a b.pdf");
        assert_eq!(clean_target("a%20b.pdf"), "a b.pdf");
        assert_eq!(clean_target("  plain.md  "), "plain.md");
        assert_eq!(clean_target("Bar/_index.md"), "Bar/_index.md");
    }

    #[test]
    fn resolve_doc_link_sibling_and_subdir() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::create_dir_all(root.join("A")).unwrap();
        std::fs::write(root.join("A/doc.md"), "x").unwrap();
        std::fs::write(root.join("A/other.md"), "y").unwrap();
        assert_eq!(resolve_doc_link_impl(root, "A/doc.md", "other.md").unwrap(), "A/other.md");
        std::fs::create_dir_all(root.join("A/B")).unwrap();
        std::fs::write(root.join("A/B/deep.scripta"), "z").unwrap();
        assert_eq!(resolve_doc_link_impl(root, "A/doc.md", "B/deep.scripta").unwrap(), "A/B/deep.scripta");
    }

    #[test]
    fn resolve_doc_link_folder_to_index() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::write(root.join("doc.md"), "x").unwrap();
        std::fs::create_dir_all(root.join("Bar")).unwrap();
        std::fs::write(root.join("Bar/_index.md"), "i").unwrap();
        // bare folder target → its _index.md
        assert_eq!(resolve_doc_link_impl(root, "doc.md", "Bar").unwrap(), "Bar/_index.md");
        // explicit _index.md target
        assert_eq!(resolve_doc_link_impl(root, "doc.md", "Bar/_index.md").unwrap(), "Bar/_index.md");
    }

    #[test]
    fn resolve_doc_link_decodes_and_strips() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::write(root.join("doc.md"), "x").unwrap();
        std::fs::write(root.join("a b.md"), "y").unwrap();
        assert_eq!(resolve_doc_link_impl(root, "doc.md", "a%20b.md").unwrap(), "a b.md");
        assert_eq!(resolve_doc_link_impl(root, "doc.md", "<a b.md>").unwrap(), "a b.md");
    }

    #[test]
    fn resolve_doc_link_rejects_escape_and_missing() {
        let base = tempfile::tempdir().unwrap();
        let root = base.path().join("vault");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("doc.md"), "x").unwrap();
        std::fs::write(base.path().join("outside.md"), "o").unwrap();
        assert!(resolve_doc_link_impl(&root, "doc.md", "../outside.md").is_err());
        assert!(resolve_doc_link_impl(&root, "doc.md", "nope.md").is_err());
    }

    #[test]
    fn resolve_link_target_cleans_target() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::write(root.join("doc.md"), "x").unwrap();
        std::fs::write(root.join("a b.pdf"), "p").unwrap();
        let p = resolve_link_target(root, "doc.md", "<a b.pdf>").unwrap();
        assert_eq!(p, root.join("a b.pdf").canonicalize().unwrap());
        let p2 = resolve_link_target(root, "doc.md", "a%20b.pdf").unwrap();
        assert_eq!(p2, root.join("a b.pdf").canonicalize().unwrap());
    }
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo test clean_target resolve_doc_link resolve_link_target 2>&1 | tail -20`
Expected: compile error — `clean_target` / `resolve_doc_link_impl` not found.

- [ ] **Step 4: Implement**

In `src-tauri/src/fs_commands.rs` add:
```rust
/// Clean a Markdown link target: trim, strip surrounding `<…>`, and percent-decode.
pub fn clean_target(target: &str) -> String {
    let t = target.trim();
    let t = if t.len() >= 2 && t.starts_with('<') && t.ends_with('>') {
        &t[1..t.len() - 1]
    } else {
        t
    };
    percent_encoding::percent_decode_str(t)
        .decode_utf8_lossy()
        .into_owned()
}

/// Resolve a relative link `target` (from document `doc`) to the vault-relative
/// path of the document to open. Folders resolve to their `_index.md`. Confined
/// to `root`. Errors if missing / not a file / escaping the vault.
pub fn resolve_doc_link_impl(root: &Path, doc_rel: &str, target: &str) -> Result<String, String> {
    let t = clean_target(target);
    let doc_abs = root.join(doc_rel);
    let base = doc_abs
        .parent()
        .ok_or_else(|| "document has no parent directory".to_string())?;
    let mut canon = base
        .join(&t)
        .canonicalize()
        .map_err(|e| format!("cannot resolve link target: {}", e))?;
    if canon.is_dir() {
        canon = canon
            .join("_index.md")
            .canonicalize()
            .map_err(|e| format!("folder has no _index.md: {}", e))?;
    }
    let root_canon = root.canonicalize().map_err(|e| e.to_string())?;
    if !canon.starts_with(&root_canon) {
        return Err("link target is outside the vault".to_string());
    }
    if !canon.is_file() {
        return Err("link target is not a file".to_string());
    }
    let rel = canon.strip_prefix(&root_canon).map_err(|e| e.to_string())?;
    Ok(rel.to_string_lossy().replace('\\', "/"))
}

#[tauri::command]
pub fn resolve_doc_link(root: String, doc: String, target: String) -> Result<String, String> {
    resolve_doc_link_impl(Path::new(&root), &doc, &target)
}
```

And in `resolve_link_target`, change the candidate join to clean the target first. The existing line:
```rust
    let canon = base
        .join(target)
        .canonicalize()
```
becomes:
```rust
    let canon = base
        .join(clean_target(target))
        .canonicalize()
```

- [ ] **Step 5: Register the command**

In `src-tauri/src/lib.rs`, add to the `tauri::generate_handler![ … ]` list:
```rust
            fs_commands::resolve_doc_link,
```

- [ ] **Step 6: Run the tests + build**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo test 2>&1 | tail -15`
Expected: all pass (6 new + existing). Handler list compiles.

- [ ] **Step 7: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add src-tauri/Cargo.toml src-tauri/Cargo.lock src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: resolve_doc_link + clean_target for in-app navigation"
```

---

## Task 2: Elm — NavigateToFile message + link classification (TDD)

**Files:** Modify `frontend/src/Render.elm`, `frontend/src/MarkdownRender.elm`, `frontend/tests/MarkdownRenderTest.elm`

- [ ] **Step 1: Add the RenderMsg variant**

In `frontend/src/Render.elm`, add to `type RenderMsg`:
```elm
    | NavigateToFile String
```

- [ ] **Step 2: Update/replace the failing tests**

In `frontend/tests/MarkdownRenderTest.elm`:

Replace the two existing classify tests that use `MarkdownRender.LocalFile`:
```elm
        , test "classifies a relative target as a local file" <|
            \_ ->
                Expect.equal MarkdownRender.LocalFile (MarkdownRender.classifyLink "III_The_Rose.pdf")
        , test "classifies a subdir target as a local file" <|
            \_ ->
                Expect.equal MarkdownRender.LocalFile (MarkdownRender.classifyLink "sub/dir/file.pdf")
```
with:
```elm
        , test "classifies a pdf target as external" <|
            \_ ->
                Expect.equal MarkdownRender.External (MarkdownRender.classifyLink "III_The_Rose.pdf")
        , test "classifies a subdir pdf target as external" <|
            \_ ->
                Expect.equal MarkdownRender.External (MarkdownRender.classifyLink "sub/dir/file.pdf")
        , test "classifies .md / .scripta targets as navigate" <|
            \_ ->
                Expect.equal [ MarkdownRender.Navigate, MarkdownRender.Navigate ]
                    [ MarkdownRender.classifyLink "black-hole-study-notes.md"
                    , MarkdownRender.classifyLink "sub/foo.scripta"
                    ]
        , test "classifies a bare folder target as navigate" <|
            \_ ->
                Expect.equal MarkdownRender.Navigate (MarkdownRender.classifyLink "Bar")
        , test "a doc link click emits NavigateToFile" <|
            \_ ->
                MarkdownRender.render "[notes](black-hole-study-notes.md)"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "a" ]
                    |> Event.simulate Event.click
                    |> Event.expect (Render.NavigateToFile "black-hole-study-notes.md")
```
(The existing `[doc](III_The_Rose.pdf)` click test still expects `Render.OpenLocalFile "III_The_Rose.pdf"` — leave it; `External` still routes to `OpenLocalFile`.)

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/MarkdownRenderTest.elm`
Expected: compile error — `MarkdownRender.External` / `Navigate` not found.

- [ ] **Step 4: Implement**

In `frontend/src/MarkdownRender.elm`:

Change the `LinkKind` type and `classifyLink`:
```elm
type LinkKind
    = Web
    | Anchor
    | Navigate
    | External


{-| Classify a markdown link href. Relative `.md`/`.scripta` targets and bare
folders navigate in-app; other relative targets (pdf, images, …) open externally.
-}
classifyLink : String -> LinkKind
classifyLink url =
    if
        String.startsWith "http://" url
            || String.startsWith "https://" url
            || String.startsWith "mailto:" url
    then
        Web

    else if String.startsWith "#" url then
        Anchor

    else if isDocTarget url then
        Navigate

    else
        External


{-| A relative target is a navigable document if it ends in `.md`/`.scripta`,
or has no file extension in its last segment (treated as a folder).
-}
isDocTarget : String -> Bool
isDocTarget url =
    let
        lower =
            String.toLower url

        lastSeg =
            url |> String.split "/" |> List.reverse |> List.head |> Maybe.withDefault url
    in
    String.endsWith ".md" lower
        || String.endsWith ".scripta" lower
        || not (String.contains "." lastSeg)
```

Update `inlineRenderer`'s `Link` case so the classify branches are:
```elm
            case classifyLink url of
                Web ->
                    Html.a [ Html.Attributes.href url, onClickPreventDefault (Render.OpenUrl url) ] children

                Navigate ->
                    Html.a [ Html.Attributes.href url, onClickPreventDefault (Render.NavigateToFile url) ] children

                External ->
                    Html.a [ Html.Attributes.href url, onClickPreventDefault (Render.OpenLocalFile url) ] children

                Anchor ->
                    Html.a [ Html.Attributes.href url ] children
```

(The module already exposes `LinkKind(..)`, so `Navigate`/`External` are exported for tests.)

- [ ] **Step 5: Run the tests to verify they pass + compile**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test && elm make src/Main.elm --output=/dev/null`
Expected: all elm-test pass; `elm make` → `Success!`. (Navigation isn't wired in `Main` yet — `NavigateToFile` falls through the `GotRenderMsg` `_ ->` no-op until Task 3 — so clicking a doc link is currently a no-op, but it compiles.)

- [ ] **Step 6: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/Render.elm frontend/src/MarkdownRender.elm frontend/tests/MarkdownRenderTest.elm
git commit -m "feat: classify doc/folder links as navigate (NavigateToFile)"
```

---

## Task 3: Elm — navigation wiring, history, Back button

**Files:** Modify `frontend/src/Types.elm`, `frontend/src/Main.elm`, `frontend/src/View.elm`

- [ ] **Step 1: Model + ops (Types.elm)**

- Add to `type alias Model` (e.g. after `selectedPath`): `, history : List String`
- Add to `type PendingOp` (after `PLaunchFile`): `| PResolveDocLink`
- Add to `type Msg` (after `ToggledTheme` or with the other Clicked msgs): `| ClickedBack`

- [ ] **Step 2: Initialize + reset history (Main.elm)**

- In the initial model record (where `selectedPath = Nothing` is set, ~line 45): add `, history = []`
- In `openVault`'s `m0` record (where `selectedPath = Nothing`, ~line 90): add `, history = []`

- [ ] **Step 3: Add `openDoc` / `openDocNoPush` and route `ClickedTreeNode` through it (Main.elm)**

Add two top-level helpers (near `request`):
```elm
{-| Open a vault-relative document path in-app, pushing the current document
onto the history stack (for Back). -}
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
    openDocNoPush path { model | history = history }


{-| Open a vault-relative document path without touching history (used by Back). -}
openDocNoPush : String -> Model -> ( Model, Cmd Msg )
openDocNoPush path model =
    case model.vaultRoot of
        Just root ->
            if Language.fromPath path == Just Language.Image then
                request (PReadImage path)
                    "read_image"
                    [ ( "root", E.string root ), ( "path", E.string path ) ]
                    { model | selectedPath = Just path, language = Just Language.Image }

            else
                request (PReadFile path)
                    "read_file"
                    [ ( "root", E.string root ), ( "path", E.string path ) ]
                    { model | selectedPath = Just path, language = Language.fromPath path, imageSrc = Nothing }

        Nothing ->
            ( model, Cmd.none )
```

Replace the `ClickedTreeNode path ->` branch body with:
```elm
        ClickedTreeNode path ->
            openDoc path model
```

- [ ] **Step 4: Handle `NavigateToFile`, the resolve response, and Back (Main.elm)**

In `GotRenderMsg`'s `case renderMsg of`, add before the `_ ->` catch-all:
```elm
                Render.NavigateToFile target ->
                    case ( model.vaultRoot, model.selectedPath ) of
                        ( Just root, Just doc ) ->
                            request PResolveDocLink
                                "resolve_doc_link"
                                [ ( "root", E.string root )
                                , ( "doc", E.string doc )
                                , ( "target", E.string target )
                                ]
                                model

                        _ ->
                            ( model, Cmd.none )
```

Add a `ClickedBack ->` branch to `update` (e.g. next to `ToggledTheme`):
```elm
        ClickedBack ->
            case model.history of
                prev :: rest ->
                    openDocNoPush prev { model | history = rest }

                [] ->
                    ( model, Cmd.none )
```

In `handleResponse`'s `Ok result -> case op of`, add a branch:
```elm
                PResolveDocLink ->
                    case D.decodeValue D.string result of
                        Ok path ->
                            openDoc path model

                        Err e ->
                            ( { model | error = Just (D.errorToString e) }, Cmd.none )
```

- [ ] **Step 5: Back button (View.elm)**

In the `toolbar` `div` in `View.elm`, add a Back button before the Reader button (it needs `Html.Attributes.disabled`):
```elm
                [ button
                    [ onClick ClickedBack
                    , Html.Attributes.disabled (List.isEmpty model.history)
                    ]
                    [ text "← Back" ]
                , button [ onClick ToggledReaderMode ]
```
(Insert the Back button as the first child of the toolbar's button list; keep the existing Reader/Parse/Dark buttons after it.)

- [ ] **Step 6: Build + full test suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test`
Expected: `Success!` (Elm confirms `PendingOp`/`Msg` exhaustiveness and the `Model` record) and all suites pass.

- [ ] **Step 7: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm
git commit -m "feat: in-app doc navigation + history Back button"
```

---

## After All Tasks

- Final code review over the whole diff.
- **Manual verification (human, GUI):** open the kbase vault; open `Subjects/Physics/Black_Holes/_index.md`; click `[notes](black-hole-study-notes.md)` (or whatever links it has) → the note renders **in-app**; inside the note click the bekenstein PDF link → opens in **Preview**; click **← Back** → returns to `_index.md`; click a folder link (e.g. to another subject) → its `_index.md` renders; confirm a link with a space/`%20` or `<…>` resolves; confirm `http(s)` links still open in the browser and `#anchors` still scroll.
- Then use superpowers:finishing-a-development-branch.

## Notes

- `resolve_doc_link` uses `canonicalize`, which requires existence and resolves `..`/symlinks before the in-vault confinement check (consistent with `resolve_link_target`). On iCloud this only stats/opens the path metadata — it does **not** read file contents — so it does not force a download. (Reading the doc afterward via `read_file` reads only that one opened doc, as today.)
- Every doc-open (tree click or link navigation) pushes the previous doc onto `history`, so **Back returns to the previously-viewed doc regardless of how you reached the current one**. `history` resets when the vault changes.
- `update` is not exported, so `openDoc`/history/Back are covered by compilation + manual verification; the tested units are `classifyLink` (Elm) and `resolve_doc_link`/`clean_target` (Rust).
