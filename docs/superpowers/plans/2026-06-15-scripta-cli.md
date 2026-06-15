# `scripta` CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `scripta <file>` shell command that opens the given `.scripta`/`.tex`/`.md` file in Mac Scripta Viewer — reusing the open window if running — with the file's parent folder as the vault.

**Architecture:** A shell script launches the app via `open -na ... --args <abspath>`. Tauri's single-instance plugin forwards the path to the running instance (emitting an `open-file` event); on cold start the path is read from `argv` into managed state and pulled by the frontend via a `take_launch_file` command. The Elm app opens the file by setting the vault to its parent folder and reading it.

**Tech Stack:** Tauri 2 + `tauri-plugin-single-instance`, Rust, Elm 0.19.1, a POSIX shell script.

---

## Reference (current state — verified)

- `src-tauri/src/fs_commands.rs`: has `Entry`, `has_doc_ext(p: &Path) -> bool`, `mtime_ms`, the `_impl` fns and `#[tauri::command]` wrappers, and `WatcherState`. Imports include `use std::path::{Path, PathBuf};`, `use std::sync::Mutex;`, serde.
- `src-tauri/src/lib.rs`: `run()` builds `tauri::Builder::default().plugin(tauri_plugin_dialog::init()).manage(fs_commands::WatcherState::default()).invoke_handler(generate_handler![...]).run(generate_context!())`.
- `frontend/src/Main.elm`: `init : () -> ( Model, Cmd Msg )` returns `( record, Cmd.none )`; `request : PendingOp -> String -> List (String, E.Value) -> Model -> ( Model, Cmd Msg )`; `handleResponse` with a branch per `PendingOp` (no `_ ->` wildcard — it was removed, so a NEW `PendingOp` variant REQUIRES a new branch or the match is non-exhaustive); `parentDir : String -> String` is a private top-level fn used by the `ClickedRename` branch; `subscriptions` batches `FileOps.fsResponse GotFsResponse` and `FileOps.fileChanged GotFileChanged`.
- `frontend/src/Types.elm`: `Model`, `Msg`, `PendingOp` (variants: `PPickWorkspace | PListWorkspace | PReadFile String | PWriteFile String | PCreateFile String | PCreateDir String | PRename String String | PDelete String | PExportSave | PNoop`).
- `frontend/src/FileOps.elm`: `port module FileOps exposing (FsResponse, fsRequest, fsResponse, fileChanged, scrollToElement, encodeRequest, responseDecoder, resultOf, send)`.
- `frontend/index.html`: boots Elm, subscribes `fsRequest`, `listen('file-changed', ...)`, `scrollToElement`. Uses `window.__TAURI__.core` / `.event`.
- The built app is installed at `/Applications/Mac Scripta Viewer.app`; the bundle is produced by `make build` at `src-tauri/target/release/bundle/macos/Mac Scripta Viewer.app`.

**Path note:** repo root has a space — always quote. End commit messages with:
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

---

## File structure

```
Mac Scripta Viewer/
├── bin/
│   └── scripta              # the CLI shell script (committed; installed to /opt/homebrew/bin)
├── install-cli.sh           # copies bin/scripta to /opt/homebrew/bin and chmod +x
├── src-tauri/src/
│   ├── fs_commands.rs        # + launch_file_from_args, LaunchFile, take_launch_file
│   └── lib.rs                # + single-instance plugin, manage(LaunchFile), register command
├── frontend/
│   ├── src/
│   │   ├── PathUtil.elm       # NEW: basename + parentDir (moved out of Main, testable)
│   │   ├── Main.elm           # + PLaunchFile flow, openFile sub, openExternalFile, use PathUtil
│   │   ├── Types.elm          # + PLaunchFile PendingOp, GotOpenFile Msg
│   │   └── FileOps.elm        # + openFile inbound port
│   ├── tests/PathUtilTest.elm # NEW
│   └── index.html             # + listen('open-file', ...)
```

---

### Task 1: Rust — `launch_file_from_args` + launch-file state + command (TDD)

**Files:**
- Modify: `src-tauri/src/fs_commands.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Write the failing test** — add to the `#[cfg(test)] mod tests` block in `fs_commands.rs`:

