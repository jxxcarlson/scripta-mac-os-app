# Dark Mode Design Spec

**Date:** 2026-06-19
**Status:** Approved (pending spec review)

## Goal

Add a whole-app dark mode to the Mac Scripta Viewer: a manual toolbar toggle that
switches the entire UI — app chrome (file tree, toolbar, borders, backgrounds), the
CodeMirror editor, and the rendered preview (Scripta + markdown) — between light and dark,
with the choice persisted across launches. Default stays light.

## Context

Theming is half-built:

- `model.isLight : Bool` already exists (`Types.elm:26`, defaults `True` at `Main.elm:55`) and
  is already threaded into the Scripta render/export path: `Render.options` switches
  `Scripta.Light`/`Scripta.Dark` (`Render.elm:30-39`), used by `renderDocument`, `parse`,
  `compile`, and `Export.html`/`Export.latex`. **There is no UI to change it and it is not
  persisted.**
- The **app chrome** in `View.elm` uses ~14 hardcoded colors (borders `#ddd`, muted text
  `#666`, error panel `#fee`/`#900`, conflict banner `#ffd`/`#cc0`, sync highlights
  `#cfe6fb`/`#e8f2fc`).
- The **CodeMirror editor** reads `--cm-*` CSS custom properties defined in `index.html`'s
  `:root` block, currently set to light values.
- **Markdown** rendering hardcodes its TOC link color (`#2563eb`, `MarkdownRender.elm`), noted
  as theme-unaware.
- **Persistence pattern** to mirror: `readerMode`/`fullParse` are read from `localStorage`
  into `Flags`, stored in the model, toggled by toolbar buttons, and saved via
  `saveReaderMode`/`saveFullParse` ports (`FileOps.elm:41,47`; `index.html:214-219`).

So the Scripta-render half already responds to `isLight`. This feature adds the toggle,
persistence, and theming for the chrome, editor, and markdown.

## Architecture

**CSS-variable palette switched by a `data-theme` attribute on the Elm root.**

`index.html` defines the color palette as CSS custom properties: a `:root` block with light
values and a `[data-theme="dark"]` block with dark values. Elm's `view` sets
`attribute "data-theme" (themeName model.isLight)` on its outermost element. CSS custom
properties inherit down the tree **and pierce shadow DOM**, so this single attribute drives
both the chrome (Elm inline styles that reference `var(--…)`) and the CodeMirror custom
element (which already reads `--cm-*` from an ancestor). The Scripta preview is driven
separately by the existing `model.isLight → Scripta.Dark` path; no change to that mechanism.

This reuses the editor's existing CSS-variable theming rather than introducing a parallel
Elm-driven color system, and keeps the switch to a single source of truth (`model.isLight`).

### Alternatives considered

- **All-Elm inline colors** — compute every color in Elm from `isLight` and push the editor
  theme through a port. Rejected: more Elm churn, and it still has to touch `index.html` for
  the editor's `--cm-*`, so it does not avoid the CSS work.
- **`prefers-color-scheme` auto-follow** — rejected per the chosen behavior (manual toggle,
  no system-follow).

## Components / Changes

1. **`frontend/index.html`**
   - Restructure the `:root` block: keep the existing `--cm-*` light values, and add semantic
     app tokens — `--app-bg`, `--app-fg`, `--panel-bg`, `--border`, `--muted`, `--link`,
     `--banner-bg`, `--banner-fg`, `--banner-border`, `--error-bg`, `--error-fg`,
     `--error-border`, `--sync-bg`, `--toc-sync-bg`.
   - Add a `[data-theme="dark"]` block overriding every token (app tokens + `--cm-*`) with
     dark values.
   - Set `html, body { background: var(--app-bg); color: var(--app-fg); }`.
   - In the boot script, add `isLight: lsGet('isLight') !== 'false'` to the `flags` object
     (unset → light), and add `subscribePort('saveIsLight', (on) => { localStorage.setItem('isLight', on ? 'true' : 'false'); })`.

