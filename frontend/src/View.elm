module View exposing (chatMessageView, imagePane, plainTextPreview, rightTabs, themeName, view)

import AiConfig
import Chat
import Dict
import Editor
import Html exposing (Html, button, div, li, span, text, ul)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick, onInput)
import Html.Keyed
import Json.Decode as D
import Language
import MarkdownRender
import PathUtil
import Render
import SaveState
import Set exposing (Set)
import Svg
import Svg.Attributes as SA
import Types exposing (Model, Msg(..))
import Workspace exposing (Node(..))


treeColumn : Model -> Html Msg
treeColumn model =
    div [ style "width" "calc(260px + 2mm)", style "border-right" "1px solid var(--border)", style "padding" "8px", style "overflow" "auto", style "background" "var(--panel-bg)" ]
        (div [ style "display" "flex", style "gap" "4px" ]
            [ button [ onClick ClickedOpenVault ] [ text "Open Vault" ]
            , button [ onClick ClickedChangeVault ] [ text "Change Vault" ]
            , button
                [ onClick ClickedReload
                , Html.Attributes.disabled (model.vaultRoot == Nothing)
                ]
                [ text "Reload" ]
            ]
            :: [ searchBox model
               , fileTree model
               , div [ style "margin-top" "4px", style "display" "flex", style "gap" "2mm" ]
                    [ button [ onClick ClickedExportHtml ] [ text "Export HTML" ]
                    , button [ onClick ClickedExportLatex ] [ text "Export LaTeX" ]
                    , button [ onClick ClickedExportPdf ] [ text "Export PDF" ]
                    ]
               ]
        )


{-| The `data-theme` attribute value for the current theme. Drives the CSS
custom-property palette in index.html (`:root` light vs `[data-theme="dark"]`).
-}
themeName : Bool -> String
themeName isLight =
    if isLight then
        "light"

    else
        "dark"