```rust
    #[test]
    fn launch_file_picks_existing_doc_path() {
        let dir = tempdir().unwrap();
        let f = dir.path().join("a.scripta");
        fs::write(&f, "x").unwrap();
        let prog = "/Applications/App.app/Contents/MacOS/app".to_string();
        let args = vec![prog, f.to_string_lossy().to_string()];
        assert_eq!(launch_file_from_args(&args), Some(f.to_string_lossy().to_string()));
    }

    #[test]
    fn launch_file_none_when_only_program() {
        let args = vec!["/path/to/app".to_string()];
        assert_eq!(launch_file_from_args(&args), None);
    }

    #[test]
    fn launch_file_ignores_flags_and_nondoc() {
        let args = vec![
            "/path/to/app".to_string(),
            "-psn_0_12345".to_string(),
            "notes.txt".to_string(),
        ];
        assert_eq!(launch_file_from_args(&args), None);
    }

    #[test]
    fn launch_file_accepts_doc_extension_even_if_missing() {
        // A path with a recognized doc extension is accepted by extension even
        // if it does not currently exist (the frontend surfaces the read error).
        let args = vec!["/path/to/app".to_string(), "/tmp/x/ghost.scripta".to_string()];
        assert_eq!(
            launch_file_from_args(&args),
            Some("/tmp/x/ghost.scripta".to_string())
        );
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd "src-tauri" && cargo test launch_file 2>&1 | tail -15`
Expected: FAIL — `launch_file_from_args` not found.

- [ ] **Step 3: Implement** — add to `fs_commands.rs` module body:

```rust
/// From a process's argv, return the first argument that is a document to open:
/// one that already exists OR has a recognized doc extension (scripta/tex/md).
/// The program name (argv[0]) and flags (starting with '-') are ignored.
pub fn launch_file_from_args(args: &[String]) -> Option<String> {
    args.iter()
        .skip(1)
        .find(|a| {
            if a.starts_with('-') {
                return false;
            }
            let p = Path::new(a);
            p.is_file() || has_doc_ext(p)
        })
        .cloned()
}

/// The file path requested at launch (from argv), pulled once by the frontend.
#[derive(Default)]
pub struct LaunchFile(pub Mutex<Option<String>>);

#[tauri::command]
pub fn take_launch_file(state: tauri::State<'_, LaunchFile>) -> Result<Option<String>, String> {
    let mut guard = state.0.lock().map_err(|e| e.to_string())?;
    Ok(guard.take())
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd "src-tauri" && cargo test launch_file 2>&1 | tail -15`
Expected: 4 new tests PASS. Then `cargo test 2>&1 | grep "test result:"` → all pass.

- [ ] **Step 5: Wire managed state + command in `lib.rs`**

In `run()`, before `.run(...)`, compute the launch file and manage it; register the command. Concretely, change the builder to:

```rust
pub fn run() {
    let args: Vec<String> = std::env::args().collect();
    let launch = fs_commands::launch_file_from_args(&args);

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(fs_commands::WatcherState::default())
        .manage(fs_commands::LaunchFile(std::sync::Mutex::new(launch)))
        .invoke_handler(tauri::generate_handler![
            fs_commands::list_workspace,
            fs_commands::pick_workspace,
            fs_commands::read_file,
            fs_commands::write_file,
            fs_commands::create_dir,
            fs_commands::create_file,
            fs_commands::rename,
            fs_commands::delete,
            fs_commands::watch_workspace,
            fs_commands::export_save,
            fs_commands::take_launch_file,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```
(Keep the existing command list; just ADD `take_launch_file` and the two lines for `args`/`launch`/`.manage(LaunchFile...)`. The single-instance plugin is added in Task 2.)

- [ ] **Step 6: Verify build**

Run: `cd "src-tauri" && cargo build 2>&1 | tail -5` → `Finished`, no new warnings. `cargo test 2>&1 | grep "test result:"` → all pass.

- [ ] **Step 7: Commit**

```bash
git add src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: launch-file argv parsing + take_launch_file command"
```

---

### Task 2: Rust — single-instance plugin forwarding `open-file`

**Files:**
- Modify: `src-tauri/Cargo.toml`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Add the dependency** to `src-tauri/Cargo.toml` under `[dependencies]`:

```toml
tauri-plugin-single-instance = "2"
```

- [ ] **Step 2: Register the plugin FIRST in `lib.rs`**

The single-instance plugin must be the FIRST plugin registered. Its callback fires in the PRIMARY instance when a second instance launches, receiving the second instance's argv. Extract the doc path and emit `open-file`. Add `use tauri::Emitter;` if not already imported (it is imported in `fs_commands.rs`, but `lib.rs` needs its own `use` for `.emit`). Update the builder so the single-instance plugin is first:

