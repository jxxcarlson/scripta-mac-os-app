# Sidebar Spacing + Reliable Last-Vault Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 2 mm of breathing room below the new-file input row and between adjacent sidebar buttons, and make the last-used vault reopen on launch by persisting it in a Rust-owned file instead of the packaged WebView's (non-persisting) localStorage.

**Architecture:** Sidebar spacing is pure `View.elm` CSS. Last-vault persistence moves to Rust: pure `read_last_vault`/`write_last_vault` helpers (TDD) behind `get_last_vault`/`set_last_vault` commands writing `last_vault.txt` in the app config dir. `index.html` reads the vault from Rust at boot (top-level `await`, so the inline script becomes a module) and saves via the command. The Elm layer is unchanged.

**Tech Stack:** Rust + Tauri 2 commands, `cargo test` (tempfile), Elm 0.19.1 view, vanilla JS in `index.html`.

---

## Reference (current state — verified)

- `frontend/src/View.elm` `treeColumn` (lines 19–48): three sidebar button rows are plain divs with inline, touching buttons:
  - new-file row: `div [ style "margin-top" "8px" ] [ Html.input [...new-file-name...] [], button [onClick ClickedNewFile] [text "New"], button [onClick ClickedRename] [text "Rename"] ]`
  - `div [ style "margin-top" "4px" ] [ button Delete, button "Change Vault" ]`
  - `div [ style "margin-top" "4px" ] [ button "Export HTML", button "Export LaTeX" ]`
- `src-tauri/src/fs_commands.rs`: imports `use std::path::{Path, PathBuf};` and `use tauri::Emitter;`. `take_launch_file` ends at line 271; the `#[cfg(test)] mod tests { use super::*; use std::fs; use tempfile::tempdir; ... }` block spans lines 273–409 and ends with `}` on line 409. Current `cargo test`: 13 passing.
- `src-tauri/src/lib.rs`: `invoke_handler![ fs_commands::list_workspace, ... fs_commands::take_launch_file, ]` (lines 17–29).
- `frontend/index.html`: the inline boot is a classic `<script>`. It loads after `<script src="dist/elm.js"></script>` and the vendored scripts. Boot reads flags from localStorage (lines 156–161):
  ```javascript
        function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
        const flags = {
          lastVault: lsGet('lastVault'),               // string | null
          readerMode: lsGet('readerMode') === 'true'   // bool
        };
        const app = Elm.Main.init({ node: document.getElementById('app'), flags: flags });
  ```
  The `saveLastVault` handler (lines 205–207):
  ```javascript
        app.ports.saveLastVault.subscribe((vault) => {
          try { localStorage.setItem('lastVault', vault); } catch (e) {}
        });
  ```
- Elm last-vault wiring (unchanged by this plan): `Main.openVault` emits `FileOps.saveLastVault root`; `PLaunchFile` falls back to `openVault model.initialLastVault`; `init` reads `flags.lastVault`.

**Path note:** repo root has a space — always quote. End commit messages with:
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File structure

```
src-tauri/src/fs_commands.rs   # read/write_last_vault helpers (tested) + get/set_last_vault commands
src-tauri/src/lib.rs           # register the two commands
frontend/index.html            # module + await get_last_vault flag + set_last_vault on save
frontend/src/View.elm          # sidebar button-row spacing
```

---

### Task 1: Rust last-vault persistence (TDD)

