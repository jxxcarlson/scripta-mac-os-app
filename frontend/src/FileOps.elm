port module FileOps exposing
    ( FsResponse
    , fsRequest, fsResponse, fileChanged, openFile
    , scrollAndHighlight, copyToClipboard
    , saveOpenFolders, requestOpenFolders, gotOpenFolders
    , saveLastVault, saveFullParse, saveIsLight, saveAiConfig, saveTerminalVisible
    , encodeRequest, responseDecoder, resultOf
    , send
    )

{-| The bridge to the Tauri shell. Every request carries a `requestId`; the
JS shim returns a matching response on `fsResponse`. `fileChanged` carries
unsolicited watcher events.
-}

import Json.Decode as D
import Json.Encode as E


port fsRequest : E.Value -> Cmd msg


port fsResponse : (E.Value -> msg) -> Sub msg


port fileChanged : (E.Value -> msg) -> Sub msg


port openFile : (E.Value -> msg) -> Sub msg


port saveOpenFolders : E.Value -> Cmd msg


port requestOpenFolders : String -> Cmd msg


port gotOpenFolders : (E.Value -> msg) -> Sub msg


port saveLastVault : String -> Cmd msg


port saveFullParse : Bool -> Cmd msg


port saveIsLight : Bool -> Cmd msg


port saveTerminalVisible : Bool -> Cmd msg


port saveAiConfig : E.Value -> Cmd msg


port scrollAndHighlight : String -> Cmd msg


port copyToClipboard : String -> Cmd msg


type alias FsResponse =
    { requestId : Int
    , ok : Bool
    , result : D.Value
    , error : Maybe String
    }


{-| Build a request envelope: { requestId, op, args }. `op` is the snake_case
Tauri command name; `args` is a list of (key, value) pairs.
-}
encodeRequest : Int -> String -> List ( String, E.Value ) -> E.Value
encodeRequest requestId op args =
    E.object
        [ ( "requestId", E.int requestId )
        , ( "op", E.string op )
        , ( "args", E.object args )
        ]


{-| Encode and dispatch a request as a Cmd.
-}
send : Int -> String -> List ( String, E.Value ) -> Cmd msg
send requestId op args =
    fsRequest (encodeRequest requestId op args)


responseDecoder : D.Decoder FsResponse
responseDecoder =
    D.map4 FsResponse
        (D.field "requestId" D.int)
        (D.field "ok" D.bool)
        (D.oneOf [ D.field "result" D.value, D.succeed E.null ])
        (D.maybe (D.field "error" D.string))


{-| Interpret a response as a Result, returning the raw result value or the
error string.
-}
resultOf : FsResponse -> Result String D.Value
resultOf resp =
    if resp.ok then
        Ok resp.result

    else
        Err (Maybe.withDefault "unknown error" resp.error)
