module MarkdownRenderTest exposing (suite)

import Expect
import Html
import MarkdownRender
import Render
import Test exposing (Test, describe, test)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector


suite : Test
suite =
    describe "MarkdownRender"
        [ test "renders a level-1 heading as an h2 (matching Scripta section sizing) carrying a slug id" <|
            \_ ->
                MarkdownRender.render "# Hello World"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "h2" ]
                    |> Query.has [ Selector.id "hello-world" ]
        , test "renders a level-2 heading as an h3 (matching Scripta section sizing)" <|
            \_ ->
                MarkdownRender.render "## Sub Section"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "h3" ]
                    |> Query.has [ Selector.id "sub-section" ]
        , test "renders headings with Scripta's non-bold section weight" <|
            \_ ->
                MarkdownRender.render "# Hello World"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "h2" ]
                    |> Query.has [ Selector.style "font-weight" "normal" ]
        , test "renders a non-heading paragraph as a p element" <|
            \_ ->
                MarkdownRender.render "just some text"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.has [ Selector.tag "p" ]
        , test "builds a TOC when there is more than one heading" <|
            \_ ->
                MarkdownRender.render "# One\n\n# Two"
                    |> .toc
                    |> List.isEmpty
                    |> Expect.equal False
        , test "omits the TOC when there is at most one heading" <|
            \_ ->
                MarkdownRender.render "# Only\n\nsome body text"
                    |> .toc
                    |> List.isEmpty
                    |> Expect.equal True
        , test "a TOC entry click produces ScrollTo with the heading slug" <|
            \_ ->
                MarkdownRender.render "# Hello World\n\n# Second"
                    |> .toc
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.findAll [ Selector.tag "span" ]
                    |> Query.index 0
                    |> Event.simulate Event.click
                    |> Event.expect (Render.ScrollTo "hello-world")
        , test "nests sub-headings as an indented sub-list" <|
            \_ ->
                MarkdownRender.render "# Parent\n\n## Child"
                    |> .toc
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.findAll [ Selector.tag "ul" ]
                    |> Query.count (Expect.equal 2)
        , test "emits a math-text element for inline math" <|
            \_ ->
                MarkdownRender.render "Pythagoras: $a^2 + b^2 = c^2$"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.has [ Selector.tag "math-text" ]
        , test "classifies a pdf target as external" <|
            \_ ->
                Expect.equal MarkdownRender.External (MarkdownRender.classifyLink "III_The_Rose.pdf")
        , test "classifies a subdir pdf target as external" <|
            \_ ->
                Expect.equal MarkdownRender.External (MarkdownRender.classifyLink "sub/dir/file.pdf")
        , test "classifies .md / .scripta targets as navigate" <|
            \_ ->
                Expect.equal [ MarkdownRender.Navigate, MarkdownRender.Navigate ]
                    [ MarkdownRender.classifyLink "black-hole-study-notes.md"
                    , MarkdownRender.classifyLink "sub/foo.scripta"
                    ]
        , test "classifies a bare folder target as navigate" <|
            \_ ->
                Expect.equal MarkdownRender.Navigate (MarkdownRender.classifyLink "Bar")
        , test "a doc link click emits NavigateToFile" <|
            \_ ->
                MarkdownRender.render "[notes](black-hole-study-notes.md)"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "a" ]
                    |> Event.simulate Event.click
                    |> Event.expect (Render.NavigateToFile "black-hole-study-notes.md")
        , test "classifies http(s) and mailto as web" <|
            \_ ->
                Expect.equal [ MarkdownRender.Web, MarkdownRender.Web, MarkdownRender.Web ]
                    [ MarkdownRender.classifyLink "http://e.com"
                    , MarkdownRender.classifyLink "https://e.com"
                    , MarkdownRender.classifyLink "mailto:a@b.c"
                    ]
        , test "classifies a fragment as an anchor" <|
            \_ ->
                Expect.equal MarkdownRender.Anchor (MarkdownRender.classifyLink "#section")
        , test "a local file link click emits OpenLocalFile" <|
            \_ ->
                MarkdownRender.render "[doc](III_The_Rose.pdf)"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "a" ]
                    |> Event.simulate Event.click
                    |> Event.expect (Render.OpenLocalFile "III_The_Rose.pdf")
        , test "a web link click emits OpenUrl" <|
            \_ ->
                MarkdownRender.render "[site](https://example.com)"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "a" ]
                    |> Event.simulate Event.click
                    |> Event.expect (Render.OpenUrl "https://example.com")
        ]
