# Source-Line-Aware PDF Error Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When PDF generation fails, show a source-line-annotated error report (each LaTeX error mapped to its Scripta source line) in a full-width in-app panel, instead of a terse one-liner.

**Architecture:** A pure, tested Rust parser reads `export_pdf`'s `document.log` + `document.tex` (which carries `%%% Line N` markers), extracts each `! …` error with its `l.<n>` LaTeX line + snippet, and maps it to the Scripta source line via the nearest preceding marker. `export_pdf` returns that report on the no-PDF failure path (falling back to `latex_error_summary`). The Elm error banner is relocated to the top of the window and styled as a scrollable monospace panel.

**Tech Stack:** Rust (`std::fs`, `std::process`), `cargo test`; Elm 0.19.1 view.

---

## Reference (current state — verified)

- `src-tauri/src/fs_commands.rs` `export_pdf` (async): writes `document.tex` to a temp dir, runs `latexmk -xelatex …`, then the no-PDF failure block is:
  ```rust
      let pdf_path = dir.path().join("document.pdf");
      if !pdf_path.exists() {
          let combined = format!(
              "{}\n{}",
              String::from_utf8_lossy(&out.stdout),
              String::from_utf8_lossy(&out.stderr)
          );
          return Err(format!("PDF generation failed:\n{}", latex_error_summary(&combined)));
      }
  ```
  `latexmk` writes `document.log` into the same temp dir. `latex_error_summary(output)` already exists. The `#[cfg(test)] mod tests { use super::*; use std::fs; use tempfile::tempdir; … }` block ends the file. Current `cargo test`: 19.
- The vendored compiler emits `%%% Line N` (N = Scripta source line) before each block's LaTeX. LaTeX `l.<N>` log lines reference the `.tex` input line number.
- `frontend/src/View.elm`:
  - `treeColumn` (lines 22–25): `(button [ onClick ClickedOpenVault ] [ text "Open Vault" ]` then `:: errorBanner model` then `++ [ searchBox model, …`.
  - `view` ends (line 151): `(conflictBanner model ++ [ toolbar, body ])`.
  - `errorBanner` (line ~181):
    ```elm
    errorBanner : Model -> List (Html Msg)
    errorBanner model =
        case model.error of
            Just e ->
                [ div
                    [ style "background" "#fee", style "color" "#900", style "padding" "6px", onClick DismissError ]
                    [ text ("Error: " ++ e ++ " (click to dismiss)") ]
                ]

            Nothing ->
                []
    ```
  `model.error : Maybe String` and `DismissError` already exist.

**Path note:** repo root has a space — always quote. End commit messages with:
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File structure

```
src-tauri/src/fs_commands.rs  # LatexError + latex_errors + format_error_report (tested); export_pdf uses them
frontend/src/View.elm         # relocate errorBanner to top; style as scrollable monospace panel
```

---

### Task 1: Rust — parse log into source-annotated error report (TDD)

**Files:**
- Modify: `src-tauri/src/fs_commands.rs`

- [ ] **Step 1: Write failing tests** — add to the `mod tests` block (before its closing `}`):

```rust

    #[test]
    fn latex_errors_maps_to_source_line() {
        let tex = "preamble\n%%% Line 5\n\\section{X}\nbody\nmore\nmore\n$s^2$\n";
        let log = "junk\n! Missing $ inserted.\n<inserted text>\nl.7 $s^2 = 2GM/c\n           more\n";
        let errs = latex_errors(log, tex);
        assert_eq!(errs.len(), 1);
        assert_eq!(errs[0].source_line, Some(5));
        assert_eq!(errs[0].latex_line, Some(7));
        assert!(errs[0].message.contains("Missing $ inserted"));
        assert!(errs[0].snippet.contains("s^2"));
    }

    #[test]
    fn latex_errors_two_errors_map_to_nearest_marker() {
        let tex = "%%% Line 1\na\n%%% Line 9\nb\n";
        let log = "! First bad.\nl.2 a\n! Second bad.\nl.4 b\n";
        let errs = latex_errors(log, tex);
        assert_eq!(errs.len(), 2);
        assert_eq!(errs[0].source_line, Some(1));
        assert_eq!(errs[1].source_line, Some(9));
    }

    #[test]
    fn latex_errors_no_marker_gives_none() {
        let errs = latex_errors("! Bad.\nl.2 b\n", "a\nb\nc\n");
        assert_eq!(errs[0].source_line, None);
        assert_eq!(errs[0].latex_line, Some(2));
    }

    #[test]
    fn latex_errors_ignores_boilerplate() {
        let log = "LaTeX Font Info: blah\n(/usr/local/texlive/x.sty)\nOverfull \\hbox\n";
        assert!(latex_errors(log, "x\n").is_empty());
    }

    #[test]
    fn format_error_report_empty_is_blank() {
        assert_eq!(format_error_report(&[]), "");
    }

    #[test]
    fn format_error_report_renders_source_line_and_snippet() {
        let errs = vec![LatexError {
            source_line: Some(17),
            latex_line: Some(7),
            message: "Missing $ inserted.".to_string(),
            snippet: "s^2".to_string(),
        }];
        let r = format_error_report(&errs);
        assert!(r.contains("Source line 17"));
        assert!(r.contains("Missing $ inserted."));
        assert!(r.contains("s^2"));
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd src-tauri && cargo test 2>&1 | tail -15`
Expected: compile FAILURE — `cannot find type LatexError` / `function latex_errors` / `format_error_report`.