view : Model -> Html Msg
view model =
    let
        threePaneRow =
            div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
                [ treeColumn model
                , Html.node "codemirror-editor"
                    [ Html.Attributes.attribute "text" model.loadedContent
                    , Html.Attributes.attribute "fill-parent" ""
                    , Html.Events.on "text-change" (D.map EditorChanged Editor.textChangeDecoder)
                    , style "flex" "1"
                    , style "border-right" "1px solid var(--border)"
                    ]
                    []
                , div
                    [ Html.Attributes.id Editor.renderedTextId
                    , style "flex" "1"
                    , style "padding" "16px"
                    , style "overflow" "auto"
                    ]
                    (previewBody model)
                ]

        toolbar =
            div
                [ style "display" "flex"
                , style "align-items" "center"
                , style "gap" "8px"
                , style "padding" "6px 8px"
                , style "border-bottom" "1px solid var(--border)"
                , style "flex-wrap" "wrap"
                ]
                [ button
                    [ onClick ClickedPrev
                    , Html.Attributes.disabled (List.isEmpty model.history)
                    ]
                    [ text "\u{2190} Prev" ]
                , button
                    [ onClick ClickedNext
                    , Html.Attributes.disabled (List.isEmpty model.future)
                    ]
                    [ text "Next \u{2192}" ]
                , button [ onClick ToggledReaderMode ]
                    [ text
                        (if model.readerMode then
                            "Exit Reader"

                         else
                            "Reader"
                        )
                    ]
                , button [ onClick ToggledParseMode ]
                    [ text
                        (if model.fullParse then
                            "Parse: Full"

                         else
                            "Parse: Incremental"
                        )
                    ]
                , button [ onClick ToggledTheme ]
                    [ text
                        (if model.isLight then
                            "Dark"

                         else
                            "Light"
                        )
                    ]
                , button [ onClick ToggledSettings ] [ text "\u{2699} Settings" ]
                , button [ onClick ToggledTerminal ] [ text "\u{2318} Terminal" ]
                , Html.input
                    [ Html.Attributes.placeholder "new-file-name"
                    , Html.Attributes.value model.newName
                    , onInput SetNewName
                    , style "width" "150px"
                    , Html.Attributes.attribute "autocapitalize" "off"
                    , Html.Attributes.attribute "autocorrect" "off"
                    , Html.Attributes.spellcheck False
                    ]
                    []
                , button [ onClick ClickedNewFile ] [ text "New" ]
                , button [ onClick ClickedRename ] [ text "Rename" ]
                , button [ onClick ClickedDeleteSelected ] [ text "Delete" ]
                , div [ style "font-size" "12px", style "color" "var(--muted)" ]
                    [ text (saveLabel model.saveState.saveStatus) ]
                ]

        readerView =
            let
                ( bodyContent, tocCols ) =
                    case ( model.language, model.parsedDoc ) of
                        ( Just Language.Scripta, Just doc ) ->
                            let
                                out =
                                    Render.renderDocument model.isLight model.contentWidth doc

                                bodyHtml =
                                    (out.title :: out.body)
                                        |> List.map (Html.map (\_ -> NoOpFromRender))

                                tocCol =
                                    if List.isEmpty out.toc then
                                        []

                                    else
                                        [ div
                                            [ style "width" "220px"
                                            , style "flex" "0 0 auto"
                                            , style "border-left" "1px solid var(--border)"
                                            , style "padding" "16px"
                                            , style "overflow" "auto"
                                            ]
                                            (List.map (Html.map GotRenderMsg) out.toc)
                                        ]
                            in
                            ( bodyHtml, tocCol )

                        ( Just Language.Markdown, _ ) ->
                            let
                                out =
                                    MarkdownRender.render model.content

                                bodyHtml =
                                    out.body
                                        |> List.map (Html.map GotRenderMsg)

                                tocCol =
                                    if List.isEmpty out.toc then
                                        []

                                    else
                                        [ div
                                            [ style "width" "220px"
                                            , style "flex" "0 0 auto"
                                            , style "border-left" "1px solid var(--border)"
                                            , style "padding" "16px"
                                            , style "overflow" "auto"
                                            ]
                                            (List.map (Html.map GotRenderMsg) out.toc)
                                        ]
                            in
                            ( bodyHtml, tocCol )

                        _ ->
                            ( previewBody model, [] )
            in
            div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
                ([ treeColumn model
                 , div
                    [ style "flex" "1"
                    , style "padding" "16px"
                    , style "overflow" "auto"
                    ]
                    [ div
                        [ Html.Attributes.id Editor.renderedTextId
                        , style "max-width" "5.5in"
                        ]
                        bodyContent
                    ]
                 ]
                    ++ tocCols
                )

        body =
            if model.language == Just Language.Image then
                imageView model

            else if model.readerMode then
                readerView

            else
                threePaneRow
    in
    div
        [ Html.Attributes.attribute "data-theme" (themeName model.isLight)
        , style "display" "flex"
        , style "flex-direction" "column"
        , style "height" "100vh"
        , style "font-family" "system-ui"
        , style "background" "var(--app-bg)"
        , style "color" "var(--app-fg)"
        ]
        (conflictBanner model
            ++ errorBanner model
            ++ [ toolbar, body ]
            ++ (if model.terminalEverOpened then
                    [ terminalDock model ]

                else
                    []
               )
            ++ (if model.showSettings then
                    [ settingsOverlay model ]

                else
                    []
               )
        )


conflictBanner : Model -> List (Html Msg)
conflictBanner model =
    if model.externalConflict then
        [ div [ style "background" "var(--banner-bg)", style "padding" "8px", style "border-bottom" "1px solid var(--banner-border)" ]
            [ text "This file changed on disk. "
            , button [ onClick ClickedReloadExternal ] [ text "Reload" ]
            , button [ onClick ClickedKeepMine ] [ text "Keep mine" ]
            ]
        ]

    else
        []


saveLabel : SaveState.SaveStatus -> String
saveLabel status =
    case status of
        SaveState.Saved ->
            "Saved"

        SaveState.Unsaved ->
            "Unsaved\u{2026}"

        SaveState.Saving ->
            "Saving\u{2026}"


errorBanner : Model -> List (Html Msg)
errorBanner model =
    case model.error of
        Just e ->
            [ div
                [ style "background" "var(--error-bg)"
                , style "color" "var(--error-fg)"
                , style "padding" "8px"
                , style "border-bottom" "1px solid var(--error-border)"
                , style "font-family" "ui-monospace, monospace"
                , style "font-size" "12px"
                , style "white-space" "pre-wrap"
                , style "max-height" "35vh"
                , style "overflow" "auto"
                , style "cursor" "pointer"
                , onClick DismissError
                ]
                [ text (e ++ "\n\n(click to dismiss)") ]
            ]

        Nothing ->
            []


