module Tools.ParserTools exposing
    ( Context
    , Problem(..)
    , StringData
    , text
    )

import Parser.Advanced as Parser exposing ((|.), (|=))


type Problem
    = ExpectingPrefix
    | ExpectingSymbol String


type Context
    = TextExpression


type alias StringData =
    { begin : Int, end : Int, content : String }


{-| Get the longest string whose first character satisfies `prefix`
and whose remaining characters satisfy `continue`.
-}
text : (Char -> Bool) -> (Char -> Bool) -> Parser.Parser Context Problem StringData
text prefix continue =
    Parser.succeed (\start finish content -> { begin = start, end = finish, content = String.slice start finish content })
        |= Parser.getOffset
        |. Parser.chompIf (\c -> prefix c) ExpectingPrefix
        |. Parser.chompWhile (\c -> continue c)
        |= Parser.getOffset
        |= Parser.getSource
