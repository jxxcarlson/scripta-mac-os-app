module Parser.Expression exposing (parse)

{-|

    > import Types exposing(..)
    > import Parser.Expression exposing(parse)

    > parse 0 "hello"
    [Text "hello" { begin = 0, end = 4, index = 0, id = "e-0.0" }]

    > parse 0 "This is [b important]"
    [Text "This is " ..., Fun "b" [Text "important" ...] ...]

    > parse 0 "I like $a^2 + b^2 = c^2$"
    [Text "I like " ..., VFun "math" "a^2 + b^2 = c^2" ...]

-}

import List.Extra
import Parser.Match as M
import Parser.Symbol as Symbol exposing (Symbol(..))
import Parser.Tokenizer as Token exposing (Meta, Token, TokenType(..), Token_(..))
import Tools.Loop exposing (Step(..), loop)
import V3.Types exposing (Expr(..), ExprMeta, Expression)


type alias State =
    { step : Int
    , tokens : List Token
    , numberOfTokens : Int
    , tokenIndex : Int
    , committed : List Expression
    , stack : List Token
    , messages : List String
    , lineNumber : Int
    , source : String
    }


parse : Int -> String -> List Expression
parse lineNumber str =
    let
        state =
            parseToState lineNumber str
    in
    state.committed |> fixup


fixup : List Expression -> List Expression
fixup input =
    case input of
        (Fun name exprList meta) :: rest ->
            let
                newExprlist =
                    case exprList of
                        (Text str meta_) :: tail ->
                            Text (String.trim str) meta_ :: tail

                        _ ->
                            exprList
            in
            Fun name newExprlist meta :: fixup rest

        other :: rest ->
            other :: fixup rest

        [] ->
            []


parseToState : Int -> String -> State
parseToState lineNumber str =
    str
        |> Token.run
        |> parseTokenListToState lineNumber str


parseTokenListToState : Int -> String -> List Token -> State
parseTokenListToState lineNumber source tokens =
    tokens |> initWithTokens lineNumber source |> run


initWithTokens : Int -> String -> List Token -> State
initWithTokens lineNumber source tokens =
    { step = 0
    , tokens = List.reverse tokens
    , numberOfTokens = List.length tokens
    , tokenIndex = 0
    , committed = []
    , stack = []
    , messages = []
    , lineNumber = lineNumber
    , source = source
    }


run : State -> State
run state =
    loop state nextStep
        |> (\state_ -> { state_ | committed = List.reverse state_.committed })


nextStep : State -> Step State State
nextStep state =
    case getToken state of
        Nothing ->
            if stackIsEmpty state then
                Done state

            else
                recoverFromError state

        Just token ->
            state
                |> advanceTokenIndex
                |> pushOrCommit token
                |> reduceState
                |> (\st -> { st | step = st.step + 1 })
                |> Loop


advanceTokenIndex : State -> State
advanceTokenIndex state =
    { state | tokenIndex = state.tokenIndex + 1 }


getToken : State -> Maybe Token
getToken state =
    List.Extra.getAt state.tokenIndex state.tokens


stackIsEmpty : State -> Bool
stackIsEmpty state =
    List.isEmpty state.stack


pushOrCommit : Token -> State -> State
pushOrCommit token state =
    case token of
        S _ _ ->
            pushOrCommit_ token state

        W _ _ ->
            pushOrCommit_ token state

        MathToken _ ->
            pushOnStack_ token state

        CodeToken _ ->
            pushOnStack_ token state

        LB _ ->
            pushOnStack_ token state

        DLB _ ->
            pushOnStack_ token state

        RB _ ->
            pushOnStack_ token state

        TokenError _ _ ->
            pushOnStack_ token state


pushOnStack_ : Token -> State -> State
pushOnStack_ token state =
    { state | stack = token :: state.stack }


pushOrCommit_ : Token -> State -> State
pushOrCommit_ token state =
    if List.isEmpty state.stack then
        commit token state

    else
        push token state


push : Token -> State -> State
push token state =
    { state | stack = token :: state.stack }


commit : Token -> State -> State
commit token state =
    case stringTokenToExpr state.lineNumber token of
        Nothing ->
            state

        Just expr ->
            { state | committed = expr :: state.committed }