{-| A small folder glyph: filled with the current text color when closed, outline-only when open.
-}
folderIcon : Bool -> Html msg
folderIcon isOpen =
    Svg.svg
        [ SA.width "13"
        , SA.height "13"
        , SA.viewBox "0 0 16 16"
        , SA.style "vertical-align: middle; margin-right: 5px;"
        ]
        [ Svg.path
            [ SA.d "M1.5 4 H6 L7.5 5.5 H14.5 V13 H1.5 Z"
            , SA.stroke "currentColor"
            , SA.strokeWidth "1"
            , SA.fill
                (if isOpen then
                    "none"

                 else
                    "currentColor"
                )
            ]
            []
        ]


searchBox : Model -> Html Msg
searchBox model =
    Html.input
        [ Html.Attributes.placeholder "Search documents\u{2026}"
        , Html.Attributes.value model.searchQuery
        , onInput SetSearchQuery
        , style "width" "100%"
        , style "box-sizing" "border-box"
        , style "margin-bottom" "8px"
        , style "margin-top" "8px"
        ]
        []


{-| Tree highlight inputs: the open document (pale-blue pill) and the folder a
new document will land in (lighter-blue fill). `currentFolder` is "" at the
vault root, which matches no folder node.
-}
type alias Highlights =
    { selectedDoc : Maybe String
    , currentFolder : String
    }


{-| The file tree, filtered to matching documents while a search is active
(folders containing matches are force-expanded so matches are visible).
-}
fileTree : Model -> Html Msg
fileTree model =
    let
        q =
            String.trim model.searchQuery

        highlights =
            { selectedDoc = model.selectedPath
            , currentFolder =
                model.selectedPath
                    |> Maybe.map PathUtil.parentDir
                    |> Maybe.withDefault ""
            }
    in
    if String.isEmpty q then
        treeView False highlights model.openFolders model.tree

    else
        treeView True highlights model.openFolders (Workspace.filter q model.tree)


treeView : Bool -> Highlights -> Set String -> List Node -> Html Msg
treeView forceOpen highlights openFolders nodes =
    ul
        [ style "list-style" "none"
        , style "padding-left" "12px"
        , style "font-size" "13px"
        ]
        (List.map (nodeView forceOpen highlights openFolders) nodes)


nodeView : Bool -> Highlights -> Set String -> Node -> Html Msg
nodeView forceOpen highlights openFolders node =
    case node of
        FileNode r ->
            li
                ([ onClick (ClickedTreeNode r.path)
                 , style "cursor" "pointer"
                 , style "margin-bottom" "4px"
                 , style "display" "flex"
                 , style "align-items" "flex-start"
                 ]
                    ++ (if Just r.path == highlights.selectedDoc then
                            [ style "background-color" "var(--tree-selected-bg)"
                            , style "border-radius" "3px"
                            , style "padding" "0 4px"
                            ]

                        else
                            []
                       )
                )
                [ span [ style "flex" "0 0 auto", style "margin-right" "5px" ] [ text "-" ]
                , span [ style "flex" "1 1 auto" ] [ text r.name ]
                ]

        FolderNode r ->
            let
                isOpen =
                    forceOpen || Set.member r.path openFolders
            in
            li []
                (div
                    ([ onClick (ToggledFolder r.path)
                     , style "cursor" "pointer"
                     , style "margin-bottom" "4px"
                     , style "display" "flex"
                     , style "align-items" "flex-start"
                     ]
                        ++ (if r.path == highlights.currentFolder then
                                [ style "background-color" "var(--tree-folder-bg)"
                                , style "border-radius" "3px"
                                , style "padding" "0 4px"
                                ]

                            else
                                []
                           )
                    )
                    [ span [ style "flex" "0 0 auto", style "margin-right" "5px" ] [ folderIcon isOpen ]
                    , span [ style "flex" "1 1 auto" ] [ text r.name ]
                    ]
                    :: (if isOpen then
                            [ treeView forceOpen highlights openFolders r.children ]

                        else
                            []
                       )
                )


{-| Preview for a non-renderable text document: show its source verbatim. -}
plainTextPreview : String -> Html msg
plainTextPreview content =
    Html.pre
        [ style "white-space" "pre-wrap"
        , style "font-family" "ui-monospace, monospace"
        , style "margin" "0"
        ]
        [ Html.text content ]


