module View exposing (view)

import Editor
import Html exposing (Html, button, div, li, span, text, ul)
import Html.Attributes exposing (style)
import Html.Events exposing (onClick, onInput)
import Json.Decode as D
import Language
import Render
import SaveState
import Set exposing (Set)
import Svg
import Svg.Attributes as SA
import Types exposing (Model, Msg(..))
import Workspace exposing (Node(..))


treeColumn : Model -> Html Msg
treeColumn model =
    div [ style "width" "260px", style "border-right" "1px solid #ddd", style "padding" "8px", style "overflow" "auto" ]
        (button [ onClick ClickedOpenVault ] [ text "Open Vault" ]
            :: errorBanner model
            ++ [ searchBox model
               , fileTree model
               , div [ style "font-size" "12px", style "color" "#666", style "margin-top" "6px" ]
                    [ text (saveLabel model.saveState.saveStatus) ]
               , div [ style "margin-top" "8px" ]
                    [ Html.input
                        [ Html.Attributes.placeholder "new-file-name"
                        , Html.Attributes.value model.newName
                        , onInput SetNewName
                        , style "width" "150px"
                        ]
                        []
                    , button [ onClick ClickedNewFile ] [ text "New" ]
                    , button [ onClick ClickedRename ] [ text "Rename" ]
                    ]
               , div [ style "margin-top" "4px" ]
                    [ button [ onClick ClickedDeleteSelected ] [ text "Delete" ]
                    , button [ onClick ClickedChangeVault ] [ text "Change Vault" ]
                    ]
               , div [ style "margin-top" "4px" ]
                    [ button [ onClick ClickedExportHtml ] [ text "Export HTML" ]
                    , button [ onClick ClickedExportLatex ] [ text "Export LaTeX" ]
                    ]
               ]
        )


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
                    , style "border-right" "1px solid #ddd"
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
                , style "border-bottom" "1px solid #ddd"
                ]
                [ button [ onClick ToggledReaderMode ]
                    [ text
                        (if model.readerMode then
                            "Exit Reader"

                         else
                            "Reader"
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
                                            , style "border-left" "1px solid #ddd"
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
                        , style "max-width" "4.5in"
                        ]
                        bodyContent
                    ]
                 ]
                    ++ tocCols
                )

        body =
            if model.readerMode then
                readerView

            else
                threePaneRow
    in
    div [ style "display" "flex", style "flex-direction" "column", style "height" "100vh", style "font-family" "system-ui" ]
        (conflictBanner model ++ [ toolbar, body ])


conflictBanner : Model -> List (Html Msg)
conflictBanner model =
    if model.externalConflict then
        [ div [ style "background" "#ffd", style "padding" "8px", style "border-bottom" "1px solid #cc0" ]
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
                [ style "background" "#fee", style "color" "#900", style "padding" "6px", onClick DismissError ]
                [ text ("Error: " ++ e ++ " (click to dismiss)") ]
            ]

        Nothing ->
            []


{-| A small folder glyph: filled black when closed, outline-only when open.
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
            , SA.stroke "#000"
            , SA.strokeWidth "1"
            , SA.fill
                (if isOpen then
                    "none"

                 else
                    "#000"
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
        , style "margin-top" "1mm"
        ]
        []


{-| The file tree, filtered to matching documents while a search is active
(folders containing matches are force-expanded so matches are visible).
-}
fileTree : Model -> Html Msg
fileTree model =
    let
        q =
            String.trim model.searchQuery
    in
    if String.isEmpty q then
        treeView False model.openFolders model.tree

    else
        treeView True model.openFolders (Workspace.filter q model.tree)


treeView : Bool -> Set String -> List Node -> Html Msg
treeView forceOpen openFolders nodes =
    ul
        [ style "list-style" "none"
        , style "padding-left" "12px"
        , style "font-size" "13px"
        ]
        (List.map (nodeView forceOpen openFolders) nodes)


nodeView : Bool -> Set String -> Node -> Html Msg
nodeView forceOpen openFolders node =
    case node of
        FileNode r ->
            li
                [ onClick (ClickedTreeNode r.path)
                , style "cursor" "pointer"
                , style "margin-bottom" "4px"
                , style "display" "flex"
                , style "align-items" "flex-start"
                ]
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
                    [ onClick (ToggledFolder r.path)
                    , style "cursor" "pointer"
                    , style "margin-bottom" "4px"
                    , style "display" "flex"
                    , style "align-items" "flex-start"
                    ]
                    [ span [ style "flex" "0 0 auto", style "margin-right" "5px" ] [ folderIcon isOpen ]
                    , span [ style "flex" "1 1 auto" ] [ text r.name ]
                    ]
                    :: (if isOpen then
                            [ treeView forceOpen openFolders r.children ]

                        else
                            []
                       )
                )


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

        ( Just lang, _ ) ->
            [ Html.text (Language.label lang ++ " rendering is not yet supported.") ]

        ( Nothing, _ ) ->
            [ Html.text "Open a .scripta file." ]
