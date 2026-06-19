# Markdown File Links (Open Externally) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clicking a link in rendered markdown opens it — relative file links open with the macOS default app (resolved relative to the viewed document's directory, confined to the vault); `http(s)`/`mailto` links open in the default browser/mail; `#anchors` stay native.

**Architecture:** A recursive custom inline renderer in `MarkdownRender` intercepts `Link` inlines, classifies the href, and dispatches a new `Render.RenderMsg` (`OpenUrl`/`OpenLocalFile`). `View` maps the markdown body through `GotRenderMsg`; `Main` routes the messages through the existing FS bridge (`request`/`FileOps.send`) to two new Rust commands (`open_url`, `open_path`) that resolve + confine the path and shell out to `open` (the pattern already used for `latexmk`).

**Tech Stack:** Elm 0.19.1 (`elm-explorations/test`, incl. `Test.Html`), Rust/Tauri 2 (`std::process::Command`, `tempfile` for tests), no new plugins/ports/capabilities.

Spec: `docs/superpowers/specs/2026-06-19-markdown-file-links-design.md`

---

## File Structure

- **Modify** `src-tauri/src/fs_commands.rs` — `resolve_link_target`, `validate_external_url`, `open_path`, `open_url` + unit tests.
- **Modify** `src-tauri/src/lib.rs` — register `open_path`, `open_url`.
- **Modify** `frontend/src/Render.elm` — add `OpenUrl`/`OpenLocalFile` to `RenderMsg`.
- **Modify** `frontend/src/MarkdownRender.elm` + `frontend/tests/MarkdownRenderTest.elm` — `classifyLink`, recursive `inlineRenderer`, link interception.
- **Modify** `frontend/src/Types.elm` — add `POpenExternal` to `PendingOp`.
- **Modify** `frontend/src/Main.elm` — `GotRenderMsg` branches + `handleResponse` `POpenExternal`.
- **Modify** `frontend/src/View.elm` — map markdown body via `GotRenderMsg`.

Note: the existing FS commands do **not** confine paths; `resolve_link_target` implements confinement fresh (canonicalize + `starts_with`).

---

## Task 1: Rust — open_path / open_url + path resolver (TDD)

**Files:**
- Modify: `src-tauri/src/fs_commands.rs`, `src-tauri/src/lib.rs`

- [ ] **Step 1: Write the failing tests**

Add to the existing `#[cfg(test)] mod tests { … }` block at the bottom of `src-tauri/src/fs_commands.rs` (it already uses `tempfile` temp dirs — follow the same `super::*` / tempdir style already present):

```rust
    #[test]
    fn resolve_link_sibling() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::write(root.join("doc.md"), "x").unwrap();
        std::fs::write(root.join("file.pdf"), "x").unwrap();
        let p = resolve_link_target(root, "doc.md", "file.pdf").unwrap();
        assert_eq!(p, root.join("file.pdf").canonicalize().unwrap());
    }

    #[test]
    fn resolve_link_in_subdir() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::create_dir_all(root.join("a/b")).unwrap();
        std::fs::write(root.join("a/b/_index.md"), "x").unwrap();
        std::fs::write(root.join("a/b/pic.pdf"), "x").unwrap();
        let p = resolve_link_target(root, "a/b/_index.md", "pic.pdf").unwrap();
        assert_eq!(p, root.join("a/b/pic.pdf").canonicalize().unwrap());
    }

    #[test]
    fn resolve_link_rejects_escape() {
        let base = tempfile::tempdir().unwrap();
        let root = base.path().join("vault");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(root.join("doc.md"), "x").unwrap();
        std::fs::write(base.path().join("secret.pdf"), "x").unwrap();
        assert!(resolve_link_target(&root, "doc.md", "../secret.pdf").is_err());
    }

    #[test]
    fn resolve_link_missing_file_errors() {
        let dir = tempfile::tempdir().unwrap();
        std::fs::write(dir.path().join("doc.md"), "x").unwrap();
        assert!(resolve_link_target(dir.path(), "doc.md", "nope.pdf").is_err());
    }

    #[test]
    fn external_url_scheme_validation() {
        assert!(validate_external_url("https://example.com").is_ok());
        assert!(validate_external_url("http://example.com").is_ok());
        assert!(validate_external_url("mailto:a@b.c").is_ok());
        assert!(validate_external_url("file:///etc/passwd").is_err());
        assert!(validate_external_url("javascript:alert(1)").is_err());
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo test resolve_link 2>&1 | tail -20`
Expected: compile error — `resolve_link_target` / `validate_external_url` not found.

