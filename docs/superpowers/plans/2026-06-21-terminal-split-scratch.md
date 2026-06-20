# Terminal Dock Split + Scratch Editor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the bottom dock into a fixed left AI-chat pane and a tabbed right pane (`Shell 1 | Shell 2 | Scratch`) divided by a draggable separator, with a persisted CodeMirror Scratch buffer.

**Architecture:** Elm renders the new two-pane layout and a second `codemirror-editor` (`id="scratch-editor"`) seeded once from a flag. The separator position and Scratch content are owned entirely by JS in `index.html` (CSS var + `localStorage`), mirroring the existing panel-height resize and terminal-I/O patterns — Elm never sees split drags or Scratch keystrokes.

**Tech Stack:** Elm 0.19.1 (`elm-test`, `Test.Html`), vendored CodeMirror custom element, Tauri WKWebView `localStorage`, plain DOM pointer/keydown events.

**Spec:** `docs/superpowers/specs/2026-06-21-terminal-split-scratch-design.md`

---

## File Structure

- `frontend/src/Flags.elm` — add `scratchContent : String` flag (decode from JS).
- `frontend/src/Types.elm` — add `scratchContent : String` to `Model`.
- `frontend/src/Main.elm` — seed `scratchContent` from flags; default `terminalTab` to `"shell1"`.
- `frontend/src/View.elm` — new two-pane `terminalDock`; exposed `rightTabs` helper; `scratchPane`; tab bar drops the AI tab.
- `frontend/index.html` — `--terminal-split` CSS var; separator drag/clamp/persist; Scratch debounce-save; Ctrl-S focus guard; `scratchContent` flag.
- `frontend/tests/FlagsTest.elm` — `scratchContent` decode tests.
- `frontend/tests/TerminalTabsTest.elm` (new) — `View.rightTabs` content tests.

JS behavior (split clamp, debounce, Ctrl-S guard) has no test harness in this repo and is verified by `make elm` build success plus manual check after `make build`, consistent with the existing resize/terminal JS.

---

### Task 1: Add `scratchContent` flag

**Files:**
- Modify: `frontend/src/Flags.elm`
- Test: `frontend/tests/FlagsTest.elm`

- [ ] **Step 1: Write the failing tests**

Add these two tests to the `describe "Flags.decode"` list in `frontend/tests/FlagsTest.elm` (insert before the closing `]` of the list):

```elm
        , test "decodes scratchContent" <|
            \_ ->
                Flags.decode (E.object [ ( "scratchContent", E.string "hello" ) ])
                    |> .scratchContent
                    |> Expect.equal "hello"
        , test "missing scratchContent defaults to empty string" <|
            \_ ->
                Flags.decode (E.object [])
                    |> .scratchContent
                    |> Expect.equal ""
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd frontend && elm-test`
Expected: FAIL — compile error, `.scratchContent` is not a field of `Flags`.

- [ ] **Step 3: Add the field to the `Flags` type alias**

In `frontend/src/Flags.elm`, add `scratchContent` as the last field of the `type alias Flags`:

```elm
    , terminalVisible : Bool
    , scratchContent : String
    }
```

- [ ] **Step 4: Add the decoder**

In `frontend/src/Flags.elm`, add this as the last field of the record returned by `decode` (after the `terminalVisible = ...` block):

```elm
    , scratchContent =
        D.decodeValue (D.field "scratchContent" D.string) value
            |> Result.withDefault ""
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd frontend && elm-test`
Expected: PASS (all tests green).

- [ ] **Step 6: Commit**

```bash
git add frontend/src/Flags.elm frontend/tests/FlagsTest.elm
git commit -m "feat: add scratchContent flag for the Scratch buffer"
```

---

### Task 2: Add `scratchContent` to Model + default the right tab

**Files:**
- Modify: `frontend/src/Types.elm`
- Modify: `frontend/src/Main.elm:73` (and the `init` record)

- [ ] **Step 1: Add the Model field**

In `frontend/src/Types.elm`, inside `type alias Model`, add a `scratchContent` field immediately after the `terminalTab : String` field (around line 44):

