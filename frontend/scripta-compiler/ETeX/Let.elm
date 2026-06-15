module ETeX.Let exposing (reduce)


type alias Definition =
    { variable : Char
    , expr : String
    }


type alias LetBlock =
    { definitions : List Definition
    , body : String
    }



-- REDUCE --


reduce : String -> String
reduce input =
    case parseLetBlock input of
        Nothing ->
            input

        Just ( preamble, letBlock ) ->
            let
                resolvedDefs =
                    resolveDefinitions letBlock.definitions

                result =
                    applyDefinitions resolvedDefs letBlock.body
            in
            if String.isEmpty preamble then
                result

            else
                preamble ++ "\n" ++ result


{-| Process definitions sequentially: substitute earlier variables into later definitions.
-}
resolveDefinitions : List Definition -> List Definition
resolveDefinitions defs =
    let
        folder def resolved =
            let
                newExpr =
                    List.foldl
                        (\prev expr -> substituteVariable prev.variable prev.expr expr)
                        def.expr
                        resolved
            in
            resolved ++ [ { def | expr = newExpr } ]
    in
    List.foldl folder [] defs


{-| Substitute all definitions into the body.
-}
applyDefinitions : List Definition -> String -> String
applyDefinitions defs body =
    List.foldl
        (\def text -> substituteVariable def.variable def.expr text)
        body
        defs



-- PARSER --


{-| Parse a LET/IN block. Returns ( preamble, LetBlock ) on success.
-}
parseLetBlock : String -> Maybe ( String, LetBlock )
parseLetBlock input =
    case splitOnLET input of
        Nothing ->
            Nothing

        Just ( preamble, letPart ) ->
            case splitOnIN letPart of
                Nothing ->
                    Nothing

                Just ( defsPart, body ) ->
                    case parseDefinitions defsPart of
                        [] ->
                            Nothing

                        defs ->
                            Just ( preamble, { definitions = defs, body = body } )


{-| Split input on the first line that is exactly "LET".
Returns ( before, fromLETonward without the LET line ).
-}
splitOnLET : String -> Maybe ( String, String )
splitOnLET input =
    let
        lines =
            String.lines input

        findLET idx remaining =
            case remaining of
                [] ->
                    Nothing

                line :: rest ->
                    if String.trim line == "LET" then
                        let
                            before =
                                List.take idx lines |> String.join "\n"

                            after =
                                rest |> String.join "\n"
                        in
                        Just ( before, after )

                    else
                        findLET (idx + 1) rest
    in
    findLET 0 lines


{-| Split on the first line that is exactly "IN".
Returns ( definitionsPart, body ).
-}
splitOnIN : String -> Maybe ( String, String )
splitOnIN input =
    let
        lines =
            String.lines input

        findIN idx remaining =
            case remaining of
                [] ->
                    Nothing

                line :: rest ->
                    if String.trim line == "IN" then
                        let
                            before =
                                List.take idx lines |> String.join "\n"

                            after =
                                rest |> String.join "\n" |> String.trim
                        in
                        Just ( before, after )

                    else
                        findIN (idx + 1) rest
    in
    findIN 0 lines


{-| Parse definitions from the block between LET and IN.
A new definition starts on a line matching the pattern: spaces, uppercase letter, spaces, "=", space.
Continuation lines (anything else) are appended to the current definition's expression.
-}
parseDefinitions : String -> List Definition
parseDefinitions input =
    let
        lines =
            String.lines input

        processLines remaining currentDef acc =
            case remaining of
                [] ->
                    case currentDef of
                        Nothing ->
                            List.reverse acc

                        Just def ->
                            List.reverse (finishDef def :: acc)

                line :: rest ->
                    case parseDefStart line of
                        Just ( var, expr ) ->
                            case currentDef of
                                Nothing ->
                                    processLines rest (Just ( var, expr )) acc

                                Just prev ->
                                    processLines rest (Just ( var, expr )) (finishDef prev :: acc)

                        Nothing ->
                            case currentDef of
                                Nothing ->
                                    -- Continuation line before any definition; skip
                                    processLines rest Nothing acc

                                Just ( var, exprSoFar ) ->
                                    processLines rest (Just ( var, exprSoFar ++ "\n" ++ String.trim line )) acc

        finishDef ( var, expr ) =
            { variable = var, expr = String.trim expr }
    in
    processLines lines Nothing []


