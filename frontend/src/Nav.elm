module Nav exposing (Step, next, prev)

{-| Pure back/forward navigation stack transitions.

`history` is the back-stack (most-recent first); `future` is the forward-stack
(most-recent first). `current` is the currently open document, if any.
-}


type alias Step =
    { target : String, history : List String, future : List String }


{-| Go back: the most recent history entry becomes the target, and the current
document (if any) is pushed onto the future stack. Nothing when history is empty.
-}
prev : Maybe String -> List String -> List String -> Maybe Step
prev current history future =
    case history of
        p :: rest ->
            Just { target = p, history = rest, future = maybeCons current future }

        [] ->
            Nothing


{-| Go forward: the most recent future entry becomes the target, and the current
document (if any) is pushed onto the history stack. Nothing when future is empty.
-}
next : Maybe String -> List String -> List String -> Maybe Step
next current history future =
    case future of
        n :: rest ->
            Just { target = n, history = maybeCons current history, future = rest }

        [] ->
            Nothing


maybeCons : Maybe a -> List a -> List a
maybeCons m xs =
    case m of
        Just x ->
            x :: xs

        Nothing ->
            xs
