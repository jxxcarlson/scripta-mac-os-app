# Open & View Any Text or Image Document — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** List/open/view any text file (source in a `<pre>` if not renderable) and common image files (shown via `<img>`, not edited) in a vault, beyond `.scripta`/`.tex`/`.md`.

**Architecture:** Rust `list_workspace` includes a file if it sniffs as text (no NUL byte in first 8 KB) or has an image extension, skipping dotfiles. A new Rust `read_image` command returns a base64 `data:` URL. Elm gains `PlainText`/`Image` language variants; images open via `read_image` into `model.imageSrc` and render as `<img>` (no editor); plain text renders its source in a `<pre>`.

**Tech Stack:** Rust/Tauri 2 (`walkdir`, new `base64` dep), Elm 0.19.1 (`elm-explorations/test`, incl. `Test.Html`).

Spec: `docs/superpowers/specs/2026-06-19-open-any-text-document-design.md`

---

## File Structure

- **Modify** `src-tauri/src/fs_commands.rs` — `is_text_file`, `is_image_ext`, dotfile pruning, swap the list filter (remove `has_doc_ext`/`EXTS`); add `read_image_impl`/`read_image` + `image_mime`.
- **Modify** `src-tauri/Cargo.toml` — add `base64`.
- **Modify** `src-tauri/src/lib.rs` — register `read_image`.
- **Modify** `frontend/src/Language.elm` + `frontend/tests/LanguageTest.elm` — `PlainText`/`Image`.
- **Modify** `frontend/src/Types.elm` — `imageSrc` field, `PReadImage` op.
- **Modify** `frontend/src/Main.elm` — open images via `read_image`, handle the response.
- **Modify** `frontend/src/View.elm` + **Create** `frontend/tests/ViewTextImageTest.elm` — `plainTextPreview`/`imagePane` helpers, image view, PlainText preview.

---

## Task 1: Rust — list text + image files, skip dotfiles (TDD)

**Files:** Modify `src-tauri/src/fs_commands.rs`

- [ ] **Step 1: Write the failing tests**

Add to the `#[cfg(test)] mod tests { … }` block (it already uses `tempfile` + `super::*`):

```rust
    #[test]
    fn is_text_file_detects_text_and_binary() {
        let dir = tempfile::tempdir().unwrap();
        let t = dir.path().join("a.txt");
        std::fs::write(&t, "hello world").unwrap();
        assert!(is_text_file(&t));
        let b = dir.path().join("a.bin");
        std::fs::write(&b, [0u8, 1, 2, 3]).unwrap();
        assert!(!is_text_file(&b));
        let e = dir.path().join("empty.txt");
        std::fs::write(&e, "").unwrap();
        assert!(is_text_file(&e));
    }

    #[test]
    fn is_image_ext_recognizes_images() {
        use std::path::Path;
        for n in ["a.png", "a.JPG", "a.jpeg", "a.gif", "a.webp"] {
            assert!(is_image_ext(Path::new(n)), "{}", n);
        }
        assert!(!is_image_ext(Path::new("a.txt")));
        assert!(!is_image_ext(Path::new("a.pdf")));
    }

    #[test]
    fn list_includes_text_and_images_excludes_binary_and_dotfiles() {
        let dir = tempfile::tempdir().unwrap();
        let root = dir.path();
        std::fs::write(root.join("note.txt"), "hi").unwrap();
        std::fs::write(root.join("pic.png"), [1u8, 2, 3]).unwrap();
        std::fs::write(root.join("doc.scripta"), "x").unwrap();
        std::fs::write(root.join("blob.bin"), [0u8, 1, 2]).unwrap();
        std::fs::write(root.join("paper.pdf"), [0x25u8, 0x50, 0x00, 0x01]).unwrap(); // NUL → binary
        std::fs::write(root.join(".DS_Store"), "x").unwrap();
        std::fs::create_dir_all(root.join(".git")).unwrap();
        std::fs::write(root.join(".git/config"), "x").unwrap();
        let entries = list_workspace_impl(root).unwrap();
        let names: Vec<&str> = entries.iter().map(|e| e.path.as_str()).collect();
        assert!(names.contains(&"note.txt"));
        assert!(names.contains(&"pic.png"));
        assert!(names.contains(&"doc.scripta"));
        assert!(!names.contains(&"blob.bin"));
        assert!(!names.contains(&"paper.pdf"));
        assert!(!names.iter().any(|n| n.starts_with(".DS_Store")));
        assert!(!names.iter().any(|n| n.starts_with(".git")));
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo test is_text_file is_image_ext list_includes 2>&1 | tail -20`
Expected: compile error — `is_text_file` / `is_image_ext` not found.

