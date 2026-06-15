module ETeX.Transform exposing
    ( evalStr
    , evalStrResult
    , inverseTransformETeX
    , makeMacroDict
    , toLaTeXNewCommands
    , transformETeX
    , transformETeXResult
    )

import Dict exposing (Dict)
import ETeX.Dictionary
import ETeX.Let
import ETeX.KaTeX exposing (isKaTeX)
import ETeX.MathMacros exposing (Deco(..), MacroBody(..), MathExpr(..), MathMacroDict, NewCommand(..))
import Maybe.Extra
import Parser.Advanced as PA
    exposing
        ( (|.)
        , (|=)
        , DeadEnd
        , Step(..)
        , Token(..)
        , backtrackable
        , chompIf
        , chompWhile
        , getChompedString
        , getOffset
        , getSource
        , lazy
        , loop
        , map
        , oneOf
        , run
        , succeed
        , symbol
        )
import Result.Extra



-- MAIN FUNCTIONS --


transformETeX : MathMacroDict -> String -> String
transformETeX userdefinedMacroDict src =
    case transformETeXResult userdefinedMacroDict (ETeX.Let.reduce src) of
        Ok result ->
            result

        Err _ ->
            -- Return input with error marker so failures are visible in output
            "[ETeX error] " ++ src


transformETeXResult : MathMacroDict -> String -> Result (List (DeadEnd Context Problem)) String
transformETeXResult userdefinedMacroDict src =
    transformETeX_ userdefinedMacroDict src
        |> Result.map (\result -> List.map print result |> String.concat)


{-| Partial inverse of `transformETeX`. Parses LaTeX-flavored input and renders
it back in ETeX form: braces become parentheses, multi-argument macros use
comma-separated arguments, and bare macros drop the leading backslash.

    inverseTransformETeX Dict.empty "\\sin{x^2}"   == "sin(x^2)"
    inverseTransformETeX Dict.empty "\\frac{1}{2}" == "frac(1,2)"
    inverseTransformETeX Dict.empty "\\alpha"      == "alpha"

This is a partial inverse: it handles the simple cases above and passes
through expressions it does not know how to re-express in ETeX form.

-}
inverseTransformETeX : MathMacroDict -> String -> String
inverseTransformETeX userdefinedMacroDict src =
    case parseManyWithDict userdefinedMacroDict src of
        Ok exprs ->
            List.map printETeX exprs |> String.concat

        Err _ ->
            "[ETeX inverse error] " ++ src


isUserDefinedMacro : MathMacroDict -> String -> Bool
isUserDefinedMacro dict name =
    Dict.member name dict


transformETeX_ userdefinedMacroDict src =
    src
        |> parseManyWithDict userdefinedMacroDict
        |> Result.map resolveSymbolNames


resolveSymbolNames : List MathExpr -> List MathExpr
resolveSymbolNames exprs =
    List.map resolveSymbolName exprs


{-|

    TODO: Need to take care of all cases where a symbol name is used.

-}
resolveSymbolName : MathExpr -> MathExpr
resolveSymbolName expr =
    case expr of
        AlphaNum str ->
            case Dict.get str ETeX.Dictionary.symbolDict of
                Just _ ->
                    AlphaNum ("\\" ++ str)

                Nothing ->
                    AlphaNum str

        PArg exprs ->
            PArg (List.map resolveSymbolName exprs)

        ParenthExpr exprs ->
            ParenthExpr (List.map resolveSymbolName exprs)

        Macro name args ->
            Macro name (List.map resolveSymbolName args)

        MacroName str ->
            MacroName str

        FunctionName str ->
            FunctionName str

        Arg exprs ->
            Arg (List.map resolveSymbolName exprs)

        Sub deco ->
            Sub (resolveSymbolNameInDeco deco)

        Super deco ->
            Super (resolveSymbolNameInDeco deco)

        Param n ->
            Param n

        WS ->
            WS

        MathSpace ->
            MathSpace

        MathSmallSpace ->
            MathSmallSpace

        MathMediumSpace ->
            MathMediumSpace

        LeftMathBrace ->
            LeftMathBrace

        RightMathBrace ->
            RightMathBrace

        LeftParen ->
            LeftParen

        RightParen ->
            RightParen

        Comma ->
            Comma

        MathSymbols str ->
            MathSymbols str

        FCall name args ->
            FCall name (List.map resolveSymbolName args)

        Expr exprs ->
            Expr (List.map resolveSymbolName exprs)

        Text str ->
            Text str

        GreekSymbol str ->
            Text ("\\" ++ str)



-- Helper function to resolve symbol names in Deco


resolveSymbolNameInDeco : Deco -> Deco
resolveSymbolNameInDeco deco =
    case deco of
        DecoM expr ->
            DecoM (resolveSymbolName expr)

        DecoI n ->
            DecoI n


evalStr : MathMacroDict -> String -> String
evalStr userDefinedMacroDict str =
    case evalStrResult userDefinedMacroDict (ETeX.Let.reduce str) of
        Ok result ->
            result

        Err _ ->
            -- Return input with error marker so failures are visible in output
            "[ETeX error] " ++ str


evalStrResult : MathMacroDict -> String -> Result (List (DeadEnd Context Problem)) String
evalStrResult userDefinedMacroDict str =
    parseManyWithDict userDefinedMacroDict (String.trim str)
        |> Result.map (\result -> List.map (expandMacroWithDict userDefinedMacroDict) result |> printList)


parseManyWithDict : MathMacroDict -> String -> Result (List (DeadEnd Context Problem)) (List MathExpr)
parseManyWithDict userMacroDict str =
    str
        |> String.trim
        |> String.lines
        |> List.map String.trim
        |> groupEnvironmentLines
        |> mergeBraceSpanningLines
        |> List.map
            (\chunk ->
                if String.startsWith "\\begin{" chunk then
                    Ok [ AlphaNum chunk ]

                else
                    parseWithDict userMacroDict chunk
            )
        |> Result.Extra.combine
        |> Result.map List.concat


{-| Merge consecutive lines whose `{}` brace nesting is unbalanced, so that a
brace group an author wrapped across several source lines (for example a
`\\frac{...}{...}` whose numerator spans lines) is parsed as a single unit.

Lines that are individually brace-balanced — ordinary lines and `\\\\`-separated
rows alike — are left as separate chunks, so multi-line aligned input is
unaffected. Environment chunks produced by `groupEnvironmentLines` are
brace-balanced and therefore also pass through untouched.

-}
mergeBraceSpanningLines : List String -> List String
mergeBraceSpanningLines lines =
    let
        step line ( pending, depth, result ) =
            let
                combined =
                    if pending == "" then
                        line

                    else
                        pending ++ " " ++ line

                newDepth =
                    depth + netBraceDepth line
            in
            if newDepth > 0 then
                ( combined, newDepth, result )

            else
                ( "", 0, combined :: result )
    in
    case List.foldl step ( "", 0, [] ) lines of
        ( "", _, result ) ->
            List.reverse result

        ( pending, _, result ) ->
            List.reverse (pending :: result)


