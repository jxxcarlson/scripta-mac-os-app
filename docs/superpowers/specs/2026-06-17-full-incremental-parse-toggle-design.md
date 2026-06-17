# Full/Incremental Parse Toggle — Design Spec

**Date:** 2026-06-17

## Goal

Add a persisted **Full / Incremental** toggle controlling how the editor reparses on each edit:
- **Full** (default): `Render.parse` (a complete reparse) on every edit — always consistent.
- **Incremental**: `Scripta.reparse` on every edit — faster, the current behavior.

Loading a file always uses `Render.parse` (unchanged).

## Current state (verified)

- `Main.elm` `EditorChanged` (lines 229–241): on each `text-change` it computes
  `reparsed = if language == Scripta then Maybe.map (\d -> Scripta.reparse (Render.options …) d newText) model.parsedDoc else model.parsedDoc`, and stores it in `model.parsedDoc`. (Reparse is per-keystroke; only the save is debounced.)
- File load uses `Render.parse model.isLight model.contentWidth content` (`Main.elm:447`).
- `Render.parse : Bool -> Int -> String -> Scripta.Document` (Render.elm:47) — returns a `Document`.
- **`readerMode` is the exact pattern to mirror** for a persisted Bool toggle:
  - `Types.Model` has `readerMode : Bool`; `Msg` has `ToggledReaderMode`.
  - `Flags` has `readerMode : Bool` (`Flags.decode` → `D.field "readerMode" D.bool |> Result.withDefault False`).
  - `Main.init`: `readerMode = flags.readerMode`; update branch
    `ToggledReaderMode -> ( { model | readerMode = rm }, FileOps.saveReaderMode rm )`.
  - `FileOps`: `port saveReaderMode : Bool -> Cmd msg` (exposed).
  - `index.html`: flag `readerMode: lsGet('readerMode') === 'true'`; port handler
    `subscribePort('saveReaderMode', (on) => localStorage.setItem('readerMode', on ? 'true' : 'false'))`.
  - `View.elm` toolbar: a `button [ onClick ToggledReaderMode ] [ text (if model.readerMode then "Exit Reader" else "Reader") ]`.
- `frontend/tests/FlagsTest.elm` tests `Flags.decode`.

## Design

Add `fullParse : Bool` (True = Full) following the `readerMode` pattern exactly.

### State + persistence

- `Types.elm`: add `fullParse : Bool` to `Model`; add `ToggledParseMode` to `Msg`.
- `Flags.elm`: add `fullParse : Bool` to the `Flags` record; in `decode`:
  ```elm
  fullParse =
      D.decodeValue (D.field "fullParse" D.bool) value
          |> Result.withDefault True
  ```
  (Defaults to **True** = Full when the field is missing/malformed — so a fresh install starts in Full.)
- `FileOps.elm`: add `saveFullParse` to the exposing list and `port saveFullParse : Bool -> Cmd msg`.
- `Main.elm` `init`: add `fullParse = flags.fullParse` to the model record.
- `index.html`:
  - In the flags object: `fullParse: lsGet('fullParse') !== 'false'` (unset → Full; `'false'` → Incremental).
  - Add a guarded port handler:
    `subscribePort('saveFullParse', (on) => { try { localStorage.setItem('fullParse', on ? 'true' : 'false'); } catch (e) {} });`

### Behavior

- `Main.elm` `EditorChanged`: branch the `reparsed` computation on `model.fullParse`:
  ```elm
  reparsed =
      if model.language == Just Language.Scripta then
          if model.fullParse then
              Just (Render.parse model.isLight model.contentWidth newText)

          else
              Maybe.map (\d -> Scripta.reparse (Render.options model.isLight model.contentWidth) d newText) model.parsedDoc

      else
          model.parsedDoc
  ```
- Add the update branch:
  ```elm
  ToggledParseMode ->
      let
          fp =
              not model.fullParse
      in
      ( { model | fullParse = fp }, FileOps.saveFullParse fp )
  ```
- Load path (`Main.elm:447`, `Render.parse` on file read) is unchanged.

### UI

- `View.elm` toolbar (the row with the Reader button): add a second button
  ```elm
  button [ onClick ToggledParseMode ]
      [ text (if model.fullParse then "Parse: Full" else "Parse: Incremental") ]
  ```
  placed after the Reader button (the toolbar is a flex row with `gap`).

## Files touched

- `frontend/src/Types.elm` — `Model.fullParse`, `Msg.ToggledParseMode`.
- `frontend/src/Flags.elm` — `Flags.fullParse` + decode (default True).
- `frontend/src/FileOps.elm` — `saveFullParse` port.
- `frontend/src/Main.elm` — `init` field; `EditorChanged` branch; `ToggledParseMode` handler.
- `frontend/src/View.elm` — toolbar toggle button.
- `frontend/index.html` — `fullParse` flag + `saveFullParse` handler.
- `frontend/tests/FlagsTest.elm` — `fullParse` decode tests.

## Testing

- **TDD** `Flags.decode` for `fullParse` in `FlagsTest.elm`:
  - missing field → `True` (default Full).
  - `fullParse = false` → `False`.
  - `fullParse = true` → `True`.
- `elm-test` rises from 42; `cargo test` unchanged (no Rust change).
- Behavior + toolbar + persistence: `elm make` build + manual.

## Manual checklist

1. Fresh launch → toolbar shows **Parse: Full**; editing a Scripta doc fully reparses (preview stays correct).
2. Click → **Parse: Incremental**; editing uses incremental reparse; quit + relaunch → still Incremental (persisted).
3. Click back → Full; persists.
4. Opening any file still parses correctly regardless of mode (load always uses `Render.parse`).

## Decisions / out of scope

- Default is **Full**; the setting **persists** (same flag+localStorage mechanism as `readerMode`).
- `Bool fullParse` (True = Full), matching the existing `readerMode`/`isLight` style (no new custom type).
- No keyboard shortcut; no per-document setting (it's a global app preference).