- [ ] **Step 3: Implement**

In `src-tauri/src/fs_commands.rs`, replace `const EXTS` + `has_doc_ext` with the text/image helpers and a hidden-entry helper:

```rust
fn is_text_file(p: &Path) -> bool {
    use std::io::Read;
    let mut f = match std::fs::File::open(p) {
        Ok(f) => f,
        Err(_) => return false,
    };
    let mut buf = [0u8; 8192];
    let n = match f.read(&mut buf) {
        Ok(n) => n,
        Err(_) => return false,
    };
    !buf[..n].contains(&0u8)
}

fn is_image_ext(p: &Path) -> bool {
    const IMG: [&str; 5] = ["jpg", "jpeg", "png", "gif", "webp"];
    p.extension()
        .and_then(|e| e.to_str())
        .map(|e| IMG.contains(&e.to_lowercase().as_str()))
        .unwrap_or(false)
}

fn is_hidden(entry: &walkdir::DirEntry) -> bool {
    entry
        .file_name()
        .to_str()
        .map(|s| s.starts_with('.'))
        .unwrap_or(false)
}
```

In `list_workspace_impl`, prune hidden entries during traversal and swap the file filter:

```rust
    for dent in WalkDir::new(root)
        .into_iter()
        .filter_entry(|e| e.depth() == 0 || !is_hidden(e))
        .filter_map(|e| e.ok())
    {
        let p = dent.path();
        if p == root {
            continue;
        }
        let is_dir = dent.file_type().is_dir();
        if !is_dir && !(is_text_file(p) || is_image_ext(p)) {
            continue;
        }
```

(Leave the rest of the function — `rel`/`name`/`mtime`/`push`/`sort` — unchanged. Update the doc comment above `list_workspace_impl` to "every directory and every text or image file".)

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo test 2>&1 | tail -15`
Expected: all pass (3 new + existing). No `has_doc_ext`/`EXTS` unused-warning (they were removed).

- [ ] **Step 5: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add src-tauri/src/fs_commands.rs
git commit -m "feat: list any text or image file, skip dotfiles"
```

---

## Task 2: Rust — read_image command (base64 data URL) (TDD)

**Files:** Modify `src-tauri/Cargo.toml`, `src-tauri/src/fs_commands.rs`, `src-tauri/src/lib.rs`

- [ ] **Step 1: Add the base64 dependency**

In `src-tauri/Cargo.toml`, under `[dependencies]`, add:

```toml
base64 = "0.22"
```

- [ ] **Step 2: Write the failing test**

Add to the `tests` module in `src-tauri/src/fs_commands.rs`:

```rust
    #[test]
    fn read_image_returns_png_data_url() {
        use base64::Engine;
        let dir = tempfile::tempdir().unwrap();
        let bytes = [0x89u8, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]; // PNG signature
        std::fs::write(dir.path().join("pic.png"), bytes).unwrap();
        let url = read_image_impl(dir.path(), "pic.png").unwrap();
        assert!(url.starts_with("data:image/png;base64,"));
        let b64 = url.strip_prefix("data:image/png;base64,").unwrap();
        let decoded = base64::engine::general_purpose::STANDARD.decode(b64).unwrap();
        assert_eq!(decoded, bytes);
    }
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo test read_image 2>&1 | tail -20`
Expected: compile error — `read_image_impl` not found.

- [ ] **Step 4: Implement**

Add to `src-tauri/src/fs_commands.rs`:

```rust
fn image_mime(p: &Path) -> &'static str {
    match p
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase())
        .as_deref()
    {
        Some("png") => "image/png",
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("gif") => "image/gif",
        Some("webp") => "image/webp",
        _ => "application/octet-stream",
    }
}

pub fn read_image_impl(root: &Path, rel: &str) -> Result<String, String> {
    use base64::Engine;
    let abs = root.join(rel);
    let bytes = std::fs::read(&abs).map_err(|e| e.to_string())?;
    let b64 = base64::engine::general_purpose::STANDARD.encode(&bytes);
    Ok(format!("data:{};base64,{}", image_mime(&abs), b64))
}

#[tauri::command]
pub fn read_image(root: String, path: String) -> Result<String, String> {
    read_image_impl(Path::new(&root), &path)
}
```

- [ ] **Step 5: Register the command**

In `src-tauri/src/lib.rs`, add to the `tauri::generate_handler![ … ]` list:

```rust
            fs_commands::read_image,
```