```rust
pub fn run() {
    let args: Vec<String> = std::env::args().collect();
    let launch = fs_commands::launch_file_from_args(&args);

    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, argv, _cwd| {
            use tauri::Emitter;
            if let Some(path) = fs_commands::launch_file_from_args(&argv) {
                let _ = app.emit("open-file", serde_json::json!({ "path": path }));
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .manage(fs_commands::WatcherState::default())
        .manage(fs_commands::LaunchFile(std::sync::Mutex::new(launch)))
        .invoke_handler(tauri::generate_handler![
            fs_commands::list_workspace,
            fs_commands::pick_workspace,
            fs_commands::read_file,
            fs_commands::write_file,
            fs_commands::create_dir,
            fs_commands::create_file,
            fs_commands::rename,
            fs_commands::delete,
            fs_commands::watch_workspace,
            fs_commands::export_save,
            fs_commands::take_launch_file,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```
NOTE: `app` in the single-instance callback is `&AppHandle` (Tauri 2). `serde_json` is already a dependency. If the plugin's callback signature differs in the installed version (e.g., arg types), adapt so it compiles — the goal is "on second launch, emit `open-file {path}` to the running app." Document any deviation.

- [ ] **Step 3: Verify build**

Run: `cd "src-tauri" && cargo build 2>&1 | tail -15` → `Finished`. (This downloads the plugin crate.) `cargo test 2>&1 | grep "test result:"` → all pass. The single-instance behavior can only be verified by running two launches (manual, Task 7).

- [ ] **Step 4: Commit**

```bash
git add src-tauri/Cargo.toml src-tauri/Cargo.lock src-tauri/src/lib.rs
git commit -m "feat: single-instance plugin forwarding open-file events"
```

---

### Task 3: Elm — `PathUtil` module (TDD), refactor `parentDir` out of `Main`

**Files:**
- Create: `frontend/src/PathUtil.elm`
- Create: `frontend/tests/PathUtilTest.elm`
- Modify: `frontend/src/Main.elm`

- [ ] **Step 1: Write the failing test** — `frontend/tests/PathUtilTest.elm`:

```elm
module PathUtilTest exposing (suite)

import Expect
import PathUtil
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "PathUtil"
        [ test "basename of an absolute path" <|
            \_ -> Expect.equal "c.scripta" (PathUtil.basename "/a/b/c.scripta")
        , test "basename of a bare filename" <|
            \_ -> Expect.equal "c.scripta" (PathUtil.basename "c.scripta")
        , test "parentDir of an absolute path" <|
            \_ -> Expect.equal "/a/b" (PathUtil.parentDir "/a/b/c.scripta")
        , test "parentDir of a bare filename is empty" <|
            \_ -> Expect.equal "" (PathUtil.parentDir "c.scripta")
        , test "parentDir of a relative path" <|
            \_ -> Expect.equal "sub" (PathUtil.parentDir "sub/c.scripta")
        ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd frontend && elm-test tests/PathUtilTest.elm 2>&1 | tail -10` → FAIL (module not found).

- [ ] **Step 3: Implement** — `frontend/src/PathUtil.elm`:

```elm
module PathUtil exposing (basename, parentDir)

{-| Small '/'-separated path helpers shared by the file-open logic.
-}


{-| The final path segment (the file name).
-}
basename : String -> String
basename path =
    path |> String.split "/" |> List.reverse |> List.head |> Maybe.withDefault path


{-| Everything before the final segment; "" if there is no '/'.
-}
parentDir : String -> String
parentDir path =
    case path |> String.split "/" |> List.reverse of
        _ :: rest ->
            rest |> List.reverse |> String.join "/"

        [] ->
            ""
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd frontend && elm-test tests/PathUtilTest.elm 2>&1 | tail -10` → 5 pass.

- [ ] **Step 5: Refactor `Main.elm` to use `PathUtil.parentDir`**

Add `import PathUtil` to `Main.elm`. DELETE the private `parentDir` function (currently near the bottom of `Main.elm`). In the `ClickedRename` branch, change the call `parentDir path` to `PathUtil.parentDir path`.

- [ ] **Step 6: Verify whole app + suite**

Run: `cd frontend && elm make src/Main.elm --output=/dev/null 2>&1 | tail -5` → Success. `cd frontend && elm-test 2>&1 | tail -6` → all pass (18 prior + 5 new = 23).

- [ ] **Step 7: Commit**

```bash
git add frontend/src/PathUtil.elm frontend/tests/PathUtilTest.elm frontend/src/Main.elm
git commit -m "refactor: extract PathUtil (basename/parentDir) with tests"
```