{-| Try to parse a line as a definition start: <spaces><uppercase letter><spaces>=<space><rest>.
Returns ( variable, expression ) on success.
-}
parseDefStart : String -> Maybe ( Char, String )
parseDefStart line =
    let
        trimmed =
            String.trimLeft line
    in
    case String.uncons trimmed of
        Just ( c, rest ) ->
            if Char.isUpper c then
                let
                    afterVar =
                        String.trimLeft rest
                in
                case String.uncons afterVar of
                    Just ( '=', afterEq ) ->
                        Just ( c, String.trim afterEq )

                    _ ->
                        Nothing

            else
                Nothing

        Nothing ->
            Nothing



-- NEEDS PARENS --


needsParens : String -> Bool
needsParens expr =
    let
        trimmed =
            String.trim expr
    in
    if isFullyWrapped trimmed then
        False

    else if isLaTeXEnvironment trimmed then
        False

    else
        hasTopLevelPlusOrMinus trimmed


{-| Check if the expression is a single \begin{env}...\end{env} LaTeX environment.
-}
isLaTeXEnvironment : String -> Bool
isLaTeXEnvironment str =
    String.startsWith "\\begin{" str
        && String.endsWith "}" str
        && (countOccurrences "\\begin{" str == 1)
        && (countOccurrences "\\end{" str == 1)


countOccurrences : String -> String -> Int
countOccurrences needle haystack =
    if String.isEmpty needle then
        0

    else
        let
            len =
                String.length needle

            helper s count =
                if String.isEmpty s then
                    count

                else if String.startsWith needle s then
                    helper (String.dropLeft len s) (count + 1)

                else
                    helper (String.dropLeft 1 s) count
        in
        helper haystack 0


{-| Check if the expression is fully wrapped in parens: "(...)".
-}
isFullyWrapped : String -> Bool
isFullyWrapped str =
    if String.startsWith "(" str && String.endsWith ")" str then
        let
            inner =
                str |> String.dropLeft 1 |> String.dropRight 1
        in
        not (hasUnmatchedParens inner)

    else
        False


{-| Check if a string has unmatched close-parens (meaning the outer parens don't match each other).
-}
hasUnmatchedParens : String -> Bool
hasUnmatchedParens str =
    let
        folder c depth =
            if depth < 0 then
                depth

            else if c == '(' then
                depth + 1

            else if c == ')' then
                depth - 1

            else
                depth
    in
    String.foldl folder 0 str < 0


{-| Check if + or - appears at brace/paren depth 0.
-}
hasTopLevelPlusOrMinus : String -> Bool
hasTopLevelPlusOrMinus str =
    let
        folder c ( depth, found ) =
            if found then
                ( depth, True )

            else if c == '{' || c == '(' then
                ( depth + 1, False )

            else if c == '}' || c == ')' then
                ( depth - 1, False )

            else if depth == 0 && (c == '+' || c == '-') then
                ( depth, True )

            else
                ( depth, False )
    in
    String.foldl folder ( 0, False ) str |> Tuple.second



-- SUBSTITUTE --


substituteVariable : Char -> String -> String -> String
substituteVariable var expr target =
    let
        replacement =
            if needsParens expr then
                "(" ++ expr ++ ")"

            else
                expr
    in
    substituteHelper var replacement (String.toList target) []
        |> List.reverse
        |> String.concat


substituteHelper : Char -> String -> List Char -> List String -> List String
substituteHelper var replacement remaining acc =
    case remaining of
        [] ->
            acc

        c :: rest ->
            if c == var && not (isLowerAlpha (lastCharOfAcc acc)) && not (isLowerAlpha (List.head rest)) then
                substituteHelper var replacement rest (replacement :: acc)

            else
                substituteHelper var replacement rest (String.fromChar c :: acc)


lastCharOfAcc : List String -> Maybe Char
lastCharOfAcc acc =
    case acc of
        [] ->
            Nothing

        s :: _ ->
            s |> String.right 1 |> String.toList |> List.head


isLowerAlpha : Maybe Char -> Bool
isLowerAlpha mc =
    case mc of
        Nothing ->
            False

        Just c ->
            Char.isAlpha c && Char.isLower c
