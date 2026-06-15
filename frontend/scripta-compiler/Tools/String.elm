module Tools.String exposing (makeSlug)

{-| String utilities for the Scripta compiler.
-}


{-| Convert a string to a URL-friendly slug.
-}
makeSlug : String -> String
makeSlug str =
    str
        |> String.toLower
        |> String.trim
        |> String.replace " " "-"
        |> String.filter isSlugChar


isSlugChar : Char -> Bool
isSlugChar c =
    Char.isAlphaNum c || c == '-' || c == '_'
