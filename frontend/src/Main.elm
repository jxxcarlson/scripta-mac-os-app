module Main exposing (main)

import Browser
import Dict
import FileOps
import Json.Decode as D
import Json.Encode as E
import Types exposing (Model, Msg(..), PendingOp(..))
import View
import Workspace


main : Program () Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = View.view
        }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { vaultRoot = Nothing
      , tree = []
      , selectedPath = Nothing
      , nextRequestId = 0
      , pending = Dict.empty
      , error = Nothing
      }
    , Cmd.none
    )


{-| Issue an FS request, recording the pending op against its requestId.
-}
request : PendingOp -> String -> List ( String, E.Value ) -> Model -> ( Model, Cmd Msg )
request op cmdName args model =
    let
        rid =
            model.nextRequestId
    in
    ( { model | nextRequestId = rid + 1, pending = Dict.insert rid op model.pending }
    , FileOps.send rid cmdName args
    )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ClickedOpenVault ->
            request PPickWorkspace "pick_workspace" [] model

        ClickedTreeNode path ->
            ( { model | selectedPath = Just path }, Cmd.none )

        DismissError ->
            ( { model | error = Nothing }, Cmd.none )

        GotFileChanged _ ->
            ( model, Cmd.none )

        GotFsResponse value ->
            case D.decodeValue FileOps.responseDecoder value of
                Err e ->
                    ( { model | error = Just (D.errorToString e) }, Cmd.none )

                Ok resp ->
                    case Dict.get resp.requestId model.pending of
                        Nothing ->
                            ( model, Cmd.none )

                        Just op ->
                            handleResponse op resp { model | pending = Dict.remove resp.requestId model.pending }


handleResponse : PendingOp -> FileOps.FsResponse -> Model -> ( Model, Cmd Msg )
handleResponse op resp model =
    case FileOps.resultOf resp of
        Err e ->
            ( { model | error = Just e }, Cmd.none )

        Ok result ->
            case op of
                PPickWorkspace ->
                    case D.decodeValue (D.nullable D.string) result of
                        Ok (Just root) ->
                            request PListWorkspace "list_workspace" [ ( "root", E.string root ) ] { model | vaultRoot = Just root }

                        _ ->
                            ( model, Cmd.none )

                PListWorkspace ->
                    case D.decodeValue (D.list Workspace.entryDecoder) result of
                        Ok entries ->
                            ( { model | tree = Workspace.toTree entries }, Cmd.none )

                        Err e ->
                            ( { model | error = Just (D.errorToString e) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ FileOps.fsResponse GotFsResponse
        , FileOps.fileChanged GotFileChanged
        ]
