module ViewTextImageTest exposing (suite)

import Html.Attributes as Attr
import Test exposing (Test, describe, test)
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import View


suite : Test
suite =
    describe "View text/image panes"
        [ test "plainTextPreview renders a pre containing the content" <|
            \_ ->
                View.plainTextPreview "hello world"
                    |> Query.fromHtml
                    |> Query.has [ Selector.tag "pre", Selector.text "hello world" ]
        , test "imagePane renders an img with the data-url src" <|
            \_ ->
                View.imagePane (Just "data:image/png;base64,AAAA")
                    |> Query.fromHtml
                    |> Query.has
                        [ Selector.tag "img"
                        , Selector.attribute (Attr.src "data:image/png;base64,AAAA")
                        ]
        ]
