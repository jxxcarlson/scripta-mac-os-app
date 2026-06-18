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
        [ test "renders a level-1 heading as an h1 carrying a slug id" <|
            \_ ->
                MarkdownRender.render "# Hello World"
                    |> .body
                    |> Html.div []
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "h1" ]
                    |> Query.has [ Selector.id "hello-world" ]
        ]