- [ ] **Step 6: Run the test + build**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo test 2>&1 | tail -15`
Expected: all pass (incl. `read_image_returns_png_data_url`); handler list compiles.

- [ ] **Step 7: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add src-tauri/Cargo.toml src-tauri/Cargo.lock src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: read_image command returning a base64 data URL"
```

---

## Task 3: Elm — PlainText + Image language variants (TDD)

**Files:** Modify `frontend/src/Language.elm`, `frontend/tests/LanguageTest.elm`

- [ ] **Step 1: Update the failing tests**

In `frontend/tests/LanguageTest.elm`, REMOVE the existing test:

```elm
        , test "returns Nothing for unknown" <|
            \_ -> Expect.equal Nothing (Language.fromPath "a.png")
```

and add these in its place (inside the `describe` list):

```elm
        , test "recognizes image extensions as Image" <|
            \_ ->
                Expect.equal [ Just Image, Just Image, Just Image, Just Image, Just Image ]
                    (List.map Language.fromPath [ "a.png", "b.jpg", "c.jpeg", "d.gif", "e.webp" ])
        , test "image extension is case-insensitive" <|
            \_ -> Expect.equal (Just Image) (Language.fromPath "PHOTO.JPG")
        , test "unknown extension is PlainText" <|
            \_ -> Expect.equal (Just PlainText) (Language.fromPath "a.xyz")
        , test "no extension is PlainText" <|
            \_ -> Expect.equal (Just PlainText) (Language.fromPath "README")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/LanguageTest.elm`
Expected: compile error — `Image` / `PlainText` not found.

- [ ] **Step 3: Implement**

In `frontend/src/Language.elm`:

- Add variants to the type:

```elm
type Language
    = Scripta
    | MiniLaTeX
    | Markdown
    | PlainText
    | Image
```

- Replace `fromPath`'s `case` with (note the `_ -> Just PlainText` fallback):

```elm
fromPath path =
    case path |> String.split "." |> lastSegment |> Maybe.map String.toLower of
        Just "scripta" ->
            Just Scripta

        Just "tex" ->
            Just MiniLaTeX

        Just "md" ->
            Just Markdown

        Just "jpg" ->
            Just Image

        Just "jpeg" ->
            Just Image

        Just "png" ->
            Just Image

        Just "gif" ->
            Just Image

        Just "webp" ->
            Just Image

        _ ->
            Just PlainText
```

- Add the two `label` cases:

```elm
        PlainText ->
            "Plain text"

        Image ->
            "Image"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/LanguageTest.elm`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/Language.elm frontend/tests/LanguageTest.elm
git commit -m "feat: add PlainText and Image language variants"
```

---

## Task 4: Elm — open images via read_image (Types + Main)

**Files:** Modify `frontend/src/Types.elm`, `frontend/src/Main.elm`

- [ ] **Step 1: Add the model field + pending op**

In `frontend/src/Types.elm`:
- Add to the `Model` record alias (e.g. after `parsedDoc`): `, imageSrc : Maybe String`
- Add to `type PendingOp` (after `PLaunchFile`): `| PReadImage String`

- [ ] **Step 2: Initialize the field**

In `frontend/src/Main.elm`'s initial model record (where `parsedDoc = Nothing` etc. are set), add:

```elm
        , imageSrc = Nothing
```

- [ ] **Step 3: Route image clicks to read_image**

In `frontend/src/Main.elm`, replace the `ClickedTreeNode path ->` branch with:

```elm
        ClickedTreeNode path ->
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

- [ ] **Step 4: Handle the read_image response + clear imageSrc on text open**

In `frontend/src/Main.elm`'s `handleResponse` `Ok` arm:

- In the existing `PReadFile _ ->` branch, add `, imageSrc = Nothing` to the record it builds for the `Ok ( content, mtime )` case (alongside `content`, `loadedContent`, `loadedMtime`, `externalConflict`, `parsedDoc`).
- Add a new branch (e.g. after `PReadFile _`):

```elm
                PReadImage _ ->
                    case D.decodeValue D.string result of
                        Ok url ->
                            ( { model | imageSrc = Just url, content = "", loadedContent = "", parsedDoc = Nothing }
                            , Cmd.none
                            )

                        Err e ->
                            ( { model | error = Just (D.errorToString e) }, Cmd.none )
```

- [ ] **Step 5: Build + tests**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test`
Expected: `Success!` (Elm confirms `PendingOp`/`Model` exhaustiveness) and all tests pass. (No new Elm unit test here — `update` is not exported; image-open is covered by compile + manual verification.)

- [ ] **Step 6: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/Types.elm frontend/src/Main.elm
git commit -m "feat: open image files via read_image into model.imageSrc"
```

