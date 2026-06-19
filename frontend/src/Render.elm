module Render exposing (RenderMsg(..), RenderOutput, options, compile, renderDocument, parse)

{-| Thin wrapper over the vendored Scripta compiler. v1 renders Scripta only.
Targets compiler-v3's public API.
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
    | OpenUrl String
    | OpenLocalFile String


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
