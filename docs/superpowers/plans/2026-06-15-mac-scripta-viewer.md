# Mac Scripta Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS desktop app (Tauri 2 + Elm) that gives full local-filesystem CRUD over a "vault" folder of `.scripta` documents, with a live KaTeX-rendered preview, CodeMirror editing, debounced autosave, external-edit detection, and HTML/LaTeX export.

**Architecture:** A Tauri 2 (Rust) shell owns the disk and exposes async `invoke` commands; the Elm UI runs in the webview and stays pure, talking to Rust through three ports bridged by a thin JS shim using a `requestId` correlation scheme. The Scripta compiler (compiler-v3) is vendored unchanged; KaTeX and the CodeMirror custom element are vendored for fully offline operation.

**Tech Stack:** Tauri 2, Rust (`notify`, `trash`, `tempfile`, `tauri-plugin-dialog`), Elm 0.19.1, `elm-test`, vendored Scripta compiler-v3, vendored KaTeX 0.16.9, prebuilt `codemirror-element.js`.

---

## Reference material (read before starting)

- Spec: `docs/superpowers/specs/2026-06-15-mac-scripta-viewer-design.md`
- v4 app (port source): `/Users/carlson/dev/elm-work/scripta/scripta-app-v4/frontend`
  - `src/Editor.elm` (29 lines — copy nearly verbatim)
  - `src/SaveState.elm` (193 lines — trim to local-writer subset)
  - `src/Render.elm` (236 lines — reference only; rewrite against compiler-v3 API)
  - `index.html` (the `math-text` custom element ≈ lines 280–331; the `Elm.Main.init` + port wiring ≈ lines 400+)
  - `codemirror-element.js` (prebuilt `<codemirror-editor>` element — copy as-is)
- Compiler (vendor unchanged): `/Users/carlson/dev/elm-work/scripta/scripta-compiler-v3`
  - Public API: `src/Scripta.elm` — `parse : Options -> String -> Document`, `reparse : Options -> Document -> String -> Document`, `render : Options -> Document -> Output Event`, `compile : Options -> String -> Output Event`, `exportHtml : Options -> Document -> String`, `mapEvent`, builders `defaultOptions`/`withTheme`/`withWindowWidth`/`withContentWidth`/`withTOC`/`withMaxLevel`/`withSizing`, types `Theme(Light|Dark)`, `Event`, `SizingConfig` (7 fields: `baseFontSize, paragraphSpacing, marginLeft, marginRight, indentation, indentUnit, scale`).
  - LaTeX export: `src/Render/Export/LaTeX.elm` (`export`).

**Important compatibility note:** Do NOT copy v4's `Render.elm` verbatim — its `toScriptaSizing` returns `lineHeight`/`headingScale`, which do not exist in compiler-v3's `SizingConfig`. Our `Render.elm` (Task 12) targets compiler-v3's 7-field record.

**Path note:** The repo root contains a space (`Mac Scripta Viewer`). Always quote paths in shell commands. Tauri/Cargo tolerate this on macOS.

---

## File structure

```
Mac Scripta Viewer/
├── Makefile                         # chains: elm make + tauri dev/build
├── frontend/
│   ├── elm.json                     # Elm app config (Task 9)
│   ├── index.html                   # webview entry: loads dist/elm.js, vendor JS, defines custom elements + port shim
│   ├── src/
│   │   ├── Main.elm                 # init/update/subscriptions/wiring
│   │   ├── Types.elm                # Model, Msg, shared records, Format
│   │   ├── Workspace.elm            # file-tree model; id = path relative to vault root
│   │   ├── FileOps.elm              # FS port request/response encode-decode + requestId
│   │   ├── Editor.elm               # DOM ids + text-change decoder (from v4)
│   │   ├── Render.elm               # wraps Scripta parse/reparse/render; Event→Msg
│   │   ├── SaveState.elm            # debounced-save state machine (trimmed)
│   │   ├── Language.elm             # extension → Scripta|MiniLaTeX|Markdown
│   │   ├── Export.elm               # HTML / LaTeX export wiring
│   │   └── View.elm                 # three-pane layout
│   ├── scripta-compiler/            # vendored copy of compiler-v3 src/ (Task 8)
│   ├── vendor/
│   │   ├── katex/                   # katex.min.css/js, mhchem.min.js, fonts/ (Task 10)
│   │   └── codemirror-element.js    # copied from v4 (Task 14)
│   ├── dist/                        # elm make output (gitignored except .gitkeep)
│   └── tests/
│       ├── WorkspaceTest.elm
│       ├── FileOpsTest.elm
│       ├── SaveStateTest.elm
│       └── LanguageTest.elm
└── src-tauri/
    ├── Cargo.toml
    ├── tauri.conf.json
    ├── build.rs
    ├── capabilities/default.json    # Tauri 2 permissions
    └── src/
        ├── main.rs                  # app builder, command registration, watcher
        └── fs_commands.rs           # FS command handlers (unit-tested)
```

---

# Milestone 0: Project scaffolding & toolchain

### Task 1: Verify toolchain

**Files:** none.

- [ ] **Step 1: Confirm required tools are installed**

Run:
```bash
elm --version          # expect 0.19.1
cargo --version        # any recent stable
rustc --version
node --version         # for tauri CLI
```
Expected: all present. If `cargo`/`rustc` missing: `brew install rustup-init && rustup-init -y`. If Tauri CLI missing, it is added per-project in Task 3.

- [ ] **Step 2: Add a root `.gitignore`**

Create `/.gitignore`:
```
# Elm
frontend/elm-stuff/
frontend/dist/*
!frontend/dist/.gitkeep

# Rust / Tauri
src-tauri/target/
src-tauri/gen/

# macOS
.DS_Store
```

- [ ] **Step 3: Commit**

```bash
git add .gitignore
git commit -m "chore: add gitignore for elm/tauri build artifacts"
```

---

### Task 2: Create the Tauri Rust crate

**Files:**
- Create: `src-tauri/Cargo.toml`
- Create: `src-tauri/build.rs`
- Create: `src-tauri/src/main.rs`
- Create: `src-tauri/tauri.conf.json`
- Create: `src-tauri/capabilities/default.json`

- [ ] **Step 1: Write `src-tauri/Cargo.toml`**

```toml
[package]
name = "mac-scripta-viewer"
version = "0.1.0"
edition = "2021"
rust-version = "1.77"

[build-dependencies]
tauri-build = { version = "2", features = [] }

[dependencies]
tauri = { version = "2", features = [] }
tauri-plugin-dialog = "2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
notify = "6"
trash = "5"
walkdir = "2"

[dev-dependencies]
tempfile = "3"

[lib]
name = "app_lib"
path = "src/lib.rs"
crate-type = ["lib", "cdylib", "staticlib"]

[[bin]]
name = "mac-scripta-viewer"
path = "src/main.rs"
```

- [ ] **Step 2: Write `src-tauri/build.rs`**

```rust
fn main() {
    tauri_build::build()
}
```

- [ ] **Step 3: Write `src-tauri/tauri.conf.json`**

```json
{
  "$schema": "https://schema.tauri.app/config/2",
  "productName": "Mac Scripta Viewer",
  "version": "0.1.0",
  "identifier": "io.scripta.viewer",
  "build": {
    "frontendDist": "../frontend",
    "beforeDevCommand": "make elm",
    "beforeBuildCommand": "make elm"
  },
  "app": {
    "windows": [
      {
        "title": "Mac Scripta Viewer",
        "width": 1200,
        "height": 800
      }
    ],
    "security": {
      "csp": null
    }
  },
  "bundle": {
    "active": true,
    "targets": "app",
    "icon": []
  }
}
```

Note: `frontendDist` points at the static `frontend/` dir (no dev server). `csp: null` keeps things simple for local files; tighten later.

- [ ] **Step 4: Write `src-tauri/capabilities/default.json`**

```json
{
  "$schema": "../gen/schemas/desktop-schema.json",
  "identifier": "default",
  "description": "Default capabilities for the main window",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "dialog:default"
  ]
}
```

- [ ] **Step 5: Write a minimal `src-tauri/src/main.rs` (compiles, no commands yet)**

```rust
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    app_lib::run();
}
```

We move the real builder into a lib (`src/lib.rs`, Task 5) so it is unit-testable. Create a stub now:

- [ ] **Step 6: Write stub `src-tauri/src/lib.rs`**

```rust
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

- [ ] **Step 7: Verify the crate builds**

Run: `cd "src-tauri" && cargo build 2>&1 | tail -5`
Expected: `Finished` (it will fail to *run* without a frontend, but must compile). If `tauri::generate_context!` complains about missing frontendDist, ensure `frontend/` exists with an `index.html` placeholder:

```bash
mkdir -p "frontend/dist" && touch "frontend/dist/.gitkeep"
printf '<!doctype html><html><body>boot</body></html>' > "frontend/index.html"
```
Re-run `cargo build`. Expected: `Finished`.

- [ ] **Step 8: Commit**

```bash
git add src-tauri frontend/index.html frontend/dist/.gitkeep
git commit -m "feat: scaffold tauri 2 rust crate"
```

---

### Task 3: Add Tauri CLI + Makefile

**Files:**
- Create: `Makefile`
- Create: `package.json` (only to pin the Tauri CLI)

- [ ] **Step 1: Write `package.json`**

```json
{
  "name": "mac-scripta-viewer-tooling",
  "private": true,
  "devDependencies": {
    "@tauri-apps/cli": "^2"
  }
}
```

- [ ] **Step 2: Install the CLI**

Run: `npm install`
Expected: `@tauri-apps/cli` in `node_modules`.

- [ ] **Step 3: Write `Makefile`**

```makefile
.PHONY: elm dev build test test-elm test-rust

elm:
	cd frontend && elm make src/Main.elm --output=dist/elm.js

dev: elm
	npx tauri dev

build:
	npx tauri build

test: test-elm test-rust

test-elm:
	cd frontend && elm-test

test-rust:
	cd src-tauri && cargo test
```

Note: the `dev`/`build` targets work once `frontend/src/Main.elm` exists (Milestone 1). Until then use `make test-rust`.

- [ ] **Step 4: Add `node_modules/` to gitignore**

Append to `/.gitignore`:
```
node_modules/
```

- [ ] **Step 5: Commit**

```bash
git add Makefile package.json package-lock.json .gitignore
git commit -m "chore: add tauri cli and makefile"
```

---

# Milestone 1: Skeleton — boot, requestId bridge, pick vault, render tree

### Task 4: Rust `list_workspace` command (TDD)

**Files:**
- Create: `src-tauri/src/fs_commands.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Write the failing test**

