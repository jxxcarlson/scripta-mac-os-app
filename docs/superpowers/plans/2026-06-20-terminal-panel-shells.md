# Terminal Panel + Working Shells — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A toggleable, drag-resizable bottom terminal dock with three tabs — AI (placeholder), Shell 1, Shell 2 — where the two shell tabs are real interactive `$SHELL` sessions rooted in the vault, persisting across hide/show within a session.

**Architecture:** Rust PTY backend (`portable-pty`) exposes open/input/resize/close commands and streams output via a `terminal-output` event. A vendored **xterm.js** terminal emulator, wrapped in a `terminal-pane` custom element (like `<codemirror-editor>`), does all terminal I/O directly with Rust — Elm only controls the dock's visibility/active-tab. Dock height is a CSS variable owned by a small JS drag handler (persisted to localStorage); shell sessions live until app quit.

**Tech Stack:** Rust/Tauri 2 + new `portable-pty` crate; vendored xterm.js + addon-fit; Elm 0.19.1.

Spec: `docs/superpowers/specs/2026-06-20-terminal-panel-shells-design.md`

> **Two real-world risk points (handle, don't fake):**
> 1. **`portable-pty` API** — the snippets below target a recent version; if the installed version's
>    signatures differ, ADAPT to the actual API until `cargo build` passes (don't invent behavior).
> 2. **Vendoring xterm.js (Task 2)** needs to fetch files. If the environment is offline and the
>    download fails, report **BLOCKED** with the exact URLs so the user can drop the files in — do
>    not stub xterm.

---

## File Structure

- **Create** `src-tauri/src/terminal.rs`; **modify** `src-tauri/Cargo.toml`, `src-tauri/src/lib.rs`.
- **Create** `frontend/vendor/xterm/` (xterm.js, xterm.css, addon-fit.js); **modify** `frontend/index.html` (head links + boot script: `terminal-pane` element, output routing, resize drag, flags).
- **Modify** `frontend/src/Types.elm`, `frontend/src/Flags.elm` (+ test), `frontend/src/FileOps.elm`, `frontend/src/Main.elm`, `frontend/src/View.elm`.

---

## Task 1: Rust PTY backend

**Files:** Modify `src-tauri/Cargo.toml`; create `src-tauri/src/terminal.rs`; modify `src-tauri/src/lib.rs`.

- [ ] **Step 1: Add the dependency**

In `src-tauri/Cargo.toml` `[dependencies]`, add:
```toml
portable-pty = "0.8"
```
Run `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo fetch` to confirm it resolves (if offline → BLOCKED).

- [ ] **Step 2: Create `terminal.rs`**

Create `src-tauri/src/terminal.rs` (adapt the `portable-pty` calls to the installed version if needed):
```rust
use base64::Engine;
use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::Mutex;
use tauri::Emitter;

struct Session {
    writer: Box<dyn Write + Send>,
    master: Box<dyn portable_pty::MasterPty + Send>,
    child: Box<dyn portable_pty::Child + Send + Sync>,
}

#[derive(Default)]
pub struct TerminalState(pub Mutex<HashMap<String, Session>>);

fn resolve_cwd(cwd: &str) -> String {
    if cwd.is_empty() {
        std::env::var("HOME").unwrap_or_else(|_| "/".to_string())
    } else {
        cwd.to_string()
    }
}

#[tauri::command]
pub fn terminal_open(
    app: tauri::AppHandle,
    state: tauri::State<'_, TerminalState>,
    id: String,
    cwd: String,
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    // Replace any existing session with this id.
    let _ = terminal_close(state.clone(), id.clone());

    let pty = native_pty_system();
    let pair = pty
        .openpty(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })
        .map_err(|e| e.to_string())?;

    let shell = std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".to_string());
    let mut cmd = CommandBuilder::new(shell);
    cmd.cwd(resolve_cwd(&cwd));

    let child = pair.slave.spawn_command(cmd).map_err(|e| e.to_string())?;
    let mut reader = pair.master.try_clone_reader().map_err(|e| e.to_string())?;
    let writer = pair.master.take_writer().map_err(|e| e.to_string())?;

    let app_for_thread = app.clone();
    let id_for_thread = id.clone();
    std::thread::spawn(move || {
        let mut buf = [0u8; 8192];
        loop {
            match reader.read(&mut buf) {
                Ok(0) | Err(_) => {
                    let _ = app_for_thread.emit("terminal-exit", serde_json::json!({ "id": id_for_thread }));
                    break;
                }
                Ok(n) => {
                    let data = base64::engine::general_purpose::STANDARD.encode(&buf[..n]);
                    let _ = app_for_thread.emit(
                        "terminal-output",
                        serde_json::json!({ "id": id_for_thread, "data": data }),
                    );
                }
            }
        }
    });

    state
        .0
        .lock()
        .map_err(|e| e.to_string())?
        .insert(id, Session { writer, master: pair.master, child });
    Ok(())
}

#[tauri::command]
pub fn terminal_input(state: tauri::State<'_, TerminalState>, id: String, data: String) -> Result<(), String> {
    if let Some(s) = state.0.lock().map_err(|e| e.to_string())?.get_mut(&id) {
        s.writer.write_all(data.as_bytes()).map_err(|e| e.to_string())?;
        s.writer.flush().map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub fn terminal_resize(state: tauri::State<'_, TerminalState>, id: String, cols: u16, rows: u16) -> Result<(), String> {
    if let Some(s) = state.0.lock().map_err(|e| e.to_string())?.get(&id) {
        s.master
            .resize(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
pub fn terminal_close(state: tauri::State<'_, TerminalState>, id: String) -> Result<(), String> {
    if let Some(mut s) = state.0.lock().map_err(|e| e.to_string())?.remove(&id) {
        let _ = s.child.kill();
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::resolve_cwd;
    #[test]
    fn resolve_cwd_empty_uses_home() {
        std::env::set_var("HOME", "/Users/test");
        assert_eq!(resolve_cwd(""), "/Users/test");
        assert_eq!(resolve_cwd("/vault/x"), "/vault/x");
    }
}
```

- [ ] **Step 3: Register in `lib.rs`**

Add `mod terminal;` at the top; add `.manage(terminal::TerminalState::default())` next to the other
`.manage(...)` calls; add to `generate_handler![ … ]`:
```rust
            terminal::terminal_open,
            terminal::terminal_input,
            terminal::terminal_resize,
            terminal::terminal_close,
```

- [ ] **Step 4: Build + test**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/src-tauri" && cargo test 2>&1 | tail -20`
Expected: compiles; `resolve_cwd_empty_uses_home` passes; existing tests pass. (If `portable-pty`'s API differs, adapt the calls — e.g. `take_writer`/`try_clone_reader`/`resize`/`spawn_command` names — until it builds.)

- [ ] **Step 5: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add src-tauri/Cargo.toml src-tauri/Cargo.lock src-tauri/src/terminal.rs src-tauri/src/lib.rs
git commit -m "feat: PTY terminal backend (open/input/resize/close)"
```

---

## Task 2: Vendor xterm.js

**Files:** Create `frontend/vendor/xterm/*`; modify `frontend/index.html` (head).

- [ ] **Step 1: Download the vendor files**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && mkdir -p vendor/xterm
curl -fsSL https://unpkg.com/@xterm/xterm@5.5.0/lib/xterm.js          -o vendor/xterm/xterm.js
curl -fsSL https://unpkg.com/@xterm/xterm@5.5.0/css/xterm.css         -o vendor/xterm/xterm.css
curl -fsSL https://unpkg.com/@xterm/addon-fit@0.10.0/lib/addon-fit.js -o vendor/xterm/addon-fit.js
ls -la vendor/xterm
```
Expected: three non-empty files. **If any `curl` fails (offline), STOP and report BLOCKED with these
three URLs** — the user will place the files. Do not stub them.

- [ ] **Step 2: Link them in `index.html` `<head>`**

Add alongside the existing KaTeX/CodeMirror tags:
```html
    <link rel="stylesheet" href="vendor/xterm/xterm.css" />
    <script src="vendor/xterm/xterm.js"></script>
    <script src="vendor/xterm/addon-fit.js"></script>
```
(These expose globals `Terminal` and `FitAddon` — the addon global is `FitAddon.FitAddon`.)

- [ ] **Step 3: Verify it still builds/loads**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=dist/elm.js`
Expected: `Success!` (no Elm change; this just confirms the head edit didn't break the page). Visual
load is confirmed in the final manual step.

- [ ] **Step 4: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/vendor/xterm frontend/index.html
git commit -m "chore: vendor xterm.js + addon-fit (offline terminal emulator)"
```

---

## Task 3: `terminal-pane` element + output routing + resize drag (index.html)

**Files:** Modify `frontend/index.html` (boot `<script type="module">` + `<style>`).

- [ ] **Step 1: Add a base64 helper + the `terminal-pane` custom element**

In the boot module script (which already has `const { invoke } = window.__TAURI__.core;` and
`const { listen } = window.__TAURI__.event;`), add near the `math-text` element definition:
```javascript
      function b64ToBytes(b64) {
        const bin = atob(b64);
        const bytes = new Uint8Array(bin.length);
        for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
        return bytes;
      }

      class TerminalPane extends HTMLElement {
        connectedCallback() {
          if (this._term) return; // already initialized
          const id = this.getAttribute('term-id');
          const cwd = this.getAttribute('cwd') || '';
          const term = new Terminal({ convertEol: false, fontFamily: 'ui-monospace, monospace', fontSize: 13 });
          const fit = new FitAddon.FitAddon();
          term.loadAddon(fit);
          term.open(this);
          this._term = term;
          this._fit = fit;
          this._id = id;
          this._fitAndResize();
          invoke('terminal_open', { id, cwd, cols: term.cols, rows: term.rows }).catch(() => {});
          term.onData((d) => invoke('terminal_input', { id, data: d }).catch(() => {}));
          this._unlistenOut = listen('terminal-output', (e) => {
            if (e.payload && e.payload.id === id) term.write(b64ToBytes(e.payload.data));
          });
          this._unlistenExit = listen('terminal-exit', (e) => {
            if (e.payload && e.payload.id === id) term.write('\r\n[process exited]\r\n');
          });
          this._ro = new ResizeObserver(() => this._fitAndResize());
          this._ro.observe(this);
        }
        _fitAndResize() {
          // Skip when hidden (0×0) so we don't resize to zero.
          if (this.offsetWidth === 0 || this.offsetHeight === 0) return;
          try { this._fit.fit(); } catch (e) { return; }
          if (this._term.cols > 0 && this._term.rows > 0) {
            invoke('terminal_resize', { id: this._id, cols: this._term.cols, rows: this._term.rows }).catch(() => {});
          }
        }
        disconnectedCallback() {
          if (this._ro) this._ro.disconnect();
          if (this._unlistenOut) this._unlistenOut.then((f) => f());
          if (this._unlistenExit) this._unlistenExit.then((f) => f());
          if (this._id) invoke('terminal_close', { id: this._id }).catch(() => {});
          if (this._term) this._term.dispose();
        }
      }
      customElements.define('terminal-pane', TerminalPane);
```

- [ ] **Step 2: Terminal-height CSS var + resize drag**

In `index.html`'s `<style>`, add a default:
```css
      :root { --terminal-height: 280px; }
```
In the boot script, set it from localStorage at startup and add a delegated pointer-drag on the
dock's resize handle (Elm renders a `<div id="terminal-resize-handle">`):
```javascript
      (function () {
        const saved = lsGet('terminalHeight');
        if (saved) document.documentElement.style.setProperty('--terminal-height', saved + 'px');
        let dragging = false;
        document.addEventListener('pointerdown', (e) => {
          if (e.target && e.target.id === 'terminal-resize-handle') { dragging = true; e.preventDefault(); }
        });
        document.addEventListener('pointermove', (e) => {
          if (!dragging) return;
          const h = Math.max(120, Math.min(window.innerHeight - 120, window.innerHeight - e.clientY));
          document.documentElement.style.setProperty('--terminal-height', h + 'px');
        });
        document.addEventListener('pointerup', () => {
          if (!dragging) return;
          dragging = false;
          const cur = getComputedStyle(document.documentElement).getPropertyValue('--terminal-height').trim();
          try { localStorage.setItem('terminalHeight', parseInt(cur, 10)); } catch (e) {}
        });
      })();
```

- [ ] **Step 3: Verify build**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=dist/elm.js`
Expected: `Success!` (JS-only change; functional check is the final manual step).

- [ ] **Step 4: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/index.html
git commit -m "feat: terminal-pane custom element + output routing + resize drag"
```

---

## Task 4: Elm state — Model, Flags, port, handlers

**Files:** Modify `frontend/src/Types.elm`, `frontend/src/Flags.elm` (+ `tests/FlagsTest.elm`), `frontend/src/FileOps.elm`, `frontend/index.html` (flags + subscribe), `frontend/src/Main.elm`.

- [ ] **Step 1: Flags — `terminalVisible` (failing test)**

In `frontend/tests/FlagsTest.elm` add:
```elm
        , test "missing terminalVisible defaults to False" <|
            \_ -> Expect.equal False (Flags.decode (E.object [])).terminalVisible
        , test "terminalVisible true decodes to True" <|
            \_ -> Expect.equal True (Flags.decode (E.object [ ( "terminalVisible", E.bool True ) ])).terminalVisible
```
Run `cd frontend && elm-test tests/FlagsTest.elm` → fails. Then in `frontend/src/Flags.elm` add
`, terminalVisible : Bool` to the alias and to `decode`:
```elm
    , terminalVisible =
        D.decodeValue (D.field "terminalVisible" D.bool) value
            |> Result.withDefault False
    }
```
Re-run → PASS.

- [ ] **Step 2: FileOps — `saveTerminalVisible` port**

In `frontend/src/FileOps.elm` add `saveTerminalVisible` to `exposing (…)` and declare:
```elm
port saveTerminalVisible : Bool -> Cmd msg
```

- [ ] **Step 3: index.html — flags read + subscribe**

In the `flags` object add (with a comma after the current last field):
```javascript
        terminalVisible: lsGet('terminalVisible') === 'true'   // bool (unset → hidden)
```
Add a save handler:
```javascript
      subscribePort('saveTerminalVisible', (on) => {
        try { localStorage.setItem('terminalVisible', on ? 'true' : 'false'); } catch (e) {}
      });
```

- [ ] **Step 4: Types — Model + Msg**

In `frontend/src/Types.elm`:
- Add to `Model`: `, terminalVisible : Bool`, `, terminalEverOpened : Bool`, `, terminalTab : String`
- Add to `Msg`: `| ToggledTerminal` and `| SelectTerminalTab String`

- [ ] **Step 5: Main — init + handlers**

In the initial model record add:
```elm
        , terminalVisible = flags.terminalVisible
        , terminalEverOpened = flags.terminalVisible
        , terminalTab = "ai"
```
Add to `update`:
```elm
        ToggledTerminal ->
            let
                visible =
                    not model.terminalVisible
            in
            ( { model | terminalVisible = visible, terminalEverOpened = model.terminalEverOpened || visible }
            , FileOps.saveTerminalVisible visible
            )

        SelectTerminalTab tab ->
            ( { model | terminalTab = tab }, Cmd.none )
```

- [ ] **Step 6: Build + tests**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test`
Expected: `Success!`; all suites pass (incl. the 2 new Flags tests). (No dock UI yet — Task 5.)

- [ ] **Step 7: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/Types.elm frontend/src/Flags.elm frontend/tests/FlagsTest.elm frontend/src/FileOps.elm frontend/index.html frontend/src/Main.elm
git commit -m "feat: terminal panel state (visible/tab) + persistence"
```

---

## Task 5: Elm View — toolbar button + dock

**Files:** Modify `frontend/src/View.elm`.

- [ ] **Step 1: Toolbar button**

In `view`'s `toolbar` button list, add (e.g. after the ⚙ Settings button):
```elm
                , button [ onClick ToggledTerminal ] [ text "\u{2318} Terminal" ]
```

- [ ] **Step 2: Render the dock in the root column**

`import Html.Keyed` at the top. In `view`, where the root `div`'s children are assembled, append the
dock after `body` (and keep the settings overlay last):
```elm
        (conflictBanner model
            ++ errorBanner model
            ++ [ toolbar, body ]
            ++ (if model.terminalEverOpened then [ terminalDock model ] else [])
            ++ (if model.showSettings then [ settingsOverlay model ] else [])
        )
```

- [ ] **Step 3: Add the dock**

Add these top-level functions to `View.elm`:
```elm
terminalDock : Model -> Html Msg
terminalDock model =
    div
        [ style "display"
            (if model.terminalVisible then
                "flex"

             else
                "none"
            )
        , style "flex-direction" "column"
        , style "height" "var(--terminal-height)"
        , style "border-top" "1px solid var(--border)"
        , style "background" "var(--app-bg)"
        , style "min-height" "0"
        ]
        [ div [ Html.Attributes.id "terminal-resize-handle", style "height" "6px", style "cursor" "row-resize", style "background" "var(--border)", style "flex" "0 0 auto" ] []
        , terminalTabBar model
        , Html.Keyed.node "div"
            [ style "flex" "1", style "min-height" "0", style "position" "relative" ]
            [ ( "ai", terminalTabContent (model.terminalTab == "ai") (aiPlaceholder) )
            , ( "shell1", terminalTabContent (model.terminalTab == "shell1") (terminalPane "shell1" model) )
            , ( "shell2", terminalTabContent (model.terminalTab == "shell2") (terminalPane "shell2" model) )
            ]
        ]


terminalTabBar : Model -> Html Msg
terminalTabBar model =
    div [ style "display" "flex", style "gap" "4px", style "padding" "4px 8px", style "flex" "0 0 auto", style "border-bottom" "1px solid var(--border)" ]
        (List.map (terminalTabButton model) [ ( "ai", "AI" ), ( "shell1", "Shell 1" ), ( "shell2", "Shell 2" ) ])


terminalTabButton : Model -> ( String, String ) -> Html Msg
terminalTabButton model ( tabId, label ) =
    button
        [ onClick (SelectTerminalTab tabId)
        , style "font-weight"
            (if model.terminalTab == tabId then
                "700"

             else
                "400"
            )
        ]
        [ text label ]


terminalTabContent : Bool -> Html Msg -> Html Msg
terminalTabContent active content =
    div
        [ style "position" "absolute"
        , style "inset" "0"
        , style "display"
            (if active then
                "block"

             else
                "none"
            )
        ]
        [ content ]


aiPlaceholder : Html Msg
aiPlaceholder =
    div [ style "padding" "16px", style "color" "var(--muted)" ]
        [ text "AI chat — coming in the next step." ]


terminalPane : String -> Model -> Html Msg
terminalPane termId model =
    Html.node "terminal-pane"
        [ Html.Attributes.attribute "term-id" termId
        , Html.Attributes.attribute "cwd" (Maybe.withDefault "" model.vaultRoot)
        , style "display" "block"
        , style "width" "100%"
        , style "height" "100%"
        ]
        []
```
(`Html.Keyed.node` keeps the `ai`/`shell1`/`shell2` children — and thus each `terminal-pane` — stable
across tab switches and re-renders, so shells are never recreated. The shell panes stay mounted
whenever the dock is mounted, even while it's `display:none`, so shells persist across hide/show.)

- [ ] **Step 4: Build + full suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer/frontend" && elm make src/Main.elm --output=/dev/null && elm-test`
Expected: `Success!` and all suites pass.

- [ ] **Step 5: Commit**

```bash
cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer"
git add frontend/src/View.elm
git commit -m "feat: terminal dock UI (tabs, resize handle, shell panes)"
```

---

## After All Tasks

- Final code review over the whole diff.
- **Manual verification (GUI):** `make build` → install → relaunch. Open the vault → click **⌘ Terminal**
  → dock appears → **Shell 1**: `pwd` shows the vault dir; run `ls`, an interactive command, Ctrl-C,
  arrow-key history → **Shell 2** is an independent session → switch back to Shell 1 (state intact) →
  drag the top edge to resize (height persists on relaunch) → **toggle the panel off then on → the
  same shells with their history are still there** → **AI** tab shows the placeholder → relaunch
  (visibility + height persist; shells start fresh) → quit the app and confirm no orphan shell
  processes (`ps` for your `$SHELL` under the app).
- Then use superpowers:finishing-a-development-branch.

## Notes

- Terminal I/O never touches Elm: the `terminal-pane` element ↔ Rust via `invoke` + the
  `terminal-output`/`terminal-exit` events, exactly like `<codemirror-editor>`.
- Dock height is owned by the `--terminal-height` CSS var (JS drag handler + localStorage); Elm does
  not track it — this avoids an Elm↔JS height sync. (Refinement of the spec, which floated either
  approach.)
- Output is base64 of raw PTY bytes → `term.write(Uint8Array)`, preserving escape sequences.
- `portable-pty` API names may differ by version — adapt Task 1's calls until `cargo build` passes;
  do not change the intended behavior.