{-| The image element for an opened image document (empty src until loaded). -}
imagePane : Maybe String -> Html msg
imagePane imageSrc =
    Html.img
        [ Html.Attributes.src (Maybe.withDefault "" imageSrc)
        , style "max-width" "100%"
        , style "height" "auto"
        ]
        []


{-| Full-width view for image documents: tree column + image pane. -}
imageView : Model -> Html Msg
imageView model =
    div [ style "display" "flex", style "flex" "1", style "min-height" "0" ]
        [ treeColumn model
        , div [ style "flex" "1", style "padding" "16px", style "overflow" "auto" ]
            [ imagePane model.imageSrc ]
        ]


previewBody : Model -> List (Html Msg)
previewBody model =
    case ( model.language, model.parsedDoc ) of
        ( Just Language.Scripta, Just doc ) ->
            let
                out =
                    Render.renderDocument model.isLight model.contentWidth doc
            in
            (out.title :: out.body)
                |> List.map (Html.map (\_ -> NoOpFromRender))

        ( Just Language.Markdown, _ ) ->
            MarkdownRender.render model.content
                |> .body
                |> List.map (Html.map GotRenderMsg)

        ( Just Language.PlainText, _ ) ->
            [ plainTextPreview model.content ]

        ( Just lang, _ ) ->
            [ Html.text (Language.label lang ++ " rendering is not yet supported.") ]

        ( Nothing, _ ) ->
            [ Html.text "Open a document." ]


settingsOverlay : Model -> Html Msg
settingsOverlay model =
    div
        [ style "position" "fixed"
        , style "inset" "0"
        , style "background" "rgba(0,0,0,0.4)"
        , style "display" "flex"
        , style "align-items" "flex-start"
        , style "justify-content" "center"
        , style "padding" "40px"
        , style "overflow" "auto"
        , style "z-index" "100"
        ]
        [ div
            [ style "background" "var(--app-bg)"
            , style "color" "var(--app-fg)"
            , style "border" "1px solid var(--border)"
            , style "border-radius" "8px"
            , style "padding" "20px"
            , style "width" "560px"
            , style "max-width" "100%"
            ]
            [ div [ style "display" "flex", style "justify-content" "space-between", style "align-items" "center", style "margin-bottom" "12px" ]
                [ Html.h2 [ style "margin" "0", style "font-size" "18px" ] [ text "AI Providers" ]
                , button [ onClick ToggledSettings ] [ text "Close" ]
                ]
            , div [ style "color" "var(--muted)", style "font-size" "12px", style "margin-bottom" "16px" ]
                [ text "Keys are stored in your macOS Keychain. Only the last 4 characters are shown back." ]
            , activeProviderRow model
            , div [ style "height" "12px" ] []
            , div [] (List.map (providerRow model) AiConfig.providers)
            ]
        ]


terminalDock : Model -> Html Msg
terminalDock model =
    div
        [ style "display"
            (if model.terminalVisible then
                "flex"

             else
                "none"
            )
        , style "flex-direction" "column"
        , style "height" "var(--terminal-height)"
        , style "max-height" "calc(100vh - 120px)"
        , style "border-top" "1px solid var(--border)"
        , style "background" "var(--app-bg)"
        , style "min-height" "0"
        ]
        [ div
            [ Html.Attributes.id "terminal-resize-handle"
            , style "height" "6px"
            , style "cursor" "row-resize"
            , style "background" "var(--border)"
            , style "flex" "0 0 auto"
            ]
            []
        , div
            [ style "display" "flex"
            , style "flex-direction" "row"
            , style "flex" "1"
            , style "min-height" "0"
            ]
            [ div
                [ style "width" "var(--terminal-split, 50%)"
                , style "flex" "0 0 auto"
                , style "min-width" "0"
                , style "overflow" "hidden"
                ]
                [ aiChatView model ]
            , div
                [ Html.Attributes.id "terminal-split-handle"
                , style "flex" "0 0 6px"
                , style "cursor" "col-resize"
                , style "background" "var(--border)"
                ]
                []
            , div
                [ style "display" "flex"
                , style "flex-direction" "column"
                , style "flex" "1"
                , style "min-width" "0"
                , style "min-height" "0"
                ]
                [ terminalTabBar model
                , Html.Keyed.node "div"
                    [ style "flex" "1", style "min-height" "0", style "position" "relative" ]
                    [ ( "shell1", terminalTabContent (model.terminalTab == "shell1") (terminalPane "shell1" model) )
                    , ( "shell2", terminalTabContent (model.terminalTab == "shell2") (terminalPane "shell2" model) )
                    , ( "scratch", terminalTabContent (model.terminalTab == "scratch") (scratchPane model) )
                    ]
                ]
            ]
        ]


