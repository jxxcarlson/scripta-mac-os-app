module Flags exposing (Flags, decode)

{-| App-launch preferences read from localStorage (via JS) as a JSON value.
Decoding is tolerant: any missing or malformed field falls back to a default.
-}

import Json.Decode as D


type alias Flags =
    { lastVault : Maybe String
    , readerMode : Bool
    }


decode : D.Value -> Flags
decode value =
    { lastVault =
        D.decodeValue (D.field "lastVault" (D.nullable D.string)) value
            |> Result.withDefault Nothing
    , readerMode =
        D.decodeValue (D.field "readerMode" D.bool) value
            |> Result.withDefault False
    }