---

### Task 4: Elm — launch-file + open-file wiring

**Files:**
- Modify: `frontend/src/Types.elm`
- Modify: `frontend/src/FileOps.elm`
- Modify: `frontend/src/Main.elm`

- [ ] **Step 1: Types.elm — add op + msg**

Add `PLaunchFile` to `PendingOp`:
```elm
    | PLaunchFile
```
Add a Msg:
```elm
    | GotOpenFile D.Value
```
(`D` is already imported in Types.elm as `import Json.Decode as D`.)

- [ ] **Step 2: FileOps.elm — add the `openFile` inbound port**

Add `openFile` to the exposing list and declare the port:
```elm
port openFile : (E.Value -> msg) -> Sub msg
```
Place it next to `fileChanged`. Update the `exposing ( ... )` list to include `openFile`.

- [ ] **Step 3: Main.elm — fire `take_launch_file` from `init`**

Change `init` so that instead of returning `Cmd.none` it issues a `take_launch_file` request. Replace the `init` body's `, Cmd.none )` tail by building the model then calling `request`:
```elm
init : () -> ( Model, Cmd Msg )
init _ =
    request PLaunchFile
        "take_launch_file"
        []
        { vaultRoot = Nothing
        , tree = []
        , selectedPath = Nothing
        , nextRequestId = 0
        , pending = Dict.empty
        , error = Nothing
        , content = ""
        , loadedContent = ""
        , loadedMtime = 0
        , externalConflict = False
        , parsedDoc = Nothing
        , language = Nothing
        , isLight = True
        , contentWidth = 500
        , saveState = SaveState.init
        , newName = ""
        }
```
(Keep the exact field set currently in `init` — just wrap it in a `request PLaunchFile "take_launch_file" [] {...}` instead of `( {...}, Cmd.none )`.)

- [ ] **Step 4: Main.elm — add the shared `openExternalFile` helper**

```elm
{-| Open an absolute file path: make its parent folder the vault, watch + list
that folder, and read the file (whose workspace-relative path is its basename).
-}
openExternalFile : String -> Model -> ( Model, Cmd Msg )
openExternalFile abs model =
    let
        parent =
            PathUtil.parentDir abs

        name =
            PathUtil.basename abs

        m0 =
            { model
                | vaultRoot = Just parent
                , selectedPath = Just name
                , language = Language.fromPath name
            }

        ( m1, c1 ) =
            request PListWorkspace "list_workspace" [ ( "root", E.string parent ) ] m0

        ( m2, c2 ) =
            request PNoop "watch_workspace" [ ( "root", E.string parent ) ] m1

        ( m3, c3 ) =
            request (PReadFile name) "read_file" [ ( "root", E.string parent ), ( "path", E.string name ) ] m2
    in
    ( m3, Cmd.batch [ c1, c2, c3 ] )
```

- [ ] **Step 5: Main.elm — handle `GotOpenFile` (forwarded event)**

Add an update branch:
```elm
        GotOpenFile value ->
            case D.decodeValue (D.field "path" D.string) value of
                Ok abs ->
                    openExternalFile abs model

                Err _ ->
                    ( model, Cmd.none )
```

- [ ] **Step 6: Main.elm — handle the `PLaunchFile` response in `handleResponse`**

