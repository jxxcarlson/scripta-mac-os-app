module Generic.Settings exposing (indentationQuantum, numberedBlockNames)

{-| Settings for the Scripta compiler.
-}


{-| Block names that should be numbered (theorems, equations, figures, etc.)
-}
numberedBlockNames : List String
numberedBlockNames =
    [ "q"
    , "axiom"
    , "box"
    , "theorem"
    , "definition"
    , "lemma"
    , "construction"
    , "principle"
    , "proposition"
    , "corollary"
    , "note"
    , "remark"
    , "exercise"
    , "question"
    , "problem"
    , "example"
    , "equation"
    , "math"
    , "aligned"
    , "quiver"
    , "image"
    , "iframe"
    , "chart"
    ]


{-| Number of spaces per indentation level.
-}
indentationQuantum : Int
indentationQuantum =
    2
