module ETeX.MathMacros exposing
    ( Context
    , Deco(..)
    , MacroBody(..)
    , MathExpr(..)
    , MathMacroDict
    , NewCommand(..)
    , Problem
    )

import Dict exposing (Dict)


type MathExpr
    = AlphaNum String
    | MacroName String
    | FunctionName String
    | Arg (List MathExpr)
    | PArg (List MathExpr)
    | ParenthExpr (List MathExpr)
    | Sub Deco
    | Super Deco
    | Param Int
    | WS
    | MathSpace
    | MathSmallSpace
    | MathMediumSpace
    | LeftMathBrace
    | RightMathBrace
    | LeftParen
    | RightParen
    | Comma
    | MathSymbols String
    | GreekSymbol String
    | Macro String (List MathExpr)
    | FCall String (List MathExpr)
    | Expr (List MathExpr)
    | Text String


type Deco
    = DecoM MathExpr
    | DecoI Int


type NewCommand
    = NewCommand MathExpr Int (List MathExpr)


type MacroBody
    = MacroBody Int (List MathExpr)


type alias MathMacroDict =
    Dict String MacroBody


type Context
    = CArg String


type Problem
    = ExpectingLeftBrace
    | ExpectingAlpha
    | ExpectingNotAlpha
    | ExpectingInt
    | InvalidNumber
    | ExpectingMathSmallSpace
    | ExpectingMathMediumSpace
    | ExpectingLeftBracket
    | ExpectingMathSpace
    | ExpectingRightBracket
    | ExpectingLeftMathBrace
    | ExpectingRightMathBrace
    | ExpectingUnderscore
    | ExpectingCaret
    | ExpectingSpace
    | ExpectingRightBrace
    | ExpectingHash
    | ExpectingBackslash
    | ExpectingNewCommand
    | ExpectingLeftParen
    | ExpectingRightParen
    | ExpectingComma