stringTokenToExpr : Int -> Token -> Maybe Expression
stringTokenToExpr lineNumber token =
    case token of
        S str loc ->
            Just (Text str (boostMeta lineNumber (Token.indexOf token) loc))

        W str loc ->
            Just (Text str (boostMeta lineNumber (Token.indexOf token) loc))

        _ ->
            Nothing


reduceState : State -> State
reduceState state =
    if tokensAreReducible state then
        { state | stack = [], committed = reduceStack state ++ state.committed }

    else
        state


tokensAreReducible : State -> Bool
tokensAreReducible state =
    M.isReducible (state.stack |> Symbol.toSymbols |> List.reverse)


reduceStack : State -> List Expression
reduceStack state =
    reduceTokens state.lineNumber state.source (state.stack |> List.reverse)


reduceTokens : Int -> String -> List Token -> List Expression
reduceTokens lineNumber source tokens =
    case tokens of
        (DLB dlbMeta) :: rest ->
            reduceWikilink lineNumber source dlbMeta rest

        _ ->
            reduceTokensNonWikilink lineNumber source tokens


reduceTokensNonWikilink : Int -> String -> List Token -> List Expression
reduceTokensNonWikilink lineNumber source tokens =
    if isExpr tokens then
        let
            args =
                unbracket tokens
        in
        case args of
            (S name meta) :: rest ->
                if List.member name verbatimFunctionNames then
                    -- For verbatim functions like [m ...], [math ...], [chem ...],
                    -- collect all remaining tokens as a single string
                    let
                        content =
                            rest
                                |> List.filterMap tokenToString
                                |> String.join ""
                                |> String.trim
                    in
                    [ VFun name content (boostMeta lineNumber meta.index meta) ]

                else
                    [ Fun name (reduceRestOfTokens lineNumber source (List.drop 1 args)) (boostMeta lineNumber meta.index meta) ]

            _ ->
                [ errorMessage "[????]" ]

    else
        case tokens of
            (MathToken meta) :: (S str _) :: (MathToken closeMeta) :: rest ->
                VFun "math" str (boostMeta lineNumber meta.index { meta | end = closeMeta.begin }) :: reduceRestOfTokens lineNumber source rest

            (MathToken meta) :: rest ->
                -- Multi-token math content: collect everything up to closing MathToken
                let
                    inner =
                        List.Extra.takeWhile (not << isMathToken) rest

                    closingToken =
                        List.drop (List.length inner) rest |> List.head

                    closeEnd =
                        case closingToken of
                            Just (MathToken cm) ->
                                cm.begin

                            _ ->
                                meta.end

                    after =
                        List.drop (List.length inner + 1) rest

                    content =
                        inner
                            |> List.filterMap tokenToString
                            |> String.join ""
                in
                VFun "math" content (boostMeta lineNumber meta.index { meta | end = closeEnd }) :: reduceRestOfTokens lineNumber source after

            (CodeToken meta) :: (S str _) :: (CodeToken closeMeta) :: rest ->
                VFun "code" str (boostMeta lineNumber meta.index { meta | end = closeMeta.begin }) :: reduceRestOfTokens lineNumber source rest

            _ ->
                [ errorMessage "[????]" ]


reduceRestOfTokens : Int -> String -> List Token -> List Expression
reduceRestOfTokens lineNumber source tokens =
    case tokens of
        (LB _) :: _ ->
            case splitTokens tokens of
                Nothing ->
                    [ Text "error on match" dummyLocWithId ]

                Just ( a, b ) ->
                    reduceTokens lineNumber source a ++ reduceRestOfTokens lineNumber source b

        (DLB _) :: _ ->
            case splitTokens tokens of
                Nothing ->
                    [ Text "error on match" dummyLocWithId ]

                Just ( a, b ) ->
                    reduceTokens lineNumber source a ++ reduceRestOfTokens lineNumber source b

        (MathToken _) :: _ ->
            let
                ( a, b ) =
                    splitTokensWithSegment tokens
            in
            reduceTokens lineNumber source a ++ reduceRestOfTokens lineNumber source b

        (CodeToken _) :: _ ->
            let
                ( a, b ) =
                    splitTokensWithSegment tokens
            in
            reduceTokens lineNumber source a ++ reduceRestOfTokens lineNumber source b

        (S str meta) :: _ ->
            Text str (boostMeta lineNumber (Token.indexOf (S str meta)) meta) :: reduceRestOfTokens lineNumber source (List.drop 1 tokens)

        token :: _ ->
            case stringTokenToExpr lineNumber token of
                Just expr ->
                    expr :: reduceRestOfTokens lineNumber source (List.drop 1 tokens)

                Nothing ->
                    [ Text "error converting Token" dummyLocWithId ]

        _ ->
            []


