module Main exposing (main)

import AiConfig
import Browser
import Browser.Events
import Chat
import Dict
import Export
import FileOps
import Flags
import Json.Decode as D
import Json.Encode as E
import Language
import Nav
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


main : Program D.Value Model Msg
main =
    Browser.element
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = View.view
        }


init : D.Value -> ( Model, Cmd Msg )
init flagsValue =
    let
        flags =
            Flags.decode flagsValue
    in
    request PLaunchFile
        "take_launch_file"
        []
        { vaultRoot = Nothing
        , tree = []
        , selectedPath = Nothing
        , history = []
        , future = []
        , nextRequestId = 0
        , pending = Dict.empty
        , error = Nothing
        , content = ""
        , loadedContent = ""
        , loadedMtime = 0
        , externalConflict = False
        , parsedDoc = Nothing
        , imageSrc = Nothing
        , language = Nothing
        , isLight = flags.isLight
        , contentWidth = 500
        , saveState = SaveState.init
        , newName = ""
        , openFolders = Set.empty
        , searchQuery = ""
        , readerMode = flags.readerMode
        , fullParse = flags.fullParse
        , initialLastVault = flags.lastVault
        , aiConfig = flags.aiConfig
        , aiKeyInput = Dict.empty
        , showSettings = False
        , terminalVisible = flags.terminalVisible
        , terminalEverOpened = flags.terminalVisible
        , terminalTab = "shell1"
        , scratchContent = flags.scratchContent
        , chatMessages = []
        , chatInput = ""
        , chatPending = False
        , chatFileTitles = Dict.empty
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


{-| Open a folder as the vault: list + watch it, restore its remembered open
folders, and persist it as the last-used vault. Clears any open document.
-}
openVault : String -> Model -> ( Model, Cmd Msg )
openVault root model =
    let
        m0 =
            { model
                | vaultRoot = Just root
                , selectedPath = Nothing
                , history = []
                , future = []
                , content = ""
                , loadedContent = ""
                , parsedDoc = Nothing
                , openFolders = Set.empty
            }

        ( m1, c1 ) =
            request PListWorkspace "list_workspace" [ ( "root", E.string root ) ] m0

        ( m2, c2 ) =
            request PNoop "watch_workspace" [ ( "root", E.string root ) ] m1
    in
    ( m2, Cmd.batch [ c1, c2, FileOps.requestOpenFolders root, FileOps.saveLastVault root ] )


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

        ( m1, c1 ) =
            openVault parent model

        m2 =
            { m1 | selectedPath = Just name, language = Language.fromPath name }

        ( m3, c3 ) =
            request (PReadFile name) "read_file" [ ( "root", E.string parent ), ( "path", E.string name ) ] m2
    in
    ( m3, Cmd.batch [ c1, c3 ] )


{-| Open a vault-relative document path in-app, pushing the current document
onto the history stack (for Prev/Next).
-}
openDoc : String -> Model -> ( Model, Cmd Msg )
openDoc path model =
    let
        history =
            case model.selectedPath of
                Just current ->
                    current :: model.history

                Nothing ->
                    model.history
    in
    openDocNoPush path { model | history = history, future = [] }


{-| Open a vault-relative document path without touching history (used by Prev/Next). -}
openDocNoPush : String -> Model -> ( Model, Cmd Msg )
openDocNoPush path model =
    case model.vaultRoot of
        Just root ->
            if Language.fromPath path == Just Language.Image then
                request (PReadImage path)
                    "read_image"
                    [ ( "root", E.string root ), ( "path", E.string path ) ]
                    { model | selectedPath = Just path, language = Just Language.Image }

            else
                request (PReadFile path)
                    "read_file"
                    [ ( "root", E.string root ), ( "path", E.string path ) ]
                    { model | selectedPath = Just path, language = Language.fromPath path, imageSrc = Nothing }

        Nothing ->
            ( model, Cmd.none )


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
            openDoc path model

        NoOpFromRender ->
            ( model, Cmd.none )

        GotRenderMsg renderMsg ->
            case renderMsg of
                Render.ScrollTo id ->
                    ( model, FileOps.scrollAndHighlight id )

                Render.OpenUrl url ->
                    request POpenExternal "open_url" [ ( "url", E.string url ) ] model

                Render.OpenLocalFile target ->
                    case ( model.vaultRoot, model.selectedPath ) of
                        ( Just root, Just doc ) ->
                            request POpenExternal
                                "open_path"
                                [ ( "root", E.string root )
                                , ( "doc", E.string doc )
                                , ( "target", E.string target )
                                ]
                                model

                        _ ->
                            ( model, Cmd.none )

                Render.NavigateToFile target ->
                    case ( model.vaultRoot, model.selectedPath ) of
                        ( Just root, Just doc ) ->
                            request PResolveDocLink
                                "resolve_doc_link"
                                [ ( "root", E.string root )
                                , ( "doc", E.string doc )
                                , ( "target", E.string target )
                                ]
                                model

                        _ ->
                            ( model, Cmd.none )

                _ ->
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
                        if model.fullParse then
                            Just (Render.parse model.isLight model.contentWidth newText)

                        else
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
                        name =
                            String.trim model.newName
                    in
                    if String.isEmpty name then
                        ( model, Cmd.none )

                    else
                        case PathUtil.kbaseRoot root of
                            Just kroot ->
                                let
                                    path =
                                        "Inbox/" ++ name
                                in
                                request (PCreateFile path)
                                    "create_file"
                                    [ ( "root", E.string kroot ), ( "path", E.string path ), ( "content", E.string "" ) ]
                                    { model | newName = "" }

                            Nothing ->
                                let
                                    path =
                                        PathUtil.siblingPath model.selectedPath name
                                in
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
                                    ++ String.trim model.newName
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

        ClickedExportPdf ->
            case model.parsedDoc of
                Just doc ->
                    request PExportPdf
                        "export_pdf"
                        [ ( "defaultName", E.string (Export.defaultName model.selectedPath ".pdf") )
                        , ( "tex", E.string (Export.latex model.isLight model.contentWidth doc) )
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

        ToggledReaderMode ->
            let
                rm =
                    not model.readerMode
            in
            ( { model | readerMode = rm }, FileOps.saveReaderMode rm )

        ToggledTheme ->
            let
                light =
                    not model.isLight
            in
            ( { model | isLight = light }, FileOps.saveIsLight light )

        ToggledTerminal ->
            let
                visible =
                    not model.terminalVisible
            in
            ( { model | terminalVisible = visible, terminalEverOpened = model.terminalEverOpened || visible }
            , FileOps.saveTerminalVisible visible
            )

        SelectTerminalTab tab ->
            ( { model | terminalTab = tab }, Cmd.none )

        CopyReply text ->
            ( model, FileOps.copyToClipboard text )

        ChatFileTitleInput n s ->
            ( { model | chatFileTitles = Dict.insert n s model.chatFileTitles }, Cmd.none )

        ClickedChatFile n content ->
            case model.vaultRoot of
                Just root ->
                    let
                        title =
                            String.trim (Dict.get n model.chatFileTitles |> Maybe.withDefault "")
                    in
                    if String.isEmpty title then
                        ( model, Cmd.none )

                    else
                        let
                            name =
                                PathUtil.withDefaultExtension "md" title

                            cleared =
                                { model | chatFileTitles = Dict.remove n model.chatFileTitles }
                        in
                        case PathUtil.kbaseRoot root of
                            Just kroot ->
                                let
                                    path =
                                        "Inbox/" ++ name
                                in
                                request (PCreateFile path)
                                    "create_file"
                                    [ ( "root", E.string kroot ), ( "path", E.string path ), ( "content", E.string content ) ]
                                    cleared

                            Nothing ->
                                let
                                    path =
                                        PathUtil.siblingPath model.selectedPath name
                                in
                                request (PCreateFile path)
                                    "create_file"
                                    [ ( "root", E.string root ), ( "path", E.string path ), ( "content", E.string content ) ]
                                    cleared

                Nothing ->
                    ( model, Cmd.none )

        ClickedReload ->
            relist model

        ToggledSettings ->
            ( { model | showSettings = not model.showSettings }, Cmd.none )

        SetActiveProvider provider ->
            let
                cfg =
                    AiConfig.setActiveProvider provider model.aiConfig
            in
            ( { model | aiConfig = cfg }, FileOps.saveAiConfig (AiConfig.encode cfg) )

        SetProviderModel provider modelName ->
            let
                cfg =
                    AiConfig.setModel provider modelName model.aiConfig
            in
            ( { model | aiConfig = cfg }, FileOps.saveAiConfig (AiConfig.encode cfg) )

        SetAgentCommand cmd ->
            let
                cfg =
                    AiConfig.setAgentCommand cmd model.aiConfig
            in
            ( { model | aiConfig = cfg }, FileOps.saveAiConfig (AiConfig.encode cfg) )

        AiKeyInput provider keyText ->
            ( { model | aiKeyInput = Dict.insert provider keyText model.aiKeyInput }, Cmd.none )

        SubmitApiKey provider ->
            let
                key =
                    Dict.get provider model.aiKeyInput |> Maybe.withDefault ""
            in
            if String.isEmpty (String.trim key) then
                ( model, Cmd.none )

            else
                request (PSetApiKey provider (AiConfig.last4 key))
                    "set_api_key"
                    [ ( "provider", E.string provider ), ( "key", E.string key ) ]
                    model

        DeleteApiKey provider ->
            request (PDeleteApiKey provider)
                "delete_api_key"
                [ ( "provider", E.string provider ) ]
                model

        ClickedPrev ->
            case Nav.prev model.selectedPath model.history model.future of
                Just step ->
                    openDocNoPush step.target { model | history = step.history, future = step.future }

                Nothing ->
                    ( model, Cmd.none )

        ClickedNext ->
            case Nav.next model.selectedPath model.history model.future of
                Just step ->
                    openDocNoPush step.target { model | history = step.history, future = step.future }

                Nothing ->
                    ( model, Cmd.none )

        ToggledParseMode ->
            let
                fp =
                    not model.fullParse

                -- Switching to Full: reparse the current content immediately so the
                -- preview is consistent without waiting for the next edit.
                reparsed =
                    if fp && model.language == Just Language.Scripta then
                        Just (Render.parse model.isLight model.contentWidth model.content)

                    else
                        model.parsedDoc
            in
            ( { model | fullParse = fp, parsedDoc = reparsed }, FileOps.saveFullParse fp )

        GotOpenFile value ->
            case D.decodeValue (D.field "path" D.string) value of
                Ok abs ->
                    openExternalFile abs model

                Err _ ->
                    ( model, Cmd.none )

        ChatInput t ->
            ( { model | chatInput = t }, Cmd.none )

        SendChat ->
            let
                text =
                    String.trim model.chatInput
            in
            if model.chatPending || String.isEmpty text then
                ( model, Cmd.none )

            else
                let
                    provider =
                        AiConfig.activeProvider model.aiConfig

                    msgs =
                        model.chatMessages ++ [ Chat.user text ]
                in
                request PChatReply
                    "ai_chat"
                    [ ( "provider", E.string provider )
                    , ( "model", E.string (AiConfig.modelFor provider model.aiConfig) )
                    , ( "messages", E.list Chat.encode msgs )
                    ]
                    { model | chatMessages = msgs, chatInput = "", chatPending = True }

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
            case op of
                PChatReply ->
                    ( { model | chatMessages = model.chatMessages ++ [ Chat.assistant ("\u{26A0} " ++ e) ], chatPending = False }, Cmd.none )

                _ ->
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
                            openVault root model

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
                                , imageSrc = Nothing
                              }
                            , Cmd.none
                            )

                        Err e ->
                            ( { model | error = Just (D.errorToString e) }, Cmd.none )

                PReadImage _ ->
                    case D.decodeValue D.string result of
                        Ok url ->
                            ( { model | imageSrc = Just url, content = "", loadedContent = "", parsedDoc = Nothing }
                            , Cmd.none
                            )

                        Err e ->
                            ( { model | error = Just (D.errorToString e) }, Cmd.none )

                PResolveDocLink ->
                    case D.decodeValue D.string result of
                        Ok path ->
                            openDoc path model

                        Err e ->
                            ( { model | error = Just (D.errorToString e) }, Cmd.none )

                PWriteFile _ ->
                    case D.decodeValue D.int result of
                        Ok mtime ->
                            update (GotSaveResult resp.requestId) { model | loadedMtime = mtime }

                        Err _ ->
                            update (GotSaveResult resp.requestId) model

                PCreateFile path ->
                    let
                        expanded =
                            { model
                                | openFolders =
                                    List.foldl Set.insert model.openFolders (PathUtil.ancestorDirs path)
                            }

                        ( opened, openCmd ) =
                            openDoc path expanded

                        ( relisted, relistCmd ) =
                            relist opened
                    in
                    ( relisted
                    , Cmd.batch
                        [ openCmd
                        , relistCmd
                        , saveOpenFoldersCmd relisted.vaultRoot relisted.openFolders
                        ]
                    )

                PCreateDir _ ->
                    relist model

                PRename _ _ ->
                    relist { model | selectedPath = Nothing, content = "", loadedContent = "", parsedDoc = Nothing }

                PDelete _ ->
                    relist { model | selectedPath = Nothing, content = "", loadedContent = "", parsedDoc = Nothing }

                PNoop ->
                    ( model, Cmd.none )

                POpenExternal ->
                    ( model, Cmd.none )

                PExportSave ->
                    -- File was written by the native save dialog; nothing to update.
                    ( model, Cmd.none )

                PExportPdf ->
                    -- PDF written by the native save dialog; errors surface via the Err arm.
                    ( model, Cmd.none )

                PLaunchFile ->
                    case D.decodeValue (D.nullable D.string) result of
                        Ok (Just abs) ->
                            openExternalFile abs model

                        _ ->
                            case model.initialLastVault of
                                Just vault ->
                                    openVault vault model

                                Nothing ->
                                    ( model, Cmd.none )

                PSetApiKey provider hint ->
                    let
                        cfg =
                            AiConfig.setHint provider hint model.aiConfig
                    in
                    ( { model | aiConfig = cfg, aiKeyInput = Dict.remove provider model.aiKeyInput }
                    , FileOps.saveAiConfig (AiConfig.encode cfg)
                    )

                PDeleteApiKey provider ->
                    let
                        cfg =
                            AiConfig.clearHint provider model.aiConfig
                    in
                    ( { model | aiConfig = cfg }, FileOps.saveAiConfig (AiConfig.encode cfg) )

                PChatReply ->
                    case D.decodeValue D.string result of
                        Ok reply ->
                            ( { model | chatMessages = model.chatMessages ++ [ Chat.assistant reply ], chatPending = False }, Cmd.none )

                        Err e ->
                            ( { model | chatMessages = model.chatMessages ++ [ Chat.assistant ("\u{26A0} " ++ D.errorToString e) ], chatPending = False }, Cmd.none )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch
        [ FileOps.fsResponse GotFsResponse
        , FileOps.fileChanged GotFileChanged
        , FileOps.openFile GotOpenFile
        , FileOps.gotOpenFolders GotOpenFolders
        , Browser.Events.onKeyDown navKeyDecoder
        ]


{-| Cmd+[ -> Prev, Cmd+] -> Next. Fails (no message) for anything else, so it
does not interfere with normal typing. The update handlers no-op when the
relevant nav stack is empty.
-}
navKeyDecoder : D.Decoder Msg
navKeyDecoder =
    D.map2 Tuple.pair (D.field "metaKey" D.bool) (D.field "key" D.string)
        |> D.andThen
            (\( meta, key ) ->
                if meta && key == "[" then
                    D.succeed ClickedPrev

                else if meta && key == "]" then
                    D.succeed ClickedNext

                else
                    D.fail "not a nav shortcut"
            )


relist : Model -> ( Model, Cmd Msg )
relist model =
    case model.vaultRoot of
        Just root ->
            request PListWorkspace "list_workspace" [ ( "root", E.string root ) ] model

        Nothing ->
            ( model, Cmd.none )