- [ ] **Step 3: Implement the parser** — add to `fs_commands.rs` just before the `#[cfg(test)]` line:

```rust

/// A single LaTeX error, mapped back to the Scripta source where possible.
#[derive(Debug, PartialEq)]
pub struct LatexError {
    pub source_line: Option<u32>, // Scripta source line (via %%% Line marker)
    pub latex_line: Option<u32>,  // .tex input line (from "l.<n>")
    pub message: String,          // e.g. "Missing $ inserted."
    pub snippet: String,          // offending LaTeX text at the error point
}

/// Scripta source line for `.tex` input line `n` (1-based): the last `%%% Line K`
/// marker at or before line `n`.
fn source_line_for(tex_lines: &[&str], n: u32) -> Option<u32> {
    let upto = (n as usize).min(tex_lines.len());
    tex_lines[..upto]
        .iter()
        .rev()
        .find_map(|l| l.strip_prefix("%%% Line ").and_then(|s| s.trim().parse::<u32>().ok()))
}

/// Parse a latexmk/xelatex log + the `.tex` source into structured errors. Each
/// `! …` line starts an error; the following `l.<n> …` line gives the `.tex`
/// line and the offending snippet; `%%% Line` markers map it to the source line.
pub fn latex_errors(log: &str, tex: &str) -> Vec<LatexError> {
    let tex_lines: Vec<&str> = tex.lines().collect();
    let log_lines: Vec<&str> = log.lines().collect();
    let mut errors = Vec::new();
    let mut i = 0;
    while i < log_lines.len() {
        if let Some(msg) = log_lines[i].strip_prefix("! ") {
            let message = msg.trim().to_string();
            let mut latex_line = None;
            let mut snippet = String::new();
            let mut j = i + 1;
            while j < log_lines.len() && j < i + 12 {
                if let Some(rest) = log_lines[j].strip_prefix("l.") {
                    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
                    if let Ok(n) = digits.parse::<u32>() {
                        latex_line = Some(n);
                        snippet = rest[digits.len()..].trim().to_string();
                        break;
                    }
                }
                j += 1;
            }
            let source_line = latex_line.and_then(|n| source_line_for(&tex_lines, n));
            errors.push(LatexError { source_line, latex_line, message, snippet });
            i = j + 1;
        } else {
            i += 1;
        }
    }
    errors
}

/// Human-readable report for the in-app panel; "" when there are no errors.
pub fn format_error_report(errors: &[LatexError]) -> String {
    if errors.is_empty() {
        return String::new();
    }
    let n = errors.len();
    let mut report = format!(
        "PDF generation failed — {} error{}:\n",
        n,
        if n == 1 { "" } else { "s" }
    );
    for e in errors {
        let loc = match (e.source_line, e.latex_line) {
            (Some(s), _) => format!("Source line {}", s),
            (None, Some(l)) => format!("LaTeX line {}", l),
            (None, None) => "Error".to_string(),
        };
        report.push_str(&format!("\n• {}: {}", loc, e.message));
        if !e.snippet.is_empty() {
            report.push_str(&format!("\n    {}", e.snippet));
        }
    }
    report
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd src-tauri && cargo test 2>&1 | tail -8`
Expected: 25 passed (19 prior + 6 new).

