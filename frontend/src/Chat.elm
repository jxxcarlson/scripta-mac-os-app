module Chat exposing (ChatMessage, user, assistant, encode)

import Json.Encode as E


type alias ChatMessage =
    { role : String, content : String }


user : String -> ChatMessage
user content =
    { role = "user", content = content }


assistant : String -> ChatMessage
assistant content =
    { role = "assistant", content = content }


encode : ChatMessage -> E.Value
encode m =
    E.object [ ( "role", E.string m.role ), ( "content", E.string m.content ) ]
