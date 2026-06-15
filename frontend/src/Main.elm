module Main exposing (main)

import Browser
import Dict
import Export
import FileOps
import Json.Decode as D
import Json.Encode as E
import Language
import OpenFolders
import Process
import Render
import SaveState
import Scripta
import Set
import Task
import PathUtil
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
    request PLaunchFile
        "take_launch_file"
        []
        { vaultRoot = Nothing
        , tree = []
        , selectedPath = Nothing
        , nextRequestId = 0
        , pending = Dict.empty
        , error = Nothing
        , content = ""
        , loadedContent = ""
        , loadedMtime = 0
        , externalConflict = False
        , parsedDoc = Nothing
        , language = Nothing
        , isLight = True
        , contentWidth = 500
        , saveState = SaveState.init
        , newName = ""
        , openFolders = Set.empty
        , searchQuery = ""
        }


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


{-| Open an absolute file path: make its parent folder the vault, watch + list
that folder, and read the file (whose workspace-relative path is its basename).
-}
openExternalFile : String -> Model -> ( Model, Cmd Msg )
openExternalFile abs model =
    let
        parent =
            PathUtil.parentDir abs

        name =
            PathUtil.basename abs

        m0 =
            { model
                | vaultRoot = Just parent
                , selectedPath = Just name
                , language = Language.fromPath name
                , openFolders = Set.empty
            }

        ( m1, c1 ) =
            request PListWorkspace "list_workspace" [ ( "root", E.string parent ) ] m0

        ( m2, c2 ) =
            request PNoop "watch_workspace" [ ( "root", E.string parent ) ] m1

        ( m3, c3 ) =
            request (PReadFile name) "read_file" [ ( "root", E.string parent ), ( "path", E.string name ) ] m2
    in
    ( m3, Cmd.batch [ c1, c2, c3, FileOps.requestOpenFolders parent ] )


saveOpenFoldersCmd : Maybe String -> Set.Set String -> Cmd Msg
saveOpenFoldersCmd maybeVault folders =
    case maybeVault of
        Just vault ->
            FileOps.saveOpenFolders
                (E.object
                    [ ( "vault", E.string vault )
                    , ( "folders", E.list E.string (Set.toList folders) )
                    ]
                )

        Nothing ->
            Cmd.none


