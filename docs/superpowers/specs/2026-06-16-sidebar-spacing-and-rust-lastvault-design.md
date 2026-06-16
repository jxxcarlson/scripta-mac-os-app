# Sidebar Spacing + Reliable Last-Vault Persistence — Design Spec

**Date:** 2026-06-16

## Goal

1. **2 mm below the new-file-name input row** in the sidebar.
2. **2 mm horizontal gap between adjacent sidebar buttons.**
3. **Reopen the last-used vault on launch** — currently broken because the vault is stored in the
   packaged WebView's localStorage, which does not persist across app launches. Move the persistence
   to a Rust-owned file so it survives relaunch.

## Current state (verified)

- `frontend/src/View.elm` `treeColumn` (lines 19–48): the sidebar is a `div` containing the
  "Open Vault" button, search box, file tree, a save-status line, then three plain `div` rows:
  - new-file row: `div [ style "margin-top" "8px" ] [ Html.input [...new-file-name...] [], button New, button Rename ]`
  - `div [ style "margin-top" "4px" ] [ button Delete, button "Change Vault" ]`
  - `div [ style "margin-top" "4px" ] [ button "Export HTML", button "Export LaTeX" ]`
  Buttons within a row are inline and touching (no gap).
- Last-vault persistence (built earlier, working logic / failing storage):
  - `Main.openVault` emits `FileOps.saveLastVault root`; `PLaunchFile` falls back to
    `openVault model.initialLastVault` on a plain launch; `init` reads `flags.lastVault` via
    `Flags.decode`.
  - `frontend/index.html` (classic inline `<script>`): boot reads `lastVault` from localStorage
    (`lsGet('lastVault')`, lines 156–161) and passes it as a flag; the `saveLastVault` port handler
    writes localStorage (lines 205–207).
  - The launch logic is correct (`take_launch_file` returns `None` on a plain launch → last-vault
    branch), so the failure is storage: localStorage is not persisting across launches in the
    packaged app, so `lastVault` is `null` at boot and no vault opens.
- `src-tauri/src/fs_commands.rs`: imports `std::path::{Path, PathBuf}`, `tauri::Emitter`; the `tests`
  module uses `tempfile::tempdir` and `std::fs`. Commands are plain `#[tauri::command]` fns.
  Current `cargo test` count: 13.
- `src-tauri/src/lib.rs`: `invoke_handler![ ... fs_commands::take_launch_file, ]` (lines 17–29).

## Design

### 1 & 2. Sidebar spacing (`View.elm` `treeColumn`)

Add flex + gap to the three button rows, and a bottom margin to the new-file row:

- New-file row: `div [ style "margin-top" "8px", style "margin-bottom" "2mm", style "display" "flex", style "align-items" "center", style "gap" "2mm" ] [ Html.input [...] [], button New, button Rename ]`
  (the `margin-bottom: 2mm` is item 1; the `gap: 2mm` spaces the input and buttons — item 2).
- Delete/Change-Vault row: `div [ style "margin-top" "4px", style "display" "flex", style "gap" "2mm" ] [...]`.
- Export row: `div [ style "margin-top" "4px", style "display" "flex", style "gap" "2mm" ] [...]`.

"Open Vault" stays solo (no adjacent button). No other layout changes.

### 3. Last-vault persistence moves to Rust

Replace localStorage-backed `lastVault` with a Rust-owned file, leaving the entire Elm layer
unchanged (it already round-trips `lastVault` through flags + the `saveLastVault` port).

**Rust (`fs_commands.rs`)** — pure, tested helpers plus thin command wrappers:
```rust
/// Read the remembered last-vault path from `file`; None if absent/empty.
pub fn read_last_vault(file: &Path) -> Option<String> {
    match std::fs::read_to_string(file) {
        Ok(s) => {
            let t = s.trim();
            if t.is_empty() { None } else { Some(t.to_string()) }
        }
        Err(_) => None,
    }
}

/// Persist `vault` to `file`, creating parent dirs.
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

#[tauri::command]
pub fn get_last_vault(app: tauri::AppHandle) -> Result<Option<String>, String> {
    Ok(read_last_vault(&last_vault_file(&app)?))
}

#[tauri::command]
pub fn set_last_vault(app: tauri::AppHandle, vault: String) -> Result<(), String> {
    write_last_vault(&last_vault_file(&app)?, &vault).map_err(|e| e.to_string())
}
```
`app.path()` requires the `tauri::Manager` trait in scope — add `use tauri::Manager;` to the module
imports (next to `use tauri::Emitter;`).

**Register (`lib.rs`)**: add `fs_commands::get_last_vault,` and `fs_commands::set_last_vault,` to the
`invoke_handler!` list.

**Shell (`index.html`)**:
- Change the inline boot `<script>` opening tag to `<script type="module">` so top-level `await`
  is allowed. (`dist/elm.js` and the vendored scripts load via their own classic `<script src>` tags
  beforehand, so `Elm` and `window.__TAURI__` remain available.)
- In the boot block, read the vault from Rust instead of localStorage:
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
- Change the `saveLastVault` port handler to persist via Rust:
  ```javascript
  app.ports.saveLastVault.subscribe((vault) => {
    invoke('set_last_vault', { vault: vault }).catch(() => {});
  });
  ```

**Elm:** unchanged. `Flags`, `Main.openVault`, `FileOps.saveLastVault` all stay as-is.

`readerMode` continues to use localStorage (same underlying limitation, but out of scope for this
request).

## Files touched

- `frontend/src/View.elm` — three button-row style changes.
- `src-tauri/src/fs_commands.rs` — `read_last_vault`/`write_last_vault` + `get_last_vault`/`set_last_vault` commands + `use tauri::Manager;`.
- `src-tauri/src/lib.rs` — register the two commands.
- `frontend/index.html` — `type="module"`, await `get_last_vault` for the flag, `set_last_vault` on save.

## Testing

- **TDD (Rust)** in the `fs_commands` `tests` module:
  - `write_last_vault` then `read_last_vault` round-trips a path (incl. creating a missing parent dir).
  - `read_last_vault` of a missing file → `None`.
  - `read_last_vault` of a whitespace-only file → `None`.
  Raises `cargo test` from 13 to 16.
- Sidebar spacing + the index.html rewiring are view/shell → `elm make` build + manual GUI.
- `elm-test` stays at 42.
- **Manual checklist:**
  1. ~2 mm gap below the new-file-name input row; adjacent sidebar buttons have a ~2 mm gap.
  2. Open a vault, quit, relaunch from Launchpad (no file arg) → the same vault reopens.
  3. `scripta <file>` still opens that file's folder (CLI launch path unaffected).

## Decisions / out of scope

- Last-vault persistence moves to a Rust-owned `last_vault.txt` in the app config dir; the Elm layer
  is unchanged.
- `readerMode` and per-vault open-folder state remain in localStorage (not in scope; may share the
  same persistence limitation and could be migrated later).
- No change to the bundle identifier or the launch-file mechanism.