---

## Task 5: Elm — image view + plain-text preview (TDD)

**Files:** Modify `frontend/src/View.elm`; Create `frontend/tests/ViewTextImageTest.elm`

- [ ] **Step 1: Write the failing tests**

Create `frontend/tests/ViewTextImageTest.elm`:

```elm
module ViewTextImageTest exposing (suite)

import Html.Attributes as Attr
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import View


suite : Test
suite =
    describe "View text/image panes"
        [ test "plainTextPreview renders a pre containing the content" <|
            \_ ->
                View.plainTextPreview "hello world"
                    |> Query.fromHtml
                    |> Query.has [ Selector.tag "pre", Selector.text "hello world" ]
        , test "imagePane renders an img with the data-url src" <|
            \_ ->
                View.imagePane (Just "data:image/png;base64,AAAA")
                    |> Query.fromHtml
                    |> Query.has
                        [ Selector.tag "img"
                        , Selector.attribute (Attr.src "data:image/png;base64,AAAA")
                        ]
        ]
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/ViewTextImageTest.elm`
Expected: compile error — `View.plainTextPreview` / `View.imagePane` not exposed.

- [ ] **Step 3: Add the helpers and expose them**

In `frontend/src/View.elm`, update the module declaration to also expose the helpers, e.g.:

```elm
module View exposing (view, themeName, plainTextPreview, imagePane)
```

(Keep whatever it currently exposes — add `plainTextPreview` and `imagePane`.)

Add the two top-level helpers (e.g. near `previewBody`):

```elm
{-| Preview for a non-renderable text document: show its source verbatim. -}
plainTextPreview : String -> Html msg
plainTextPreview content =
    Html.pre
        [ style "white-space" "pre-wrap"
        , style "font-family" "ui-monospace, monospace"
        , style "margin" "0"
        ]
        [ Html.text content ]


{-| The image element for an opened image document (empty src until loaded). -}
imagePane : Maybe String -> Html msg
imagePane imageSrc =
    Html.img
        [ Html.Attributes.src (Maybe.withDefault "" imageSrc)
        , style "max-width" "100%"
        , style "height" "auto"
        ]
        []
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm-test tests/ViewTextImageTest.elm`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire the helpers into the view**

In `frontend/src/View.elm`:

(a) Add a top-level `imageView` (mirrors `treeColumn` + a content pane; uses `imagePane`):

```elm
imageView : Model -> Html Msg
imageView model =
    div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
        [ treeColumn model
        , div [ style "flex" "1", style "padding" "16px", style "overflow" "auto" ]
            [ imagePane model.imageSrc ]
        ]
```

(b) In `view`, where `body` is chosen, route images first (before the `readerMode` split):

```elm
        body =
            if model.language == Just Language.Image then
                imageView model

            else if model.readerMode then
                readerView

            else
                threePaneRow
```

(c) In `previewBody`, add a `PlainText` branch before the `( Just lang, _ )` catch-all:

```elm
        ( Just Language.PlainText, _ ) ->
            [ plainTextPreview model.content ]
```

(d) Change the no-document empty-state text from `"Open a .scripta file."` to `"Open a document."`

(`readerView`'s existing `_ -> ( previewBody model, [] )` fallback already covers `PlainText` — no change needed there.)

- [ ] **Step 6: Build + full test suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test`
Expected: `Success!` and all suites pass.

- [ ] **Step 7: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/View.elm frontend/tests/ViewTextImageTest.elm
git commit -m "feat: image view + plain-text source preview"
```

---

## After All Tasks

- Final code review over the whole diff.
- **Manual verification (human, GUI):** `make build`, install over `/Applications/Scripta.app`, fully quit + relaunch. Open a vault containing a `.txt`, `.json`, `.png`, `.jpg`, a `.scripta`, and a `.md`. Confirm: text files list/open and show their source in the preview; images list and display as an image with no editor; a `.pdf` and `.git`/`.DS_Store` are not listed; `.scripta`/`.md` still render normally; markdown links to PDFs still open in Preview.
- Then use superpowers:finishing-a-development-branch.

## Notes

- `is_text_file` reads up to 8 KB per file during listing; capped, so large files aren't fully read. A binary file with no NUL byte in its first 8 KB would be mis-listed as text — acceptable per the chosen heuristic.
- `read_image` base64-encodes the whole file into the response; fine for typical KB images. Very large images produce large strings but only surface read errors, not size limits (out of scope).
- The new-file/`Inbox` placement is a separate sub-project (next), as is the deferred image-companion-`.md` idea (memory `image-companion-files`).
