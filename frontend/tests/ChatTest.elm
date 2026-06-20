module ChatTest exposing (suite)

import Chat
import Expect
import Json.Decode as D
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Chat"
        [ test "user / assistant build messages with the right role" <|
            \_ ->
                Expect.equal ( "user", "hi", "assistant" )
                    ( (Chat.user "hi").role, (Chat.user "hi").content, (Chat.assistant "ok").role )
        , test "encode produces {role, content}" <|
            \_ ->
                let
                    v = Chat.encode (Chat.user "hello")
                    role = D.decodeValue (D.field "role" D.string) v
                    content = D.decodeValue (D.field "content" D.string) v
                in
                Expect.equal ( Ok "user", Ok "hello" ) ( role, content )
        ]