```elm
    , terminalTab : String
    , scratchContent : String
```

- [ ] **Step 2: Seed it in `init` and change the default tab**

In `frontend/src/Main.elm`, in the `init` record, change the `terminalTab` line and add `scratchContent` right after it:

```elm
        , terminalTab = "shell1"
        , scratchContent = flags.scratchContent
```

(Replace the existing `, terminalTab = "ai"` line.)

- [ ] **Step 3: Verify it compiles**

Run: `cd frontend && elm make src/Main.elm --output=/dev/null`
Expected: `Success!` (no errors). The existing `elm-test` suite still passes: `elm-test`.

- [ ] **Step 4: Commit**

```bash
git add frontend/src/Types.elm frontend/src/Main.elm
git commit -m "feat: store scratchContent in Model; default right tab to shell1"
```

---

### Task 3: Add and test the `rightTabs` helper

**Files:**
- Modify: `frontend/src/View.elm:1` (exposing list) + add helper
- Test: `frontend/tests/TerminalTabsTest.elm` (new)

- [ ] **Step 1: Write the failing test**

Create `frontend/tests/TerminalTabsTest.elm`:

```elm
module TerminalTabsTest exposing (suite)

import Expect
import Test exposing (Test, describe, test)
import View


suite : Test
suite =
    describe "View.rightTabs"
        [ test "lists shell1, shell2, scratch in order" <|
            \_ ->
                Expect.equal
                    [ ( "shell1", "Shell 1" ), ( "shell2", "Shell 2" ), ( "scratch", "Scratch" ) ]
                    View.rightTabs
        , test "does not include an AI tab" <|
            \_ ->
                View.rightTabs
                    |> List.map Tuple.first
                    |> List.member "ai"
                    |> Expect.equal False
        ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd frontend && elm-test`
Expected: FAIL — `View.rightTabs` is not exposed / does not exist.

- [ ] **Step 3: Expose and implement `rightTabs`**

In `frontend/src/View.elm`, change the module line to expose `rightTabs`:

```elm
module View exposing (imagePane, plainTextPreview, rightTabs, themeName, view)
```

Add this top-level definition (place it just above `terminalTabBar`, around line 570):

```elm
rightTabs : List ( String, String )
rightTabs =
    [ ( "shell1", "Shell 1" ), ( "shell2", "Shell 2" ), ( "scratch", "Scratch" ) ]
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd frontend && elm-test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add frontend/src/View.elm frontend/tests/TerminalTabsTest.elm
git commit -m "feat: add View.rightTabs (shell1/shell2/scratch) with tests"
```

---

### Task 4: Restructure `terminalDock` into the two-pane layout

**Files:**
- Modify: `frontend/src/View.elm:535-567` (`terminalDock`), `terminalTabBar`, add `scratchPane`

- [ ] **Step 1: Replace `terminalDock`**

In `frontend/src/View.elm`, replace the entire `terminalDock` function (currently lines ~535-567) with:

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
        , style "max-height" "calc(100vh - 120px)"
        , style "border-top" "1px solid var(--border)"
        , style "background" "var(--app-bg)"
        , style "min-height" "0"
        ]
        [ div
            [ Html.Attributes.id "terminal-resize-handle"
            , style "height" "6px"
            , style "cursor" "row-resize"
            , style "background" "var(--border)"
            , style "flex" "0 0 auto"
            ]
            []
        , div
            [ style "display" "flex"
            , style "flex-direction" "row"
            , style "flex" "1"
            , style "min-height" "0"
            ]
            [ div
                [ style "width" "var(--terminal-split, 50%)"
                , style "flex" "0 0 auto"
                , style "min-width" "0"
                , style "overflow" "hidden"
                ]
                [ aiChatView model ]
            , div
                [ Html.Attributes.id "terminal-split-handle"
                , style "flex" "0 0 6px"
                , style "cursor" "col-resize"
                , style "background" "var(--border)"
                ]
                []
            , div
                [ style "display" "flex"
                , style "flex-direction" "column"
                , style "flex" "1"
                , style "min-width" "0"
                , style "min-height" "0"
                ]
                [ terminalTabBar model
                , Html.Keyed.node "div"
                    [ style "flex" "1", style "min-height" "0", style "position" "relative" ]
                    [ ( "shell1", terminalTabContent (model.terminalTab == "shell1") (terminalPane "shell1" model) )
                    , ( "shell2", terminalTabContent (model.terminalTab == "shell2") (terminalPane "shell2" model) )
                    , ( "scratch", terminalTabContent (model.terminalTab == "scratch") (scratchPane model) )
                    ]
                ]
            ]
        ]
