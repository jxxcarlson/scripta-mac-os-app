module Scripta.Internal exposing
    ( Document(..)
    , DocumentData
    , Filter(..)
    , Options(..)
    , OptionsData
    , SizingConfig
    , Theme(..)
    , optionsToParams
    )

{-| Internal definitions for the Scripta public API.

This module is NOT part of the public API. Consumers import `Scripta` and
`Scripta.Document`. The opaque `Document` and `Options` types are defined here
so that both `Scripta` and `Scripta.Document` can construct and inspect them.

-}

import RoseTree.Tree exposing (Tree)
import V3.Types exposing (Accumulator, ExpressionBlock, ExpressionCache)


{-| Sizing configuration. Re-exported from V3.Types (a record alias, so this
re-export is legal in Elm).
-}
type alias SizingConfig =
    V3.Types.SizingConfig


{-| Light or dark theme. Defined here (not re-exported from V3.Types) because
Elm cannot re-export a custom type's constructors.
-}
type Theme
    = Light
    | Dark


{-| Forest filter.
-}
type Filter
    = NoFilter
    | SuppressDocumentBlocks


{-| The data carried by an opaque Options value.
-}
type alias OptionsData =
    { filter : Filter
    , windowWidth : Int
    , theme : Theme
    , contentWidth : Int
    , showTOC : Bool
    , sizing : SizingConfig
    , maxLevel : Int
    }


{-| Opaque options value. Built with `Scripta.defaultOptions` and `with*`.
-}
type Options
    = Options OptionsData


{-| The data carried by an opaque Document value.
-}
type alias DocumentData =
    { accumulator : Accumulator
    , forest : List (Tree ExpressionBlock)
    , cache : ExpressionCache
    }


{-| Opaque parsed document. Produced by `Scripta.parse` / `Scripta.reparse`,
consumed by `Scripta.render` and `Scripta.Document` queries.
-}
type Document
    = Document DocumentData


{-| Convert public Options to the internal CompilerParameters.
-}
optionsToParams : Options -> V3.Types.CompilerParameters
optionsToParams (Options data) =
    { filter =
        case data.filter of
            NoFilter ->
                V3.Types.NoFilter

            SuppressDocumentBlocks ->
                V3.Types.SuppressDocumentBlocks
    , windowWidth = data.windowWidth
    , theme =
        case data.theme of
            Light ->
                V3.Types.Light

            Dark ->
                V3.Types.Dark
    , editCount = 0
    , width = data.contentWidth
    , showTOC = data.showTOC
    , sizing = data.sizing
    , maxLevel = data.maxLevel
    }
