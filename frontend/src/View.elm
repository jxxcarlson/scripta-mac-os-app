module View exposing (imagePane, plainTextPreview, themeName, view)

import Editor
import Html exposing (Html, button, div, li, span, text, ul)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick, onInput)
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
        (button [ onClick ClickedOpenVault ] [ text "Open Vault" ]
            :: [ searchBox model
               , fileTree model
               , div [ style "font-size" "12px", style "color" "var(--muted)", style "margin-top" "6px" ]
                    [ text (saveLabel model.saveState.saveStatus) ]
               , div [ style "margin-top" "8px", style "margin-bottom" "2mm", style "display" "flex", style "align-items" "center", style "gap" "2mm" ]
                    [ Html.input
                        [ Html.Attributes.placeholder "new-file-name"
                        , Html.Attributes.value model.newName
                        , onInput SetNewName
                        , style "width" "150px"

                        -- Filenames are typed verbatim; stop macOS WKWebView from
                        -- auto-capitalizing / auto-correcting them.
                        , Html.Attributes.attribute "autocapitalize" "off"
                        , Html.Attributes.attribute "autocorrect" "off"
                        , Html.Attributes.spellcheck False
                        ]
                        []
                    , button [ onClick ClickedNewFile ] [ text "New" ]
                    , button [ onClick ClickedRename ] [ text "Rename" ]
                    ]
               , div [ style "margin-top" "4px", style "display" "flex", style "gap" "2mm" ]
                    [ button [ onClick ClickedDeleteSelected ] [ text "Delete" ]
                    , button [ onClick ClickedChangeVault ] [ text "Change Vault" ]
                    ]
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
                ]
                [ button [ onClick ToggledReaderMode ]
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
        (conflictBanner model ++ errorBanner model ++ [ toolbar, body ])


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
