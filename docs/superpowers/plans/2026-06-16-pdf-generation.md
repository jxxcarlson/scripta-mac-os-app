# PDF Generation (LaTeX → PDF) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an **Export PDF** button that compiles the open Scripta document's LaTeX export to a PDF with the installed TeX engine and saves it via the native dialog.

**Architecture:** Reuse `Export.latex` for the `.tex` source. A new async Rust command `export_pdf` writes the `.tex` to a temp dir, runs `latexmk -pdf` (PATH augmented for Finder launches), and on success opens the native Save dialog and copies the PDF out. Errors surface in the existing error banner. Elm gains an `Export PDF` button, a `ClickedExportPdf` Msg, and a `PExportPdf` op.

**Tech Stack:** Elm 0.19.1, Tauri 2 command + `std::process::Command` (latexmk), `tempfile`, `cargo test`.

---

## Reference (current state — verified)

- `frontend/src/Export.elm`: `latex : Bool -> Int -> Scripta.Document -> String`; `defaultName : Maybe String -> String -> String`.
- `frontend/src/Types.elm`: `type PendingOp = ... | PExportSave | PNoop | PLaunchFile` (lines 39–50, exposed `PendingOp(..)`); `type Msg = ... | ClickedExportHtml | ClickedExportLatex | ...` (line 59+, exposed `Msg(..)`).
- `frontend/src/Main.elm` `ClickedExportLatex` branch (lines 334–345):
  ```elm
        ClickedExportLatex ->
            case model.parsedDoc of
                Just doc ->
                    request PExportSave
                        "export_save"
                        [ ( "defaultName", E.string (Export.defaultName model.selectedPath ".tex") )
                        , ( "content", E.string (Export.latex model.isLight model.contentWidth doc) )
                        ]
                        model

                Nothing ->
                    ( model, Cmd.none )
  ```
  `PExportSave ->` handler (lines 475–477) is a no-op. The top-level `Err e ->` arm of `handleResponse` sets `model | error = Just e` (surfaced by the error banner) for ANY failing command. `Main` imports `Types exposing (Model, Msg(..), PendingOp(..))` and `Export`, `Json.Encode as E`.
- `frontend/src/View.elm` Export row (lines 43–46): `div [ style "margin-top" "4px", style "display" "flex", style "gap" "2mm" ] [ button [ onClick ClickedExportHtml ] [ text "Export HTML" ], button [ onClick ClickedExportLatex ] [ text "Export LaTeX" ] ]`.
- `src-tauri/src/fs_commands.rs`: `export_save` is an `async` `#[tauri::command]` using `tauri_plugin_dialog::DialogExt` + `blocking_save_file()`. Imports include `std::path::{Path, PathBuf}`, `tauri::Manager`. The `#[cfg(test)] mod tests { use super::*; use std::fs; use tempfile::tempdir; ... }` block ends the file. Current `cargo test`: 16.
- `src-tauri/src/lib.rs`: `invoke_handler!` ends with `fs_commands::export_save, fs_commands::take_launch_file, fs_commands::get_last_vault, fs_commands::set_last_vault,` (lines 27–30).
- `src-tauri/Cargo.toml`: `tempfile = "3"` is under `[dev-dependencies]` ONLY (not `[dependencies]`).
- Tauri maps JS arg keys (camelCase) to Rust snake_case params: Elm sends `( "defaultName", … )` → Rust `default_name` (confirmed working for `export_save`). Single-word keys (`tex`, `content`) map directly.
- MacTeX present at `/Library/TeX/texbin/` (`latexmk`, `pdflatex`, `makeindex`). GUI launches have a minimal PATH excluding it.

**Path note:** repo root has a space — always quote. End commit messages with:
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File structure

```
src-tauri/Cargo.toml         # tempfile → [dependencies]
src-tauri/src/fs_commands.rs # latex_error_summary (tested) + tex_path_env + export_pdf command
src-tauri/src/lib.rs         # register export_pdf
frontend/src/Types.elm       # ClickedExportPdf Msg + PExportPdf op
frontend/src/Main.elm        # ClickedExportPdf branch + PExportPdf handler
frontend/src/View.elm        # Export PDF button
```

---

### Task 1: Rust — `export_pdf` command + `latex_error_summary` (TDD)