Because `handleResponse` has NO `_ ->` wildcard, you MUST add a `PLaunchFile` branch (otherwise the `case` is non-exhaustive and won't compile). Add, inside the `Ok result ->` arm:
```elm
                PLaunchFile ->
                    case D.decodeValue (D.nullable D.string) result of
                        Ok (Just abs) ->
                            openExternalFile abs model

                        _ ->
                            ( model, Cmd.none )
```

- [ ] **Step 7: Main.elm — subscribe to `openFile`**

Update `subscriptions`:
```elm
subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ FileOps.fsResponse GotFsResponse
        , FileOps.fileChanged GotFileChanged
        , FileOps.openFile GotOpenFile
        ]
```

- [ ] **Step 8: Verify**

Run: `cd frontend && elm make src/Main.elm --output=dist/elm.js 2>&1 | tail -20` → Success. Fix any compile errors (likely: a missing `import PathUtil` — added in Task 3; ensure `Language` is imported in Main, it is). `cd frontend && elm-test 2>&1 | tail -6` → 23 pass.

- [ ] **Step 9: Commit**

```bash
git add frontend/src/Types.elm frontend/src/FileOps.elm frontend/src/Main.elm
git commit -m "feat: open a file passed at launch or forwarded via open-file"
```

---

### Task 5: index.html — forward the `open-file` event to Elm

**Files:**
- Modify: `frontend/index.html`

- [ ] **Step 1: Add the listener**

In the inline boot script, next to the existing `listen('file-changed', ...)` block, add:
```javascript
      listen('open-file', (e) => {
        app.ports.openFile.send(e.payload);
      });
```
(`listen` is already obtained from `window.__TAURI__.event`. `app.ports.openFile` exists after Task 4.)

- [ ] **Step 2: Verify it's well-formed**

Run: `grep -n "open-file\|app.ports.openFile" frontend/index.html` → shows the new listener. (Full behavior is verified by running the app in Task 7.)

- [ ] **Step 3: Commit**

```bash
git add frontend/index.html
git commit -m "feat: forward open-file event to the Elm openFile port"
```

---

### Task 6: The `scripta` shell script + installer

**Files:**
- Create: `bin/scripta`
- Create: `install-cli.sh`

- [ ] **Step 1: Write `bin/scripta`**

```sh
#!/bin/sh
# Open a file in Mac Scripta Viewer. Usage: scripta [file]
if [ -n "$1" ]; then
  if [ ! -e "$1" ]; then
    echo "scripta: warning: '$1' does not exist; opening anyway" >&2
  fi
  abs="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"
  open -na "Mac Scripta Viewer" --args "$abs"
else
  open -a "Mac Scripta Viewer"
fi
```

- [ ] **Step 2: Write `install-cli.sh`**

```sh
#!/bin/sh
# Install the `scripta` CLI to /opt/homebrew/bin.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)/bin/scripta"
DEST="/opt/homebrew/bin/scripta"
cp "$SRC" "$DEST"
chmod +x "$DEST"
echo "Installed scripta -> $DEST"
```

- [ ] **Step 3: Make both executable and commit**

```bash
chmod +x bin/scripta install-cli.sh
git add bin/scripta install-cli.sh
git commit -m "feat: scripta CLI script and installer"
```

---

### Task 7: Build, install, and manual verification

**Files:** none (build + manual).

- [ ] **Step 1: Full automated suite**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make test 2>&1 | tail -20`
Expected: elm-test (23) and cargo test all pass.

- [ ] **Step 2: Build the release app**

Run: `make build 2>&1 | tail -15`
Expected: `Finished N bundle(s)` and the `.app` path printed.

- [ ] **Step 3: Reinstall the app to /Applications**

```bash
SRC="src-tauri/target/release/bundle/macos/Mac Scripta Viewer.app"
DEST="/Applications/Mac Scripta Viewer.app"
rm -rf "$DEST" && ditto "$SRC" "$DEST"
```

- [ ] **Step 4: Install the CLI**

Run: `sh install-cli.sh` then `which scripta` → `/opt/homebrew/bin/scripta`.

- [ ] **Step 5: Manual verification (requires GUI — user runs these)**

1. Quit the app if open. Run `scripta <some>.scripta` from a folder containing a `.scripta` file → app launches, that file opens in the preview, and the tree shows the folder's files.
2. With the app still open, run `scripta <another>.scripta` → the file opens **in the same window** (no second app instance).
3. `scripta nonexistent.scripta` → app opens, error banner shows the read failure.
4. `scripta` with no argument → app opens normally (empty).

- [ ] **Step 6: Commit any fixes** found during manual testing (no commit if none).

---

## Self-review notes (coverage map)

- Shell script → `/opt/homebrew/bin/scripta`, abs-path + `open -na --args`, no-arg launch → Task 6, install Task 7.
- Single-instance reuse + `open-file` emit → Task 2; frontend listen → Task 5; handler → Task 4.
- Cold-start argv → `LaunchFile` state + `take_launch_file` → Task 1; `init` pull + handler → Task 4.
- Shared `launch_file_from_args` (unit-tested) → Task 1.
- Vault = file's parent, open file → `openExternalFile` (Task 4) using `PathUtil` (Task 3).
- Error handling (bad path → banner; no-arg → no-op) → Task 4 (`PLaunchFile`/`GotOpenFile` decode), Task 6 (script).
- Tests: Rust `launch_file_from_args` (Task 1), Elm `PathUtil` (Task 3), manual (Task 7).
- Rebuild + reinstall impact → Task 7.

## Deferred (not in scope)

- Finder double-click association (`.scripta` UTI + document types in Info.plist).
- Prompting on dirty-document replacement when a new file is opened.
- A real app icon.