- [ ] **Step 3: Implement the resolver, validator, and commands**

Add to `src-tauri/src/fs_commands.rs` (near the other commands; `Path`/`PathBuf` are already imported at the top):

```rust
/// Resolve a markdown link `target` relative to the directory of the document
/// `doc_rel` (vault-relative), confined to `root`. Canonicalization requires the
/// target to exist; a target escaping the vault is rejected.
pub fn resolve_link_target(root: &Path, doc_rel: &str, target: &str) -> Result<PathBuf, String> {
    let doc_abs = root.join(doc_rel);
    let base = doc_abs
        .parent()
        .ok_or_else(|| "document has no parent directory".to_string())?;
    let canon = base
        .join(target)
        .canonicalize()
        .map_err(|e| format!("cannot resolve link target: {}", e))?;
    let root_canon = root.canonicalize().map_err(|e| e.to_string())?;
    if !canon.starts_with(&root_canon) {
        return Err("link target is outside the vault".to_string());
    }
    Ok(canon)
}

/// Only http/https/mailto URLs may be opened externally.
pub fn validate_external_url(url: &str) -> Result<(), String> {
    if url.starts_with("http://") || url.starts_with("https://") || url.starts_with("mailto:") {
        Ok(())
    } else {
        Err(format!("refusing to open non-web URL: {}", url))
    }
}

#[tauri::command]
pub fn open_path(root: String, doc: String, target: String) -> Result<(), String> {
    let abs = resolve_link_target(Path::new(&root), &doc, &target)?;
    std::process::Command::new("open")
        .arg(&abs)
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub fn open_url(url: String) -> Result<(), String> {
    validate_external_url(&url)?;
    std::process::Command::new("open")
        .arg(&url)
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}
```

- [ ] **Step 4: Register the commands**

In `src-tauri/src/lib.rs`, add to the `tauri::generate_handler![ … ]` list (around `lib.rs:17`, after the existing `fs_commands::…` entries):

```rust
            fs_commands::open_path,
            fs_commands::open_url,
```

- [ ] **Step 5: Run the tests to verify they pass + the crate builds**

Run:
```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo test 2>&1 | tail -15
```
Expected: all tests pass (the 5 new ones + the existing ~26). The handler list compiles.

- [ ] **Step 6: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: open_path/open_url commands with vault-confined link resolution"
```

---

## Task 2: Elm — RenderMsg variants + markdown link interception (TDD)

**Files:**
- Modify: `frontend/src/Render.elm`, `frontend/src/MarkdownRender.elm`
- Test: `frontend/tests/MarkdownRenderTest.elm`

- [ ] **Step 1: Add the RenderMsg variants**

In `frontend/src/Render.elm`, add two constructors to `type RenderMsg` (after `RenderNoOp` or anywhere in the list):

```elm
    | OpenUrl String
    | OpenLocalFile String
