module Flags exposing (Flags, decode)

{-| App-launch preferences passed in from JS as a JSON value (`lastVault` from a
Rust-owned file, `readerMode` from localStorage). Decoding is tolerant: any
missing or malformed field falls back to a default.
-}

import Json.Decode as D


type alias Flags =
    { lastVault : Maybe String
    , readerMode : Bool
    , fullParse : Bool
    }


decode : D.Value -> Flags
decode value =
    { lastVault =
        D.decodeValue (D.field "lastVault" (D.nullable D.string)) value
            |> Result.withDefault Nothing
    , readerMode =
        D.decodeValue (D.field "readerMode" D.bool) value
            |> Result.withDefault False
    , fullParse =
        D.decodeValue (D.field "fullParse" D.bool) value
            |> Result.withDefault True
    }
