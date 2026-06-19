# New-File Creation: Verbatim Name + Inbox Placement — Design Spec

**Date:** 2026-06-19
**Status:** Approved (pending spec review)

## Goal

Fix three problems with creating a new file via the **New** button:

1. The typed name is auto-capitalized / auto-corrected by the OS.
2. A `.scripta` extension is force-appended (so `black-hole-study-notes.md` became
   `…md.scripta`).
3. Placement is wrong. New rule:
   - If the vault is **`kbase` or any descendant of it**, create the file in **`kbase/Inbox`**
     (a single capture inbox), regardless of where in the tree you are.
   - Otherwise, create the file in the **current folder** = the open document's folder
     (today's sibling behavior).

The filename must be used **exactly as typed** (extension included; no auto-added extension,
no capitalization changes).

## Context (root causes)

- The new-file-name `Html.input` (`frontend/src/View.elm:30`) sets only
  `placeholder`/`value`/`onInput`/`style`. macOS WKWebView auto-capitalizes and auto-corrects
  text inputs unless told not to → mangled filenames.
- `ClickedNewFile` (`frontend/src/Main.elm`) builds the path as
  `PathUtil.siblingPath model.selectedPath (ensureScriptaExt model.newName)`:
  - `ensureScriptaExt` appends `.scripta` unless the name already ends in `.scripta`.
  - `siblingPath` places the file in the folder of the currently-open document
    (`model.selectedPath`); folders in the tree are not selectable (clicking a folder only
    toggles it via `ToggledFolder`), so you cannot target a folder you have merely expanded.
- `model.vaultRoot : Maybe String` is the absolute path of the opened vault. `create_file`
  (`fs_commands.rs`) writes `root.join(path)` and creates parent directories
  (there is a "creates parent dirs" test), so writing `Inbox/<name>` auto-creates `Inbox/`.
- The user opens **kbase** directly *and* sometimes a **subfolder** of kbase.

## Design

### 1. `frontend/src/View.elm` — stop OS mangling

Add to the new-file-name `Html.input` attribute list:

```elm
, Html.Attributes.attribute "autocapitalize" "off"
, Html.Attributes.attribute "autocorrect" "off"
, Html.Attributes.spellcheck False
```

### 2. `frontend/src/PathUtil.elm` — locate the kbase root

Add:

```elm
{-| If `path` contains a directory segment named "kbase", return the path
truncated to and including that segment (the kbase root); otherwise Nothing.
"kbase or a descendant" ⇒ this returns Just for both `…/kbase` and `…/kbase/sub`.
-}
kbaseRoot : String -> Maybe String
kbaseRoot path =
    let
        go acc remaining =
            case remaining of
                [] ->
                    Nothing

                seg :: rest ->
                    if seg == "kbase" then
                        Just (String.join "/" (List.reverse (seg :: acc)))

                    else
                        go (seg :: acc) rest
    in
    go [] (String.split "/" path)
```

(Exact-segment match, so `kbase-backup` does not qualify; the leading empty segment of an
absolute path is preserved by the join, so `/Users/x/kbase/...` → `/Users/x/kbase`.)

### 3. `frontend/src/Main.elm` — `ClickedNewFile` placement + verbatim name

- Remove `ensureScriptaExt` (function and use).
- Rewrite `ClickedNewFile`:

```elm
        ClickedNewFile ->
            case model.vaultRoot of
                Just root ->
                    let
                        name =
                            String.trim model.newName
                    in
                    if String.isEmpty name then
                        ( model, Cmd.none )

                    else
                        case PathUtil.kbaseRoot root of
                            Just kroot ->
                                let
                                    path =
                                        "Inbox/" ++ name
                                in
                                request (PCreateFile path)
                                    "create_file"
                                    [ ( "root", E.string kroot ), ( "path", E.string path ), ( "content", E.string "" ) ]
                                    { model | newName = "" }

                            Nothing ->
                                let
                                    path =
                                        PathUtil.siblingPath model.selectedPath name
                                in
                                request (PCreateFile path)
                                    "create_file"
                                    [ ( "root", E.string root ), ( "path", E.string path ), ( "content", E.string "" ) ]
                                    { model | newName = "" }

                Nothing ->
                    ( model, Cmd.none )
```

Note the kbase branch passes **`kroot`** (the kbase root) as the command's `root`, with
`Inbox/<name>` relative to it — so the file lands in the real `kbase/Inbox` whether the opened
vault is kbase itself or a subfolder. `create_file` creates `Inbox/` if absent.

## Data Flow

```
New clicked
  → name = trim(model.newName); empty → no-op
  → kbaseRoot(vaultRoot):
       Just kroot → create_file { root = kroot, path = "Inbox/<name>" }   (→ kbase/Inbox/<name>)
       Nothing    → create_file { root = vaultRoot, path = siblingPath(selectedPath, <name>) }
  → PCreateFile → relist(vaultRoot)  (re-lists the OPENED vault)
```

## Behavior Notes / Caveats

- **Verbatim name:** whatever you type is the filename, including the extension. No extension is
  added; if you type none, the file has none. Auto-capitalize/correct are disabled.
- **Sidebar visibility in the subfolder case:** when the opened vault is a *subfolder* of kbase,
  `kbase/Inbox` is *above* the vault, so `relist` (which lists only the opened vault) will **not**
  show the new file. It is correctly created in `kbase/Inbox`; it becomes visible when you open
  `kbase` as the vault. (Accepted — the Inbox is a capture location.) When the vault *is* kbase,
  `Inbox/` is inside the tree and the file appears immediately after the relist.

## Error Handling

- Empty/whitespace name → no-op (unchanged).
- `create_file` failure → existing error banner (via `handleResponse` `Err` arm), unchanged.

## Testing

- **Elm `PathUtil` unit tests:**
  - `kbaseRoot "/Users/c/Library/Mobile Documents/com~apple~CloudDocs/kbase"` → `Just ".../kbase"`.
  - `kbaseRoot ".../kbase/Subjects/Physics"` → `Just ".../kbase"` (truncated to kbase).
  - `kbaseRoot "/Users/c/projects/notes"` → `Nothing`.
  - `kbaseRoot "/Users/c/kbase-backup/x"` → `Nothing` (exact-segment match).
- **Elm:** confirm `ensureScriptaExt` is gone (compile) — the name is no longer transformed.
- **Manual:** in the kbase vault, New `foo.md` → creates `kbase/Inbox/foo.md`, lowercase
  preserved, no `.scripta`; appears in the sidebar (vault = kbase). Open a non-kbase folder as a
  vault, open a doc, New `bar.txt` → created beside that doc. (Auto-capitalize off can only be
  verified in the GUI.)

## Out of Scope (YAGNI)

- Making the special folder name (`kbase`) or inbox name (`Inbox`) configurable.
- Auto-revealing / auto-opening the new Inbox file when the opened vault is a subfolder (would
  require listing/selecting outside the opened vault).
- Selectable tree folders as a create target (the chosen rule doesn't need it).
- The deferred image-companion-`.md` idea (separate, in memory).