```

(`eventToMsg` does not need a new branch — these are produced only by the markdown renderer. The `RenderMsg` export is already `RenderMsg(..)`.)

- [ ] **Step 2: Write the failing tests**

Add to `frontend/tests/MarkdownRenderTest.elm` (the `describe "MarkdownRender"` list). The file already imports `Render`, `Test.Html.Query as Query`, `Test.Html.Selector as Selector`, `Test.Html.Event as Event`, `Html`, `Expect`:

```elm
        , test "classifies a relative target as a local file" <|
            \_ ->
                Expect.equal MarkdownRender.LocalFile (MarkdownRender.classifyLink "III_The_Rose.pdf")
        , test "classifies a subdir target as a local file" <|
            \_ ->
                Expect.equal MarkdownRender.LocalFile (MarkdownRender.classifyLink "sub/dir/file.pdf")
        , test "classifies http(s) and mailto as web" <|
            \_ ->
                Expect.equal [ MarkdownRender.Web, MarkdownRender.Web, MarkdownRender.Web ]
                    [ MarkdownRender.classifyLink "http://e.com"
                    , MarkdownRender.classifyLink "https://e.com"
                    , MarkdownRender.classifyLink "mailto:a@b.c"
                    ]
        , test "classifies a fragment as an anchor" <|
            \_ ->
                Expect.equal MarkdownRender.Anchor (MarkdownRender.classifyLink "#section")
        , test "a local file link click emits OpenLocalFile" <|
            \_ ->
                MarkdownRender.render "[doc](III_The_Rose.pdf)"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "a" ]
                    |> Event.simulate Event.click
                    |> Event.expect (Render.OpenLocalFile "III_The_Rose.pdf")
        , test "a web link click emits OpenUrl" <|
            \_ ->
                MarkdownRender.render "[site](https://example.com)"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "a" ]
                    |> Event.simulate Event.click
                    |> Event.expect (Render.OpenUrl "https://example.com")
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/MarkdownRenderTest.elm`
Expected: compile error — `MarkdownRender.classifyLink` / `LinkKind` not found.

- [ ] **Step 4: Implement classification + interception**

In `frontend/src/MarkdownRender.elm`:

(a) Update the module declaration to expose the new items:
```elm
module MarkdownRender exposing (LinkKind(..), classifyLink, render)
```

(b) Update imports: expose the `Inline` constructors and add `Json.Decode`:
```elm
import Json.Decode as D
import Markdown.Inline as Inline exposing (Inline(..))
```
(Replace the existing `import Markdown.Inline as Inline` line. `Html.Events` is already imported.)

(c) Add the classifier (top-level):
```elm
type LinkKind
    = Web
    | Anchor
    | LocalFile