rightTabs : List ( String, String )
rightTabs =
    [ ( "shell1", "Shell 1" ), ( "shell2", "Shell 2" ), ( "scratch", "Scratch" ) ]


terminalTabBar : Model -> Html Msg
terminalTabBar model =
    div
        [ style "display" "flex"
        , style "gap" "4px"
        , style "padding" "4px 8px"
        , style "flex" "0 0 auto"
        , style "border-bottom" "1px solid var(--border)"
        ]
        (List.map (terminalTabButton model) rightTabs)


terminalTabButton : Model -> ( String, String ) -> Html Msg
terminalTabButton model ( tabId, label ) =
    button
        [ onClick (SelectTerminalTab tabId)
        , style "font-weight"
            (if model.terminalTab == tabId then
                "700"

             else
                "400"
            )
        ]
        [ text label ]


terminalTabContent : Bool -> Html Msg -> Html Msg
terminalTabContent active content =
    div
        [ style "position" "absolute"
        , style "inset" "0"
        , style "display"
            (if active then
                "block"

             else
                "none"
            )
        ]
        [ content ]


aiChatView : Model -> Html Msg
aiChatView model =
    let
        provider =
            AiConfig.activeProvider model.aiConfig

        hasKey =
            AiConfig.keyHint provider model.aiConfig /= Nothing
    in
    div [ style "display" "flex", style "flex-direction" "column", style "height" "100%", style "min-height" "0" ]
        [ div [ style "flex" "1", style "overflow" "auto", style "padding" "12px" ]
            (List.map chatMessageView model.chatMessages
                ++ (if model.chatPending then
                        [ div [ style "color" "var(--muted)", style "font-style" "italic", style "padding" "4px 0" ] [ text "thinking\u{2026}" ] ]

                    else
                        []
                   )
            )
        , if hasKey then
            chatInputRow model

          else
            div [ style "padding" "12px", style "color" "var(--muted)", style "border-top" "1px solid var(--border)" ]
                [ text ("Set an API key for " ++ AiConfig.providerLabel provider ++ " in \u{2699} Settings to use chat.") ]
        ]


chatMessageView : Chat.ChatMessage -> Html Msg
chatMessageView m =
    let
        isUser =
            m.role == "user"

        body =
            if isUser then
                [ Html.pre [ style "white-space" "pre-wrap", style "margin" "0", style "font-family" "inherit" ] [ text m.content ] ]

            else
                MarkdownRender.render m.content |> .body |> List.map (Html.map (\_ -> NoOpFromRender))
    in
    div
        [ style "margin-bottom" "12px"
        , style "padding" "8px 10px"
        , style "border-radius" "6px"
        , style "background"
            (if isUser then
                "var(--tree-selected-bg)"

             else
                "var(--panel-bg)"
            )
        ]
        (div
            [ style "display" "flex"
            , style "align-items" "center"
            , style "gap" "8px"
            , style "font-size" "11px"
            , style "font-weight" "700"
            , style "color" "var(--muted)"
            , style "margin-bottom" "4px"
            ]
            (text
                (if isUser then
                    "You"

                 else
                    "Assistant"
                )
                :: (if isUser then
                        []

                    else
                        [ button
                            [ onClick (CopyReply m.content)
                            , style "font-size" "10px"
                            , style "font-weight" "400"
                            , style "padding" "0 6px"
                            ]
                            [ text "Copy" ]
                        ]
                   )
            )
            :: body
        )