**Files:**
- Modify: `src-tauri/src/fs_commands.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Write failing tests** — add these three tests inside the `mod tests` block in `fs_commands.rs`, immediately before its closing `}` (line 409):

```rust

    #[test]
    fn last_vault_round_trips_and_creates_parent() {
        let dir = tempdir().unwrap();
        let f = dir.path().join("sub/last_vault.txt");
        write_last_vault(&f, "/Users/me/My Vault").unwrap();
        assert_eq!(read_last_vault(&f), Some("/Users/me/My Vault".to_string()));
    }

    #[test]
    fn last_vault_missing_file_is_none() {
        let dir = tempdir().unwrap();
        assert_eq!(read_last_vault(&dir.path().join("nope.txt")), None);
    }

    #[test]
    fn last_vault_whitespace_only_is_none() {
        let dir = tempdir().unwrap();
        let f = dir.path().join("last_vault.txt");
        write_last_vault(&f, "   \n").unwrap();
        assert_eq!(read_last_vault(&f), None);
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd src-tauri && cargo test 2>&1 | tail -20`
Expected: FAIL — `cannot find function read_last_vault`/`write_last_vault` in this scope (compile error).

- [ ] **Step 3: Implement helpers + commands** — in `fs_commands.rs`, add `use tauri::Manager;` next to the existing `use tauri::Emitter;` (line 5):
```rust
use tauri::Emitter;
use tauri::Manager;
```
Then add this block immediately AFTER the `take_launch_file` function (after its closing `}` on line 271, before the `#[cfg(test)]` line):
```rust

/// Read the remembered last-vault path from `file`; None if absent or blank.
pub fn read_last_vault(file: &Path) -> Option<String> {
    match std::fs::read_to_string(file) {
        Ok(s) => {
            let t = s.trim();
            if t.is_empty() {
                None
            } else {
                Some(t.to_string())
            }
        }
        Err(_) => None,
    }
}

/// Persist `vault` to `file`, creating parent directories as needed.
pub fn write_last_vault(file: &Path, vault: &str) -> std::io::Result<()> {
    if let Some(parent) = file.parent() {
        std::fs::create_dir_all(parent)?;
    }
    std::fs::write(file, vault)
}

fn last_vault_file(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let dir = app.path().app_config_dir().map_err(|e| e.to_string())?;
    Ok(dir.join("last_vault.txt"))
}

/// The remembered last-used vault path, if any.
#[tauri::command]
pub fn get_last_vault(app: tauri::AppHandle) -> Result<Option<String>, String> {
    Ok(read_last_vault(&last_vault_file(&app)?))
}

/// Remember `vault` as the last-used vault.
#[tauri::command]
pub fn set_last_vault(app: tauri::AppHandle, vault: String) -> Result<(), String> {
    write_last_vault(&last_vault_file(&app)?, &vault).map_err(|e| e.to_string())
}
```

- [ ] **Step 4: Register the commands** — in `lib.rs`, add the two commands to the `invoke_handler!` list (after `fs_commands::take_launch_file,`):
```rust
            fs_commands::take_launch_file,
            fs_commands::get_last_vault,
            fs_commands::set_last_vault,
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd src-tauri && cargo test 2>&1 | tail -20`
Expected: PASS — 16 tests (13 prior + 3 new). Also confirm `cargo build` has no warnings about unused `Manager`.

- [ ] **Step 6: Commit**

```bash
git add src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: Rust-backed last-vault persistence (get/set_last_vault commands)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: index.html — read/write the vault via Rust

**Files:**
- Modify: `frontend/index.html`

- [ ] **Step 1: Make the inline boot script a module**

Change the inline boot script's opening tag from `<script>` to `<script type="module">`. (This is the `<script>` that defines `MathText`, grabs `__TAURI__`, and boots Elm — the one immediately after `<script src="dist/elm.js"></script>`. Do NOT change the vendored `<script src=...>` tags.)

- [ ] **Step 2: Read the last vault from Rust at boot**

Replace the boot flags block:
```javascript
      function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
      const flags = {
        lastVault: lsGet('lastVault'),               // string | null
        readerMode: lsGet('readerMode') === 'true'   // bool
      };
      const app = Elm.Main.init({ node: document.getElementById('app'), flags: flags });