{-| Net change in `{}` nesting contributed by a line: count of unescaped `{`
minus unescaped `}`. Escaped braces (`\\{`, `\\}`) are literal and not counted.
-}
netBraceDepth : String -> Int
netBraceDepth line =
    String.foldl
        (\c ( depth, escaped ) ->
            if escaped then
                ( depth, False )

            else
                case c of
                    '\\' ->
                        ( depth, True )

                    '{' ->
                        ( depth + 1, False )

                    '}' ->
                        ( depth - 1, False )

                    _ ->
                        ( depth, False )
        )
        ( 0, False )
        line
        |> Tuple.first


{-| Group lines that form \\begin{...}...\\end{...} blocks into single strings,
leaving other lines as individual entries.
-}
groupEnvironmentLines : List String -> List String
groupEnvironmentLines lines =
    groupEnvironmentLinesHelper lines [] [] Nothing
        |> List.reverse


groupEnvironmentLinesHelper : List String -> List String -> List String -> Maybe String -> List String
groupEnvironmentLinesHelper remaining envAcc result currentEnv =
    case remaining of
        [] ->
            case currentEnv of
                Nothing ->
                    result

                Just _ ->
                    -- Unclosed environment: emit accumulated lines as-is
                    String.join "\n" (List.reverse envAcc) :: result

        line :: rest ->
            case currentEnv of
                Nothing ->
                    case extractBeginEnv line of
                        Just envName ->
                            if String.contains ("\\end{" ++ envName ++ "}") line then
                                -- Single-line environment
                                groupEnvironmentLinesHelper rest [] (line :: result) Nothing

                            else
                                groupEnvironmentLinesHelper rest [ line ] result (Just envName)

                        Nothing ->
                            -- Check if \begin{ appears later in the line (e.g., "= \begin{pmatrix}")
                            case splitOnBegin line of
                                Just ( prefix, beginPart ) ->
                                    -- Emit the prefix as a regular line, push \begin{...} back
                                    groupEnvironmentLinesHelper (beginPart :: rest) [] (prefix :: result) Nothing

                                Nothing ->
                                    groupEnvironmentLinesHelper rest [] (line :: result) Nothing

                Just envName ->
                    let
                        newAcc =
                            line :: envAcc
                    in
                    if String.contains ("\\end{" ++ envName ++ "}") line then
                        let
                            endTag =
                                "\\end{" ++ envName ++ "}"

                            ( beforeEnd, afterEnd ) =
                                splitOnFirst endTag line

                            envLine =
                                beforeEnd ++ endTag

                            collapsed =
                                String.join "\n" (List.reverse (envLine :: envAcc))

                            newRemaining =
                                if String.isEmpty (String.trim afterEnd) then
                                    rest

                                else
                                    String.trim afterEnd :: rest
                        in
                        groupEnvironmentLinesHelper newRemaining [] (collapsed :: result) Nothing

                    else
                        groupEnvironmentLinesHelper rest newAcc result (Just envName)


{-| Extract environment name from a \\begin{name} line.
-}
extractBeginEnv : String -> Maybe String
extractBeginEnv line =
    if String.startsWith "\\begin{" line then
        let
            afterBegin =
                String.dropLeft 7 line
        in
        case String.split "}" afterBegin of
            name :: _ ->
                if String.isEmpty name then
                    Nothing

                else
                    Just name

            [] ->
                Nothing

    else
        Nothing


{-| Split a line at the first \\begin{ if it doesn't start with \\begin{.
Returns ( prefix, "\\begin{..." ) on success.
-}
splitOnBegin : String -> Maybe ( String, String )
splitOnBegin line =
    if String.startsWith "\\begin{" line then
        Nothing

    else
        case String.indexes "\\begin{" line of
            idx :: _ ->
                let
                    prefix =
                        String.trim (String.left idx line)

                    beginPart =
                        String.dropLeft idx line
                in
                if String.isEmpty prefix then
                    Nothing

                else
                    Just ( prefix, beginPart )

            [] ->
                Nothing


{-| Split a string on the first occurrence of a separator.
Returns ( before, after ) where the separator is excluded from both.
-}
splitOnFirst : String -> String -> ( String, String )
splitOnFirst sep str =
    case String.indexes sep str of
        idx :: _ ->
            ( String.left idx str
            , String.dropLeft (idx + String.length sep) str
            )

        [] ->
            ( str, "" )



-- Helper to extract just PArg elements from a comma-separated list


extractMacroArgs : List MathExpr -> List MathExpr
extractMacroArgs args =
    case args of
        [] ->
            []

        (PArg contents) :: rest ->
            Arg contents :: extractMacroArgs rest

        Comma :: rest ->
            extractMacroArgs rest

        other :: rest ->
            other :: extractMacroArgs rest



-- Helper to flatten PArg content for single-argument macros


flattenForSingleArg : List MathExpr -> List MathExpr
flattenForSingleArg args =
    case args of
        [] ->
            []

        (PArg contents) :: rest ->
            contents ++ flattenForSingleArg rest

        other :: rest ->
            other :: flattenForSingleArg rest


expandMacroWithDict : MathMacroDict -> MathExpr -> MathExpr
expandMacroWithDict dict expr =
    case expr of
        Macro macroName args ->
            case Dict.get macroName dict of
                Nothing ->
                    Macro macroName (List.map (expandMacroWithDict dict) args)

                Just (MacroBody arity exprs) ->
                    let
                        macroArgs =
                            if arity == 1 then
                                -- For single-argument macros, combine all content into one Arg
                                case args of
                                    [] ->
                                        []

                                    _ ->
                                        [ Arg (flattenForSingleArg args) ]

                            else
                                -- For multi-argument macros, extract PArg elements separately
                                extractMacroArgs args
                    in
                    Expr (expandMacro_ (List.map (expandMacroWithDict dict) macroArgs) (MacroBody arity exprs))
                        |> expandMacroWithDict dict

        Arg exprs ->
            Arg (List.map (expandMacroWithDict dict) exprs)

        Sub decoExpr ->
            case decoExpr of
                DecoM decoMExpr ->
                    Sub (DecoM (expandMacroWithDict dict decoMExpr))

                DecoI m ->
                    Sub (DecoI m)

        Super decoExpr ->
            case decoExpr of
                DecoM decoMExpr ->
                    Super (DecoM (expandMacroWithDict dict decoMExpr))

                DecoI m ->
                    Super (DecoI m)

        PArg exprs ->
            PArg (List.map (expandMacroWithDict dict) exprs)

        ParenthExpr exprs ->
            ParenthExpr (List.map (expandMacroWithDict dict) exprs)

        FCall name args ->
            FCall name (List.map (expandMacroWithDict dict) args)

        Expr exprs ->
            Expr (List.map (expandMacroWithDict dict) exprs)

        Text str ->
            Text str

        -- Simple cases that don't contain sub-expressions
        AlphaNum str ->
            AlphaNum str

        MacroName str ->
            MacroName str

        FunctionName str ->
            FunctionName str

        Param n ->
            Param n

        WS ->
            WS

        MathSpace ->
            MathSpace

        MathSmallSpace ->
            MathSmallSpace

        MathMediumSpace ->
            MathMediumSpace

        LeftMathBrace ->
            LeftMathBrace

        RightMathBrace ->
            RightMathBrace

        LeftParen ->
            LeftParen

        RightParen ->
            RightParen

        Comma ->
            Comma

        MathSymbols str ->
            MathSymbols str

        GreekSymbol str ->
            GreekSymbol str


{-|

    > args = [Exprs [AlphaNum "x"],Exprs [AlphaNum "y"]]
    > macroDefBody = (MacroBody 2 [Macro "alpha" [],MathSymbols "(",Param 1,MathSymbols ",",Param 2,MathSymbols ")"])
    > expandMacro_  args macroDefBody
    [Macro "alpha" [],MathSymbols "(",Exprs [AlphaNum "x"],MathSymbols ",",Exprs [AlphaNum "y"],MathSymbols ")"]

-}
expandMacro_ : List MathExpr -> MacroBody -> List MathExpr
expandMacro_ args (MacroBody _ macroDefBody) =
    replaceParams args macroDefBody


replaceParam_ : Int -> MathExpr -> MathExpr -> MathExpr
replaceParam_ k expr target =
    case target of
        Arg exprs ->
            Arg (List.map (replaceParam_ k expr) exprs)

        Sub decoExpr ->
            case decoExpr of
                DecoM decoMExpr ->
                    Sub (DecoM (replaceParam_ k expr decoMExpr))

                DecoI m ->
                    Sub (DecoI m)

        Super decoExpr ->
            case decoExpr of
                DecoM decoMExpr ->
                    Super (DecoM (replaceParam_ k expr decoMExpr))

                DecoI m ->
                    Super (DecoI m)

        Param m ->
            if m == k then
                expr

            else
                Param m

        Macro name exprs ->
            Macro name (List.map (replaceParam_ k expr) exprs)

        PArg exprs ->
            PArg (List.map (replaceParam_ k expr) exprs)

        ParenthExpr exprs ->
            ParenthExpr (List.map (replaceParam_ k expr) exprs)

        FCall name args ->
            FCall name (List.map (replaceParam_ k expr) args)

        Expr exprs ->
            Expr (List.map (replaceParam_ k expr) exprs)

        Text str ->
            Text str

        -- Simple cases that don't contain sub-expressions
        AlphaNum str ->
            AlphaNum str

        MacroName str ->
            MacroName str

        FunctionName str ->
            FunctionName str

        WS ->
            WS

        MathSpace ->
            MathSpace

        MathSmallSpace ->
            MathSmallSpace

        MathMediumSpace ->
            MathMediumSpace

        LeftMathBrace ->
            LeftMathBrace

        RightMathBrace ->
            RightMathBrace

        LeftParen ->
            LeftParen

        RightParen ->
            RightParen

        Comma ->
            Comma

        MathSymbols str ->
            MathSymbols str

        GreekSymbol str ->
            GreekSymbol str


replaceParam : Int -> MathExpr -> List MathExpr -> List MathExpr
replaceParam k expr exprs =
    List.map (replaceParam_ k expr) exprs


replaceParams : List MathExpr -> List MathExpr -> List MathExpr
replaceParams replacementList target =
    List.foldl (\( k, replacement ) acc -> replaceParam (k + 1) replacement acc) target (List.indexedMap (\k item -> ( k, item )) replacementList)


makeMacroDict : String -> Dict String MacroBody
makeMacroDict str =
    str
        |> String.trim
        |> String.lines
        |> List.map String.trim
        |> List.filter (not << String.isEmpty)
        |> makeMacroDictFromMixedLines



-- Process lines that can be either format


makeMacroDictFromMixedLines : List String -> Dict String MacroBody
makeMacroDictFromMixedLines lines =
    List.foldl addMixedFormatMacro Dict.empty lines



-- Add a macro in either format


addMixedFormatMacro : String -> Dict String MacroBody -> Dict String MacroBody
addMixedFormatMacro line dict =
    let
        knownMacros =
            Dict.keys dict
    in
    if String.startsWith "\\newcommand" line then
        -- Traditional format
        case parseNewCommand Dict.empty line |> makeEntry of
            Just ( name, body ) ->
                Dict.insert name body dict

            Nothing ->
                dict

    else if String.contains ":" line then
        -- Simple format
        case parseSimpleMacroWithContext knownMacros dict line of
            Just ( name, body ) ->
                Dict.insert name body dict

            Nothing ->
                dict

    else
        -- Skip unrecognized lines
        dict



-- Parse with context of known macro names


parseSimpleMacroWithContext : List String -> MathMacroDict -> String -> Maybe ( String, MacroBody )
parseSimpleMacroWithContext knownMacros macroDict line =
    case String.split ":" line of
        [ name, body ] ->
            let
                trimmedName =
                    String.trim name

                trimmedBody =
                    String.trim body

                -- Process body with knowledge of what macros exist
                processedBody =
                    processSimpleMacroBodyWithContext knownMacros trimmedBody

                -- Convert the simplified syntax to standard newcommand format
                newCommandStr =
                    "\\newcommand{\\" ++ trimmedName ++ "}{" ++ processedBody ++ "}"
            in
            parseNewCommand macroDict newCommandStr
                |> makeEntry

        _ ->
            Nothing



-- Process the body of a simple macro to handle various shortcuts


processSimpleMacroBody : String -> String
processSimpleMacroBody body =
    processSimpleMacroBodyWithContext [] body



-- Process with knowledge of existing macros


processSimpleMacroBodyWithContext : List String -> String -> String
processSimpleMacroBodyWithContext knownMacros body =
    -- Parse the body to identify and process tokens
    body
        |> tokenizeSimpleMacroBody
        |> processTokensWithLookahead knownMacros
        |> List.map tokenToString
        |> String.concat



-- Token types for simple macro parsing


type SimpleToken
    = SimpleWord String
    | SimpleBackslash
    | SimpleSpace String
    | SimpleSymbol String
    | SimpleBrace String String -- open/close brace with content
    | SimpleParam Int



-- Tokenize the macro body into recognizable parts


tokenizeSimpleMacroBody : String -> List SimpleToken
tokenizeSimpleMacroBody body =
    tokenizeHelper (String.toList body) []
        |> List.reverse


tokenizeHelper : List Char -> List SimpleToken -> List SimpleToken
tokenizeHelper chars acc =
    case chars of
        [] ->
            acc

        '\\' :: rest ->
            tokenizeHelper rest (SimpleBackslash :: acc)

        '#' :: rest ->
            -- Parse parameter number
            let
                ( digits, remaining ) =
                    takeDigits rest
            in
            case String.toInt (String.fromList digits) of
                Just n ->
                    tokenizeHelper remaining (SimpleParam n :: acc)

                Nothing ->
                    tokenizeHelper rest (SimpleSymbol "#" :: acc)

        '{' :: rest ->
            -- Collect content until matching '}'
            let
                ( content, remaining ) =
                    collectUntilCloseBrace rest 1 []
            in
            tokenizeHelper remaining (SimpleBrace "{" (String.fromList content) :: acc)

        c :: rest ->
            if Char.isAlpha c then
                -- Collect alphabetic word
                let
                    ( word, remaining ) =
                        takeAlphas (c :: rest)
                in
                tokenizeHelper remaining (SimpleWord (String.fromList word) :: acc)

            else if c == ' ' || c == '\t' || c == '\n' then
                -- Collect whitespace
                let
                    ( spaces, remaining ) =
                        takeSpaces (c :: rest)
                in
                tokenizeHelper remaining (SimpleSpace (String.fromList spaces) :: acc)

            else
                -- Single symbol
                tokenizeHelper rest (SimpleSymbol (String.fromChar c) :: acc)



-- Helper to take digits


takeWhile : (Char -> Bool) -> List Char -> ( List Char, List Char )
takeWhile pred chars =
    case chars of
        [] ->
            ( [], [] )

        c :: rest ->
            if pred c then
                let
                    ( taken, remaining ) =
                        takeWhile pred rest
                in
                ( c :: taken, remaining )

            else
                ( [], chars )


takeDigits : List Char -> ( List Char, List Char )
takeDigits =
    takeWhile Char.isDigit


takeAlphas : List Char -> ( List Char, List Char )
takeAlphas =
    takeWhile Char.isAlpha


takeSpaces : List Char -> ( List Char, List Char )
takeSpaces =
    takeWhile (\c -> c == ' ' || c == '\t' || c == '\n')



-- Helper to collect content until closing brace


collectUntilCloseBrace : List Char -> Int -> List Char -> ( List Char, List Char )
collectUntilCloseBrace chars depth acc =
    case chars of
        [] ->
            ( List.reverse acc, [] )

        '{' :: rest ->
            collectUntilCloseBrace rest (depth + 1) ('{' :: acc)

        '}' :: rest ->
            if depth == 1 then
                ( List.reverse acc, rest )

            else
                collectUntilCloseBrace rest (depth - 1) ('}' :: acc)

        c :: rest ->
            collectUntilCloseBrace rest depth (c :: acc)



-- Process tokens with lookahead to make better decisions


processTokensWithLookahead : List String -> List SimpleToken -> List SimpleToken
processTokensWithLookahead knownMacros tokens =
    case tokens of
        [] ->
            []

        (SimpleWord word1) :: (SimpleSpace space) :: (SimpleWord word2) :: rest ->
            -- Check for "mathbb X" pattern
            if word1 == "mathbb" && String.length word2 == 1 then
                SimpleWord "\\mathbb" :: SimpleBrace "{" word2 :: processTokensWithLookahead knownMacros rest

            else
                SimpleWord word1 :: SimpleSpace space :: processTokensWithLookahead knownMacros (SimpleWord word2 :: rest)

        (SimpleWord word) :: (SimpleSymbol "^") :: rest ->
            -- Word followed by ^ - likely a macro reference
            if isKaTeX word || List.member word knownMacros then
                SimpleWord ("\\" ++ word) :: SimpleSymbol "^" :: processTokensWithLookahead knownMacros rest

            else
                SimpleWord word :: SimpleSymbol "^" :: processTokensWithLookahead knownMacros rest

        (SimpleWord word) :: (SimpleSymbol "(") :: rest ->
            -- Word followed by ( - check if it's a function-like macro
            if (isKaTeX word && needsBraceConversion word) || List.member word knownMacros then
                -- For macros like frac, binom that need brace arguments,
                -- and user-defined macros with parenthesized arguments
                let
                    ( args, remaining ) =
                        extractParenArgs rest []

                    processedArgs =
                        args |> List.map (processTokensWithLookahead knownMacros)
                in
                SimpleWord ("\\" ++ word) :: convertArgsToBraces processedArgs ++ processTokensWithLookahead knownMacros remaining

            else if isKaTeX word then
                SimpleWord ("\\" ++ word) :: SimpleSymbol "(" :: processTokensWithLookahead knownMacros rest

            else
                SimpleWord word :: SimpleSymbol "(" :: processTokensWithLookahead knownMacros rest

        (SimpleWord word) :: rest ->
            -- Check if it's a known function or macro
            if isKaTeX word || List.member word knownMacros then
                SimpleWord ("\\" ++ word) :: processTokensWithLookahead knownMacros rest

            else
                SimpleWord word :: processTokensWithLookahead knownMacros rest

        token :: rest ->
            token :: processTokensWithLookahead knownMacros rest



-- Check if a KaTeX command needs brace conversion


needsBraceConversion : String -> Bool
needsBraceConversion cmd =
    -- Commands that take multiple arguments in braces
    List.member cmd [ "frac", "binom", "overset", "underset", "stackrel", "tfrac", "dfrac", "cfrac", "dbinom", "tbinom" ]



-- Extract arguments from parentheses and remaining tokens


extractParenArgs : List SimpleToken -> List SimpleToken -> ( List (List SimpleToken), List SimpleToken )
extractParenArgs tokens currentArg =
    case tokens of
        [] ->
            if List.isEmpty currentArg then
                ( [], [] )

            else
                ( [ List.reverse currentArg ], [] )

        (SimpleSymbol ")") :: rest ->
            if List.isEmpty currentArg then
                ( [], rest )

            else
                ( [ List.reverse currentArg ], rest )

        (SimpleSymbol ",") :: rest ->
            let
                ( args, remaining ) =
                    extractParenArgs rest []
            in
            ( List.reverse currentArg :: args, remaining )

        token :: rest ->
            extractParenArgs rest (token :: currentArg)



-- Convert comma-separated args to brace notation


convertArgsToBraces : List (List SimpleToken) -> List SimpleToken
convertArgsToBraces args =
    args
        |> List.map (\arg -> SimpleBrace "{" (arg |> List.map tokenToString |> String.concat))



-- Convert token back to string


tokenToString : SimpleToken -> String
tokenToString token =
    case token of
        SimpleWord word ->
            word

        SimpleBackslash ->
            "\\"

        SimpleSpace s ->
            s

        SimpleSymbol s ->
            s

        SimpleBrace open content ->
            open ++ content ++ "}"

        SimpleParam n ->
            "#" ++ String.fromInt n



-- Convert simple macro syntax to LaTeX newcommands


toLaTeXNewCommands : String -> String
toLaTeXNewCommands input =
    input
        |> String.trim
        |> String.lines
        |> List.map String.trim
        |> List.filter (not << String.isEmpty)
        |> List.map simpleMacroToLaTeX
        |> List.filter ((/=) "")
        |> String.join "\n"



-- Convert a single macro line to LaTeX newcommand.
-- Handles both legacy LaTeX-style (\newcommand{...}{...})
-- and new ETeX-style (name : body) definitions.


simpleMacroToLaTeX : String -> String
simpleMacroToLaTeX line =
    if String.startsWith "\\newcommand" line || String.startsWith "\\renewcommand" line then
        -- Legacy LaTeX-style: pass through verbatim
        line

    else if String.contains ":" line then
        -- New ETeX-style: name : body
        case parseSimpleMacroWithContext [] Dict.empty line of
            Just ( name, MacroBody arity _ ) ->
                let
                    processedBody =
                        processSimpleMacroBody (String.split ":" line |> List.drop 1 |> String.join ":" |> String.trim)

                    arityStr =
                        if arity > 0 then
                            "[" ++ String.fromInt arity ++ "]"

                        else
                            ""
                in
                "\\newcommand{\\" ++ name ++ "}" ++ arityStr ++ "{" ++ processedBody ++ "}"

            Nothing ->
                ""

    else
        ""



-- HELPERS


findMaxParam : List MathExpr -> Int
findMaxParam exprs =
    case exprs of
        [] ->
            0

        (Param n) :: rest ->
            max n (findMaxParam rest)

        (Arg innerExprs) :: rest ->
            max (findMaxParam innerExprs) (findMaxParam rest)

        (PArg innerExprs) :: rest ->
            max (findMaxParam innerExprs) (findMaxParam rest)

        (ParenthExpr innerExprs) :: rest ->
            max (findMaxParam innerExprs) (findMaxParam rest)

        (Macro _ args) :: rest ->
            max (findMaxParam args) (findMaxParam rest)

        (FCall _ args) :: rest ->
            max (findMaxParam args) (findMaxParam rest)

        (Expr innerExprs) :: rest ->
            max (findMaxParam innerExprs) (findMaxParam rest)

        (Sub (DecoM expr)) :: rest ->
            max (findMaxParam [ expr ]) (findMaxParam rest)

        (Super (DecoM expr)) :: rest ->
            max (findMaxParam [ expr ]) (findMaxParam rest)

        _ :: rest ->
            findMaxParam rest


makeEntry : Result error NewCommand -> Maybe ( String, MacroBody )
makeEntry newCommand_ =
    case newCommand_ of
        Ok (NewCommand (MacroName name) arity [ Arg body ]) ->
            -- Use the arity from the NewCommand or deduce from parameters
            let
                deducedArity =
                    if arity > 0 then
                        arity

                    else
                        findMaxParam body
            in
            Just ( name, MacroBody deducedArity body )

        _ ->
            Nothing


type Context
    = CArg String


type Problem
    = ExpectingLeftBrace
    | ExpectingAlpha
    | ExpectingNotAlpha
    | ExpectingInt
    | InvalidNumber
    | ExpectingMathSmallSpace
    | ExpectingMathMediumSpace
    | ExpectingLeftBracket
    | ExpectingMathSpace
    | ExpectingRightBracket
    | ExpectingLeftMathBrace
    | ExpectingRightMathBrace
    | ExpectingLeftParen
    | ExpectingRightParen
    | ExpectingUnderscore
    | ExpectingCaret
    | ExpectingSpace
    | ExpectingRightBrace
    | ExpectingHash
    | ExpectingBackslash
    | ExpectingNewCommand
    | ExpectingComma
    | ExpectingQuote
    | ExpectingGreekLetter


type alias MathExprParser a =
    PA.Parser Context Problem a



-- PARSER


parseWithDict : MathMacroDict -> String -> Result (List (DeadEnd Context Problem)) (List MathExpr)
parseWithDict userMacroDict str =
    PA.run (many (mathExprParser userMacroDict)) str


isTextModeCommand : String -> Bool
isTextModeCommand name =
    List.member name [ "text", "textsf", "textbf", "textit", "texttt", "textrm", "textsc", "mbox" ]


chompBraceBalanced : PA.Parser Context Problem ()
chompBraceBalanced =
    loop 0 chompBraceBalancedStep


chompBraceBalancedStep : Int -> PA.Parser Context Problem (Step Int ())
chompBraceBalancedStep depth =
    if depth == 0 then
        oneOf
            [ chompIf (\c -> c == '{') ExpectingLeftBrace |> map (\_ -> Loop 1)
            , chompIf (\c -> c /= '{' && c /= '}') ExpectingNotAlpha |> map (\_ -> Loop 0)
            , succeed (Done ())
            ]

    else
        oneOf
            [ chompIf (\c -> c == '{') ExpectingLeftBrace |> map (\_ -> Loop (depth + 1))
            , chompIf (\c -> c == '}') ExpectingRightBrace |> map (\_ -> Loop (depth - 1))
            , chompIf (\c -> c /= '{' && c /= '}') ExpectingNotAlpha |> map (\_ -> Loop depth)
            ]


rawBraceArg : PA.Parser Context Problem MathExpr
rawBraceArg =
    succeed (\start end src -> Arg [ AlphaNum (String.slice start end src) ])
        |. symbol (Token "{" ExpectingLeftBrace)
        |= getOffset
        |. chompBraceBalanced
        |= getOffset
        |= getSource
        |. symbol (Token "}" ExpectingRightBrace)


macroParser : MathMacroDict -> PA.Parser Context Problem MathExpr
macroParser userMacroDict =
    succeed identity
        |. symbol (Token "\\" ExpectingBackslash)
        |= oneOf
            [ alphaNumParser_
                |> PA.andThen
                    (\name ->
                        if isTextModeCommand name then
                            many rawBraceArg |> map (\args -> Macro name args)

                        else
                            many (argParser userMacroDict) |> map (\args -> Macro name args)
                    )

            -- LaTeX control symbol: a backslash followed by a single
            -- non-alphanumeric character, e.g. \$ \% \& \# \_
            , controlSymbolParser
            ]


{-| Parse a LaTeX control symbol — a single non-alphanumeric character whose
leading backslash has already been consumed by `macroParser`. The result
prints back verbatim (e.g. `\$` renders as a literal dollar sign in KaTeX).
-}
controlSymbolParser : PA.Parser Context Problem MathExpr
controlSymbolParser =
    succeed (\start end src -> AlphaNum ("\\" ++ String.slice start end src))
        |= getOffset
        |. chompIf (\c -> not (Char.isAlphaNum c)) ExpectingNotAlpha
        |= getOffset
        |= getSource



-- Parser that parses comma-separated function arguments


functionArgsParser : MathMacroDict -> PA.Parser Context Problem (List MathExpr)
functionArgsParser userMacroDict =
    succeed identity
        |. symbol (Token "(" ExpectingLeftParen)
        |= lazy (\_ -> functionArgListParser userMacroDict)
        |. symbol (Token ")" ExpectingRightParen)



-- Helper to parse comma-separated arguments


functionArgListParser : MathMacroDict -> PA.Parser Context Problem (List MathExpr)
functionArgListParser userMacroDict =
    let
        -- Parse content that can appear in an argument (excluding commas)
        argContentParser =
            oneOf
                [ textParser -- Parse quoted text
                , mathMediumSpaceParser
                , mathSmallSpaceParser
                , mathSpaceParser
                , leftBraceParser
                , rightBraceParser
                , macroParser userMacroDict
                , lazy (\_ -> alphaNumWithLookaheadParser userMacroDict) -- Check if alphaNum is a macro (with lookahead for nested calls like bvec(p))
                , mathSymbolsParser
                , lazy (\_ -> argParser userMacroDict)
                , lazy (\_ -> standaloneParenthExprParser userMacroDict)
                , paramParser
                , whitespaceParser
                , f0Parser
                , subscriptParser userMacroDict
                , superscriptParser userMacroDict
                ]
    in
    sepByComma (PA.map PArg (many1 argContentParser))



-- Parse alpha numeric without lookahead (to avoid recursion)


-- Helper for parsing one or more items


many1 : PA.Parser Context Problem a -> PA.Parser Context Problem (List a)
many1 p =
    succeed (::)
        |= p
        |= many p



-- Parse items separated by commas, returning the items and commas


sepByComma : PA.Parser Context Problem MathExpr -> PA.Parser Context Problem (List MathExpr)
sepByComma itemParser =
    oneOf
        [ -- Parse at least one item
          itemParser
            |> PA.andThen
                (\firstItem ->
                    loop [ firstItem ] (sepByCommaHelp itemParser)
                )
        , -- Empty case
          succeed []
        ]



-- Helper for parsing more comma-separated items


sepByCommaHelp : PA.Parser Context Problem MathExpr -> List MathExpr -> PA.Parser Context Problem (Step (List MathExpr) (List MathExpr))
sepByCommaHelp itemParser revItems =
    oneOf
        [ -- Try to parse comma and another item
          succeed (\item -> Loop (item :: Comma :: revItems))
            |. symbol (Token "," ExpectingComma)
            |= itemParser
        , -- No more items
          succeed (Done (List.reverse revItems))
        ]



-- Parser for quoted text


textParser : PA.Parser Context Problem MathExpr
textParser =
    succeed Text
        |. symbol (Token "\"" ExpectingQuote)
        |= getChompedString (chompWhile (\c -> c /= '"'))
        |. symbol (Token "\"" ExpectingQuote)



--greekLetterParser : PA.Parser Context Problem MathExpr
--greekLetterParser =
--    succeed AlphaNum
--        |. symbol (Token "\\" ExpectingBackslash)
--        |= greekLetterNameParser
--
-- Parser that looks for function calls with lookahead


alphaNumWithLookaheadParser : MathMacroDict -> PA.Parser Context Problem MathExpr
alphaNumWithLookaheadParser userMacroDict =
    succeed identity
        |= alphaNumParser_
        |> PA.andThen
            (\name ->
                oneOf
                    [ -- Check if followed by '(' and parse comma-separated arguments
                      -- backtrackable: if argument parsing fails (e.g. \, inside parens),
                      -- fall back to treating the identifier as plain AlphaNum
                      backtrackable (functionArgsParser userMacroDict)
                        |> PA.map
                            (\args ->
                                if isKaTeX name || isUserDefinedMacro userMacroDict name then
                                    Macro name args

                                else
                                    FCall name args
                            )
                    , -- Otherwise, check if it's a macro or just alphanumeric
                      succeed
                        (if isKaTeX name || isUserDefinedMacro userMacroDict name then
                            Macro name []

                         else
                            AlphaNum name
                        )
                    ]
            )


mathExprParser : MathMacroDict -> PA.Parser Context Problem MathExpr
mathExprParser userMacroDict =
    oneOf
        [ textParser -- Parse quoted text first
        , backtrackable greekSymbolParser -- For Greek letters without lookahead
        , mathMediumSpaceParser
        , mathSmallSpaceParser
        , mathSpaceParser
        , leftBraceParser
        , rightBraceParser
        , backtrackable lineBreakParser
        , alphaNumWithLookaheadParser userMacroDict -- This handles both function calls and plain alphanums
        , macroParser userMacroDict
        , backtrackable (lazy (\_ -> standaloneParenthExprParser userMacroDict)) -- For standalone parentheses
        , leftParenParser -- Fallback: bare ( when standaloneParenthExprParser backtracks
        , rightParenParser -- Bare )
        , commaParser
        , mathSymbolsParser
        , lazy (\_ -> argParser userMacroDict)
        , paramParser
        , whitespaceParser
        , f0Parser
        , subscriptParser userMacroDict
        , superscriptParser userMacroDict
        ]


greekSymbolParser : PA.Parser Context Problem MathExpr
greekSymbolParser =
    succeed identity
        |= alphaNumParser_
        |> PA.andThen
            (\str ->
                if List.member str ETeX.KaTeX.greekLetters then
                    succeed (AlphaNum ("\\" ++ str))

                else
                    PA.problem ExpectingGreekLetter
            )


mathSymbolsParser =
    (succeed String.slice
        |= getOffset
        |. chompIf (\c -> not (Char.isAlpha c) && not (List.member c [ '_', '^', '#', '\\', '{', '}', '(', ')', ',', '"' ])) ExpectingNotAlpha
        |. chompWhile (\c -> not (Char.isAlpha c) && not (List.member c [ '_', '^', '#', '\\', '{', '}', '(', ')', ',', '"' ]))
        |= getOffset
        |= getSource
    )
        |> PA.map MathSymbols


optionalParamParser =
    succeed identity
        |. symbol (Token "[" ExpectingLeftBracket)
        |= PA.int ExpectingInt InvalidNumber
        |. symbol (Token "]" ExpectingRightBracket)


parseNewCommand : MathMacroDict -> String -> Result (List (DeadEnd Context Problem)) NewCommand
parseNewCommand userMacroDict str =
    run (newCommandParser userMacroDict) str


newCommandParser : MathMacroDict -> PA.Parser Context Problem NewCommand
newCommandParser userMacroDict =
    oneOf [ backtrackable (newCommandParser1 userMacroDict), newCommandParser2 userMacroDict ]


mathSpaceParser : PA.Parser c Problem MathExpr
mathSpaceParser =
    succeed MathSpace
        |. symbol (Token "\\ " ExpectingMathSpace)


mathSmallSpaceParser : PA.Parser c Problem MathExpr
mathSmallSpaceParser =
    succeed MathSmallSpace
        |. symbol (Token "\\," ExpectingMathSmallSpace)


mathMediumSpaceParser : PA.Parser c Problem MathExpr
mathMediumSpaceParser =
    succeed MathMediumSpace
        |. symbol (Token "\\;" ExpectingMathMediumSpace)


lineBreakParser : PA.Parser c Problem MathExpr
lineBreakParser =
    succeed (MathSymbols "\\\\")
        |. symbol (Token "\\\\" ExpectingBackslash)


leftBraceParser : PA.Parser c Problem MathExpr
leftBraceParser =
    succeed LeftMathBrace
        |. symbol (Token "\\{" ExpectingLeftMathBrace)


rightBraceParser : PA.Parser c Problem MathExpr
rightBraceParser =
    succeed RightMathBrace
        |. symbol (Token "\\}" ExpectingRightMathBrace)



leftParenParser : PA.Parser c Problem MathExpr
leftParenParser =
    succeed LeftParen
        |. symbol (Token "(" ExpectingLeftParen)


rightParenParser : PA.Parser c Problem MathExpr
rightParenParser =
    succeed RightParen
        |. symbol (Token ")" ExpectingRightParen)


commaParser : PA.Parser c Problem MathExpr
commaParser =
    succeed Comma
        |. symbol (Token "," ExpectingComma)


newCommandParser1 : MathMacroDict -> PA.Parser Context Problem NewCommand
newCommandParser1 userMacroDict =
    succeed (\name arity body -> NewCommand name arity body)
        |. symbol (Token "\\newcommand" ExpectingNewCommand)
        |. symbol (Token "{" ExpectingLeftBrace)
        |= f0Parser
        |. symbol (Token "}" ExpectingRightBrace)
        |= optionalParamParser
        |= many (mathExprParser userMacroDict)


newCommandParser2 : MathMacroDict -> PA.Parser Context Problem NewCommand
newCommandParser2 userMacroDict =
    succeed (\name body -> NewCommand name 0 body)
        |. symbol (Token "\\newcommand" ExpectingNewCommand)
        |. symbol (Token "{" ExpectingLeftBrace)
        |= f0Parser
        |. symbol (Token "}" ExpectingRightBrace)
        |= many (mathExprParser userMacroDict)


argParser : MathMacroDict -> PA.Parser Context Problem MathExpr
argParser userMacroDict =
    (succeed identity
        |. symbol (Token "{" ExpectingLeftBrace)
        |= lazy (\_ -> many (mathExprParser userMacroDict))
    )
        |. symbol (Token "}" ExpectingRightBrace)
        |> PA.map Arg



-- Removed unused parsers: parentheticalExprParser and parentheticalExprParserM


standaloneParenthExprParser : MathMacroDict -> PA.Parser Context Problem MathExpr
standaloneParenthExprParser userMacroDict =
    (succeed identity
        |. symbol (Token "(" ExpectingLeftParen)
        |= lazy (\_ -> many (mathExprParserInsideParens userMacroDict))
    )
        |. symbol (Token ")" ExpectingRightParen)
        |> PA.map ParenthExpr


{-| Like mathExprParser but without rightParenParser.

Inside a parenthesized expression, `)` must NOT be consumed as a RightParen node
by the inner parser. Instead, `)` should be invisible to the inner `many` loop so
it stops, allowing standaloneParenthExprParser's own `)` delimiter to consume it.
Nested parens are handled by recursive standaloneParenthExprParser calls.
-}
mathExprParserInsideParens : MathMacroDict -> PA.Parser Context Problem MathExpr
mathExprParserInsideParens userMacroDict =
    oneOf
        [ textParser
        , backtrackable greekSymbolParser
        , mathMediumSpaceParser
        , mathSmallSpaceParser
        , mathSpaceParser
        , leftBraceParser
        , rightBraceParser
        , alphaNumWithLookaheadParser userMacroDict
        , macroParser userMacroDict
        , backtrackable (lazy (\_ -> standaloneParenthExprParser userMacroDict))
        , leftParenParser
        , commaParser
        , mathSymbolsParser
        , lazy (\_ -> argParser userMacroDict)
        , paramParser
        , whitespaceParser
        , f0Parser
        , subscriptParser userMacroDict
        , superscriptParser userMacroDict
        ]


whitespaceParser =
    symbol (Token " " ExpectingSpace) |> PA.map (\_ -> WS)



-- Removed unused parser: alphaNumParser


alphaNumParser_ : PA.Parser c Problem String
alphaNumParser_ =
    succeed String.slice
        |= getOffset
        |. chompIf Char.isAlpha ExpectingAlpha
        |. chompWhile Char.isAlphaNum
        |= getOffset
        |= getSource


f0Parser : PA.Parser Context Problem MathExpr
f0Parser =
    second (symbol (Token "\\" ExpectingBackslash)) alphaNumParser_
        |> PA.map MacroName


paramParser =
    (succeed identity
        |. symbol (Token "#" ExpectingHash)
        |= PA.int ExpectingInt InvalidNumber
    )
        |> PA.map Param


subscriptParser : MathMacroDict -> PA.Parser Context Problem MathExpr
subscriptParser userMacroDict =
    (succeed identity
        |. symbol (Token "_" ExpectingUnderscore)
        |= decoParser userMacroDict
    )
        |> PA.map Sub


superscriptParser : MathMacroDict -> PA.Parser Context Problem MathExpr
superscriptParser userMacroDict =
    (succeed identity
        |. symbol (Token "^" ExpectingCaret)
        |= decoParser userMacroDict
    )
        |> PA.map Super


decoParser : MathMacroDict -> PA.Parser Context Problem Deco
decoParser userMacroDict =
    oneOf [ backtrackable numericDecoParser, lazy (\_ -> mathExprParser userMacroDict) |> PA.map DecoM ]


numericDecoParser =
    PA.int ExpectingInt InvalidNumber |> PA.map DecoI



-- PRINT



printList : List MathExpr -> String
printList exprs =
    List.map print exprs |> String.concat


print : MathExpr -> String
print expr =
    case expr of
        AlphaNum str ->
            str

        LeftMathBrace ->
            "\\{"

        RightMathBrace ->
            "\\}"

        LeftParen ->
            "("

        RightParen ->
            ")"

        MathSmallSpace ->
            "\\,"

        MathMediumSpace ->
            "\\;"

        MathSpace ->
            "\\ "

        MacroName str ->
            "\\" ++ str

        FunctionName str ->
            str

        Param k ->
            "#" ++ String.fromInt k

        Arg exprs ->
            encloseB (printList exprs)

        PArg exprs ->
            encloseP (printList exprs)

        Sub deco ->
            -- "_" ++ enclose (printDeco deco)
            "_" ++ printDeco deco

        Super deco ->
            -- "^" ++ enclose (printDeco deco)
            "^" ++ printDeco deco

        MathSymbols str ->
            str

        WS ->
            " "

        Macro name body ->
            case body of
                [ PArg exprs ] ->
                    -- Single argument in parentheses: convert to braces
                    "\\" ++ name ++ encloseB (printList exprs)

                [ ParenthExpr exprs ] ->
                    -- Convert parentheses to braces for macro
                    "\\" ++ name ++ encloseB (printList exprs)

                _ ->
                    -- Multiple arguments or complex case
                    case body of
                        (PArg _) :: _ ->
                            -- Comma-separated arguments: each gets its own braces
                            "\\" ++ name ++ printMacroArgs body

                        _ ->
                            "\\" ++ name ++ printList body

        FCall name args ->
            -- Function calls always use parentheses
            name ++ "(" ++ printArgList args ++ ")"

        Expr exprs ->
            List.map print exprs |> String.concat

        Comma ->
            ","

        ParenthExpr exprs ->
            encloseP (printList exprs)

        Text str ->
            "\\text{" ++ str ++ "}"

        GreekSymbol str ->
            "\\" ++ str


printDeco : Deco -> String
printDeco deco =
    case deco of
        DecoM expr ->
            print expr

        DecoI k ->
            String.fromInt k



-- PRINT (ETeX form — used by inverseTransformETeX)


printETeXList : List MathExpr -> String
printETeXList exprs =
    List.map printETeX exprs |> String.concat


printETeX : MathExpr -> String
printETeX expr =
    case expr of
        Macro name body ->
            printETeXMacro name body

        Arg exprs ->
            encloseB (printETeXList exprs)

        PArg exprs ->
            encloseP (printETeXList exprs)

        ParenthExpr exprs ->
            encloseP (printETeXList exprs)

        Sub deco ->
            "_" ++ printETeXDeco deco

        Super deco ->
            "^" ++ printETeXDeco deco

        Expr exprs ->
            printETeXList exprs

        AlphaNum str ->
            str

        LeftMathBrace ->
            "\\{"

        RightMathBrace ->
            "\\}"

        LeftParen ->
            "("

        RightParen ->
            ")"

        MathSmallSpace ->
            "\\,"

        MathMediumSpace ->
            "\\;"

        MathSpace ->
            "\\ "

        MacroName str ->
            "\\" ++ str

        FunctionName str ->
            str

        Param k ->
            "#" ++ String.fromInt k

        MathSymbols str ->
            str

        WS ->
            " "

        Comma ->
            ","

        FCall name args ->
            name ++ "(" ++ printETeXArgList args ++ ")"

        Text str ->
            "\"" ++ str ++ "\""

        GreekSymbol str ->
            str


printETeXDeco : Deco -> String
printETeXDeco deco =
    case deco of
        DecoM expr ->
            printETeX expr

        DecoI k ->
            String.fromInt k


{-| Render a parsed Macro in ETeX form:

  - `Macro "sin" []`                           → `"sin"`
  - `Macro "sin" [Arg [x^2]]`                  → `"sin(x^2)"`
  - `Macro "frac" [Arg [1], Arg [2]]`          → `"frac(1,2)"`

If the body contains something other than `Arg` nodes, we cannot cleanly
re-express the macro in ETeX form, so we fall back to LaTeX form.

-}
printETeXMacro : String -> List MathExpr -> String
printETeXMacro name body =
    case ( name, body ) of
        ( "text", [ Arg [ AlphaNum str ] ] ) ->
            -- Inverse of `Text str -> "\\text{" ++ str ++ "}"` in `print`.
            -- Only applies to simple text (no backslash); other shapes fall
            -- through to the default macro rendering below.
            if String.contains "\\" str then
                defaultPrintETeXMacro name body

            else
                "\"" ++ str ++ "\""

        _ ->
            defaultPrintETeXMacro name body


defaultPrintETeXMacro : String -> List MathExpr -> String
defaultPrintETeXMacro name body =
    case body of
        [] ->
            name

        _ ->
            if List.all isArgNode body then
                name
                    ++ "("
                    ++ (body |> List.map printETeXArgInner |> String.join ",")
                    ++ ")"

            else
                "\\" ++ name ++ printETeXList body


isArgNode : MathExpr -> Bool
isArgNode expr =
    case expr of
        Arg _ ->
            True

        _ ->
            False


{-| When a Macro body is a list of `Arg` nodes, render each argument's
interior (without the surrounding braces), so that `Arg [AlphaNum "1"]`
prints as `"1"` rather than `"{1}"`.
-}
printETeXArgInner : MathExpr -> String
printETeXArgInner expr =
    case expr of
        Arg exprs ->
            printETeXList exprs

        _ ->
            printETeX expr


{-| Mirror of `printArgList`, but recursing via `printETeX` so that any
nested macros are also rendered in ETeX form.
-}
printETeXArgList : List MathExpr -> String
printETeXArgList exprs =
    case exprs of
        [] ->
            ""

        [ PArg contents ] ->
            printETeXList contents

        (PArg contents) :: Comma :: rest ->
            printETeXList contents ++ "," ++ printETeXArgList rest

        (PArg contents) :: rest ->
            printETeXList contents ++ printETeXArgList rest

        other :: rest ->
            printETeX other ++ printETeXArgList rest



-- HELPERS


second : MathExprParser a -> MathExprParser b -> MathExprParser b
second p q =
    p |> PA.andThen (\_ -> q)


{-| Apply a parser zero or more times and return a list of the results.
-}
many : MathExprParser a -> MathExprParser (List a)
many p =
    loop [] (manyHelp p)


manyHelp : MathExprParser a -> List a -> MathExprParser (Step (List a) (List a))
manyHelp p vs =
    oneOf
        [ succeed (\v -> Loop (v :: vs))
            |= p

        -- |. PA.spaces
        , succeed ()
            |> map (\_ -> Done (List.reverse vs))
        ]


encloseB : String -> String
encloseB str =
    "{" ++ str ++ "}"


encloseP : String -> String
encloseP str =
    "(" ++ str ++ ")"



-- Print a list of arguments (handling comma separation)


printArgList : List MathExpr -> String
printArgList exprs =
    case exprs of
        [] ->
            ""

        [ PArg contents ] ->
            printList contents

        (PArg contents) :: Comma :: rest ->
            printList contents ++ "," ++ printArgList rest

        (PArg contents) :: rest ->
            printList contents ++ printArgList rest

        other :: rest ->
            print other ++ printArgList rest



-- Print macro arguments where each comma-separated arg gets its own braces


printMacroArgs : List MathExpr -> String
printMacroArgs exprs =
    case exprs of
        [] ->
            ""

        [ PArg contents ] ->
            encloseB (printList contents)

        (PArg contents) :: Comma :: rest ->
            encloseB (printList contents) ++ printMacroArgs rest

        (PArg contents) :: rest ->
            encloseB (printList contents) ++ printMacroArgs rest

        other :: rest ->
            print other ++ printMacroArgs rest
