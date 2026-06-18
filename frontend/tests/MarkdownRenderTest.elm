module MarkdownRenderTest exposing (suite)

import Expect
import Html
import MarkdownRender
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector


suite : Test
suite =
    describe "MarkdownRender"
        [ test "renders a level-1 heading as an h1 carrying a slug id" <|
            \_ ->
                MarkdownRender.render "# Hello World"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "h1" ]
                    |> Query.has [ Selector.id "hello-world" ]
        , test "renders a level-2 heading as an h2" <|
            \_ ->
                MarkdownRender.render "## Sub Section"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "h2" ]
                    |> Query.has [ Selector.id "sub-section" ]
        , test "renders a non-heading paragraph as a p element" <|
            \_ ->
                MarkdownRender.render "just some text"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.has [ Selector.tag "p" ]
        ]