- [ ] **Step 5: Wire into `export_pdf`** — replace the no-PDF failure block:
```rust
    let pdf_path = dir.path().join("document.pdf");
    if !pdf_path.exists() {
        let combined = format!(
            "{}\n{}",
            String::from_utf8_lossy(&out.stdout),
            String::from_utf8_lossy(&out.stderr)
        );
        return Err(format!("PDF generation failed:\n{}", latex_error_summary(&combined)));
    }
```
with:
```rust
    let pdf_path = dir.path().join("document.pdf");
    if !pdf_path.exists() {
        let log = std::fs::read_to_string(dir.path().join("document.log")).unwrap_or_default();
        let errors = latex_errors(&log, &tex);
        return Err(if errors.is_empty() {
            let combined = format!(
                "{}\n{}",
                String::from_utf8_lossy(&out.stdout),
                String::from_utf8_lossy(&out.stderr)
            );
            format!("PDF generation failed:\n{}", latex_error_summary(&combined))
        } else {
            format_error_report(&errors)
        });
    }
```

- [ ] **Step 6: Build + test**

Run: `cd src-tauri && cargo build 2>&1 | tail -10` → no errors/warnings.
Run: `cd src-tauri && cargo test 2>&1 | tail -6` → 25 passed.

- [ ] **Step 7: Commit**

```bash
git add src-tauri/src/fs_commands.rs
git commit -m "feat: source-line-aware PDF error report (latex_errors + format_error_report)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Elm — relocate + style the error panel

**Files:**
- Modify: `frontend/src/View.elm`

- [ ] **Step 1: Remove `errorBanner` from the sidebar (`treeColumn`)**

Change:
```elm
        (button [ onClick ClickedOpenVault ] [ text "Open Vault" ]
            :: errorBanner model
            ++ [ searchBox model
```
to:
```elm
        (button [ onClick ClickedOpenVault ] [ text "Open Vault" ]
            :: [ searchBox model
```

- [ ] **Step 2: Render `errorBanner` full-width at the top**

Change the final expression of `view`:
```elm
        (conflictBanner model ++ [ toolbar, body ])
```
to:
```elm
        (conflictBanner model ++ errorBanner model ++ [ toolbar, body ])
```

- [ ] **Step 3: Restyle `errorBanner` as a scrollable monospace panel**

Replace the whole `errorBanner` function with:
```elm
errorBanner : Model -> List (Html Msg)
errorBanner model =
    case model.error of
        Just e ->
            [ div
                [ style "background" "#fee"
                , style "color" "#900"
                , style "padding" "8px"
                , style "border-bottom" "1px solid #c99"
                , style "font-family" "ui-monospace, monospace"
                , style "font-size" "12px"
                , style "white-space" "pre-wrap"
                , style "max-height" "35vh"
                , style "overflow" "auto"
                , style "cursor" "pointer"
                , onClick DismissError
                ]
                [ text (e ++ "\n\n(click to dismiss)") ]
            ]

        Nothing ->
            []
```

- [ ] **Step 4: Verify build + tests**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -10` → `Success!`.
Run: `cd frontend && elm-test 2>&1 | tail -6` → 42 pass.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/View.elm
git commit -m "feat: full-width scrollable error panel for PDF (and other) errors

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Build, reinstall, manual verification

**Files:** none (build + manual).

- [ ] **Step 1: Full automated suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make test 2>&1 | tail -15`
Expected: elm-test (42) and cargo test (25) pass.

- [ ] **Step 2: Build + reinstall**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
make build 2>&1 | tail -6
SRC="src-tauri/target/release/bundle/macos/Scripta.app"
rm -rf "/Applications/Scripta.app" && ditto "$SRC" "/Applications/Scripta.app"
```

- [ ] **Step 3: Manual verification (GUI — user runs these)**

1. Open a document with a deliberate LaTeX error (e.g. a bare `s^` outside math), click **Export PDF** → a full-width red panel appears at the top listing the error with its **Scripta source line** and the offending snippet; no Save dialog.
2. The panel scrolls for long/multi-error reports and dismisses on click.
3. A clean document → PDF saves normally (no panel).
4. A non-PDF error (e.g. a failed file op) still shows in the same top panel.

- [ ] **Step 4: Commit any fixes** found during manual testing (none if all good).

---

## Self-review notes (coverage map)

- Parse log → source-annotated errors → Task 1 (`latex_errors`, `source_line_for`, tested).
- `%%% Line` concordance (LaTeX line → Scripta line) → Task 1 (`source_line_for`).
- Report on no-PDF failure, fallback to `latex_error_summary` → Task 1 Step 5.
- Full-width scrollable monospace panel → Task 2 (relocate + restyle `errorBanner`).

## Out of scope

- The "partial PDF + errors" case (xelatex exits nonzero but emits a PDF) — current behavior keeps saving the PDF.
- Error `.txt`/`.pdf` artifacts or matching v4's JSON schema.
