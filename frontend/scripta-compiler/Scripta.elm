module Scripta exposing
    ( Options, defaultOptions
    , withTheme, withWindowWidth, withContentWidth, withTOC, withMaxLevel, withSizing, withFilter
    , Theme(..), Filter(..), SizingConfig, defaultSizing
    , Document
    , Event(..), Output
    , parse, reparse, render, compile, mapEvent
    , exportHtml
    )

{-| Public API for the Scripta compiler.


# Options

@docs Options, defaultOptions
@docs withTheme, withWindowWidth, withContentWidth, withTOC, withMaxLevel, withSizing, withFilter
@docs Theme, Filter, SizingConfig, defaultSizing


# Documents and rendering

@docs Document
@docs Event, Output
@docs parse, reparse, render, compile, mapEvent


# Static export

@docs exportHtml

-}

import Dict
import Either
import Html exposing (Html)
import Parser.Forest
import Render.Export.Html
import Render.Settings
import Render.Types
import Scripta.Internal as Internal exposing (Document(..), Options(..))
import V3.Compiler
import V3.Types


{-| Opaque compiler options. Build with `defaultOptions` and the `with*`
functions.
-}
type alias Options =
    Internal.Options


{-| Light or dark theme.
-}
type Theme
    = Light
    | Dark


{-| Forest filter. `NoFilter` renders everything; `SuppressDocumentBlocks`
hides `document` and `title` blocks.
-}
type Filter
    = NoFilter
    | SuppressDocumentBlocks


{-| Sizing/spacing configuration (a record).
-}
type alias SizingConfig =
    Internal.SizingConfig


{-| Default sizing configuration.
-}
defaultSizing : SizingConfig
defaultSizing =
    V3.Types.defaultSizingConfig


themeToInternal : Theme -> Internal.Theme
themeToInternal theme =
    case theme of
        Light ->
            Internal.Light

        Dark ->
            Internal.Dark


filterToInternal : Filter -> Internal.Filter
filterToInternal filter =
    case filter of
        NoFilter ->
            Internal.NoFilter

        SuppressDocumentBlocks ->
            Internal.SuppressDocumentBlocks


{-| Default options: no filter, 800px window and content width, light theme,
no table of contents, default sizing, unlimited heading level.
-}
defaultOptions : Options
defaultOptions =
    Internal.Options
        { filter = Internal.NoFilter
        , windowWidth = 800
        , theme = Internal.Light
        , contentWidth = 800
        , showTOC = False
        , sizing = V3.Types.defaultSizingConfig
        , maxLevel = 0
        }


{-| Set the theme.
-}
withTheme : Theme -> Options -> Options
withTheme theme (Internal.Options data) =
    Internal.Options { data | theme = themeToInternal theme }


{-| Set the window width in pixels.
-}
withWindowWidth : Int -> Options -> Options
withWindowWidth w (Internal.Options data) =
    Internal.Options { data | windowWidth = w }


{-| Set the content (text column) width in pixels.
-}
withContentWidth : Int -> Options -> Options
withContentWidth w (Internal.Options data) =
    Internal.Options { data | contentWidth = w }


{-| Show or hide the table of contents.
-}
withTOC : Bool -> Options -> Options
withTOC show (Internal.Options data) =
    Internal.Options { data | showTOC = show }


{-| Set the maximum heading level to render.
-}
withMaxLevel : Int -> Options -> Options
withMaxLevel level (Internal.Options data) =
    Internal.Options { data | maxLevel = level }


{-| Set the sizing configuration.
-}
withSizing : SizingConfig -> Options -> Options
withSizing sizing (Internal.Options data) =
    Internal.Options { data | sizing = sizing }


{-| Set the forest filter.
-}
withFilter : Filter -> Options -> Options
withFilter filter (Internal.Options data) =
    Internal.Options { data | filter = filterToInternal filter }


{-| An opaque parsed document. Produced by `parse` / `reparse`, consumed by
`render` and the `Scripta.Document` query functions.
-}
type alias Document =
    Internal.Document