applySaveAction : SaveState.Action -> Model -> ( Model, Cmd Msg )
applySaveAction action model =
    case action of
        SaveState.NoAction ->
            ( model, Cmd.none )

        SaveState.ScheduleDebounce id delay ->
            ( model, Process.sleep delay |> Task.perform (\_ -> DebounceFired id) )

        SaveState.PerformSave _ ->
            case ( model.vaultRoot, model.selectedPath ) of
                ( Just root, Just path ) ->
                    request (PWriteFile path)
                        "write_file"
                        [ ( "root", E.string root ), ( "path", E.string path ), ( "content", E.string model.content ) ]
                        model

                _ ->
                    ( model, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ClickedOpenVault ->
            request PPickWorkspace "pick_workspace" [] model

        ClickedTreeNode path ->
            case model.vaultRoot of
                Just root ->
                    request (PReadFile path)
                        "read_file"
                        [ ( "root", E.string root ), ( "path", E.string path ) ]
                        { model | selectedPath = Just path, language = Language.fromPath path }

                Nothing ->
                    ( model, Cmd.none )

        NoOpFromRender ->
            ( model, Cmd.none )

        DismissError ->
            ( { model | error = Nothing }, Cmd.none )

        GotFileChanged value ->
            case D.decodeValue (D.map2 Tuple.pair (D.field "path" D.string) (D.field "mtime" D.int)) value of
                Ok ( path, mtime ) ->
                    if Just path == model.selectedPath && mtime > model.loadedMtime && model.saveState.saveStatus /= SaveState.Saving then
                        ( { model | externalConflict = True }, Cmd.none )

                    else
                        ( model, Cmd.none )

                Err _ ->
                    ( model, Cmd.none )

        ClickedReloadExternal ->
            case ( model.vaultRoot, model.selectedPath ) of
                ( Just root, Just path ) ->
                    request (PReadFile path)
                        "read_file"
                        [ ( "root", E.string root ), ( "path", E.string path ) ]
                        { model | externalConflict = False }

                _ ->
                    ( model, Cmd.none )

        ClickedKeepMine ->
            case ( model.vaultRoot, model.selectedPath ) of
                ( Just root, Just path ) ->
                    request (PWriteFile path)
                        "write_file"
                        [ ( "root", E.string root ), ( "path", E.string path ), ( "content", E.string model.content ) ]
                        { model | externalConflict = False }

                _ ->
                    ( model, Cmd.none )

        EditorChanged newText ->
            let
                ( ss, action ) =
                    SaveState.textChanged 1000 model.saveState

                reparsed =
                    if model.language == Just Language.Scripta then
                        Maybe.map (\d -> Scripta.reparse (Render.options model.isLight model.contentWidth) d newText) model.parsedDoc

                    else
                        model.parsedDoc
            in
            applySaveAction action { model | content = newText, parsedDoc = reparsed, saveState = ss }

        DebounceFired firedId ->
            let
                ( ss, action ) =
                    SaveState.debounceFired firedId model.saveState
            in
            applySaveAction action { model | saveState = ss }

        GotSaveResult _ ->
            let
                ( ss, action ) =
                    SaveState.saveSucceeded model.saveState
            in
            applySaveAction action { model | saveState = ss }

        SetNewName s ->
            ( { model | newName = s }, Cmd.none )

        ClickedChangeVault ->
            request PPickWorkspace "pick_workspace" [] model

        ClickedNewFile ->
            case model.vaultRoot of
                Just root ->
                    let
                        path =
                            ensureScriptaExt model.newName
                    in
                    if String.isEmpty (String.trim model.newName) then
                        ( model, Cmd.none )

                    else
                        request (PCreateFile path)
                            "create_file"
                            [ ( "root", E.string root ), ( "path", E.string path ), ( "content", E.string "" ) ]
                            { model | newName = "" }

                Nothing ->
                    ( model, Cmd.none )

        ClickedDeleteSelected ->
            case ( model.vaultRoot, model.selectedPath ) of
                ( Just root, Just path ) ->
                    request (PDelete path)
                        "delete"
                        [ ( "root", E.string root ), ( "path", E.string path ) ]
                        model

                _ ->
                    ( model, Cmd.none )

        ClickedRename ->
            case ( model.vaultRoot, model.selectedPath ) of
                ( Just root, Just path ) ->
                    if String.isEmpty (String.trim model.newName) then
                        ( model, Cmd.none )

                    else
                        let
                            dir =
                                PathUtil.parentDir path

                            newPath =
                                (if dir == "" then
                                    ""

                                 else
                                    dir ++ "/"
                                )
                                    ++ ensureScriptaExt model.newName
                        in
                        request (PRename path newPath)
                            "rename"
                            [ ( "root", E.string root ), ( "path", E.string path ), ( "newPath", E.string newPath ) ]
                            { model | newName = "" }

                _ ->
                    ( model, Cmd.none )

        ClickedExportHtml ->
            case model.parsedDoc of
                Just doc ->
                    request PExportSave
                        "export_save"
                        [ ( "defaultName", E.string (Export.defaultName model.selectedPath ".html") )
                        , ( "content", E.string (Export.html model.isLight model.contentWidth doc) )
                        ]
                        model

                Nothing ->
                    ( model, Cmd.none )

        ClickedExportLatex ->
            case model.parsedDoc of
                Just doc ->
                    request PExportSave
                        "export_save"
                        [ ( "defaultName", E.string (Export.defaultName model.selectedPath ".tex") )
                        , ( "content", E.string (Export.latex model.isLight model.contentWidth doc) )
                        ]
                        model

                Nothing ->
                    ( model, Cmd.none )

        ToggledFolder path ->
            let
                folders =
                    OpenFolders.toggle path model.openFolders
            in
            ( { model | openFolders = folders }
            , saveOpenFoldersCmd model.vaultRoot folders
            )

        GotOpenFolders value ->
            ( { model | openFolders = OpenFolders.fromValue value }, Cmd.none )

        SetSearchQuery q ->
            ( { model | searchQuery = q }, Cmd.none )

        GotOpenFile value ->
            case D.decodeValue (D.field "path" D.string) value of
                Ok abs ->
                    openExternalFile abs model

                Err _ ->
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
            let
                newSaveState =
                    case op of
                        PWriteFile _ ->
                            Tuple.first (SaveState.saveFailed model.saveState)

                        _ ->
                            model.saveState
            in
            ( { model | error = Just e, saveState = newSaveState }, Cmd.none )

        Ok result ->
            case op of
                PPickWorkspace ->
                    case D.decodeValue (D.nullable D.string) result of
                        Ok (Just root) ->
                            let
                                ( m1, c1 ) =
                                    request PListWorkspace "list_workspace" [ ( "root", E.string root ) ] { model | vaultRoot = Just root, openFolders = Set.empty }

                                ( m2, c2 ) =
                                    request PNoop "watch_workspace" [ ( "root", E.string root ) ] m1
                            in
                            ( m2, Cmd.batch [ c1, c2, FileOps.requestOpenFolders root ] )

                        Ok Nothing ->
                            -- user cancelled the folder picker
                            ( model, Cmd.none )

                        Err e ->
                            ( { model | error = Just (D.errorToString e) }, Cmd.none )

                PListWorkspace ->
                    case D.decodeValue (D.list Workspace.entryDecoder) result of
                        Ok entries ->
                            ( { model | tree = Workspace.toTree entries }, Cmd.none )

                        Err e ->
                            ( { model | error = Just (D.errorToString e) }, Cmd.none )

                PReadFile _ ->
                    case D.decodeValue (D.map2 Tuple.pair (D.field "content" D.string) (D.field "mtime" D.int)) result of
                        Ok ( content, mtime ) ->
                            let
                                parsed =
                                    if model.language == Just Language.Scripta then
                                        Just (Render.parse model.isLight model.contentWidth content)

                                    else
                                        Nothing
                            in
                            ( { model
                                | content = content
                                , loadedContent = content
                                , loadedMtime = mtime
                                , externalConflict = False
                                , parsedDoc = parsed
                              }
                            , Cmd.none
                            )

                        Err e ->
                            ( { model | error = Just (D.errorToString e) }, Cmd.none )

                PWriteFile _ ->
                    case D.decodeValue D.int result of
                        Ok mtime ->
                            update (GotSaveResult resp.requestId) { model | loadedMtime = mtime }

                        Err _ ->
                            update (GotSaveResult resp.requestId) model

                PCreateFile _ ->
                    relist model

                PCreateDir _ ->
                    relist model

                PRename _ _ ->
                    relist { model | selectedPath = Nothing, content = "", loadedContent = "", parsedDoc = Nothing }

                PDelete _ ->
                    relist { model | selectedPath = Nothing, content = "", loadedContent = "", parsedDoc = Nothing }

                PNoop ->
                    ( model, Cmd.none )

                PExportSave ->
                    -- File was written by the native save dialog; nothing to update.
                    ( model, Cmd.none )

                PLaunchFile ->
                    case D.decodeValue (D.nullable D.string) result of
                        Ok (Just abs) ->
                            openExternalFile abs model

                        _ ->
                            ( model, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ FileOps.fsResponse GotFsResponse
        , FileOps.fileChanged GotFileChanged
        , FileOps.openFile GotOpenFile
        , FileOps.gotOpenFolders GotOpenFolders
        ]


relist : Model -> ( Model, Cmd Msg )
relist model =
    case model.vaultRoot of
        Just root ->
            request PListWorkspace "list_workspace" [ ( "root", E.string root ) ] model

        Nothing ->
            ( model, Cmd.none )


ensureScriptaExt : String -> String
ensureScriptaExt name =
    if String.endsWith ".scripta" name then
        name

    else
        name ++ ".scripta"