{-| Classify a markdown link href: web (open in browser), in-page anchor (native),
or a relative local file (open with the default app, resolved against the doc dir).
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

    else
        LocalFile
```

(d) Add the recursive inline renderer + a preventDefault click helper (top-level):
```elm
{-| Render markdown inlines, intercepting Link inlines so file/web links open
externally instead of navigating the webview. Recurses with itself so links
nested inside emphasis are also intercepted.
-}
inlineRenderer : Inline i -> Html Render.RenderMsg
inlineRenderer inline =
    case inline of
        Link url _ inlines ->
            let
                children =
                    List.map inlineRenderer inlines
            in
            case classifyLink url of
                Web ->
                    Html.a [ Html.Attributes.href url, onClickPreventDefault (Render.OpenUrl url) ] children

                LocalFile ->
                    Html.a [ Html.Attributes.href url, onClickPreventDefault (Render.OpenLocalFile url) ] children

                Anchor ->
                    Html.a [ Html.Attributes.href url ] children

        _ ->
            Inline.defaultHtml (Just inlineRenderer) inline


onClickPreventDefault : Render.RenderMsg -> Html.Attribute Render.RenderMsg
onClickPreventDefault msg =
    Html.Events.preventDefaultOn "click" (D.succeed ( msg, True ))
```

(e) Wire `inlineRenderer` into block rendering. The body's element type becomes
`Html Render.RenderMsg`, so update the two helper signatures and the two inline call sites:
- Change `markdownBlockToHtmlIndexed : Int -> Block b i -> List (Html msg)` to
  `markdownBlockToHtmlIndexed : Int -> Block b i -> List (Html Render.RenderMsg)`.
- Change `markdownBlockToHtml : Block b i -> List (Html msg)` to
  `markdownBlockToHtml : Block b i -> List (Html Render.RenderMsg)`.
- In the heading case, change `(List.map Inline.toHtml inlines)` to `(List.map inlineRenderer inlines)`.
- In the `_ ->` (default) case, change `Block.defaultHtml (Just markdownBlockToHtml) Nothing block` to
  `Block.defaultHtml (Just markdownBlockToHtml) (Just inlineRenderer) block`.

(`render`'s `body` already flows from `markdownBlockToHtmlIndexed`, so `RenderOutput.body`
becomes `List (Html Render.RenderMsg)` — which matches `RenderOutput`'s declared type.)

- [ ] **Step 5: Run the tests to verify they pass + the app compiles**

Run:
```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test && elm make src/Main.elm --output=/dev/null
```
Expected: all elm-test suites pass (incl. the 6 new tests) and `elm make` → `Success!`. (At this point `View` still maps the markdown body to `NoOpFromRender`, so clicks aren't wired yet — that's Task 3. It still compiles because the `\_ ->` map discards the message.)

- [ ] **Step 6: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/Render.elm frontend/src/MarkdownRender.elm frontend/tests/MarkdownRenderTest.elm
git commit -m "feat: intercept markdown links (classify web/anchor/local) -> RenderMsg"
```

---

## Task 3: Wire View + Main

**Files:**
- Modify: `frontend/src/Types.elm`, `frontend/src/Main.elm`, `frontend/src/View.elm`

- [ ] **Step 1: Add the PendingOp variant**

In `frontend/src/Types.elm`, add a constructor to `type PendingOp` (after `PLaunchFile`):

```elm
    | POpenExternal
```

- [ ] **Step 2: Route the markdown body clicks (View)**

In `frontend/src/View.elm`, the markdown branches currently map the body with
`List.map (Html.map (\_ -> NoOpFromRender))`. Change BOTH occurrences (the `previewBody`
markdown branch and the `readerView` markdown branch's `bodyHtml`) to:

```elm
                |> List.map (Html.map GotRenderMsg)
```

(For `previewBody`, the branch is the pipeline `MarkdownRender.render model.content |> .body |> List.map (Html.map (\_ -> NoOpFromRender))` → replace the last line. For `readerView`, the `bodyHtml = out.body |> List.map (Html.map (\_ -> NoOpFromRender))` → replace with `out.body |> List.map (Html.map GotRenderMsg)`. Leave the Scripta branches unchanged.)

- [ ] **Step 3: Handle the new messages (Main)**

In `frontend/src/Main.elm`'s `GotRenderMsg` case, add two branches BEFORE the `_ ->` catch-all (`E` = `Json.Encode`, already imported; `request` is the existing helper at `Main.elm:69`):

```elm
                Render.OpenUrl url ->
                    request POpenExternal "open_url" [ ( "url", E.string url ) ] model

                Render.OpenLocalFile target ->
                    case ( model.vaultRoot, model.selectedPath ) of
                        ( Just root, Just doc ) ->
                            request POpenExternal
                                "open_path"
                                [ ( "root", E.string root )
                                , ( "doc", E.string doc )
                                , ( "target", E.string target )
                                ]
                                model

                        _ ->
                            ( model, Cmd.none )
```

- [ ] **Step 4: Handle the response (Main)**

In `handleResponse`'s `Ok` arm (the `case op of` around `Main.elm:448`), add a branch
(e.g. next to `PNoop`):

```elm
                POpenExternal ->
                    ( model, Cmd.none )
```

(The `Err` arm already sets `model.error` for any op, so a failed open surfaces in the error banner with no extra code.)

- [ ] **Step 5: Build + full test suite**

Run:
```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test
```
Expected: `Success!` and all suites pass.

- [ ] **Step 6: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm
git commit -m "feat: route markdown link clicks to open_path/open_url"
```

---

## After All Tasks

- Final code review over the whole diff.
- **Manual verification (human, GUI):** `make build`, install over `/Applications/Scripta.app`, fully quit + relaunch. In a vault with an `_index.md` that has: a relative PDF link, a relative link into a subdirectory, a web link, and a broken link — confirm: PDF opens in Preview; subdir link resolves relative to the doc and opens; web link opens in the browser; broken link shows the error banner. Confirm a non-markdown (Scripta) doc's links are unaffected.
- Then use superpowers:finishing-a-development-branch.

## Notes

- `canonicalize()` requires the target to exist, which gives the "missing file → error" behavior for free and resolves symlinks before the in-vault check.
- No Tauri capability/permission change is needed: `open_path`/`open_url` are custom `invoke_handler` commands, the same kind already called from the frontend (`read_file`, etc.).
