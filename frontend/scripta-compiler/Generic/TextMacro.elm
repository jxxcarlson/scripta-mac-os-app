module Generic.TextMacro exposing
    ( buildDictionary
    , expand
    , exportTexMacros
    , extract
    , getTextMacroFunctionNames
    , toString
    )

import Dict exposing (Dict)
import Generic.ASTTools as AT
import List.Extra
import V3.Types exposing (Expr(..), Expression, Macro)


extract : Expression -> Maybe Macro
extract expr_ =
    case expr_ of
        Fun "macro" ((Text argString _) :: exprs) _ ->
            case String.words (String.trim argString) of
                name :: rest ->
                    Just { name = name, vars = rest, body = exprs }

                _ ->
                    Nothing

        _ ->
            Nothing


toString : (Expression -> String) -> Macro -> String
toString exprToString macro =
    [ "\\newcommand{\\"
    , macro.name
    , "}["
    , String.fromInt (List.length macro.vars)
    , "]{"
    , macro.body |> List.map exprToString |> String.join ""
    , "}    "
    ]
        |> String.join ""


toLaTeXString : Expression -> String
toLaTeXString expr =
    case expr of
        Fun name expressions _ ->
            let
                body_ =
                    List.map toLaTeXString expressions |> String.join ""

                body =
                    if body_ == "" then
                        body_

                    else if String.left 1 body_ == "[" then
                        body_

                    else if String.left 1 body_ == " " then
                        body_

                    else
                        " " ++ body_
            in
            "\\" ++ name ++ "{" ++ body ++ "}"

        Text str _ ->
            str

        VFun name str _ ->
            case name of
                "math" ->
                    "$" ++ str ++ "$"

                "code" ->
                    "`" ++ str ++ "`"

                _ ->
                    "error: verbatim " ++ name ++ " not recognized"

        ExprList _ _ _ ->
            "[ExprList]"


printLaTeXMacro : Macro -> String
printLaTeXMacro macro =
    if List.length macro.vars == 0 then
        "\\newcommand{\\"
            ++ macro.name
            ++ "}{"
            ++ (List.map toLaTeXString macro.body |> String.join "")
            ++ "}"

    else
        "\\newcommand{\\"
            ++ macro.name
            ++ "}"
            ++ "["
            ++ String.fromInt (List.length macro.vars)
            ++ "]{"
            ++ (List.map toLaTeXString macro.body |> String.join "")
            ++ "}"


buildDictionary : List String -> Dict String Macro
buildDictionary _ =
    -- NOTE: Full macro parsing requires Scripta.Expression which is not in V3.
    -- Text macros defined in documents will not be expanded in PDF export.
    Dict.empty


getTextMacroFunctionNames : String -> List String
getTextMacroFunctionNames str =
    str
        |> String.lines
        |> buildDictionary
        |> Dict.toList
        |> List.map Tuple.second
        |> List.map .body
        |> List.map functionNames
        |> List.concat
        |> List.Extra.unique
        |> List.sort


functionNames : List Expression -> List String
functionNames exprs =
    List.map functionNames_ exprs |> List.concat


functionNames_ : Expression -> List String
functionNames_ expr =
    case expr of
        Fun name body _ ->
            name :: (List.map functionNames_ body |> List.concat)

        Text _ _ ->
            []

        VFun _ _ _ ->
            []

        ExprList _ _ _ ->
            []


exportTexMacros : String -> String
exportTexMacros str =
    str
        |> String.lines
        |> buildDictionary
        |> Dict.toList
        |> List.map Tuple.second
        |> List.map printLaTeXMacro
        |> String.join "\n"


expand : Dict String Macro -> Expression -> Expression
expand dict expr =
    case expr of
        Fun name _ _ ->
            case Dict.get name dict of
                Nothing ->
                    expr

                Just macro ->
                    expandWithMacro macro expr

        _ ->
            expr


expandWithMacro : Macro -> Expression -> Expression
expandWithMacro macro expr =
    case expr of
        Fun name fArgs _ ->
            if name == macro.name then
                listSubst (fArgs |> filterOutBlanks) macro.vars macro.body |> group

            else
                expr

        _ ->
            expr


listSubst : List Expression -> List String -> List Expression -> List Expression
listSubst as_ vars exprs =
    if List.length as_ /= List.length vars then
        exprs

    else
        let
            funcs =
                List.map2 makeF as_ vars
        in
        List.foldl (\func acc -> func acc) exprs funcs


subst : Expression -> String -> Expression -> Expression
subst a var body =
    case body of
        Text str _ ->
            if String.trim str == String.trim var then
                a

            else if String.contains var str then
                let
                    parts =
                        String.split var str |> List.map (\s -> Text s dummy)
                in
                List.intersperse a parts |> group

            else
                body

        Fun name exprs meta ->
            Fun name (List.map (subst a var) exprs) meta

        _ ->
            body


group : List Expression -> Expression
group exprs =
    Fun "group" exprs dummy


makeF : Expression -> String -> (List Expression -> List Expression)
makeF a var =
    List.map (subst a var)


filterOutBlanks : List Expression -> List Expression
filterOutBlanks =
    AT.filterExprs (\e -> not (AT.isBlank e))


dummy : V3.Types.ExprMeta
dummy =
    { begin = 0, end = 0, index = 0, id = "dummyId" }
