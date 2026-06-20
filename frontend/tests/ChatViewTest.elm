module ChatViewTest exposing (suite)

import Chat
import Expect
import Test exposing (Test, describe, test)
import Test.Html.Event as Event
import Test.Html.Query as Query
import Test.Html.Selector as Selector
import Types exposing (Msg(..))
import View


suite : Test
suite =
    describe "View.chatMessageView"
        [ test "assistant reply has a Copy button that emits CopyReply with the raw content" <|
            \_ ->
                View.chatMessageView (Chat.assistant "# Hi\n\nsource")
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "button", Selector.containing [ Selector.text "Copy" ] ]
                    |> Event.simulate Event.click
                    |> Event.expect (CopyReply "# Hi\n\nsource")
        , test "user message has no Copy button" <|
            \_ ->
                View.chatMessageView (Chat.user "hello")
                    |> Query.fromHtml
                    |> Query.findAll [ Selector.tag "button", Selector.containing [ Selector.text "Copy" ] ]
                    |> Query.count (Expect.equal 0)
        ]