```

- [ ] **Step 2: Point `terminalTabBar` at `rightTabs`**

In `frontend/src/View.elm`, in `terminalTabBar`, replace the inline tab list passed to `List.map (terminalTabButton model)` with `rightTabs`. The function body's last expression becomes:

```elm
        (List.map (terminalTabButton model) rightTabs)
```

(Delete the old literal list `[ ( "ai", "AI" ), ( "shell1", "Shell 1" ), ( "shell2", "Shell 2" ) ]`.)

- [ ] **Step 3: Add `scratchPane`**

In `frontend/src/View.elm`, add this definition next to `terminalPane` (around line 713):

```elm
scratchPane : Model -> Html Msg
scratchPane model =
    Html.node "codemirror-editor"
        [ Html.Attributes.id "scratch-editor"
        , Html.Attributes.attribute "text" model.scratchContent
        , style "display" "block"
        , style "width" "100%"
        , style "height" "100%"
        ]
        []
```

- [ ] **Step 4: Verify build + tests**

Run: `cd frontend && elm make src/Main.elm --output=/dev/null && elm-test`
Expected: `Success!` and all tests PASS (the `rightTabs` test from Task 3 still green).

- [ ] **Step 5: Commit**

```bash
git add frontend/src/View.elm
git commit -m "feat: split terminal dock into AI (left) + tabbed shells/scratch (right)"
```

---

### Task 5: JS — separator drag, Scratch persistence, Ctrl-S guard, flag

**Files:**
- Modify: `frontend/index.html` (CSS `:root` line ~74; flags object ~298-305; boot IIFE after ~296; Ctrl-S handler ~451-457)

- [ ] **Step 1: Add the split CSS var default**

In `frontend/index.html`, change the `:root` rule (line ~74) from:

```css
      :root { --terminal-height: 280px; }
```

to:

```css
      :root { --terminal-height: 280px; --terminal-split: 50%; }
```

- [ ] **Step 2: Add the `scratchContent` flag**

In `frontend/index.html`, in the `const flags = { ... }` object, add a `scratchContent` entry (after the `terminalVisible` line — add a comma to the `terminalVisible` line):

```js
        terminalVisible: lsGet('terminalVisible') === 'true',   // bool (unset → hidden)
        scratchContent: lsGet('scratch') || ''                  // string (Scratch buffer)
```

- [ ] **Step 3: Add the separator drag IIFE + Scratch save listener**

In `frontend/index.html`, immediately after the closing `})();` of the existing terminal-height IIFE (the block that ends right before `let lastVault = null;`, around line 296), insert:

```js
      // --- Vertical separator between the AI pane (left) and shells/scratch (right). ---
      (function () {
        // Clamp left-pane width to [150, innerWidth-150] so the divider can never be
        // dragged within 150px of either edge (and can't get stuck off-screen).
        function applySplit(px, persist) {
          var h = Math.max(150, Math.min(window.innerWidth - 150, px));
          document.documentElement.style.setProperty('--terminal-split', h + 'px');
          if (persist) { try { localStorage.setItem('terminalSplit', h); } catch (e) {} }
          return h;
        }
        // Read current split from localStorage only (always px) — never parse the CSS
        // var, which may still be the "50%" default.
        var saved = parseInt(lsGet('terminalSplit'), 10);
        if (!isNaN(saved)) applySplit(saved, true);
        var dragging = false;
        document.addEventListener('pointerdown', function (e) {
          if (e.target && e.target.id === 'terminal-split-handle') { dragging = true; e.preventDefault(); }
        });
        document.addEventListener('pointermove', function (e) {
          if (!dragging) return;
          applySplit(e.clientX, false);
        });
        document.addEventListener('pointerup', function (e) {
          if (!dragging) return;
          dragging = false;
          applySplit(e.clientX, true);
        });
        window.addEventListener('resize', function () {
          var s = parseInt(lsGet('terminalSplit'), 10);
          if (!isNaN(s)) applySplit(s, true);
        });
      })();

      // --- Scratch buffer: debounce-save the scratch editor to localStorage. ---
      (function () {
        var saveTimer = null;
        document.addEventListener('text-change', function (e) {
          if (!(e.target && e.target.closest && e.target.closest('#scratch-editor'))) return;
          var content = (e.detail && e.detail.source != null) ? e.detail.source : '';
          clearTimeout(saveTimer);
          saveTimer = setTimeout(function () {
            try { localStorage.setItem('scratch', content); } catch (err) {}
          }, 400);
        });
      })();