Create `src-tauri/src/fs_commands.rs`:
```rust
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use walkdir::WalkDir;

/// One entry in the workspace tree, as sent to Elm.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Entry {
    /// Path relative to the workspace root, using '/' separators. This is the node id.
    pub path: String,
    pub name: String,
    pub is_dir: bool,
    /// Modification time in milliseconds since epoch (0 for dirs).
    pub mtime: u64,
}

const EXTS: [&str; 3] = ["scripta", "tex", "md"];

fn has_doc_ext(p: &Path) -> bool {
    p.extension()
        .and_then(|e| e.to_str())
        .map(|e| EXTS.contains(&e.to_lowercase().as_str()))
        .unwrap_or(false)
}

/// List all document files (and the dirs containing them) under `root`,
/// returning entries with workspace-relative paths.
pub fn list_workspace_impl(root: &Path) -> Result<Vec<Entry>, String> {
    let mut out = Vec::new();
    for dent in WalkDir::new(root).into_iter().filter_map(|e| e.ok()) {
        let p = dent.path();
        if p == root {
            continue;
        }
        let is_dir = dent.file_type().is_dir();
        if !is_dir && !has_doc_ext(p) {
            continue;
        }
        let rel = p
            .strip_prefix(root)
            .map_err(|e| e.to_string())?
            .to_string_lossy()
            .replace('\\', "/");
        let mtime = if is_dir { 0 } else { mtime_ms(p) };
        out.push(Entry {
            path: rel,
            name: dent.file_name().to_string_lossy().to_string(),
            is_dir,
            mtime,
        });
    }
    out.sort_by(|a, b| a.path.cmp(&b.path));
    Ok(out)
}

fn mtime_ms(p: &Path) -> u64 {
    std::fs::metadata(p)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

#[allow(dead_code)]
fn to_abs(root: &Path, rel: &str) -> PathBuf {
    root.join(rel)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn lists_only_doc_files_with_relative_paths() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        fs::create_dir(root.join("sub")).unwrap();
        fs::write(root.join("a.scripta"), "hello").unwrap();
        fs::write(root.join("sub/b.tex"), "x").unwrap();
        fs::write(root.join("ignore.png"), "x").unwrap();

        let entries = list_workspace_impl(root).unwrap();
        let paths: Vec<&str> = entries.iter().map(|e| e.path.as_str()).collect();

        assert!(paths.contains(&"a.scripta"));
        assert!(paths.contains(&"sub"));
        assert!(paths.contains(&"sub/b.tex"));
        assert!(!paths.iter().any(|p| p.contains("ignore.png")));
    }
}
```

- [ ] **Step 2: Run the test to verify it fails (then passes)**

Run: `cd "src-tauri" && cargo test list_workspace 2>&1 | tail -15`
Expected: compiles and **PASSES** (the impl is written alongside the test — this task is impl+test together because Rust unit tests live in the module). If it fails to compile, fix the module before moving on.

- [ ] **Step 3: Register the module in `lib.rs`**

Edit `src-tauri/src/lib.rs` to add at the top:
```rust
mod fs_commands;
```

- [ ] **Step 4: Verify build**

Run: `cd "src-tauri" && cargo build 2>&1 | tail -3`
Expected: `Finished`.

- [ ] **Step 5: Commit**

```bash
git add src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: list_workspace impl with tests"
```

---

### Task 5: Wire `list_workspace` + `pick_workspace` as Tauri commands

**Files:**
- Modify: `src-tauri/src/fs_commands.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Add the `#[tauri::command]` wrappers in `fs_commands.rs`**

Append:
```rust
#[tauri::command]
pub fn list_workspace(root: String) -> Result<Vec<Entry>, String> {
    list_workspace_impl(Path::new(&root))
}

#[tauri::command]
pub async fn pick_workspace(app: tauri::AppHandle) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;
    let (tx, rx) = std::sync::mpsc::channel();
    app.dialog().file().pick_folder(move |maybe| {
        let _ = tx.send(maybe);
    });
    let chosen = rx.recv().map_err(|e| e.to_string())?;
    Ok(chosen.map(|p| p.to_string()))
}
```

- [ ] **Step 2: Register commands in `lib.rs`**

Replace the `lib.rs` body:
```rust
mod fs_commands;

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            fs_commands::list_workspace,
            fs_commands::pick_workspace,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

- [ ] **Step 3: Verify build**

Run: `cd "src-tauri" && cargo build 2>&1 | tail -3`
Expected: `Finished`.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: expose list_workspace and pick_workspace commands"
```

---

### Task 6: Elm `Language` module (TDD)

**Files:**
- Create: `frontend/src/Language.elm`
- Create: `frontend/tests/LanguageTest.elm`

- [ ] **Step 1: Write the failing test**

Create `frontend/tests/LanguageTest.elm`:
```elm
module LanguageTest exposing (suite)

import Expect
import Language exposing (Language(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Language.fromPath"
        [ test "recognizes .scripta" <|
            \_ -> Expect.equal (Just Scripta) (Language.fromPath "notes/a.scripta")
        , test "recognizes .tex" <|
            \_ -> Expect.equal (Just MiniLaTeX) (Language.fromPath "a.tex")
        , test "recognizes .md" <|
            \_ -> Expect.equal (Just Markdown) (Language.fromPath "a.md")
        , test "is case-insensitive" <|
            \_ -> Expect.equal (Just Scripta) (Language.fromPath "A.SCRIPTA")
        , test "returns Nothing for unknown" <|
            \_ -> Expect.equal Nothing (Language.fromPath "a.png")
        , test "v1 supports only Scripta" <|
            \_ ->
                Expect.equal ( True, False, False )
                    ( Language.isSupported Scripta
                    , Language.isSupported MiniLaTeX
                    , Language.isSupported Markdown
                    )
        ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd "frontend" && elm-test tests/LanguageTest.elm 2>&1 | tail -10`
Expected: FAIL — `Language` module not found.

- [ ] **Step 3: Write `frontend/src/Language.elm`**

```elm
module Language exposing (Language(..), fromPath, isSupported, label)

{-| The markup language of a document, derived from its file extension.
Only Scripta is wired for rendering in v1; the others are reserved for
later milestones (the compiler needs a dispatch layer added upstream).
-}


type Language
    = Scripta
    | MiniLaTeX
    | Markdown


{-| Determine the language from a file path by its extension (case-insensitive).
-}
fromPath : String -> Maybe Language
fromPath path =
    case path |> String.split "." |> lastSegment |> Maybe.map String.toLower of
        Just "scripta" ->
            Just Scripta

        Just "tex" ->
            Just MiniLaTeX

        Just "md" ->
            Just Markdown

        _ ->
            Nothing


lastSegment : List String -> Maybe String
lastSegment xs =
    List.head (List.reverse xs)


{-| Whether v1 can render this language. Only Scripta for now.
-}
isSupported : Language -> Bool
isSupported lang =
    lang == Scripta


label : Language -> String
label lang =
    case lang of
        Scripta ->
            "Scripta"

        MiniLaTeX ->
            "MiniLaTeX"

        Markdown ->
            "Markdown"
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd "frontend" && elm-test tests/LanguageTest.elm 2>&1 | tail -10`
Expected: PASS (requires `elm.json` from Task 9 — if not yet present, do Task 9 first, then return).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/Language.elm frontend/tests/LanguageTest.elm
git commit -m "feat: Language module with extension detection"
```

---

### Task 7: Elm `Workspace` module (TDD)

**Files:**
- Create: `frontend/src/Workspace.elm`
- Create: `frontend/tests/WorkspaceTest.elm`

The Rust side sends a *flat* list of entries. `Workspace` decodes them and builds a sorted tree for display. Node id = `path`.

- [ ] **Step 1: Write the failing test**

Create `frontend/tests/WorkspaceTest.elm`:
```elm
module WorkspaceTest exposing (suite)

import Expect
import Json.Decode as D
import Test exposing (Test, describe, test)
import Workspace exposing (Entry, Node(..))


flatJson : String
flatJson =
    """
    [ {"path":"a.scripta","name":"a.scripta","is_dir":false,"mtime":10}
    , {"path":"sub","name":"sub","is_dir":true,"mtime":0}
    , {"path":"sub/b.scripta","name":"b.scripta","is_dir":false,"mtime":20}
    ]
    """