```
with:
```javascript
      function lsGet(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
      let lastVault = null;
      try { lastVault = await invoke('get_last_vault'); } catch (e) { lastVault = null; }
      const flags = {
        lastVault: lastVault,                        // string | null (from Rust)
        readerMode: lsGet('readerMode') === 'true'   // bool
      };
      const app = Elm.Main.init({ node: document.getElementById('app'), flags: flags });
```

- [ ] **Step 3: Save the vault via Rust**

Replace the `saveLastVault` handler:
```javascript
      app.ports.saveLastVault.subscribe((vault) => {
        try { localStorage.setItem('lastVault', vault); } catch (e) {}
      });
```
with:
```javascript
      app.ports.saveLastVault.subscribe((vault) => {
        invoke('set_last_vault', { vault: vault }).catch(() => {});
      });
```

- [ ] **Step 4: Verify wiring + build**

Run: `grep -n "type=\"module\"\|get_last_vault\|set_last_vault\|await invoke" frontend/index.html`
Expected: the module tag, the `await invoke('get_last_vault')`, and the `set_last_vault` handler all present.
Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -3`
Expected: `Success!` (Elm unchanged; confirms the app still builds).

- [ ] **Step 5: Commit**

```bash
git add frontend/index.html
git commit -m "feat: persist last vault via Rust commands instead of localStorage

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Sidebar spacing (`View.elm`)

**Files:**
- Modify: `frontend/src/View.elm`

- [ ] **Step 1: Space the new-file row (item 1 + item 2)**

Replace the new-file row's opening div attributes. Change:
```elm
               , div [ style "margin-top" "8px" ]
                    [ Html.input
```
to:
```elm
               , div [ style "margin-top" "8px", style "margin-bottom" "2mm", style "display" "flex", style "align-items" "center", style "gap" "2mm" ]
                    [ Html.input
```

- [ ] **Step 2: Space the Delete / Change-Vault row (item 2)**

Change:
```elm
               , div [ style "margin-top" "4px" ]
                    [ button [ onClick ClickedDeleteSelected ] [ text "Delete" ]
                    , button [ onClick ClickedChangeVault ] [ text "Change Vault" ]
                    ]
```
to:
```elm
               , div [ style "margin-top" "4px", style "display" "flex", style "gap" "2mm" ]
                    [ button [ onClick ClickedDeleteSelected ] [ text "Delete" ]
                    , button [ onClick ClickedChangeVault ] [ text "Change Vault" ]
                    ]
```

- [ ] **Step 3: Space the Export row (item 2)**

Change:
```elm
               , div [ style "margin-top" "4px" ]
                    [ button [ onClick ClickedExportHtml ] [ text "Export HTML" ]
                    , button [ onClick ClickedExportLatex ] [ text "Export LaTeX" ]
                    ]
```
to:
```elm
               , div [ style "margin-top" "4px", style "display" "flex", style "gap" "2mm" ]
                    [ button [ onClick ClickedExportHtml ] [ text "Export HTML" ]
                    , button [ onClick ClickedExportLatex ] [ text "Export LaTeX" ]
                    ]
```

- [ ] **Step 4: Verify build + tests**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -10` → `Success!`.
Run: `cd frontend && elm-test 2>&1 | tail -6` → 42 pass.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/View.elm
git commit -m "feat: 2mm gap below new-file row and between sidebar buttons

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Build, reinstall, manual verification

**Files:** none (build + manual).

- [ ] **Step 1: Full automated suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make test 2>&1 | tail -15`
Expected: elm-test (42) and cargo test (16) pass.

- [ ] **Step 2: Build + reinstall**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
make build 2>&1 | tail -6
SRC="src-tauri/target/release/bundle/macos/Scripta.app"
rm -rf "/Applications/Scripta.app" && ditto "$SRC" "/Applications/Scripta.app"
```

- [ ] **Step 3: Manual verification (GUI — user runs these)**

1. **Spacing:** ~2 mm gap below the new-file-name input row; ~2 mm horizontal gap between adjacent sidebar buttons (New|Rename, Delete|Change Vault, Export HTML|Export LaTeX).
2. **Last vault on launch:** open a vault, quit the app, relaunch from Launchpad (no file argument) → the same vault reopens. Open a different vault, quit, relaunch → the new one reopens (proves it tracks the latest).
3. **CLI still works:** `scripta <file>` opens that file (and its folder) as before.

- [ ] **Step 4: Commit any fixes** found during manual testing (none if all good).

---

## Self-review notes (coverage map)

- 2 mm below new-file row → Task 3 Step 1 (`margin-bottom: 2mm`).
- 2 mm between adjacent buttons → Task 3 Steps 1–3 (`display:flex; gap:2mm` on each multi-button row).
- Reopen last vault on launch (reliable) → Task 1 (Rust `get/set_last_vault` + tested helpers), Task 2 (index.html reads/writes via Rust). Elm wiring already present.

## Out of scope

- `readerMode` and per-vault open-folder persistence stay in localStorage.
- No change to the bundle identifier or the launch-file mechanism.
