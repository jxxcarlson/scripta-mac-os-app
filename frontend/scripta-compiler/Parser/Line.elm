module Parser.Line exposing (Line, classify)

{-| Line classification for the parser.
-}


type alias Line =
    { indent : Int
    , prefix : String
    , content : String
    , lineNumber : Int
    , position : Int
    }


{-| Classify a raw string into a Line record.
-}
classify : Int -> Int -> String -> Line
classify position lineNumber str =
    let
        leadingSpaces =
            countLeadingSpaces str

        prefix =
            String.left leadingSpaces str

        content =
            str
    in
    { indent = leadingSpaces
    , prefix = prefix
    , content = content
    , lineNumber = lineNumber
    , position = position
    }


countLeadingSpaces : String -> Int
countLeadingSpaces str =
    str
        |> String.toList
        |> List.foldl
            (\c ( count, counting ) ->
                if counting && c == ' ' then
                    ( count + 1, True )

                else
                    ( count, False )
            )
            ( 0, True )
        |> Tuple.first
