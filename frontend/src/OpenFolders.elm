module OpenFolders exposing (fromValue, toggle)

{-| Pure helpers for the set of open (expanded) folder paths in the file tree.
-}

import Json.Decode as D
import Set exposing (Set)


{-| Flip a folder path's membership: remove it if present, otherwise add it.
-}
toggle : String -> Set String -> Set String
toggle path set =
    if Set.member path set then
        Set.remove path set

    else
        Set.insert path set


{-| Decode a persisted JSON array of folder paths into a Set. Any malformed
value yields the empty set (all folders closed).
-}
fromValue : D.Value -> Set String
fromValue value =
    case D.decodeValue (D.list D.string) value of
        Ok xs ->
            Set.fromList xs

        Err _ ->
            Set.empty