2. **`frontend/src/Flags.elm`** — add field `isLight : Bool`; decode it (default `True` when
   absent), mirroring how `readerMode`/`fullParse` are decoded.

3. **`frontend/src/FileOps.elm`** — add `port saveIsLight : Bool -> Cmd msg` and export it.

4. **`frontend/src/Main.elm`**
   - Init `isLight = flags.isLight` (replacing the hardcoded `True` at `Main.elm:55`).
   - Add `ToggledTheme` to the `Msg` type and an `update` branch:
     `( { model | isLight = not model.isLight }, FileOps.saveIsLight (not model.isLight) )`
     — the exact shape of the existing `ToggledReaderMode` branch (`Main.elm:380-385`).

5. **`frontend/src/View.elm`**
   - Add `Html.Attributes.attribute "data-theme" (if model.isLight then "light" else "dark")`
     to the outermost element returned by `view`.
   - Add a theme toggle button to the toolbar (alongside the Reader and Parse buttons):
     `button [ onClick ToggledTheme ] [ text (if model.isLight then "Dark" else "Light") ]`
     (label is the action, matching the Reader button's "Reader"/"Exit Reader" convention).
   - Replace the hardcoded colors with `var(--…)` references using the tokens above (borders →
     `var(--border)`, muted text → `var(--muted)`, error panel → `var(--error-*)`, conflict
     banner → `var(--banner-*)`, sync-highlight backgrounds → `var(--sync-bg)`/`var(--toc-sync-bg)`).

6. **`frontend/src/MarkdownRender.elm`** — change the TOC link color from `#2563eb` to
   `var(--link)`; remove the "theme-unaware" NOTE comment. Markdown body text inherits
   `--app-fg` from the themed container.

## Data Flow

```
flags.isLight (localStorage 'isLight')
  → model.isLight
  → (a) View root attribute data-theme="light"|"dark"
        → CSS custom properties (:root vs [data-theme=dark])
        → app chrome (var(--…)) + CodeMirror editor (var(--cm-*), via inheritance through shadow DOM)
  → (b) Render.options isLight → Scripta.Light|Scripta.Dark → rendered Scripta preview

Toolbar toggle click
  → ToggledTheme
  → model.isLight := not isLight  +  FileOps.saveIsLight (not isLight)
  → index.html saveIsLight handler → localStorage.setItem('isLight', …)
```

## Error Handling

- `localStorage` access already guarded by the existing `lsGet` helper (returns `null` on
  failure → defaults to light) and the `subscribePort` guard (`index.html:170-179`). No new
  error paths.
- If `Scripta.Dark` text proves hard to read on the chosen `--app-bg`, adjust `--app-bg`
  during implementation (verify manually); the dark background token is the single knob.

## Testing

- **elm-test**:
  - `Flags` decodes `isLight`: present `"false"` → `False`; absent → `True` (default).
  - `update ToggledTheme` flips `model.isLight` and the returned command is `saveIsLight`
    with the new value. (Follow the existing `ToggledReaderMode`/`SaveStateTest` style; if
    the command isn't directly inspectable, assert the model flip and that the branch exists.)
  - A `View` test: the root element carries `data-theme="dark"` when `isLight` is `False` and
    `data-theme="light"` when `True` (via `Test.Html.Query`/`Selector.attribute`).
- **Manual verification**: click the toggle → entire app (tree, toolbar, editor, preview)
  switches; relaunch the app → theme is remembered; confirm a `.scripta` doc and a `.md` doc
  (with math + TOC) are readable in dark mode; confirm the error panel and conflict banner are
  legible in dark.

## Out of Scope (YAGNI)

- Auto-follow of the macOS system appearance (`prefers-color-scheme`).
- Per-document or per-pane themes.
- Theming the PDF/LaTeX export output (export already takes `isLight`, but dark PDFs are not a
  goal).