{-| An interaction event emitted by rendered output.

  - `ClickedId` — the user clicked an element with the given id.
  - `ClickedFootnote` / `ClickedCitation` — jump to a target, remembering a return id.
  - `ClickedImage` — the user clicked an image (url).
  - `ClickedLink` — the user clicked an internal document link (slug).
  - `HighlightedId` — request to highlight the element with the given id.

-}
type Event
    = ClickedId String
    | ClickedFootnote { targetId : String, returnId : String }
    | ClickedCitation { targetId : String, returnId : String }
    | ClickedImage String
    | ClickedLink String
    | HighlightedId String


{-| Rendered output, polymorphic in the message type so `mapEvent` can retarget it.
-}
type alias Output msg =
    { title : Html msg
    , body : List (Html msg)
    , toc : List (Html msg)
    , banner : Maybe (Html msg)
    }


{-| Translate the internal compiler Msg to the public Event type.
-}
msgToEvent : V3.Types.Msg -> Event
msgToEvent msg =
    case msg of
        V3.Types.SelectId id ->
            ClickedId id

        V3.Types.HighlightId id ->
            HighlightedId id

        V3.Types.ExpandImage url ->
            ClickedImage url

        V3.Types.FootnoteClick record ->
            ClickedFootnote record

        V3.Types.CitationClick record ->
            ClickedCitation record

        -- ExprMeta is scroll-position context, not part of the public API
        V3.Types.GoToDocument slug _ ->
            ClickedLink slug


{-| Parse source text into a Document (cold path: full parse).

For editor keystroke updates use `reparse`, which is incremental.

-}
parse : Options -> String -> Document
parse options source =
    let
        params =
            Internal.optionsToParams options

        ( cache, accumulator, forest ) =
            Parser.Forest.parseIncrementally params Dict.empty (String.lines source)
    in
    Document
        { accumulator = accumulator
        , forest = forest
        , cache = cache
        }


{-| Re-parse source text incrementally, reusing the previous Document's cache
and accumulator where it is safe to do so. Use this for editor keystroke
updates; use `parse` for initial load and document switches.
-}
reparse : Options -> Document -> String -> Document
reparse options (Document prev) source =
    let
        params =
            Internal.optionsToParams options

        result =
            Parser.Forest.parseIncrementallySkipAcc params
                prev.cache
                ( prev.accumulator, prev.forest )
                (String.lines source)
    in
    Document
        { accumulator = result.acc
        , forest = result.forest
        , cache = result.cache
        }


{-| Render a parsed Document to HTML output carrying `Event`s.
-}
render : Options -> Document -> Output Event
render options (Document data) =
    V3.Compiler.render (Internal.optionsToParams options)
        ( data.accumulator, data.forest )
        |> toEventOutput


{-| Parse and render in one step (cold path).
-}
compile : Options -> String -> Output Event
compile options source =
    render options (parse options source)


{-| Retarget a whole Output from `Event` to the consumer's own message type.
-}
mapEvent : (Event -> msg) -> Output Event -> Output msg
mapEvent f output =
    { title = Html.map f output.title
    , body = List.map (Html.map f) output.body
    , toc = List.map (Html.map f) output.toc
    , banner = Maybe.map (Html.map f) output.banner
    }


{-| Convert the internal CompilerOutput Msg to an Output Event.
-}
toEventOutput : V3.Types.CompilerOutput V3.Types.Msg -> Output Event
toEventOutput output =
    { title = Html.map msgToEvent output.title
    , body = List.map (Html.map msgToEvent) output.body
    , toc = List.map (Html.map msgToEvent) output.toc
    , banner = Maybe.map (Html.map msgToEvent) output.banner
    }


{-| Export a parsed Document as a complete standalone HTML document (a single String).

The output is meant for static viewing or printing: it includes a `<head>`
that pulls KaTeX from a CDN for math rendering and a default stylesheet,
plus a `<body>` containing the title, optional TOC, and rendered content.
None of the interactive editor-sync handlers are included.

-}
exportHtml : Options -> Document -> String
exportHtml _ (Document data) =
    let
        publicationData : Render.Types.PublicationData
        publicationData =
            { title = ""
            , authorList = []
            , kind = Render.Types.DKArticle
            , date = Either.Right ""
            }
    in
    Render.Export.Html.export publicationData
        Render.Settings.defaultRenderSettings
        data.accumulator
        data.forest
