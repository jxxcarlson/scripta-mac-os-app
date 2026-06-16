# PDF Generation (LaTeX → PDF) — Design Spec

**Date:** 2026-06-16

## Goal

Add an **Export PDF** action that turns the open Scripta document into a PDF by compiling the
existing LaTeX export with the installed TeX engine, then saving via the native dialog.

## Current state (verified)

- `frontend/src/Export.elm`: `latex : Bool -> Int -> Scripta.Document -> String` produces a full
  standalone `.tex` document; `defaultName : Maybe String -> String -> String` derives an export
  filename from `selectedPath` + extension.
- `frontend/src/Main.elm`: `ClickedExportHtml` / `ClickedExportLatex` issue
  `request PExportSave "export_save" [ ("defaultName", …), ("content", …) ]`. `handleResponse`'s
  `Err e ->` arm already sets `model.error` (shown by the existing error banner). The `Msg` `case`
  has no `_ ->` wildcard, so a new Msg needs its own branch.
- `frontend/src/View.elm` `treeColumn`: the Export row is
  `div [ style "margin-top" "4px", style "display" "flex", style "gap" "2mm" ] [ button [ onClick ClickedExportHtml ] [ text "Export HTML" ], button [ onClick ClickedExportLatex ] [ text "Export LaTeX" ] ]`.
- `frontend/src/FileOps.elm`: requests go through `send`/`fsRequest`; a Rust `#[tauri::command]`
  named `export_pdf` is invoked by command name (the `op` field), matching the existing
  `export_save` pattern.
- `src-tauri/src/fs_commands.rs`: `export_save(app, default_name, content)` is an `async` command
  using `tauri_plugin_dialog::DialogExt` `blocking_save_file()` then `std::fs::write`. Imports
  include `std::path::{Path, PathBuf}`, `tauri::Manager`. Tests use `tempfile::tempdir`.
- The Scripta LaTeX preamble (`scripta-compiler/Render/Export/Preamble.elm`) uses
  `\documentclass{article|book}`, `[T1]{fontenc}`, `lmodern`, `hyperref`, `imakeidx`/`makeidx`,
  `geometry`, `graphicx`, `amsmath`, `mhchem`, etc. — a **pdflatex** setup that needs **multiple
  passes + makeindex** (TOC, `hyperref` refs, index).
- MacTeX is installed at `/Library/TeX/texbin/` (`latexmk`, `pdflatex`, `makeindex`, …). A GUI app
  launched from Finder has a minimal `PATH` that typically excludes `/Library/TeX/texbin`.

## Design

### UX

Add an **Export PDF** button to the Export row in `treeColumn`, after Export LaTeX. Clicking it:
generates the LaTeX (`Export.latex`), compiles to PDF, and on success opens the native Save dialog
for the `.pdf`. On a compile error the existing red error banner shows a concise message and **no**
save dialog appears. Compilation takes a few seconds and runs off the UI thread (Tauri command
thread pool).

### Elm

- `Types.elm`: add `ClickedExportPdf` to `Msg` and `PExportPdf` to `PendingOp`.
- `View.elm`: add `button [ onClick ClickedExportPdf ] [ text "Export PDF" ]` to the Export row.
- `Main.elm`: add the `ClickedExportPdf` `update` branch (parallel to `ClickedExportLatex`):
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
  (Match the exact shape of the existing `ClickedExportLatex` branch, including its `case model.parsedDoc of`.)
- `handleResponse` `PExportPdf` branch: success/cancel are no-ops; errors are already surfaced by the
  generic `Err e ->` arm, so:
  ```elm
                PExportPdf ->
                    ( model, Cmd.none )
  ```

### Rust (`fs_commands.rs`)

Add a pure, tested helper and an async command:

```rust
/// A concise, human-readable error from a latexmk/pdflatex run for the UI banner:
/// the first LaTeX error line ("! ...") plus the line after it, else a tail of the output.
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
        let tail: Vec<&str> = lines.iter().rev().take(8).cloned().collect();
        let mut t = tail;
        t.reverse();
        t.join("\n")
    }
}

/// PATH for invoking TeX tools, augmented with common install dirs so the engine
/// resolves even when the app is launched from Finder (minimal PATH).
fn tex_path_env() -> String {
    let extra = "/Library/TeX/texbin:/usr/local/bin:/opt/homebrew/bin";
    match std::env::var("PATH") {
        Ok(p) if !p.is_empty() => format!("{extra}:{p}"),
        _ => extra.to_string(),
    }
}

#[tauri::command]
pub async fn export_pdf(
    app: tauri::AppHandle,
    default_name: String,
    tex: String,
) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;

    // 1. temp dir + write document.tex
    let dir = tempfile::tempdir().map_err(|e| e.to_string())?;
    let tex_path = dir.path().join("document.tex");
    std::fs::write(&tex_path, &tex).map_err(|e| e.to_string())?;

    // 2. latexmk -pdf in the temp dir, PATH augmented for Finder launches
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

    // 3. compile succeeded → native Save dialog → copy the PDF to the chosen path
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
Register `fs_commands::export_pdf` in `lib.rs`'s `invoke_handler!`.

`tempfile` is currently in `[dev-dependencies]` only (verified), so `export_pdf` would not compile.
Add `tempfile = "3"` to `[dependencies]` in `src-tauri/Cargo.toml` (it can stay listed under
dev-dependencies too, but the normal dependency is what matters).

### Testing

- **TDD (Rust)** for `latex_error_summary`:
  - a log containing `! Undefined control sequence.` + the next line → returns those two lines.
  - a log with no `! ` line → returns a tail of the output (non-empty).
- The compile + dialog path is integration/manual: Export PDF on a real document → a PDF is written
  and opens; a deliberately broken document (e.g. an unbalanced math environment) → the error banner
  shows a concise `! …` message and no save dialog.
- `elm-test` stays at 42; `cargo test` rises from 16 with the new `latex_error_summary` cases.

### Manual checklist

1. Open a Scripta doc, click **Export PDF** → after a few seconds the Save dialog appears; saving
   produces a valid PDF.
2. A document that fails to compile → red error banner with a concise LaTeX error; no save dialog.
3. Export HTML / Export LaTeX still work unchanged.

## Decisions / out of scope

- **Engine:** `latexmk -pdf` (orchestrates pdflatex passes + makeindex; preamble is pdflatex-style).
- **Compile-first, then prompt** — a failed compile never shows a save dialog.
- **No auto-open** of the PDF after saving.
- Relies on an installed TeX engine (MacTeX); a missing engine yields a clear error rather than
  bundling TeX.
- Images referenced by relative path may not resolve from the temp dir (acceptable for v1).
- No progress UI during compilation beyond it running off the UI thread.