chatInputRow : Model -> Html Msg
chatInputRow model =
    div [ style "display" "flex", style "gap" "8px", style "padding" "8px", style "border-top" "1px solid var(--border)", style "align-items" "flex-end" ]
        [ Html.textarea
            [ Html.Attributes.placeholder "Message the AI\u{2026}"
            , Html.Attributes.value model.chatInput
            , onInput ChatInput
            , Html.Events.preventDefaultOn "keydown" chatKeydownDecoder
            , Html.Attributes.rows 3
            , style "flex" "1"
            , style "resize" "vertical"
            , style "font" "inherit"
            , style "min-height" "2.5em"
            ]
            []
        , button
            [ onClick SendChat
            , Html.Attributes.disabled (model.chatPending || String.isEmpty (String.trim model.chatInput))
            ]
            [ text "Send" ]
        ]


chatKeydownDecoder : D.Decoder ( Msg, Bool )
chatKeydownDecoder =
    D.map2 Tuple.pair (D.field "key" D.string) (D.field "shiftKey" D.bool)
        |> D.andThen
            (\( key, shift ) ->
                if key == "Enter" && not shift then
                    -- send, and preventDefault so no newline is inserted
                    D.succeed ( SendChat, True )

                else
                    -- Shift+Enter (and everything else) falls through to the textarea
                    D.fail "not plain Enter"
            )


terminalPane : String -> Model -> Html Msg
terminalPane termId model =
    Html.node "terminal-pane"
        [ Html.Attributes.attribute "term-id" termId
        , Html.Attributes.attribute "cwd" (Maybe.withDefault "" model.vaultRoot)
        , style "display" "block"
        , style "width" "100%"
        , style "height" "100%"
        ]
        []


scratchPane : Model -> Html Msg
scratchPane model =
    Html.node "codemirror-editor"
        [ Html.Attributes.id "scratch-editor"
        , Html.Attributes.attribute "text" model.scratchContent
        , Html.Attributes.attribute "fill-parent" ""
        , style "display" "block"
        , style "width" "100%"
        , style "height" "100%"
        ]
        []


activeProviderRow : Model -> Html Msg
activeProviderRow model =
    div [ style "display" "flex", style "align-items" "center", style "gap" "8px", style "margin-bottom" "8px" ]
        [ Html.label [ style "font-weight" "600", style "font-size" "13px" ] [ text "Active provider:" ]
        , Html.select [ onInput SetActiveProvider ]
            (List.map
                (\p ->
                    Html.option
                        [ Html.Attributes.value p, Html.Attributes.selected (p == AiConfig.activeProvider model.aiConfig) ]
                        [ text (AiConfig.providerLabel p) ]
                )
                AiConfig.providers
            )
        ]


providerRow : Model -> String -> Html Msg
providerRow model provider =
    let
        keyText =
            Dict.get provider model.aiKeyInput |> Maybe.withDefault ""
    in
    div
        [ style "border-top" "1px solid var(--border)"
        , style "padding" "12px 0"
        ]
        [ div [ style "display" "flex", style "align-items" "center", style "gap" "8px" ]
            [ div [ style "font-weight" "600", style "width" "90px" ] [ text (AiConfig.providerLabel provider) ]
            , Html.select [ onInput (SetProviderModel provider) ]
                (List.map
                    (\m ->
                        Html.option
                            [ Html.Attributes.value m, Html.Attributes.selected (m == AiConfig.modelFor provider model.aiConfig) ]
                            [ text m ]
                    )
                    (AiConfig.modelsFor provider)
                )
            ]
        , div [ style "display" "flex", style "align-items" "center", style "gap" "8px", style "margin-top" "8px" ]
            [ Html.input
                [ Html.Attributes.type_ "password"
                , Html.Attributes.placeholder "Paste your API key"
                , Html.Attributes.value keyText
                , onInput (AiKeyInput provider)
                , style "flex" "1"
                ]
                []
            , button [ onClick (SubmitApiKey provider) ] [ text "Set" ]
            , case AiConfig.keyHint provider model.aiConfig of
                Just hint ->
                    span [ style "display" "flex", style "align-items" "center", style "gap" "8px" ]
                        [ span [ style "color" "var(--muted)", style "font-family" "ui-monospace, monospace", style "font-size" "12px" ]
                            [ text ("key: \u{2022}\u{2022}\u{2022}\u{2022}" ++ hint) ]
                        , button [ onClick (DeleteApiKey provider) ] [ text "Delete" ]
                        ]

                Nothing ->
                    span [ style "color" "var(--muted)", style "font-size" "12px" ] [ text "no key" ]
            ]
        ]