```

- [ ] **Step 4: Add the Ctrl-S focus guard**

In `frontend/index.html`, replace the Ctrl-S keydown handler (around lines 451-457):

```js
      window.addEventListener('keydown', function (e) {
        if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S')) {
          e.preventDefault();
          lrSync();
        }
      }, true);
```

with:

```js
      window.addEventListener('keydown', function (e) {
        if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S')) {
          e.preventDefault();
          // Scratch has no rendered panel and auto-saves; don't run document sync from it.
          var ae = document.activeElement;
          if (ae && ae.closest && ae.closest('#scratch-editor')) return;
          lrSync();
        }
      }, true);
```

- [ ] **Step 5: Build the frontend**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make elm`
Expected: `Success! Compiled 1 module.` (index.html is not compiled; this confirms the Elm side still builds. JS changes are verified manually after `make build`.)

- [ ] **Step 6: Commit**

```bash
git add frontend/index.html
git commit -m "feat: draggable split separator + Scratch localStorage persistence + Ctrl-S guard"
```

---

### Task 6: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the full Elm suite + build**

Run: `cd "/Users/carlson/dev/scripta-viewer/Mac Scripta Viewer" && make elm && (cd frontend && elm-test)`
Expected: `Success!` build, `TEST RUN PASSED` (95 tests: prior 93 + the 2 new `rightTabs` tests; FlagsTest gains 2 within its file).

- [ ] **Step 2: Confirm clean tree**

Run: `git status -sb`
Expected: branch clean (all task commits landed). Ready for `make build` and manual GUI verification (left AI pane, right Shell 1/Shell 2/Scratch tabs, draggable divider clamped 150px from edges, Scratch content surviving tab switches and relaunch).

---

## Self-Review

**1. Spec coverage:**
- Two equal halves, AI left / shells right → Task 4 (`--terminal-split` default 50%, left pane + right column).
- Scratch tab right of Shell 2 → Tasks 3 (`rightTabs`) + 4 (`scratchPane`, keyed entry).
- Scratch raises a CodeMirror editor → Task 4 (`Html.node "codemirror-editor"`).
- Debounced real-time save to localStorage → Task 5 Step 3 (400ms `text-change` listener).
- Single global buffer → Task 5 (`localStorage['scratch']`, one key) + Task 1 (flag).
- Restored on launch → Task 1 + Task 2 (`scratchContent` flag → Model → `text` attr seed).
- Thin draggable separator → Task 4 (`#terminal-split-handle`) + Task 5 Step 3 (drag).
- Cannot drag within 150px of either side → Task 5 Step 3 (`Math.max(150, Math.min(innerWidth-150, px))`).
- Split persists across restarts → Task 5 (`localStorage['terminalSplit']`, load+clamp+persist).
- Ctrl-S no-op in Scratch → Task 5 Step 4 (focus guard).

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"; every code step shows full code and exact commands. ✔

**3. Type/name consistency:** `scratchContent` used identically across Flags / Model / init / `text` attr; `terminalSplit` (localStorage key) vs `--terminal-split` (CSS var) used consistently; tab id `"scratch"` matches between `rightTabs`, the keyed content, and `scratchPane`'s `#scratch-editor` id matched by the JS `closest('#scratch-editor')`. ✔