suite : Test
suite =
    describe "Workspace"
        [ test "decodes a flat entry list" <|
            \_ ->
                case D.decodeString (D.list Workspace.entryDecoder) flatJson of
                    Ok entries ->
                        Expect.equal 3 (List.length entries)

                    Err e ->
                        Expect.fail (D.errorToString e)
        , test "builds a tree with sub-folder nesting" <|
            \_ ->
                case D.decodeString (D.list Workspace.entryDecoder) flatJson of
                    Ok entries ->
                        let
                            roots =
                                Workspace.toTree entries
                        in
                        Expect.equal [ "a.scripta", "sub" ] (List.map Workspace.nodeName roots)

                    Err e ->
                        Expect.fail (D.errorToString e)
        , test "folder node contains its child file" <|
            \_ ->
                case D.decodeString (D.list Workspace.entryDecoder) flatJson of
                    Ok entries ->
                        let
                            childNames =
                                Workspace.toTree entries
                                    |> List.filterMap Workspace.folderChildren
                                    |> List.concat
                                    |> List.map Workspace.nodeName
                        in
                        Expect.equal [ "b.scripta" ] childNames

                    Err e ->
                        Expect.fail (D.errorToString e)
        ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd "frontend" && elm-test tests/WorkspaceTest.elm 2>&1 | tail -10`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `frontend/src/Workspace.elm`**

```elm
module Workspace exposing
    ( Entry, Node(..)
    , entryDecoder, toTree
    , nodeName, nodePath, folderChildren
    )

{-| Workspace (vault) file tree. The Rust shell sends a flat list of `Entry`;
`toTree` nests them by path. A node's id is its workspace-relative `path`.
-}

import Json.Decode as D
import Dict exposing (Dict)


type alias Entry =
    { path : String
    , name : String
    , isDir : Bool
    , mtime : Int
    }


type Node
    = FileNode { path : String, name : String, mtime : Int }
    | FolderNode { path : String, name : String, children : List Node }


entryDecoder : D.Decoder Entry
entryDecoder =
    D.map4 Entry
        (D.field "path" D.string)
        (D.field "name" D.string)
        (D.field "is_dir" D.bool)
        (D.field "mtime" D.int)


{-| Build top-level nodes from the flat entry list. Entries are assumed to be
sorted by path (the Rust side sorts), so a parent always precedes its children.
-}
toTree : List Entry -> List Node
toTree entries =
    let
        depth path =
            path |> String.split "/" |> List.length

        sorted =
            List.sortBy .path entries
    in
    -- Build by grouping on the parent path.
    buildLevel "" sorted


parentOf : String -> String
parentOf path =
    case path |> String.split "/" |> List.reverse of
        _ :: rest ->
            rest |> List.reverse |> String.join "/"

        [] ->
            ""


{-| Build all nodes whose parent path equals `parent`.
-}
buildLevel : String -> List Entry -> List Node
buildLevel parent entries =
    entries
        |> List.filter (\e -> parentOf e.path == parent)
        |> List.map
            (\e ->
                if e.isDir then
                    FolderNode
                        { path = e.path
                        , name = e.name
                        , children = buildLevel e.path entries
                        }

                else
                    FileNode { path = e.path, name = e.name, mtime = e.mtime }
            )


nodeName : Node -> String
nodeName node =
    case node of
        FileNode r ->
            r.name

        FolderNode r ->
            r.name


nodePath : Node -> String
nodePath node =
    case node of
        FileNode r ->
            r.path

        FolderNode r ->
            r.path


folderChildren : Node -> Maybe (List Node)
folderChildren node =
    case node of
        FolderNode r ->
            Just r.children

        FileNode _ ->
            Nothing
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd "frontend" && elm-test tests/WorkspaceTest.elm 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Remove the unused `depth`/`Dict` import warnings**

Delete the unused `depth` binding and the `import Dict` line if `elm make` reports them unused (Elm warns but compiles; keep the module clean).

- [ ] **Step 6: Commit**

```bash
git add frontend/src/Workspace.elm frontend/tests/WorkspaceTest.elm
git commit -m "feat: Workspace tree model with decoder and tests"
```

---

### Task 8: Vendor the Scripta compiler

**Files:**
- Create: `frontend/scripta-compiler/` (copied tree)

- [ ] **Step 1: Copy the compiler source**

Run:
```bash
cp -R "/Users/carlson/dev/elm-work/scripta/scripta-compiler-v3/src/." "frontend/scripta-compiler/"
ls "frontend/scripta-compiler/Scripta.elm"
```
Expected: the file exists.

- [ ] **Step 2: Note the extra packages the compiler needs**

Run: `grep -RhoE "^import [A-Za-z0-9_.]+" "frontend/scripta-compiler" | sort -u | head -50`
Expected: a list of imports. The dependency set is captured in `elm.json` (Task 9): notably `elm/parser`, `elm/regex`, `zwilias/elm-rosetree` (or `maca/elm-rose-tree`), `toastal/either`, `Janiczek/elm-bidict`, `mpizenberg/elm-pointer-events`, `pablohirafuji/elm-syntax-highlight`. Cross-check against the v4 `elm.json` direct deps list if compilation later reports a missing package.

- [ ] **Step 3: Commit**

```bash
git add frontend/scripta-compiler
git commit -m "vendor: copy scripta compiler-v3 source"
```

---

### Task 9: Elm app `elm.json`

**Files:**
- Create: `frontend/elm.json`

- [ ] **Step 1: Write `frontend/elm.json`**

Mirror the v4 direct deps that the compiler + app need. Start from this set:
```json
{
    "type": "application",
    "source-directories": [
        "src",
        "scripta-compiler"
    ],
    "elm-version": "0.19.1",
    "dependencies": {
        "direct": {
            "Garados007/elm-svg-parser": "1.1.2",
            "Janiczek/elm-bidict": "3.1.1",
            "elm/browser": "1.0.2",
            "elm/core": "1.0.5",
            "elm/html": "1.0.1",
            "elm/json": "1.1.4",
            "elm/parser": "1.1.0",
            "elm/regex": "1.0.0",
            "elm/time": "1.0.0",
            "elm/url": "1.0.0",
            "elm-community/list-extra": "8.7.0",
            "elm-community/maybe-extra": "5.3.0",
            "elm-community/result-extra": "2.4.0",
            "maca/elm-rose-tree": "1.2.1",
            "mpizenberg/elm-pointer-events": "5.0.0",
            "pablohirafuji/elm-syntax-highlight": "3.7.1",
            "toastal/either": "3.6.3",
            "zwilias/elm-rosetree": "1.5.0"
        },
        "indirect": {}
    },
    "test-dependencies": {
        "direct": {
            "elm-explorations/test": "2.2.1"
        },
        "indirect": {}
    }
}
```

- [ ] **Step 2: Resolve indirect dependencies automatically**

Run: `cd "frontend" && elm make src/Language.elm --output=/dev/null 2>&1 | tail -20`
Expected: Elm will report any missing packages. For each "I cannot find module X" or missing-package message, run `elm install <package>` (it edits `elm.json`). Repeat until `Language.elm` compiles. Then do the same compiling one compiler file: `elm make scripta-compiler/Scripta.elm --output=/dev/null`. Add packages until it succeeds. (This is the authoritative way to fill `indirect`.)

- [ ] **Step 3: Verify the test runner sees deps**

Run: `cd "frontend" && elm-test tests/LanguageTest.elm 2>&1 | tail -10`
Expected: PASS. If `elm-test` reports missing test deps, run `elm-test install elm-explorations/test`.

- [ ] **Step 4: Commit**

```bash
git add frontend/elm.json frontend/elm-tooling* 2>/dev/null; git add frontend/elm.json
git commit -m "feat: elm.json with compiler + app dependencies"
```

---

### Task 10: Vendor KaTeX (offline math)

**Files:**
- Create: `frontend/vendor/katex/` (css, js, mhchem, fonts)

- [ ] **Step 1: Download KaTeX 0.16.9 distribution**

Run:
```bash
mkdir -p "frontend/vendor/katex"
cd "frontend/vendor/katex"
curl -L -o katex.tgz https://registry.npmjs.org/katex/-/katex-0.16.9.tgz
tar -xzf katex.tgz
# the package unpacks to ./package/dist
cp package/dist/katex.min.css .
cp package/dist/katex.min.js .
cp package/dist/contrib/mhchem.min.js .
cp -R package/dist/fonts ./fonts
rm -rf package katex.tgz
ls
```
Expected: `katex.min.css  katex.min.js  mhchem.min.js  fonts/`.

- [ ] **Step 2: Verify font URLs resolve locally**

Run: `grep -o "fonts/[^)\"']*" katex.min.css | head -3`
Expected: paths like `fonts/KaTeX_Main-Regular.woff2`. Because `index.html` loads the CSS from `vendor/katex/katex.min.css`, these relative URLs resolve to `vendor/katex/fonts/...`. No edit needed.

- [ ] **Step 3: Commit**

```bash
git add -f frontend/vendor/katex
git commit -m "vendor: bundle KaTeX 0.16.9 for offline math"
```

(`-f` because some `.gitignore` rules may match; verify with `git status`.)

---

### Task 11: Elm `FileOps` module — port protocol + requestId (TDD)

**Files:**
- Create: `frontend/src/FileOps.elm`
- Create: `frontend/tests/FileOpsTest.elm`

`FileOps` defines the three ports and pure encode/decode helpers. Ports themselves cannot be unit-tested, but the request *encoders* and response *decoders* can.

- [ ] **Step 1: Write the failing test**

Create `frontend/tests/FileOpsTest.elm`:
```elm
module FileOpsTest exposing (suite)

import Expect
import FileOps exposing (FsResponse)
import Json.Decode as D
import Json.Encode as E
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "FileOps"
        [ test "encodes a readFile request with op, requestId, and args" <|
            \_ ->
                let
                    value =
                        FileOps.encodeRequest 7 "read_file" [ ( "path", E.string "a.scripta" ) ]

                    decoded =
                        D.decodeValue
                            (D.map3 (\a b c -> ( a, b, c ))
                                (D.field "requestId" D.int)
                                (D.field "op" D.string)
                                (D.at [ "args", "path" ] D.string)
                            )
                            value
                in
                Expect.equal (Ok ( 7, "read_file", "a.scripta" )) decoded
        , test "decodes a successful response" <|
            \_ ->
                let
                    json =
                        """{"requestId":7,"ok":true,"result":{"content":"hi","mtime":42}}"""
                in
                case D.decodeString FileOps.responseDecoder json of
                    Ok resp ->
                        Expect.equal 7 resp.requestId

                    Err e ->
                        Expect.fail (D.errorToString e)
        , test "decodes a failed response carrying the error" <|
            \_ ->
                let
                    json =
                        """{"requestId":9,"ok":false,"error":"ENOENT"}"""
                in
                case D.decodeString FileOps.responseDecoder json of
                    Ok resp ->
                        Expect.equal (Err "ENOENT") (FileOps.resultOf resp)

                    Err e ->
                        Expect.fail (D.errorToString e)
        ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd "frontend" && elm-test tests/FileOpsTest.elm 2>&1 | tail -10`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `frontend/src/FileOps.elm`**

```elm
port module FileOps exposing
    ( FsResponse
    , fsRequest, fsResponse, fileChanged
    , encodeRequest, responseDecoder, resultOf
    , send
    )

{-| The bridge to the Tauri shell. Every request carries a `requestId`; the
JS shim returns a matching response on `fsResponse`. `fileChanged` carries
unsolicited watcher events.
-}

import Json.Decode as D
import Json.Encode as E


port fsRequest : E.Value -> Cmd msg


port fsResponse : (E.Value -> msg) -> Sub msg


port fileChanged : (E.Value -> msg) -> Sub msg


type alias FsResponse =
    { requestId : Int
    , ok : Bool
    , result : D.Value
    , error : Maybe String
    }


{-| Build a request envelope: { requestId, op, args }. `op` is the snake_case
Tauri command name; `args` is a list of (key, value) pairs.
-}
encodeRequest : Int -> String -> List ( String, E.Value ) -> E.Value
encodeRequest requestId op args =
    E.object
        [ ( "requestId", E.int requestId )
        , ( "op", E.string op )
        , ( "args", E.object args )
        ]


{-| Encode and dispatch a request as a Cmd.
-}
send : Int -> String -> List ( String, E.Value ) -> Cmd msg
send requestId op args =
    fsRequest (encodeRequest requestId op args)


responseDecoder : D.Decoder FsResponse
responseDecoder =
    D.map4 FsResponse
        (D.field "requestId" D.int)
        (D.field "ok" D.bool)
        (D.oneOf [ D.field "result" D.value, D.succeed E.null ])
        (D.maybe (D.field "error" D.string))


{-| Interpret a response as a Result, returning the raw result value or the
error string.
-}
resultOf : FsResponse -> Result String D.Value
resultOf resp =
    if resp.ok then
        Ok resp.result

    else
        Err (Maybe.withDefault "unknown error" resp.error)
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd "frontend" && elm-test tests/FileOpsTest.elm 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/FileOps.elm frontend/tests/FileOpsTest.elm
git commit -m "feat: FileOps port protocol with requestId and tests"
```

---

### Task 12: Elm `Render` module (against compiler-v3 API)

**Files:**
- Create: `frontend/src/Render.elm`

No unit test (it produces opaque `Html`); verified via compilation here and visually in Task 17. Targets compiler-v3's 7-field `SizingConfig`.

- [ ] **Step 1: Write `frontend/src/Render.elm`**

```elm
module Render exposing (RenderMsg(..), RenderOutput, options, compile, renderDocument, parse)

{-| Thin wrapper over the vendored Scripta compiler. v1 renders Scripta only.
Targets compiler-v3's public API (SizingConfig has 7 fields — no lineHeight).
-}

import Html exposing (Html)
import Scripta


type RenderMsg
    = ScrollTo String
    | ScrollToWithReturn { targetId : String, returnId : String }
    | ExpandImage String
    | NavigateToDocument String
    | HighlightId String
    | RenderNoOp


type alias RenderOutput =
    { title : Html RenderMsg
    , body : List (Html RenderMsg)
    , toc : List (Html RenderMsg)
    }


{-| Compiler options for the given theme and content width (px).
-}
options : Bool -> Int -> Scripta.Options
options isLight contentWidth =
    Scripta.defaultOptions
        |> Scripta.withTheme
            (if isLight then
                Scripta.Light

             else
                Scripta.Dark
            )
        |> Scripta.withWindowWidth contentWidth
        |> Scripta.withContentWidth contentWidth
        |> Scripta.withTOC True
        |> Scripta.withMaxLevel 4


{-| Full parse — keep the returned Document in the model for incremental reparse.
-}
parse : Bool -> Int -> String -> Scripta.Document
parse isLight contentWidth source =
    Scripta.parse (options isLight contentWidth) source


{-| One-shot parse + render (cold path).
-}
compile : Bool -> Int -> String -> RenderOutput
compile isLight contentWidth source =
    Scripta.compile (options isLight contentWidth) source
        |> scriptaOutput


{-| Render a pre-parsed document (warm path, after reparse).
-}
renderDocument : Bool -> Int -> Scripta.Document -> RenderOutput
renderDocument isLight contentWidth document =
    Scripta.render (options isLight contentWidth) document
        |> scriptaOutput


scriptaOutput : Scripta.Output Scripta.Event -> RenderOutput
scriptaOutput out =
    let
        mapped =
            Scripta.mapEvent eventToMsg out
    in
    { title = mapped.title, body = mapped.body, toc = mapped.toc }


eventToMsg : Scripta.Event -> RenderMsg
eventToMsg event =
    case event of
        Scripta.ClickedId id_ ->
            ScrollTo id_

        Scripta.ClickedFootnote { targetId } ->
            ScrollTo targetId

        Scripta.ClickedCitation data ->
            ScrollToWithReturn data

        Scripta.ClickedImage url ->
            ExpandImage url

        Scripta.ClickedLink slug ->
            NavigateToDocument slug

        Scripta.HighlightedId id_ ->
            HighlightId id_
```

- [ ] **Step 2: Verify it compiles**

Run: `cd "frontend" && elm make src/Render.elm --output=/dev/null 2>&1 | tail -15`
Expected: success. If it reports `Output`/`mapEvent` arity issues, open `scripta-compiler/Scripta.elm` and match the exact signatures.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/Render.elm
git commit -m "feat: Render wrapper over scripta compiler (scripta-only v1)"
```

---

### Task 13: Elm `Editor` module (from v4)

**Files:**
- Create: `frontend/src/Editor.elm`

- [ ] **Step 1: Write `frontend/src/Editor.elm`** (copied from v4, unchanged)

```elm
module Editor exposing (docBodyId, renderedTextId, textChangeDecoder)

import Json.Decode as D


renderedTextId : String
renderedTextId =
    "__RENDERED_TEXT__"


docBodyId : String
docBodyId =
    "__DOC_BODY__"


{-| Decode the `text-change` custom event from the CodeMirror custom element.
Shape: `{ detail: { position: Int, source: String } }`.
-}
textChangeDecoder : D.Decoder String
textChangeDecoder =
    D.at [ "detail", "source" ] D.string
```

- [ ] **Step 2: Verify compile**

Run: `cd "frontend" && elm make src/Editor.elm --output=/dev/null 2>&1 | tail -5`
Expected: success.

- [ ] **Step 3: Commit**

```bash
git add frontend/src/Editor.elm
git commit -m "feat: Editor module (text-change decoder) from v4"
```

---

### Task 14: Vendor CodeMirror element + write `index.html` shell

**Files:**
- Create: `frontend/vendor/codemirror-element.js` (copied)
- Modify: `frontend/index.html`

- [ ] **Step 1: Copy the prebuilt CodeMirror element**

Run:
```bash
cp "/Users/carlson/dev/elm-work/scripta/scripta-app-v4/frontend/codemirror-element.js" "frontend/vendor/codemirror-element.js"
wc -l "frontend/vendor/codemirror-element.js"
```
Expected: ~27000 lines.

- [ ] **Step 2: Extract the `math-text` custom element from v4**

Open `/Users/carlson/dev/elm-work/scripta/scripta-app-v4/frontend/index.html` and copy the `class MathText extends HTMLElement { ... }` block plus `customElements.define('math-text', MathText)` (approx lines 280–331). You will paste it into `index.html` below.

- [ ] **Step 3: Write `frontend/index.html`**

```html
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>Mac Scripta Viewer</title>

    <!-- Vendored KaTeX (offline) -->
    <link rel="stylesheet" href="vendor/katex/katex.min.css" />
    <script defer src="vendor/katex/katex.min.js"></script>
    <script defer src="vendor/katex/mhchem.min.js"></script>

    <!-- Vendored CodeMirror custom element -->
    <script src="vendor/codemirror-element.js"></script>

    <style>
      html, body { margin: 0; height: 100%; }
      #app { height: 100vh; }
    </style>
  </head>
  <body>
    <div id="app"></div>
    <script src="dist/elm.js"></script>
    <script type="module">
      import { invoke } from 'https://unpkg.com/@tauri-apps/api/core';
      // NOTE: replace the import above with the bundled local module in Step 4.

      // --- math-text custom element (pasted from v4) ---
      // PASTE the MathText class + customElements.define('math-text', MathText) here.

      const app = Elm.Main.init({ node: document.getElementById('app') });

      // FS request bridge: Elm -> invoke -> Elm
      app.ports.fsRequest.subscribe(async (req) => {
        try {
          const result = await invoke(req.op, req.args || {});
          app.ports.fsResponse.send({ requestId: req.requestId, ok: true, result });
        } catch (e) {
          app.ports.fsResponse.send({ requestId: req.requestId, ok: false, error: String(e) });
        }
      });

      // Watcher events: Rust -> Elm
      const { listen } = await import('https://unpkg.com/@tauri-apps/api/event');
      await listen('file-changed', (e) => {
        app.ports.fileChanged.send(e.payload);
      });

      // scrollToElement port
      app.ports.scrollToElement.subscribe((id) => {
        const el = document.getElementById(id);
        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    </script>
  </body>
</html>
```

- [ ] **Step 4: Replace CDN imports with the local Tauri API**

The `@tauri-apps/api` import must be local for offline use. Install and copy it:
```bash
cd "frontend" && npm init -y >/dev/null 2>&1 || true
npm install @tauri-apps/api@^2
mkdir -p vendor/tauri
cp node_modules/@tauri-apps/api/*.js vendor/tauri/ 2>/dev/null || true
```
Then change the two `import ... from 'https://unpkg.com/...'` lines to import from `./vendor/tauri/core.js` and `./vendor/tauri/event.js`. Verify the filenames exist in `vendor/tauri/`; adjust the paths to match. Commit `vendor/tauri`.

If the bundled API module shape differs, the simpler fallback is to use the global injected by Tauri: replace `import { invoke }` with `const { invoke } = window.__TAURI__.core;` and `const { listen } = window.__TAURI__.event;` and set `"app": { "withGlobalTauri": true }` in `tauri.conf.json`. Prefer this fallback if module imports give trouble.

- [ ] **Step 5: Commit**

```bash
git add -f frontend/vendor/codemirror-element.js frontend/vendor/tauri 2>/dev/null
git add frontend/index.html
git commit -m "feat: webview shell — vendored codemirror, math-text, port bridge"
```

---

### Task 15: Elm `Types`, minimal `View`, and `Main` — boot + pick vault + show tree

**Files:**
- Create: `frontend/src/Types.elm`
- Create: `frontend/src/View.elm`
- Create: `frontend/src/Main.elm`

This is the first runnable end-to-end slice: open the app, click "Open Vault", pick a folder, see the file tree.

- [ ] **Step 1: Write `frontend/src/Types.elm`**

```elm
module Types exposing (Model, Msg(..), PendingOp(..), Pane(..))

import Dict exposing (Dict)
import FileOps
import Json.Decode as D
import Workspace exposing (Node)


type alias Model =
    { vaultRoot : Maybe String
    , tree : List Node
    , selectedPath : Maybe String
    , nextRequestId : Int
    , pending : Dict Int PendingOp
    , error : Maybe String
    }


{-| What a given requestId is waiting for, so the response can be interpreted.
-}
type PendingOp
    = PPickWorkspace
    | PListWorkspace
    | PReadFile String
    | PWriteFile String
    | PCreateFile String
    | PCreateDir String
    | PRename String String
    | PDelete String
    | PExportSave


type Pane
    = TreePane
    | EditorPane
    | PreviewPane


type Msg
    = ClickedOpenVault
    | ClickedTreeNode String
    | GotFsResponse D.Value
    | GotFileChanged D.Value
    | DismissError
```

- [ ] **Step 2: Write a minimal `frontend/src/View.elm`**

```elm
module View exposing (view)

import Html exposing (Html, button, div, li, text, ul)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick)
import Types exposing (Model, Msg(..))
import Workspace exposing (Node(..))


view : Model -> Html Msg
view model =
    div [ style "display" "flex", style "height" "100vh", style "font-family" "system-ui" ]
        [ div [ style "width" "260px", style "border-right" "1px solid #ddd", style "padding" "8px", style "overflow" "auto" ]
            (button [ onClick ClickedOpenVault ] [ text "Open Vault" ]
                :: errorBanner model
                ++ [ treeView model.tree ]
            )
        , div [ style "flex" "1", style "padding" "8px" ]
            [ text (Maybe.withDefault "No file selected" model.selectedPath) ]
        ]


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


treeView : List Node -> Html Msg
treeView nodes =
    ul [ style "list-style" "none", style "padding-left" "12px" ]
        (List.map nodeView nodes)


nodeView : Node -> Html Msg
nodeView node =
    case node of
        FileNode r ->
            li [ onClick (ClickedTreeNode r.path), style "cursor" "pointer" ] [ text r.name ]

        FolderNode r ->
            li []
                [ text ("📁 " ++ r.name)
                , treeView r.children
                ]
```

- [ ] **Step 3: Write `frontend/src/Main.elm`**

```elm
module Main exposing (main)

import Browser
import Dict
import FileOps
import Json.Decode as D
import Json.Encode as E
import Types exposing (Model, Msg(..), PendingOp(..))
import View
import Workspace


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = View.view
        }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { vaultRoot = Nothing
      , tree = []
      , selectedPath = Nothing
      , nextRequestId = 0
      , pending = Dict.empty
      , error = Nothing
      }
    , Cmd.none
    )


{-| Issue an FS request, recording the pending op against its requestId.
-}
request : PendingOp -> String -> List ( String, E.Value ) -> Model -> ( Model, Cmd Msg )
request op cmdName args model =
    let
        rid =
            model.nextRequestId
    in
    ( { model
        | nextRequestId = rid + 1
        , pending = Dict.insert rid op model.pending
      }
    , FileOps.send rid cmdName args
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ClickedOpenVault ->
            request PPickWorkspace "pick_workspace" [] model

        ClickedTreeNode path ->
            ( { model | selectedPath = Just path }, Cmd.none )

        DismissError ->
            ( { model | error = Nothing }, Cmd.none )

        GotFileChanged _ ->
            ( model, Cmd.none )

        GotFsResponse value ->
            case D.decodeValue FileOps.responseDecoder value of
                Err e ->
                    ( { model | error = Just (D.errorToString e) }, Cmd.none )

                Ok resp ->
                    case Dict.get resp.requestId model.pending of
                        Nothing ->
                            ( model, Cmd.none )

                        Just op ->
                            handleResponse op resp { model | pending = Dict.remove resp.requestId model.pending }


handleResponse : PendingOp -> FileOps.FsResponse -> Model -> ( Model, Cmd Msg )
handleResponse op resp model =
    case FileOps.resultOf resp of
        Err e ->
            ( { model | error = Just e }, Cmd.none )

        Ok result ->
            case op of
                PPickWorkspace ->
                    case D.decodeValue (D.nullable D.string) result of
                        Ok (Just root) ->
                            request PListWorkspace "list_workspace" [ ( "root", E.string root ) ] { model | vaultRoot = Just root }

                        _ ->
                            ( model, Cmd.none )

                PListWorkspace ->
                    case D.decodeValue (D.list Workspace.entryDecoder) result of
                        Ok entries ->
                            ( { model | tree = Workspace.toTree entries }, Cmd.none )

                        Err e ->
                            ( { model | error = Just (D.errorToString e) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ FileOps.fsResponse GotFsResponse
        , FileOps.fileChanged GotFileChanged
        ]
```

- [ ] **Step 4: Add the `scrollToElement` port (needed by index.html)**

`index.html` subscribes to `app.ports.scrollToElement`. Declare it now so the JS does not error. Add to `frontend/src/FileOps.elm` exposing list and body:
```elm
port scrollToElement : String -> Cmd msg
```
(Add `scrollToElement` to the `port module FileOps exposing (...)` list.)

- [ ] **Step 5: Build the Elm app**

Run: `make elm 2>&1 | tail -20`
Expected: `Success! Compiled ... dist/elm.js`. Fix any compile errors (unused imports, etc.) until green.

- [ ] **Step 6: Run the app and verify the slice**

Run: `make dev`
Manual check: window opens → click **Open Vault** → native folder dialog appears → pick a folder containing a `.scripta` file → the file tree shows it. Click a file → its path appears in the right pane.
Expected: all of the above works. If the dialog does not appear, confirm `dialog:default` is in `capabilities/default.json` and the plugin is registered in `lib.rs`.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/Types.elm frontend/src/View.elm frontend/src/Main.elm frontend/src/FileOps.elm
git commit -m "feat: milestone 1 — boot, open vault, render file tree"
```

---

# Milestone 2: Read + render

### Task 16: Rust `read_file` command (TDD)

**Files:**
- Modify: `src-tauri/src/fs_commands.rs`
- Modify: `src-tauri/src/lib.rs`

- [ ] **Step 1: Write the failing test**

Add to the `tests` module in `fs_commands.rs`:
```rust
    #[test]
    fn reads_file_content_and_mtime() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        fs::write(root.join("a.scripta"), "# Title\nbody").unwrap();

        let fc = read_file_impl(root, "a.scripta").unwrap();
        assert_eq!(fc.content, "# Title\nbody");
        assert!(fc.mtime > 0);
    }

    #[test]
    fn read_missing_file_errors() {
        let dir = tempdir().unwrap();
        assert!(read_file_impl(dir.path(), "nope.scripta").is_err());
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd "src-tauri" && cargo test reads_file 2>&1 | tail -15`
Expected: FAIL — `read_file_impl` / `FileContent` not found.

- [ ] **Step 3: Implement**

Add to `fs_commands.rs`:
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileContent {
    pub content: String,
    pub mtime: u64,
}

pub fn read_file_impl(root: &Path, rel: &str) -> Result<FileContent, String> {
    let abs = root.join(rel);
    let content = std::fs::read_to_string(&abs).map_err(|e| e.to_string())?;
    Ok(FileContent { content, mtime: mtime_ms(&abs) })
}

#[tauri::command]
pub fn read_file(root: String, path: String) -> Result<FileContent, String> {
    read_file_impl(Path::new(&root), &path)
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd "src-tauri" && cargo test reads_file 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Register the command** in `lib.rs` `generate_handler!` list (add `fs_commands::read_file,`).

- [ ] **Step 6: Commit**

```bash
git add src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: read_file command with tests"
```

---

### Task 17: Read a file and show the live preview

**Files:**
- Modify: `frontend/src/Types.elm`
- Modify: `frontend/src/Main.elm`
- Modify: `frontend/src/View.elm`

- [ ] **Step 1: Extend the Model and Msg**

In `Types.elm`, add fields to `Model`:
```elm
    , content : String
    , parsedDoc : Maybe Scripta.Document
    , language : Maybe Language.Language
    , isLight : Bool
    , contentWidth : Int
```
Add imports: `import Scripta`, `import Language`. The `read_file` result needs decoding — add a Msg path is already covered by `GotFsResponse`. No new Msg needed yet.

- [ ] **Step 2: Initialize the new fields** in `Main.init`:
```elm
      , content = ""
      , parsedDoc = Nothing
      , language = Nothing
      , isLight = True
      , contentWidth = 500
```

- [ ] **Step 3: Trigger `read_file` on node click**

In `Main.update`, change `ClickedTreeNode`:
```elm
        ClickedTreeNode path ->
            case model.vaultRoot of
                Just root ->
                    request (PReadFile path)
                        "read_file"
                        [ ( "root", E.string root ), ( "path", E.string path ) ]
                        { model | selectedPath = Just path, language = Language.fromPath path }

                Nothing ->
                    ( model, Cmd.none )
```

- [ ] **Step 4: Handle the `read_file` response** in `handleResponse`:
```elm
                PReadFile _ ->
                    case D.decodeValue (D.field "content" D.string) result of
                        Ok content ->
                            let
                                parsed =
                                    if model.language == Just Language.Scripta then
                                        Just (Render.parse model.isLight model.contentWidth content)

                                    else
                                        Nothing
                            in
                            ( { model | content = content, parsedDoc = parsed }, Cmd.none )

                        Err e ->
                            ( { model | error = Just (D.errorToString e) }, Cmd.none )
```
Add `import Render` to `Main.elm`.

- [ ] **Step 5: Render the preview pane in `View.elm`**

Replace the right-hand `div` with a preview that maps `Render.RenderMsg` to a no-op for now (interactions wired in Milestone 3+):
```elm
        , div [ Html.Attributes.id Editor.renderedTextId, style "flex" "1", style "padding" "16px", style "overflow" "auto" ]
            (previewBody model)
        ]


previewBody : Model -> List (Html Msg)
previewBody model =
    case ( model.language, model.parsedDoc ) of
        ( Just Language.Scripta, Just doc ) ->
            let
                out =
                    Render.renderDocument model.isLight model.contentWidth doc
            in
            (out.title :: out.body)
                |> List.map (Html.map (\_ -> NoOpFromRender))

        ( Just lang, _ ) ->
            [ Html.text (Language.label lang ++ " rendering is not yet supported.") ]

        ( Nothing, _ ) ->
            [ Html.text "Open a .scripta file." ]
```
Add a `NoOpFromRender` variant to `Msg` (Types.elm) to absorb render events for now:
```elm
    | NoOpFromRender
```
Handle it in `update`:
```elm
        NoOpFromRender ->
            ( model, Cmd.none )
```
Add imports to `View.elm`: `import Render`, `import Language`, `import Editor`, `import Html`.

- [ ] **Step 6: Build, run, verify**

Run: `make elm 2>&1 | tail -5 && make dev`
Manual check: open vault → click a `.scripta` file → rendered HTML appears in the right pane, **math renders via KaTeX** (try a file with `$x^2$`). Open a `.tex`/`.md` file → "not yet supported" message.
Expected: as above. If math shows raw `$...$`, confirm the `math-text` element is pasted into `index.html` and KaTeX assets load (check devtools network — all local, no CDN).

- [ ] **Step 7: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm
git commit -m "feat: milestone 2 — read file and live preview with KaTeX"
```

---

# Milestone 3: Edit + debounced autosave

### Task 18: Rust `write_file` command (TDD)

**Files:**
- Modify: `src-tauri/src/fs_commands.rs`, `src-tauri/src/lib.rs`

- [ ] **Step 1: Write the failing test**

Add to `tests`:
```rust
    #[test]
    fn writes_file_and_returns_new_mtime() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        let mt = write_file_impl(root, "a.scripta", "new content").unwrap();
        assert!(mt > 0);
        assert_eq!(fs::read_to_string(root.join("a.scripta")).unwrap(), "new content");
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd "src-tauri" && cargo test writes_file 2>&1 | tail -10`
Expected: FAIL — `write_file_impl` not found.

- [ ] **Step 3: Implement**

```rust
pub fn write_file_impl(root: &Path, rel: &str, content: &str) -> Result<u64, String> {
    let abs = root.join(rel);
    if let Some(parent) = abs.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    std::fs::write(&abs, content).map_err(|e| e.to_string())?;
    Ok(mtime_ms(&abs))
}

#[tauri::command]
pub fn write_file(root: String, path: String, content: String) -> Result<u64, String> {
    write_file_impl(Path::new(&root), &path, &content)
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd "src-tauri" && cargo test writes_file 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Register `write_file`** in `lib.rs`.

- [ ] **Step 6: Commit**

```bash
git add src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: write_file command with tests"
```

---

### Task 19: Trim and add `SaveState` (TDD)

**Files:**
- Create: `frontend/src/SaveState.elm`
- Create: `frontend/tests/SaveStateTest.elm`

This is a trimmed version of v4's `SaveState.elm`: keep the debounce + single-in-flight + resave-latest logic; drop the 403 (baton) and 409 (version) recovery since there is one local writer. Define `SaveStatus` locally (v4 imported it from Types).

- [ ] **Step 1: Write the failing test**

Create `frontend/tests/SaveStateTest.elm`:
```elm
module SaveStateTest exposing (suite)

import Expect
import SaveState exposing (Action(..), SaveStatus(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "SaveState"
        [ test "textChanged bumps debounceId and schedules a debounce" <|
            \_ ->
                let
                    ( s, action ) =
                        SaveState.textChanged 1000 SaveState.init
                in
                Expect.equal ( s.debounceId, action ) ( 1, ScheduleDebounce 1 1000 )
        , test "debounceFired for the latest id starts a save" <|
            \_ ->
                let
                    ( s1, _ ) =
                        SaveState.textChanged 1000 SaveState.init

                    ( _, action ) =
                        SaveState.debounceFired s1.debounceId s1
                in
                Expect.equal (PerformSave 1) action
        , test "a stale debounce id does nothing" <|
            \_ ->
                let
                    ( s1, _ ) =
                        SaveState.textChanged 1000 SaveState.init
                in
                Expect.equal NoAction (Tuple.second (SaveState.debounceFired 0 s1))
        , test "no overlapping saves: debounceFired is a no-op while in flight" <|
            \_ ->
                let
                    ( s1, _ ) =
                        SaveState.textChanged 1000 SaveState.init

                    ( s2, _ ) =
                        SaveState.debounceFired s1.debounceId s1

                    -- user types again while save in flight
                    ( s3, _ ) =
                        SaveState.textChanged 1000 s2

                    ( _, action ) =
                        SaveState.debounceFired s3.debounceId s3
                in
                Expect.equal NoAction action
        , test "saveSucceeded resaves latest if user typed during the save" <|
            \_ ->
                let
                    ( s1, _ ) =
                        SaveState.textChanged 1000 SaveState.init

                    ( s2, _ ) =
                        SaveState.debounceFired s1.debounceId s1

                    ( s3, _ ) =
                        SaveState.textChanged 1000 s2

                    ( _, action ) =
                        SaveState.saveSucceeded s3
                in
                Expect.equal (PerformSave s3.debounceId) action
        , test "saveSucceeded settles to Saved when nothing changed" <|
            \_ ->
                let
                    ( s1, _ ) =
                        SaveState.textChanged 1000 SaveState.init

                    ( s2, _ ) =
                        SaveState.debounceFired s1.debounceId s1

                    ( s3, action ) =
                        SaveState.saveSucceeded s2
                in
                Expect.equal ( Saved, NoAction ) ( s3.saveStatus, action )
        ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd "frontend" && elm-test tests/SaveStateTest.elm 2>&1 | tail -10`
Expected: FAIL — module not found.

- [ ] **Step 3: Write `frontend/src/SaveState.elm`**

```elm
module SaveState exposing
    ( SaveState, SaveStatus(..), Action(..)
    , init, textChanged, debounceFired, saveSucceeded, saveFailed
    )

{-| Pure debounced-save state machine for a single local writer.

Guarantees:
  - At most one write is in flight (`inFlight`).
  - If the user types while a write is in flight, exactly one follow-up write
    fires after it completes, capturing the latest content (debounceId /= savingId).

Trimmed from scripta-app-v4's SaveState: the 403 (baton) and 409 (version
conflict) recovery paths are removed — there is only one local writer. External
edits are handled separately via the file watcher (Milestone 5).
-}


type SaveStatus
    = Saved
    | Unsaved
    | Saving


type alias SaveState =
    { saveStatus : SaveStatus
    , debounceId : Int
    , hasUnsavedContent : Bool
    , inFlight : Bool
    , savingId : Int
    }


type Action
    = NoAction
    | ScheduleDebounce Int Float
    | PerformSave Int


init : SaveState
init =
    { saveStatus = Saved
    , debounceId = 0
    , hasUnsavedContent = False
    , inFlight = False
    , savingId = 0
    }


textChanged : Float -> SaveState -> ( SaveState, Action )
textChanged debounceDelayMs state =
    let
        newId =
            state.debounceId + 1

        newStatus =
            if state.inFlight then
                Saving

            else
                Unsaved
    in
    ( { state | saveStatus = newStatus, debounceId = newId, hasUnsavedContent = True }
    , ScheduleDebounce newId debounceDelayMs
    )


debounceFired : Int -> SaveState -> ( SaveState, Action )
debounceFired firedId state =
    if firedId == state.debounceId && state.hasUnsavedContent && not state.inFlight then
        ( { state | saveStatus = Saving, inFlight = True, savingId = firedId }
        , PerformSave firedId
        )

    else
        ( state, NoAction )


saveSucceeded : SaveState -> ( SaveState, Action )
saveSucceeded state =
    if state.debounceId /= state.savingId then
        ( { state | saveStatus = Saving, inFlight = True, savingId = state.debounceId }
        , PerformSave state.debounceId
        )

    else
        ( { state | saveStatus = Saved, hasUnsavedContent = False, inFlight = False }
        , NoAction
        )


saveFailed : SaveState -> ( SaveState, Action )
saveFailed state =
    ( { state | saveStatus = Unsaved, inFlight = False }, NoAction )
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd "frontend" && elm-test tests/SaveStateTest.elm 2>&1 | tail -10`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/SaveState.elm frontend/tests/SaveStateTest.elm
git commit -m "feat: trimmed SaveState debounce machine with tests"
```

---

### Task 20: Wire the CodeMirror editor + autosave into the app

**Files:**
- Modify: `frontend/src/Types.elm`, `frontend/src/Main.elm`, `frontend/src/View.elm`

- [ ] **Step 1: Extend Model/Msg** in `Types.elm`

Add to `Model`:
```elm
    , saveState : SaveState.SaveState
```
Add Msgs:
```elm
    | EditorChanged String
    | DebounceFired Int
    | GotSaveResult Int
```
Add `import SaveState`.

- [ ] **Step 2: Initialize** `saveState = SaveState.init` in `Main.init`.

- [ ] **Step 3: Render the CodeMirror element** in `View.elm` middle pane

Insert between tree and preview:
```elm
        , Html.node "codemirror-editor"
            [ Html.Attributes.attribute "text" model.content
            , Html.Events.on "text-change" (D.map EditorChanged Editor.textChangeDecoder)
            , style "flex" "1"
            ]
            []
```
Add `import Json.Decode as D` to `View.elm`. (The `text` attribute seeds the editor; the element emits `text-change` on edits — confirm the attribute name against `codemirror-element.js`; adjust if it expects `doc` or `value`.)

- [ ] **Step 4: Handle editor + save Msgs** in `Main.update`

```elm
        EditorChanged newText ->
            let
                ( ss, action ) =
                    SaveState.textChanged 1000 model.saveState

                reparsed =
                    if model.language == Just Language.Scripta then
                        Maybe.map (\d -> Scripta.reparse (Render.options model.isLight model.contentWidth) d newText) model.parsedDoc

                    else
                        model.parsedDoc
            in
            ( { model | content = newText, parsedDoc = reparsed, saveState = ss }
            , performSaveAction action
            )

        DebounceFired firedId ->
            let
                ( ss, action ) =
                    SaveState.debounceFired firedId model.saveState
            in
            ( { model | saveState = ss }, performSaveAction action )

        GotSaveResult _ ->
            let
                ( ss, action ) =
                    SaveState.saveSucceeded model.saveState
            in
            ( { model | saveState = ss }, performSaveAction action )
```
Add the action interpreter and a save dispatcher:
```elm
performSaveAction : SaveState.Action -> Cmd Msg
performSaveAction action =
    case action of
        SaveState.NoAction ->
            Cmd.none

        SaveState.ScheduleDebounce id delay ->
            Process.sleep delay |> Task.perform (\_ -> DebounceFired id)

        SaveState.PerformSave _ ->
            -- handled in update where model is in scope; see saveCurrent
            Cmd.none
```
Because `PerformSave` needs `vaultRoot`/`selectedPath`/`content`, handle it in `update` instead of the pure interpreter. Replace the `performSaveAction` calls for `PerformSave` with a guard that issues the write request. Concretely, factor a helper used by all three branches:
```elm
applySaveAction : SaveState.Action -> Model -> ( Model, Cmd Msg )
applySaveAction action model =
    case action of
        SaveState.NoAction ->
            ( model, Cmd.none )

        SaveState.ScheduleDebounce id delay ->
            ( model, Process.sleep delay |> Task.perform (\_ -> DebounceFired id) )

        SaveState.PerformSave _ ->
            case ( model.vaultRoot, model.selectedPath ) of
                ( Just root, Just path ) ->
                    request (PWriteFile path)
                        "write_file"
                        [ ( "root", E.string root ), ( "path", E.string path ), ( "content", E.string model.content ) ]
                        model

                _ ->
                    ( model, Cmd.none )
```
Then in each branch use `applySaveAction action { model | ... }` instead of `performSaveAction`, and remove the standalone `performSaveAction`. In `handleResponse`, add:
```elm
                PWriteFile _ ->
                    update (GotSaveResult resp.requestId) model
```
Add imports to `Main.elm`: `import Process`, `import Task`, `import Scripta`.

- [ ] **Step 5: Show save status** in `View.elm` tree pane

```elm
        , div [ style "font-size" "12px", style "color" "#666" ]
            [ text (saveLabel model.saveState.saveStatus) ]
```
with
```elm
saveLabel : SaveState.SaveStatus -> String
saveLabel status =
    case status of
        SaveState.Saved -> "Saved"
        SaveState.Unsaved -> "Unsaved…"
        SaveState.Saving -> "Saving…"
```
Add `import SaveState` to `View.elm`.

- [ ] **Step 6: Build, run, verify**

Run: `make elm 2>&1 | tail -5 && make dev`
Manual check: open a `.scripta` file → edit in the middle pane → preview updates live → status shows "Unsaved…" then "Saved" ~1s after you stop typing → reopen the file (or check on disk) and confirm the edit persisted.
Expected: as above.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm
git commit -m "feat: milestone 3 — CodeMirror editing with debounced autosave"
```

---

# Milestone 4: Full CRUD + change vault

### Task 21: Rust create/rename/delete commands (TDD)

**Files:**
- Modify: `src-tauri/src/fs_commands.rs`, `src-tauri/src/lib.rs`

- [ ] **Step 1: Write the failing tests**

Add to `tests`:
```rust
    #[test]
    fn creates_file_and_dir() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        create_dir_impl(root, "newdir").unwrap();
        create_file_impl(root, "newdir/x.scripta", "").unwrap();
        assert!(root.join("newdir/x.scripta").exists());
    }

    #[test]
    fn renames_path() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        fs::write(root.join("a.scripta"), "x").unwrap();
        rename_impl(root, "a.scripta", "b.scripta").unwrap();
        assert!(!root.join("a.scripta").exists());
        assert!(root.join("b.scripta").exists());
    }

    #[test]
    fn delete_moves_to_trash_not_hard_delete() {
        let dir = tempdir().unwrap();
        let root = dir.path();
        fs::write(root.join("a.scripta"), "x").unwrap();
        delete_impl(root, "a.scripta").unwrap();
        assert!(!root.join("a.scripta").exists());
        // We cannot assert the trash location portably; just assert no error + gone.
    }
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd "src-tauri" && cargo test creates_file 2>&1 | tail -10`
Expected: FAIL — impls not found.

- [ ] **Step 3: Implement**

```rust
pub fn create_dir_impl(root: &Path, rel: &str) -> Result<(), String> {
    std::fs::create_dir_all(root.join(rel)).map_err(|e| e.to_string())
}

pub fn create_file_impl(root: &Path, rel: &str, content: &str) -> Result<u64, String> {
    let abs = root.join(rel);
    if abs.exists() {
        return Err(format!("{} already exists", rel));
    }
    write_file_impl(root, rel, content)
}

pub fn rename_impl(root: &Path, rel: &str, new_rel: &str) -> Result<(), String> {
    let to = root.join(new_rel);
    if let Some(parent) = to.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    std::fs::rename(root.join(rel), to).map_err(|e| e.to_string())
}

pub fn delete_impl(root: &Path, rel: &str) -> Result<(), String> {
    trash::delete(root.join(rel)).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn create_dir(root: String, path: String) -> Result<(), String> {
    create_dir_impl(Path::new(&root), &path)
}

#[tauri::command]
pub fn create_file(root: String, path: String, content: String) -> Result<u64, String> {
    create_file_impl(Path::new(&root), &path, &content)
}

#[tauri::command]
pub fn rename(root: String, path: String, new_path: String) -> Result<(), String> {
    rename_impl(Path::new(&root), &path, &new_path)
}

#[tauri::command]
pub fn delete(root: String, path: String) -> Result<(), String> {
    delete_impl(Path::new(&root), &path)
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd "src-tauri" && cargo test 2>&1 | tail -15`
Expected: all FS tests PASS.

- [ ] **Step 5: Register** the four commands in `lib.rs`.

- [ ] **Step 6: Commit**

```bash
git add src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: create/rename/delete (trash) commands with tests"
```

---

### Task 22: Wire CRUD + change-vault into the UI

**Files:**
- Modify: `frontend/src/Types.elm`, `frontend/src/Main.elm`, `frontend/src/View.elm`

- [ ] **Step 1: Add Msgs** in `Types.elm`

```elm
    | ClickedNewFile
    | ClickedDeleteSelected
    | ClickedRenameSelected String
    | ClickedChangeVault
```
(For v1, gather new-file/rename names with `Browser.Dom`-free simple approach: prompt via a small text input in the tree pane. To keep the plan concrete, use a `newName` field.)
Add to `Model`: `newName : String` and Msg `SetNewName String`.

- [ ] **Step 2: Initialize** `newName = ""`.

- [ ] **Step 3: Implement handlers** in `Main.update`

```elm
        SetNewName s ->
            ( { model | newName = s }, Cmd.none )

        ClickedChangeVault ->
            request PPickWorkspace "pick_workspace" [] model

        ClickedNewFile ->
            case model.vaultRoot of
                Just root ->
                    let
                        path =
                            ensureScriptaExt model.newName
                    in
                    request (PCreateFile path)
                        "create_file"
                        [ ( "root", E.string root ), ( "path", E.string path ), ( "content", E.string "" ) ]
                        { model | newName = "" }

                Nothing ->
                    ( model, Cmd.none )

        ClickedDeleteSelected ->
            case ( model.vaultRoot, model.selectedPath ) of
                ( Just root, Just path ) ->
                    request (PDelete path)
                        "delete"
                        [ ( "root", E.string root ), ( "path", E.string path ) ]
                        model

                _ ->
                    ( model, Cmd.none )

        ClickedRenameSelected newPath ->
            case ( model.vaultRoot, model.selectedPath ) of
                ( Just root, Just path ) ->
                    request (PRename path newPath)
                        "rename"
                        [ ( "root", E.string root ), ( "path", E.string path ), ( "new_path", E.string newPath ) ]
                        model

                _ ->
                    ( model, Cmd.none )
```
Add helper:
```elm
ensureScriptaExt : String -> String
ensureScriptaExt name =
    if String.endsWith ".scripta" name then
        name

    else
        name ++ ".scripta"
```

- [ ] **Step 4: Refresh the tree after each mutation** in `handleResponse`

After create/rename/delete succeed, re-list the workspace:
```elm
                PCreateFile _ ->
                    relist model

                PCreateDir _ ->
                    relist model

                PRename _ _ ->
                    relist { model | selectedPath = Nothing, content = "", parsedDoc = Nothing }

                PDelete _ ->
                    relist { model | selectedPath = Nothing, content = "", parsedDoc = Nothing }
```
with
```elm
relist : Model -> ( Model, Cmd Msg )
relist model =
    case model.vaultRoot of
        Just root ->
            request PListWorkspace "list_workspace" [ ( "root", E.string root ) ] model

        Nothing ->
            ( model, Cmd.none )
```

- [ ] **Step 5: Add UI controls** in `View.elm` tree pane

```elm
        , div []
            [ Html.input
                [ Html.Attributes.placeholder "new-file-name"
                , Html.Attributes.value model.newName
                , Html.Events.onInput SetNewName
                ]
                []
            , button [ onClick ClickedNewFile ] [ text "New" ]
            , button [ onClick ClickedDeleteSelected ] [ text "Delete" ]
            , button [ onClick ClickedChangeVault ] [ text "Change Vault" ]
            ]
```

- [ ] **Step 6: Build, run, verify**

Run: `make elm 2>&1 | tail -5 && make dev`
Manual check: type a name → **New** creates `name.scripta` and it appears in the tree → select it, edit, autosave → **Delete** moves it to Trash (verify in Finder Trash) and it disappears → **Change Vault** opens a new folder and replaces the tree.
Expected: all of the above. Confirm the deleted file is recoverable from Trash.

- [ ] **Step 7: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm
git commit -m "feat: milestone 4 — full CRUD and change-vault"
```

---

# Milestone 5: Watcher + external-edit conflict + export

### Task 23: Rust file watcher

**Files:**
- Modify: `src-tauri/src/lib.rs`, `src-tauri/src/fs_commands.rs`

The watcher watches the current vault root and emits `file-changed { path, mtime }` (path relative to root). Watching is (re)started by a `watch_workspace(root)` command called from Elm after a vault is chosen.

- [ ] **Step 1: Add a `watch_workspace` command** in `fs_commands.rs`

```rust
use notify::{RecommendedWatcher, RecursiveMode, Watcher};
use std::sync::Mutex;
use tauri::{Emitter, Manager};

#[derive(Default)]
pub struct WatcherState(pub Mutex<Option<RecommendedWatcher>>);

#[derive(Clone, Serialize)]
struct FileChanged {
    path: String,
    mtime: u64,
}

#[tauri::command]
pub fn watch_workspace(
    app: tauri::AppHandle,
    state: tauri::State<'_, WatcherState>,
    root: String,
) -> Result<(), String> {
    let root_path = PathBuf::from(&root);
    let app_handle = app.clone();
    let root_for_cb = root_path.clone();

    let mut watcher = notify::recommended_watcher(move |res: notify::Result<notify::Event>| {
        if let Ok(event) = res {
            for p in event.paths {
                if !has_doc_ext(&p) {
                    continue;
                }
                if let Ok(rel) = p.strip_prefix(&root_for_cb) {
                    let payload = FileChanged {
                        path: rel.to_string_lossy().replace('\\', "/"),
                        mtime: mtime_ms(&p),
                    };
                    let _ = app_handle.emit("file-changed", payload);
                }
            }
        }
    })
    .map_err(|e| e.to_string())?;

    watcher
        .watch(&root_path, RecursiveMode::Recursive)
        .map_err(|e| e.to_string())?;

    *state.0.lock().map_err(|e| e.to_string())? = Some(watcher);
    Ok(())
}
```

- [ ] **Step 2: Register state + command** in `lib.rs`

```rust
        .manage(fs_commands::WatcherState::default())
```
and add `fs_commands::watch_workspace,` to `generate_handler!`.

- [ ] **Step 3: Verify build**

Run: `cd "src-tauri" && cargo build 2>&1 | tail -5`
Expected: `Finished`.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: file watcher emitting file-changed events"
```

---

### Task 24: External-edit conflict handling in Elm

**Files:**
- Modify: `frontend/src/Types.elm`, `frontend/src/Main.elm`, `frontend/src/View.elm`

- [ ] **Step 1: Track loaded mtime + conflict flag** in `Types.elm`

Add to `Model`:
```elm
    , loadedMtime : Int
    , externalConflict : Bool
```
Add Msgs:
```elm
    | ClickedReloadExternal
    | ClickedKeepMine
```
Add `import` nothing new (FileChanged already routed via `GotFileChanged`).

- [ ] **Step 2: Initialize** `loadedMtime = 0`, `externalConflict = False`.

- [ ] **Step 3: Start watching after a vault is chosen** — in `handleResponse` `PPickWorkspace` branch, after issuing `list_workspace`, also issue `watch_workspace`. Change it to batch both:
```elm
                PPickWorkspace ->
                    case D.decodeValue (D.nullable D.string) result of
                        Ok (Just root) ->
                            let
                                ( m1, c1 ) =
                                    request PListWorkspace "list_workspace" [ ( "root", E.string root ) ] { model | vaultRoot = Just root }

                                ( m2, c2 ) =
                                    request PListWorkspace "watch_workspace" [ ( "root", E.string root ) ] m1
                            in
                            ( m2, Cmd.batch [ c1, c2 ] )

                        _ ->
                            ( model, Cmd.none )
```
(The `watch_workspace` response carries nothing meaningful; reusing `PListWorkspace` as a benign pending tag is fine because its handler just rebuilds the tree from an empty/!ok result — guard it: if decode fails, ignore. To avoid a spurious tree rebuild, add a dedicated `PNoop` pending op and use it for the watch call.)

Add `PNoop` to `PendingOp` and handle it as `( model, Cmd.none )`. Use `PNoop` for the watch request.

- [ ] **Step 4: Record mtime on read** — in the `PReadFile` branch, also decode `mtime` and store it, clearing any conflict:
```elm
                PReadFile _ ->
                    case D.decodeValue (D.map2 Tuple.pair (D.field "content" D.string) (D.field "mtime" D.int)) result of
                        Ok ( content, mtime ) ->
                            ( { model
                                | content = content
                                , loadedMtime = mtime
                                , externalConflict = False
                                , parsedDoc = parseIf model content
                              }
                            , Cmd.none
                            )

                        Err e ->
                            ( { model | error = Just (D.errorToString e) }, Cmd.none )
```
with helper:
```elm
parseIf : Model -> String -> Maybe Scripta.Document
parseIf model content =
    if model.language == Just Language.Scripta then
        Just (Render.parse model.isLight model.contentWidth content)

    else
        Nothing
```

- [ ] **Step 5: Detect conflict** in `GotFileChanged`:
```elm
        GotFileChanged value ->
            case D.decodeValue (D.map2 Tuple.pair (D.field "path" D.string) (D.field "mtime" D.int)) value of
                Ok ( path, mtime ) ->
                    if Just path == model.selectedPath && mtime > model.loadedMtime && model.saveState.saveStatus /= SaveState.Saving then
                        ( { model | externalConflict = True }, Cmd.none )

                    else
                        ( model, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )
```
Note: our own writes also fire the watcher; the `mtime > loadedMtime` plus `not Saving` check avoids most self-trigger noise. After our own save completes, update `loadedMtime` from the `write_file` result. In `PWriteFile` handling, capture the returned mtime:
```elm
                PWriteFile _ ->
                    case D.decodeValue D.int result of
                        Ok mtime ->
                            update (GotSaveResult resp.requestId) { model | loadedMtime = mtime }

                        Err _ ->
                            update (GotSaveResult resp.requestId) model
```

- [ ] **Step 6: Resolve conflict**:
```elm
        ClickedReloadExternal ->
            case ( model.vaultRoot, model.selectedPath ) of
                ( Just root, Just path ) ->
                    request (PReadFile path)
                        "read_file"
                        [ ( "root", E.string root ), ( "path", E.string path ) ]
                        { model | externalConflict = False }

                _ ->
                    ( model, Cmd.none )

        ClickedKeepMine ->
            -- overwrite: bump loadedMtime past the external one by saving now
            case ( model.vaultRoot, model.selectedPath ) of
                ( Just root, Just path ) ->
                    request (PWriteFile path)
                        "write_file"
                        [ ( "root", E.string root ), ( "path", E.string path ), ( "content", E.string model.content ) ]
                        { model | externalConflict = False }

                _ ->
                    ( model, Cmd.none )
```

- [ ] **Step 7: Conflict banner** in `View.elm`:
```elm
conflictBanner : Model -> List (Html Msg)
conflictBanner model =
    if model.externalConflict then
        [ div [ style "background" "#ffd", style "padding" "8px" ]
            [ text "This file changed on disk. "
            , button [ onClick ClickedReloadExternal ] [ text "Reload" ]
            , button [ onClick ClickedKeepMine ] [ text "Keep mine" ]
            ]
        ]

    else
        []
```
Render `conflictBanner model` at the top of the editor/preview column.

- [ ] **Step 8: Build, run, verify**

Run: `make elm 2>&1 | tail -5 && make dev`
Manual check: open a file in the app; in another editor (or `printf` from a terminal) modify the same file and save → the app shows the conflict banner → **Reload** loads the external content; **Keep mine** overwrites it. Confirm normal autosave does NOT trigger the banner.
Expected: as above.

- [ ] **Step 9: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm
git commit -m "feat: milestone 5a — external-edit detection and conflict banner"
```

---

### Task 25: Rust `export_save` command (save dialog)

**Files:**
- Modify: `src-tauri/src/fs_commands.rs`, `src-tauri/src/lib.rs`

- [ ] **Step 1: Implement `export_save`**

```rust
#[tauri::command]
pub async fn export_save(
    app: tauri::AppHandle,
    default_name: String,
    content: String,
) -> Result<Option<String>, String> {
    use tauri_plugin_dialog::DialogExt;
    let (tx, rx) = std::sync::mpsc::channel();
    app.dialog()
        .file()
        .set_file_name(&default_name)
        .save_file(move |maybe| {
            let _ = tx.send(maybe);
        });
    let chosen = rx.recv().map_err(|e| e.to_string())?;
    match chosen {
        Some(path) => {
            let pb = path.into_path().map_err(|e| e.to_string())?;
            std::fs::write(&pb, content).map_err(|e| e.to_string())?;
            Ok(Some(pb.to_string_lossy().to_string()))
        }
        None => Ok(None),
    }
}
```
(If `into_path()` is unavailable in the installed plugin version, match the `FilePath` API: use `path.to_string()` then `Path::new`. Adjust to compile.)

- [ ] **Step 2: Register** `export_save` in `lib.rs`.

- [ ] **Step 3: Verify build**

Run: `cd "src-tauri" && cargo build 2>&1 | tail -5`
Expected: `Finished`.

- [ ] **Step 4: Commit**

```bash
git add src-tauri/src/fs_commands.rs src-tauri/src/lib.rs
git commit -m "feat: export_save command with save dialog"
```

---

### Task 26: Elm `Export` module + UI

**Files:**
- Create: `frontend/src/Export.elm`
- Modify: `frontend/src/Types.elm`, `frontend/src/Main.elm`, `frontend/src/View.elm`

- [ ] **Step 1: Write `frontend/src/Export.elm`**

```elm
module Export exposing (html, latex, defaultName)

{-| Export the current Scripta document to standalone HTML or LaTeX using the
vendored compiler. v1 exports Scripta documents only.
-}

import Render
import Render.Export.LaTeX
import Scripta


{-| Standalone HTML (KaTeX CDN + default CSS are embedded by the compiler).
-}
html : Bool -> Int -> Scripta.Document -> String
html isLight contentWidth doc =
    Scripta.exportHtml (Render.options isLight contentWidth) doc


{-| LaTeX source. Signature must match Render/Export/LaTeX.elm `export`.
Open that module and adapt the argument list; the placeholder below assumes a
`Document -> String` convenience does not exist, so we expose what compiles.
-}
latex : Scripta.Document -> String
latex _ =
    "% LaTeX export: wire Render.Export.LaTeX.export with the document's"
        ++ "\n% RenderSettings + Accumulator + Forest. See scripta-compiler/Render/Export/LaTeX.elm."
```

Note: `exportHtml` is a clean public function. LaTeX export in compiler-v3 is `Render.Export.LaTeX.export` taking lower-level args (PublicationData, RenderSettings, Accumulator, Forest), not a `Document`. **Sub-step:** open `scripta-compiler/Scripta.elm` and check whether a `Document -> String` LaTeX helper exists; if not, add a small exposed helper `exportLaTeX : Options -> Document -> String` to the vendored `Scripta.elm` mirroring `exportHtml` (it already destructures `Document data` and has access to the forest/accumulator). Then call `Scripta.exportLaTeX` here. This is the one place we modify the vendored compiler — keep the change minimal and documented with a comment.

- [ ] **Step 2: Add export Msgs** in `Types.elm`

```elm
    | ClickedExportHtml
    | ClickedExportLatex
```

- [ ] **Step 3: Handle export** in `Main.update`

```elm
        ClickedExportHtml ->
            case model.parsedDoc of
                Just doc ->
                    request PExportSave
                        "export_save"
                        [ ( "defaultName", E.string (Export.defaultName model ".html") )
                        , ( "content", E.string (Export.html model.isLight model.contentWidth doc) )
                        ]
                        model

                Nothing ->
                    ( model, Cmd.none )

        ClickedExportLatex ->
            case model.parsedDoc of
                Just doc ->
                    request PExportSave
                        "export_save"
                        [ ( "defaultName", E.string (Export.defaultName model ".tex") )
                        , ( "content", E.string (Export.latex doc) )
                        ]
                        model

                Nothing ->
                    ( model, Cmd.none )
```
Add `import Export`. Implement `Export.defaultName`:
```elm
defaultName : { a | selectedPath : Maybe String } -> String -> String
defaultName model ext =
    model.selectedPath
        |> Maybe.withDefault "document"
        |> String.split "/"
        |> List.reverse
        |> List.head
        |> Maybe.withDefault "document"
        |> stripExt
        |> (\base -> base ++ ext)


stripExt : String -> String
stripExt name =
    case String.split "." name of
        [ single ] ->
            single

        parts ->
            parts |> List.reverse |> List.drop 1 |> List.reverse |> String.join "."
```
Handle `PExportSave` in `handleResponse`: `( model, Cmd.none )` (a no-op; success means the file was written).

- [ ] **Step 4: Export buttons** in `View.elm`

```elm
        , button [ onClick ClickedExportHtml ] [ text "Export HTML" ]
        , button [ onClick ClickedExportLatex ] [ text "Export LaTeX" ]
```

- [ ] **Step 5: Build, run, verify**

Run: `make elm 2>&1 | tail -10 && make dev`
Manual check: open a `.scripta` file → **Export HTML** → save dialog → choose a location → open the saved `.html` in a browser; it renders (math may use the compiler's embedded KaTeX CDN reference — acceptable for exported files). **Export LaTeX** → save → file contains LaTeX source.
Expected: HTML export works fully; LaTeX export works once `Scripta.exportLaTeX` is added (Step 1 sub-step).

- [ ] **Step 6: Commit**

```bash
git add frontend/src/Export.elm frontend/src/Types.elm frontend/src/Main.elm frontend/src/View.elm frontend/scripta-compiler/Scripta.elm
git commit -m "feat: milestone 5b — HTML and LaTeX export via save dialog"
```

---

### Task 27: Full regression + smoke checklist

**Files:** none (verification only).

- [ ] **Step 1: Run all automated tests**

Run: `make test 2>&1 | tail -30`
Expected: `elm-test` all green; `cargo test` all green.

- [ ] **Step 2: Run the manual smoke checklist**

Run: `make dev`, then verify in order:
1. Open Vault → tree shows `.scripta`/`.tex`/`.md` files.
2. Open a `.scripta` file → preview renders, math via local KaTeX (offline: disable network, confirm math still renders).
3. Edit → live preview updates → "Saved" after ~1s → content persisted on disk.
4. New file → appears, editable, saved.
5. Rename → tree updates.
6. Delete → file moves to Trash (recoverable).
7. Change Vault → tree replaced.
8. External edit (modify file in another app) → conflict banner → Reload / Keep mine both work.
9. Export HTML and LaTeX via save dialog.
10. Open a `.tex`/`.md` file → "not yet supported" message (no crash).

- [ ] **Step 3: Build a release bundle**

Run: `make build 2>&1 | tail -20`
Expected: a `.app` under `src-tauri/target/release/bundle/macos/`. Launch it and re-run a quick subset of the smoke checklist.

- [ ] **Step 4: Commit any fixes** found during smoke testing, then tag:

```bash
git tag v0.1.0
```

---

## Self-review notes (coverage map)

- **Tauri/Elm split + requestId bridge** → Tasks 2, 11, 14, 15.
- **Vault model, node id = relative path** → Tasks 4, 7, 15.
- **CodeMirror (ported), text-change** → Tasks 13, 14, 20.
- **Live preview + incremental reparse** → Tasks 12, 17, 20.
- **KaTeX vendored offline** → Tasks 10, 14, 17 (Step 6 offline check), 27.
- **Debounced save (trimmed SaveState)** → Tasks 18, 19, 20.
- **Full CRUD, trash-on-delete, change vault** → Tasks 21, 22.
- **Watcher + external-edit conflict** → Tasks 23, 24.
- **Export HTML/LaTeX via save dialog** → Tasks 25, 26.
- **`.tex`/`.md` seam (listed, openable, "not supported" placeholder)** → Tasks 6, 17.
- **Error handling as non-blocking banner** → Task 15 (errorBanner) + every `handleResponse` Err branch.
- **Testing (Elm + Rust)** → Tasks 4, 6, 7, 11, 16, 18, 19, 21, 27.

## Known open items deferred beyond v1 (not in scope)

- Actual `.tex`/`.md` rendering (needs compiler `Language` dispatch + porting v4's `elm-markdown`/`MiniLatex` paths).
- PDF export (print-to-PDF or LaTeX pipeline).
- Internal-link navigation between documents (`NavigateToDocument` currently a no-op).
- Tightened CSP; app icon; auto-reload of the tree on watcher create/delete (v1 re-lists only after the app's own mutations).
```
