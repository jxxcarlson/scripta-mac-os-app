# TOC items: bold-dot prefix + hanging indent — Design

Date: 2026-06-22

Each table-of-contents item gets a **bold `•` followed by one space** as its
prefix, and its text is laid out with a **hanging indent** (wrapped lines align
under the text, not under the dot). Applies to BOTH the Markdown and the Scripta
TOCs.

## Shared visual

- Prefix: an inline `<span style="font-weight:bold">•</span>` then a literal
  `" "` (one space), then the item's existing link/text.
- Hanging indent: on the item's line element, `padding-left: 1.1em` +
  `text-indent: -1.1em` (the `1.1em` ≈ width of "• "; tunable).

```
• 1. Introduction
• 2. A heading that wraps
  to a second line, hanging
• 2.1 Submethod
```

## Feature 1 — Markdown TOC (`frontend/src/MarkdownRender.elm`)

`tocItemView (Item _ str kids)` currently puts a clickable `link` span directly
in an `<li>` (with a nested `<ul>` for children). Wrap the link line in a block
that carries the dot + hanging indent, leaving the nested `<ul>` untouched:

```elm
tocItemView : ToCItem -> Html Render.RenderMsg
tocItemView (Item _ str kids) =
    let
        link =
            Html.span
                [ Html.Events.onClick (Render.ScrollTo (ToC.headingId str))
                , style "cursor" "pointer"
                , style "color" "var(--link)"
                ]
                [ Html.text str ]

        line =
            Html.div
                [ style "padding-left" "1.1em", style "text-indent" "-1.1em" ]
                [ Html.span [ style "font-weight" "bold" ] [ Html.text "•" ]
                , Html.text " "
                , link
                ]
    in
    if List.isEmpty kids then
        Html.li [] [ line ]

    else
        Html.li []
            [ line
            , Html.ul (ulStyle "1em")
                (List.map tocItemView kids)
            ]
```

## Feature 2 — Scripta TOC (`frontend/scripta-compiler/Render/TOC.elm`)

`buildTocItem` currently renders a single **truncated** line
(`white-space:nowrap`, `text-overflow:ellipsis`, `overflow:hidden`) with the
section-number prefix on the `<a>`. To allow wrapping (so the hanging indent is
visible), drop those three styles; add the dot + hanging indent; keep the
per-level `margin-left`, `margin-bottom`, the `title` tooltip, and the section
number (`• 1. Title`).

Replace the `Html.div [ … ] [ Html.a [ … ] [ Html.text (prefix ++ entry.title) ] ]`
with:

```elm
    Html.div
        [ HA.style "margin-left" (String.fromInt indent ++ "px")
        , HA.style "margin-bottom" "0.25em"
        , HA.style "padding-left" "1.1em"
        , HA.style "text-indent" "-1.1em"
        , HA.title (prefix ++ entry.title)
        ]
        [ Html.span [ HA.style "font-weight" "bold" ] [ Html.text "•" ]
        , Html.text " "
        , Html.a
            [ HA.href ("#" ++ entry.id)
            , HE.onClick (SelectId entry.id)
            , HA.style "color"
                (case params.theme of
                    Light ->
                        "#0066cc"

                    Dark ->
                        "#66b3ff"
                )
            , HA.style "text-decoration" "none"
            ]
            [ Html.text (prefix ++ entry.title) ]
        ]
```

(`indent` and `prefix` are the existing `let` bindings, unchanged. The removed
styles are exactly `overflow:hidden`, `white-space:nowrap`, `text-overflow:ellipsis`.)

## Notes
- Editing `scripta-compiler/Render/TOC.elm` modifies the **vendored** Scripta
  compiler copy in this app; it diverges from upstream until synced. (User owns
  Scripta; approved.)
- Section numbers are **kept** for Scripta (`• 1. Title`).
- Scripta TOC items now **wrap** instead of truncating with an ellipsis — a
  deliberate consequence of the hanging-indent requirement.

## Testing
- Both changes are view-typed (produce `Html`); verified by compile + manual:
  Markdown and Scripta TOCs each show `• ` bold-dot bullets, and a long heading
  wraps with its continuation aligned under the title text.

## Out of scope
- Changing the Scripta TOC's outer "Contents" box/border.
- The `1.1em` exact value (tunable on iteration).
