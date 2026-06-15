# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

This is a new, empty project named **Mac Scripta Viewer** — intended as a macOS viewer for
[Scripta](https://scripta.io) markup. No application source code exists yet; the repository
currently contains only IntelliJ IDEA project files (`.idea/`, `Mac Scripta Viewer.iml`).

## Tooling

The IDE is configured for **Elm** development (see `.idea/workspace.xml`):

- Compiler: `/opt/homebrew/bin/elm`
- Formatter: `/opt/homebrew/bin/elm-format` (format-on-save enabled)
- Tests: `/opt/homebrew/bin/elm-test`
- elm-review on-the-fly is enabled

## Next steps

Once source code, `elm.json`, and a build/run/test setup are added, expand this file with the
build/lint/test commands and a description of the architecture. Update it from real code, not
assumptions.
