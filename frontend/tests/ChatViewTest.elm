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
                View.chatMessageView 0 "" (Chat.assistant "# Hi\n\nsource")
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "button", Selector.containing [ Selector.text "Copy" ] ]
                    |> Event.simulate Event.click
                    |> Event.expect (CopyReply "# Hi\n\nsource")
        , test "assistant reply File button emits ClickedChatFile with index and content" <|
            \_ ->
                View.chatMessageView 2 "notes" (Chat.assistant "body text")
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "button", Selector.containing [ Selector.text "File" ] ]
                    |> Event.simulate Event.click
                    |> Event.expect (ClickedChatFile 2 "body text")
        , test "assistant title field emits ChatFileTitleInput with the reply index" <|
            \_ ->
                View.chatMessageView 3 "" (Chat.assistant "body")
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "input" ]
                    |> Event.simulate (Event.input "draft")
                    |> Event.expect (ChatFileTitleInput 3 "draft")
        , test "File button is disabled when the title draft is blank" <|
            \_ ->
                View.chatMessageView 0 "   " (Chat.assistant "body")
                    |> Query.fromHtml
                    |> Query.find [ Selector.tag "button", Selector.containing [ Selector.text "File" ] ]
                    |> Query.has [ Selector.disabled True ]
        , test "user message has no Copy button" <|
            \_ ->
                View.chatMessageView 0 "" (Chat.user "hello")
                    |> Query.fromHtml
                    |> Query.findAll [ Selector.tag "button", Selector.containing [ Selector.text "Copy" ] ]
                    |> Query.count (Expect.equal 0)
        ]