recoverFromError : State -> Step State State
recoverFromError state =
    case List.reverse state.stack of
        (DLB dlbMeta) :: _ ->
            let
                closeMeta =
                    case List.head state.stack of
                        Just t ->
                            Token.getMeta t

                        Nothing ->
                            dlbMeta
            in
            Done
                { state
                    | committed =
                        redLiteral state.lineNumber dlbMeta closeMeta state.source
                            :: state.committed
                    , stack = []
                    , tokenIndex = 0
                    , numberOfTokens = 0
                    , messages = prependMessage state.lineNumber "Unclosed [[" state.messages
                }

        (LB _) :: (RB meta) :: _ ->
            Loop
                { state
                    | committed = errorMessage "[?]" :: state.committed
                    , stack = []
                    , tokenIndex = meta.index + 1
                    , messages = prependMessage state.lineNumber "Brackets must enclose something" state.messages
                }

        (LB _) :: (S fName meta) :: _ ->
            Loop
                { state
                    | committed = errorMessage ("[" ++ fName ++ "]?") :: state.committed
                    , stack = []
                    , tokenIndex = meta.index + 1
                    , messages = prependMessage state.lineNumber "Missing right bracket" state.messages
                }

        (LB _) :: (W " " meta) :: _ ->
            Loop
                { state
                    | committed = errorMessage "[ - can't have space after the bracket " :: state.committed
                    , stack = []
                    , tokenIndex = meta.index + 1
                    , messages = prependMessage state.lineNumber "Can't have space after left bracket" state.messages
                }

        (LB _) :: [] ->
            Done
                { state
                    | committed = errorMessage "[...?" :: state.committed
                    , stack = []
                    , tokenIndex = 0
                    , numberOfTokens = 0
                    , messages = prependMessage state.lineNumber "That left bracket needs something after it" state.messages
                }

        (RB meta) :: _ ->
            Loop
                { state
                    | committed = errorMessage " extra ]?" :: state.committed
                    , stack = []
                    , tokenIndex = meta.index + 1
                    , messages = prependMessage state.lineNumber "Extra right bracket(s)" state.messages
                }

        (MathToken meta) :: _ ->
            Loop
                { state
                    | committed = errorMessage "$?$" :: state.committed
                    , stack = []
                    , tokenIndex = meta.index + 1
                    , numberOfTokens = 0
                    , messages = prependMessage state.lineNumber "opening dollar sign needs to be matched" state.messages
                }

        (CodeToken meta) :: _ ->
            Loop
                { state
                    | committed = errorMessage "`?`" :: state.committed
                    , stack = []
                    , tokenIndex = meta.index + 1
                    , numberOfTokens = 0
                    , messages = prependMessage state.lineNumber "opening backtick needs to be matched" state.messages
                }

        _ ->
            Done
                { state
                    | committed = errorMessage " ?!? " :: state.committed
                    , messages = prependMessage state.lineNumber "Unknown error" state.messages
                }



-- HELPERS


unbracket : List a -> List a
unbracket list =
    List.drop 1 (List.take (List.length list - 1) list)


isExpr : List Token -> Bool
isExpr tokens =
    List.map Token.type_ (List.take 1 tokens)
        == [ TLB ]
        && List.map Token.type_ (List.take 1 (List.reverse tokens))
        == [ TRB ]


boostMeta : Int -> Int -> { begin : Int, end : Int, index : Int } -> ExprMeta
boostMeta lineNumber tokenIndex { begin, end, index } =
    { begin = begin, end = end, index = index, id = makeId lineNumber tokenIndex }


