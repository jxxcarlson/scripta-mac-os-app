module Flags exposing (Flags, decode)

{-| App-launch preferences passed in from JS as a JSON value (`lastVault` from a
Rust-owned file, `readerMode` from localStorage). Decoding is tolerant: any
missing or malformed field falls back to a default.
-}

import AiConfig
import Json.Decode as D


type alias Flags =
    { lastVault : Maybe String
    , readerMode : Bool
    , fullParse : Bool
    , isLight : Bool
    , aiConfig : AiConfig.AiConfig
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
    , isLight =
        D.decodeValue (D.field "isLight" D.bool) value
            |> Result.withDefault True
    , aiConfig =
        D.decodeValue (D.field "aiConfig" AiConfig.decoder) value
            |> Result.withDefault AiConfig.init
    }
