# Source-Line-Aware PDF Error Report — Design Spec

**Date:** 2026-06-16

## Goal

When `export_pdf` fails to produce a PDF, show a useful, **source-line-annotated** error report
in an in-app panel — replacing the terse one-line error — by parsing the LaTeX `.log` and mapping
each error back to its **Scripta source line** via the `%%% Line N` markers already embedded in the
generated LaTeX. This mirrors the v4 web-app / pdfServer2 mechanism, adapted to a local app.

## Current state (verified)

- `src-tauri/src/fs_commands.rs` `export_pdf` (async): writes `document.tex` to a temp dir, runs
  `latexmk -xelatex -interaction=nonstopmode -halt-on-error document.tex` (PATH-augmented), then:
  - if `document.pdf` is missing → `Err(format!("PDF generation failed:\n{}", latex_error_summary(&combined)))`
    where `combined` is stdout+stderr.
  - else → native Save dialog → copy → `Ok(Some/None)`.
  `latex_error_summary(output)` already extracts the first `! …` error + the `l.<n>` location line.
  `latexmk` writes `document.log` (and `document.tex`) into the same temp dir.
- The vendored compiler emits `%%% Line N` markers before each block's LaTeX
  (`frontend/scripta-compiler/Render/Export/LaTeX.elm:322`, `annotateWithLineNumber`; `N` = Scripta
  source line, `> 0`). LaTeX's `l.<N>` log lines reference the **`.tex`** input line number.
- `frontend/src/View.elm`: `errorBanner model` renders `model.error` as a one-line div, and is
  called **inside `treeColumn`** (the 260px sidebar). `view` ends with
  `div [...] (conflictBanner model ++ [ toolbar, body ])`. The generic `Err e ->` arm of
  `Main.handleResponse` sets `model.error = Just e`, so the report string flows there.

## Design

### 1. Rust: parse the log into source-annotated errors (`fs_commands.rs`)

Pure, tested helpers (no Tauri deps):

```rust
pub struct LatexError {
    pub source_line: Option<u32>, // Scripta source line (via %%% Line marker)
    pub latex_line: Option<u32>,  // .tex input line (from "l.<n>")
    pub message: String,          // e.g. "Missing $ inserted."
    pub snippet: String,          // offending LaTeX text at the error point
}

/// Parse a latexmk/xelatex log + the .tex source into structured errors.
pub fn latex_errors(log: &str, tex: &str) -> Vec<LatexError>
```

Algorithm:
- Collect `tex` lines. `source_line_for(n)` = scan `.tex` lines `1..=n` for the **last** line matching
  `^%%% Line (\d+)` and return that number (else `None`).
- Walk the log. For each line starting with `"! "`:
  - `message` = that line (kept verbatim, e.g. `! Missing $ inserted.`).
  - Look ahead (next ~10 lines) for the first line matching `^l\.(\d+)\b` → `latex_line = n`, and
    `snippet` = the remainder of that `l.<n>` line (the source up to the error point), trimmed.
  - `source_line = source_line_for(latex_line)`.
  - push the `LatexError`.
- Only `"! "` lines start an error (warnings/`Overfull`/font-info are ignored), which inherently
  filters boilerplate; the `^l\.` anchor (not mid-line `l.`) avoids the v4 false-positive.

```rust
/// Human-readable report for the in-app panel. Empty input → "" (caller falls back).
pub fn format_error_report(errors: &[LatexError]) -> String
```
Format:
```
PDF generation failed — 2 errors:

• Source line 17: Missing $ inserted.
    s^2 = 2GM/c
• Source line 23: Undefined control sequence.
    \foo
```
Each bullet shows `Source line K` when known, else `LaTeX line N`, else just the message; the
`snippet` line is omitted when empty.

`export_pdf` failure path becomes:
```rust
if !pdf_path.exists() {
    let log = std::fs::read_to_string(dir.path().join("document.log")).unwrap_or_default();
    let errors = latex_errors(&log, &tex);
    let report =
        if errors.is_empty() {
            let combined = format!("{}\n{}",
                String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
            format!("PDF generation failed:\n{}", latex_error_summary(&combined))
        } else {
            format_error_report(&errors)
        };
    return Err(report);
}
```
`latex_error_summary` is retained as the fallback.

### 2. Elm/View: full-width, readable error panel

The report is multi-line, so render it as a **full-width panel at the top of the window** instead of
in the narrow sidebar:
- In `view`, change the final element to `div [...] (conflictBanner model ++ errorBanner model ++ [ toolbar, body ])`.
- Remove the `errorBanner model` call from `treeColumn`.
- Restyle `errorBanner`'s div: `background:#fee`, `color:#900`, `padding:8px`,
  `border-bottom:1px solid #c99`, `font-family: ui-monospace, monospace`, `font-size:12px`,
  `white-space: pre-wrap`, `max-height: 35vh`, `overflow:auto`, `cursor:pointer`, `onClick DismissError`.
  Keep a trailing "(click to dismiss)" hint. The error text already contains newlines and renders
  legibly with `pre-wrap`.

No `Msg`/`Model` changes — `model.error` and `DismissError` already exist.

## Files touched

- `src-tauri/src/fs_commands.rs` — `LatexError`, `latex_errors`, `format_error_report`; `export_pdf`
  reads `document.log` and returns the report on failure.
- `frontend/src/View.elm` — relocate + restyle `errorBanner` as a top, full-width, scrollable panel.

## Testing

- **TDD (Rust)** for `latex_errors` / `format_error_report`:
  - A `.tex` with `%%% Line 5\n...` and a log with `! Missing $ inserted.` … `l.7 s^2 = 2GM/c` →
    one error with `source_line = Some(5)`, `message` containing "Missing $ inserted", `snippet`
    containing `s^2`.
  - Two `! …` errors → two records, each mapped to the nearest preceding marker.
  - A log error whose `.tex` line has no preceding `%%% Line` marker → `source_line = None`
    (report shows `LaTeX line N`).
  - `format_error_report(&[])` → `""`.
  - Boilerplate-only log (no `! ` lines) → `latex_errors` returns empty.
- `cargo test` rises from 19; `elm-test` stays at 42. Panel styling is view-only (build + manual).

## Manual checklist

1. Export a doc with a deliberate LaTeX error (e.g. a bare `s^` outside math) → a top panel appears
   listing the error with its **Scripta source line** and the offending snippet; no Save dialog.
2. A doc whose log has no parseable `! …` error → panel falls back to the `latex_error_summary` text.
3. A clean doc → PDF saved as before (no panel).
4. The panel is click-to-dismiss; long/multi-error reports scroll.

## Decisions / out of scope

- Only the **no-PDF hard-failure** path is enriched. The "partial PDF + errors" case (xelatex exits
  nonzero but still emits a PDF) keeps current behavior (the PDF is saved).
- In-app panel only — no error `.txt`/`.pdf` artifact, no JSON schema matching v4.
- The report is plain text (source line + message + snippet); not the full filtered log.