splitTokens : List Token -> Maybe ( List Token, List Token )
splitTokens tokens =
    case M.match (Symbol.toSymbols tokens) of
        Nothing ->
            Nothing

        Just k ->
            Just (M.splitAt (k + 1) tokens)


splitTokensWithSegment : List Token -> ( List Token, List Token )
splitTokensWithSegment tokens =
    M.splitAt (segLength tokens + 1) tokens


segLength : List Token -> Int
segLength tokens =
    M.getSegment M (tokens |> Symbol.toSymbols) |> List.length


makeId : Int -> Int -> String
makeId lineNumber tokenIndex =
    "e-" ++ String.fromInt lineNumber ++ "." ++ String.fromInt tokenIndex


dummyTokenIndex : Int
dummyTokenIndex =
    0


dummyLocWithId : ExprMeta
dummyLocWithId =
    { begin = 0, end = 0, index = dummyTokenIndex, id = "dummy" }


errorMessage : String -> Expression
errorMessage message =
    Fun "errorHighlight" [ Text message dummyLocWithId ] dummyLocWithId


prependMessage : Int -> String -> List String -> List String
prependMessage lineNumber message messages =
    (message ++ " (line " ++ String.fromInt lineNumber ++ ")") :: List.take 2 messages


{-| List of function names that should be parsed as VFun (verbatim functions).
These functions receive their content as a raw string rather than parsed expressions.
-}
verbatimFunctionNames : List String
verbatimFunctionNames =
    [ "m", "math", "chem", "code" ]


isMathToken : Token -> Bool
isMathToken token =
    case token of
        MathToken _ ->
            True

        _ ->
            False


{-| Convert a token to its string representation for verbatim functions.
-}
tokenToString : Token -> Maybe String
tokenToString token =
    case token of
        S str _ ->
            Just str

        W str _ ->
            Just str

        LB _ ->
            Just "["

        RB _ ->
            Just "]"

        _ ->
            Nothing


reduceWikilink : Int -> String -> Meta -> List Token -> List Expression
reduceWikilink lineNumber source dlbMeta rest =
    case splitOffWikilinkBody rest of
        Just ( body, closeMeta ) ->
            if List.any isSToken body then
                let
                    spanMeta =
                        boostMeta lineNumber dlbMeta.index { dlbMeta | end = closeMeta.end }
                in
                [ Fun "wikilink" (wikilinkArgs lineNumber body) spanMeta ]

            else
                [ redLiteral lineNumber dlbMeta closeMeta source ]

        Nothing ->
            [ redLiteral lineNumber dlbMeta (lastMeta rest) source ]


splitOffWikilinkBody : List Token -> Maybe ( List Token, Meta )
splitOffWikilinkBody tokens =
    case List.reverse tokens of
        (RB m2) :: (RB _) :: revBody ->
            let
                body =
                    List.reverse revBody
            in
            if List.all isFlatBodyToken body then
                Just ( body, m2 )

            else
                Nothing

        _ ->
            Nothing


isFlatBodyToken : Token -> Bool
isFlatBodyToken token =
    case token of
        S _ _ ->
            True

        W _ _ ->
            True

        _ ->
            False


isSToken : Token -> Bool
isSToken token =
    case token of
        S str _ ->
            String.trim str /= ""

        _ ->
            False


wikilinkArgs : Int -> List Token -> List Expression
wikilinkArgs lineNumber tokens =
    List.filterMap (stringTokenToExpr lineNumber) tokens


lastMeta : List Token -> Meta
lastMeta tokens =
    case List.reverse tokens of
        t :: _ ->
            Token.getMeta t

        [] ->
            { begin = 0, end = 0, index = 0 }


redLiteral : Int -> Meta -> Meta -> String -> Expression
redLiteral lineNumber dlbMeta closeMeta source =
    let
        sliced =
            String.slice dlbMeta.begin (closeMeta.end + 1) source

        spanMeta =
            boostMeta lineNumber dlbMeta.index
                { begin = dlbMeta.begin, end = closeMeta.end, index = dlbMeta.index }
    in
    Fun "red" [ Text sliced spanMeta ] spanMeta