**Files:**
- Modify: `src-tauri/Cargo.toml`
- Modify: `src-tauri/src/fs_commands.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Write failing tests** — add to the `mod tests` block in `fs_commands.rs`, before its closing `}`:
```rust

    #[test]
    fn latex_error_summary_extracts_bang_line() {
        let log = "noise\n! Undefined control sequence.\nl.42 \\foo\ntrailing";
        assert_eq!(
            latex_error_summary(log),
            "! Undefined control sequence.\nl.42 \\foo"
        );
    }

    #[test]
    fn latex_error_summary_falls_back_to_tail() {
        let log = "alpha\nbeta\ngamma";
        let s = latex_error_summary(log);
        assert!(!s.is_empty());
        assert!(s.contains("gamma"));
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd src-tauri && cargo test 2>&1 | tail -15`
Expected: compile FAILURE — `cannot find function latex_error_summary`.

- [ ] **Step 3: Implement `latex_error_summary`** — add to `fs_commands.rs` (e.g. just before the `#[cfg(test)]` line):
```rust

/// A concise, human-readable error from a latexmk/pdflatex run for the UI banner:
/// the first LaTeX error line ("! ...") plus the following line, else a tail of the output.
pub fn latex_error_summary(output: &str) -> String {
    let lines: Vec<&str> = output.lines().collect();
    if let Some(i) = lines.iter().position(|l| l.starts_with("! ")) {
        let mut msg = lines[i].to_string();
        if let Some(next) = lines.get(i + 1) {
            if !next.trim().is_empty() {
                msg.push('\n');
                msg.push_str(next);
            }
        }
        msg
    } else {
        let mut tail: Vec<&str> = lines.iter().rev().take(8).cloned().collect();
        tail.reverse();
        tail.join("\n")
    }
}
```

- [ ] **Step 4: Run to verify the helper passes**

Run: `cd src-tauri && cargo test latex_error_summary 2>&1 | tail -10`
Expected: 2 new tests pass.

- [ ] **Step 5: Make `tempfile` a normal dependency** — in `src-tauri/Cargo.toml`, add `tempfile = "3"` under `[dependencies]` (leave the `[dev-dependencies]` entry as-is):
```toml
[dependencies]
tauri = { version = "2", features = [] }
tempfile = "3"
```
(Add the `tempfile` line; keep all other existing `[dependencies]` lines unchanged.)

- [ ] **Step 6: Add `tex_path_env` + the `export_pdf` command** — add to `fs_commands.rs` (after `latex_error_summary`, before the tests):
```rust

/// PATH for invoking TeX tools, augmented with common install dirs so the engine
/// resolves even when the app is launched from Finder (minimal PATH).
fn tex_path_env() -> String {
    let extra = "/Library/TeX/texbin:/usr/local/bin:/opt/homebrew/bin";
    match std::env::var("PATH") {
        Ok(p) if !p.is_empty() => format!("{extra}:{p}"),
        _ => extra.to_string(),
    }
}

/// Compile the given LaTeX source to PDF with latexmk, then save via a dialog.
#[tauri::command]
pub async fn export_pdf(
    app: tauri::AppHandle,
    default_name: String,
    tex: String,
) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;

    let dir = tempfile::tempdir().map_err(|e| e.to_string())?;
    let tex_path = dir.path().join("document.tex");
    std::fs::write(&tex_path, &tex).map_err(|e| e.to_string())?;

    let out = std::process::Command::new("latexmk")
        .args(["-pdf", "-interaction=nonstopmode", "-halt-on-error", "document.tex"])
        .current_dir(dir.path())
        .env("PATH", tex_path_env())
        .output()
        .map_err(|e| format!("Could not run latexmk (is MacTeX installed?): {e}"))?;

    let pdf_path = dir.path().join("document.pdf");
    if !pdf_path.exists() {
        let combined = format!(
            "{}\n{}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        );
        return Err(format!("PDF generation failed:\n{}", latex_error_summary(&combined)));
    }

    let chosen = app
        .dialog()
        .file()
        .set_file_name(&default_name)
        .blocking_save_file();
    match chosen {
        Some(path) => {
            let dest = path.into_path().map_err(|e| e.to_string())?;
            std::fs::copy(&pdf_path, &dest).map_err(|e| e.to_string())?;
            Ok(Some(dest.to_string_lossy().to_string()))
        }
        None => Ok(None),
    }
}
```

- [ ] **Step 7: Register the command** — in `src-tauri/src/lib.rs`, add to the `invoke_handler!` list after `fs_commands::set_last_vault,`:
```rust
            fs_commands::set_last_vault,
            fs_commands::export_pdf,
```

- [ ] **Step 8: Build + full test run**

Run: `cd src-tauri && cargo build 2>&1 | tail -15` → no errors, no warnings.
Run: `cd src-tauri && cargo test 2>&1 | tail -8` → 18 passed (16 prior + 2 new).

- [ ] **Step 9: Commit**

```bash
git add src-tauri/Cargo.toml src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: export_pdf command (latexmk LaTeX->PDF) + latex_error_summary

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Elm — Export PDF wiring

**Files:**
- Modify: `frontend/src/Types.elm`
- Modify: `frontend/src/Main.elm`
- Modify: `frontend/src/View.elm`

- [ ] **Step 1: Types.elm — add the op and the Msg**

In `type PendingOp`, add after `| PExportSave`:
```elm
    | PExportPdf
```
In `type Msg`, add after `| ClickedExportLatex`:
```elm
    | ClickedExportPdf
```

- [ ] **Step 2: Main.elm — `ClickedExportPdf` update branch**

Add this branch immediately after the `ClickedExportLatex -> …` branch:
```elm
        ClickedExportPdf ->
            case model.parsedDoc of
                Just doc ->
                    request PExportPdf
                        "export_pdf"
                        [ ( "defaultName", E.string (Export.defaultName model.selectedPath ".pdf") )
                        , ( "tex", E.string (Export.latex model.isLight model.contentWidth doc) )
                        ]
                        model

                Nothing ->
                    ( model, Cmd.none )
```

- [ ] **Step 3: Main.elm — `PExportPdf` response handler**

Add this branch immediately after the `PExportSave -> …` branch in `handleResponse`:
```elm
                PExportPdf ->
                    -- PDF written by the native save dialog; errors surface via the Err arm.
                    ( model, Cmd.none )
```

- [ ] **Step 4: View.elm — Export PDF button**

In the Export row, add a third button after Export LaTeX. Change:
```elm
                    [ button [ onClick ClickedExportHtml ] [ text "Export HTML" ]
                    , button [ onClick ClickedExportLatex ] [ text "Export LaTeX" ]
                    ]
```
to:
```elm
                    [ button [ onClick ClickedExportHtml ] [ text "Export HTML" ]
                    , button [ onClick ClickedExportLatex ] [ text "Export LaTeX" ]
                    , button [ onClick ClickedExportPdf ] [ text "Export PDF" ]
                    ]
```

- [ ] **Step 5: Verify build + tests**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -20` → `Success!`.
Run: `cd frontend && elm-test 2>&1 | tail -6` → 42 pass.

- [ ] **Step 6: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm
git commit -m "feat: Export PDF button wired to export_pdf command

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Build, reinstall, manual verification

**Files:** none (build + manual).

- [ ] **Step 1: Full automated suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make test 2>&1 | tail -15`
Expected: elm-test (42) and cargo test (18) pass.

- [ ] **Step 2: Build + reinstall**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
make build 2>&1 | tail -6
SRC="src-tauri/target/release/bundle/macos/Scripta.app"
rm -rf "/Applications/Scripta.app" && ditto "$SRC" "/Applications/Scripta.app"
```

- [ ] **Step 3: Manual verification (GUI — user runs these)**

1. Open a Scripta document, click **Export PDF** → after a few seconds the Save dialog appears; choose a location → a valid `.pdf` is written and opens.
2. Open a document that fails to compile (e.g. malformed math) → a red error banner shows a concise `! …` LaTeX error and NO save dialog appears.
3. **Export HTML** and **Export LaTeX** still work unchanged.

- [ ] **Step 4: Commit any fixes** found during manual testing (none if all good).

---

## Self-review notes (coverage map)

- Export PDF button → Task 2 Step 4.
- LaTeX → PDF compile (latexmk, PATH-augmented, temp dir) → Task 1 Step 6 (`export_pdf`).
- Compile-first then Save dialog; errors to banner → Task 1 (`export_pdf` returns Err on no-PDF) + Main `Err` arm (existing) + Task 2 Step 3.
- `latex_error_summary` tested helper → Task 1 Steps 1–4.
- `tempfile` as a normal dependency → Task 1 Step 5.

## Out of scope

- Auto-opening the PDF after saving; bundling a TeX engine; relative-path images; a progress UI.
