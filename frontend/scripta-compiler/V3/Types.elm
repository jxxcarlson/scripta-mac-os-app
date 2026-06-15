module V3.Types exposing (..)

{-| The Scripta Language consists of blocks and expressions.

  - GenericBlocks
  - PrimitiveBlocks
  - ExpressionBlocks

-}

import Dict exposing (Dict)
import ETeX.MathMacros as MathMacros
import Either exposing (Either)
import Generic.Vector exposing (Vector)
import Html exposing (Html)



-- EXPRESSION CACHE


{-| Cache for expression parsing results, keyed by block source text.
-}
type alias ExpressionCache =
    Dict String (Either String (List Expression))



-- BLOCKS


{-| GenericBlock: a parameterized block, i.e., a type constructor

  - PrimitiveBlocks: content = List String
  - ExpressionBlocks: content = Either String (List Expression)

-}
type alias GenericBlock content metaData style =
    { heading : Heading
    , indent : Int
    , args : List String
    , properties : Dict String String
    , firstLine : String
    , body : content
    , meta : metaData
    , style : style
    }


type Heading
    = Paragraph
    | Ordinary String -- block name
    | Verbatim String -- block name


{-| A block whose content is a list of strings.
-}
type alias PrimitiveBlock =
    GenericBlock (List String) BlockMeta NullStyle


{-| A block whose content is a list of expressions.
-}
type alias ExpressionBlock =
    GenericBlock (Either String (List Expression)) BlockMeta NullStyle



-- EXPRESSIONS


type alias Expression =
    Expr ExprMeta


type Expr metaData
    = Text String metaData
    | Fun String (List (Expr metaData)) metaData
    | VFun String String metaData
    | ExprList Int (List (Expr metaData)) metaData -- the Int parameter is the indentation of the expression list in the source



-- METADATA


type alias BlockMeta =
    { id : String
    , position : Int
    , lineNumber : Int
    , bodyLineNumber : Int
    , numberOfLines : Int
    , begin : Int
    , end : Int
    , contentBegin : Int
    , contentEnd : Int
    , messages : List String
    , sourceText : String
    , error : Maybe String
    }


type alias ExprMeta =
    { begin : Int, end : Int, index : Int, id : String }



-- STYLE


type alias NullStyle =
    {}



-- ACCUMULATOR


{-|


# Reference field

The reference field in the Accumulator is a dictionary that
maps label names to their rendered reference information:

reference : Dict String { id : String, numRef : String }

Purpose: It stores cross-reference data so that [ref ...] and [eqref ...] elements can look up:

  - id - the HTML element id to scroll to
  - numRef - the display number/label (e.g., "1.4" for a section, "3" for an equation)

How it gets populated:

1.  Sections (# Heading, | section): Stores section number like "1.2.3" with the section's tag/slug
      - src/Generic/Acc.elm:741 - updateReference called with section data
2.  Equations (| equation with label:foo): Stores equation number
      - src/Generic/Acc.elm:937 - Updates reference when equation has a label property
3.  Theorems and numbered blocks: Stores block numbers
      - src/Generic/Acc.elm:877 - For numbered block names like theorem, lemma, etc.
4.  Bibitems (| bibitem key): Stores bibliography number
      - src/Generic/Acc.elm:800 - Now stores { id = id, numRef = "7" }

How it's used in rendering:

  - renderRef looks up the label and displays numRef, scrolling to the target
  - renderEqRef displays equation numbers in parentheses like "(3)"

For example, if you have [label pythag] on an equation numbered "2.1",
then [eqref pythag] looks up "pythag" in reference to get { id: "...", numRef: "2.1" }
and renders as "(2.1)".

-}
type alias Accumulator =
    { headingIndex : Vector
    , documentIndex : Vector
    , counter : Dict String Int
    , blockCounter : Int
    , chapterCounter : Int
    , itemVector : Vector -- Used for section numbering
    , deltaLevel : Int
    , numberedItemDict : Dict String { level : Int, index : Int }
    , numberedBlockNames : List String
    , inListState : InListState
    , reference : Dict String { id : String, numRef : String }
    , terms : Dict String TermLoc
    , footnotes : Dict String TermLoc2
    , footnoteNumbers : Dict String Int
    , mathMacroDict : MathMacroDict
    , textMacroDict : Dict String Macro
    , keyValueDict : Dict String String
    , qAndAList : List ( String, String )
    , qAndADict : Dict String String
    , maxLevel : Int
    , bibliography : Dict String (Maybe Int) -- cite key -> bibitem number
    }


{-| Tracks whether we're currently inside a numbered list.
-}
type InListState
    = InList
    | NotInList


{-| Location of a term in the source.
The displayAs field allows customizing how the term appears in the index.
For example, [term change color show-as:color, change] displays as "color, change" in the index.
-}
type alias TermLoc =
    { begin : Int, end : Int, id : String, displayAs : Maybe String }


{-| Location of a footnote with optional source reference.
-}
type alias TermLoc2 =
    { begin : Int, end : Int, id : String, mSourceId : Maybe String }


{-| A text macro with name, variables, and body.
-}
type alias Macro =
    { name : String, vars : List String, body : List Expression }


{-| Dictionary of math macros. Re-exported from ETeX.MathMacros.
Uses MacroBody (arity, List MathExpr) for proper ETeX macro expansion.
-}
type alias MathMacroDict =
    MathMacros.MathMacroDict



-- COMPILER PARAMETERS


{-| Parameters for the compiler.
-}
type alias CompilerParameters =
    { filter : Filter
    , windowWidth : Int
    , theme : Theme
    , editCount : Int
    , width : Int
    , showTOC : Bool
    , sizing : SizingConfig
    , maxLevel : Int
    }


{-| Filter for the forest of expression blocks.
-}
type Filter
    = NoFilter
    | SuppressDocumentBlocks



-- COMPILER OUTPUT


{-| Output from the compiler containing rendered HTML.
-}
type alias CompilerOutput msg =
    { body : List (Html msg)
    , banner : Maybe (Html msg)
    , toc : List (Html msg)
    , title : Html msg
    }



-- MSG TYPE


{-| Messages for interactive rendering.
-}
type Msg
    = SelectId String
    | HighlightId String
    | ExpandImage String
    | FootnoteClick { targetId : String, returnId : String }
    | CitationClick { targetId : String, returnId : String }
    | GoToDocument String ExprMeta



-- RENDER SETTINGS
-- THEME


{-| Light or dark theme.
-}
type Theme
    = Light
    | Dark


{-| Configuration for sizing and spacing.
All values in pixels (Float), with a scale multiplier for global adjustments.
-}
type alias SizingConfig =
    { baseFontSize : Float -- in px, default 14.0
    , paragraphSpacing : Float -- in px, default 12.0
    , marginLeft : Float -- in px, default 0.0
    , marginRight : Float -- in px, default 0.0
    , indentation : Float -- in px, default 20.0, per indent level
    , indentUnit : Int -- spaces per indent level in source, default 2
    , scale : Float -- multiplier, default 1.0
    }


{-| Default sizing configuration.
-}
defaultSizingConfig : SizingConfig
defaultSizingConfig =
    { baseFontSize = 14.0
    , paragraphSpacing = 12.0
    , marginLeft = 0.0
    , marginRight = 0.0
    , indentation = 20.0
    , indentUnit = 2
    , scale = 1.0
    }
