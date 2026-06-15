module Parser.PrimitiveBlock exposing (parse)

{-| Parse a list of strings into a list of primitive blocks.

NOTE (TODO) for the moment we assume that the input ends with
a blank line.

-}

import Dict exposing (Dict)
import Parser.Line as Line exposing (Line)
import Tools.KV
import Tools.Loop exposing (Step(..), loop)
import V3.Types exposing (BlockMeta, Heading(..), PrimitiveBlock)


verbatimNames : List String
verbatimNames =
    [ "math"
    , "chem"
    , "compute"
    , "equation"
    , "aligned"
    , "array"
    , "textarray"
    , "table"
    , "code"
    , "verse"
    , "verbatim"
    , "load"
    , "load-data"
    , "load-files"
    , "include"
    , "hide"
    , "texComment"
    , "docinfo"
    , "mathmacros"
    , "textmacros"
    , "csvtable"
    , "chart"
    , "svg"
    , "quiver"
    , "image"
    , "tikz"
    , "setup"
    , "iframe"
    , "settings"
    , "book"
    , "article"
    ]


{-| Parse a list of strings into a list of PrimitiveBlocks.
-}
parse : List String -> List PrimitiveBlock
parse lines =
    loop (init lines) nextStep



-- STATE


type alias State =
    { blocks : List PrimitiveBlock -- accumulated blocks (reversed)
    , currentBlock : Maybe PrimitiveBlock -- block being built
    , lines : List String -- remaining input lines
    , inBlock : Bool -- are we currently in a block?
    , indent : Int -- current indentation level
    , lineNumber : Int -- current line number
    , position : Int -- character position in source
    , inVerbatim : Bool -- are we in a verbatim block?
    , blocksCommitted : Int -- number of committed blocks
    , inHeader : Bool -- are we still in the extended header (continuation lines)?
    }


init : List String -> State
init lines =
    { blocks = []
    , currentBlock = Nothing
    , lines = lines
    , inBlock = False
    , indent = 0
    , lineNumber = 0
    , position = 0
    , inVerbatim = False
    , blocksCommitted = 0
    , inHeader = False
    }



-- MAIN LOOP


nextStep : State -> Step State (List PrimitiveBlock)
nextStep state =
    case List.head state.lines of
        Nothing ->
            -- No more lines: finalize and return
            case state.currentBlock of
                Nothing ->
                    Done (List.reverse state.blocks)

                Just block ->
                    let
                        finalBlock =
                            finalize block
                    in
                    Done (List.reverse (finalBlock :: state.blocks))

        Just rawLine ->
            let
                currentLine =
                    Line.classify state.position state.lineNumber rawLine

                isEmpty =
                    currentLine.indent == 0 && String.isEmpty (String.trim currentLine.content)

                isNonEmptyBlank =
                    currentLine.indent > 0 && String.isEmpty (String.trim (String.dropLeft currentLine.indent currentLine.content))
            in
            case ( state.inBlock, isEmpty, isNonEmptyBlank ) of
                -- State 1: Not in block, empty line -> skip
                ( False, True, _ ) ->
                    Loop (advance currentLine state)

                -- State 2: Not in block, non-empty blank line -> skip
                ( False, False, True ) ->
                    Loop (advance currentLine state)

                -- State 3: Not in block, content line -> create new block
                ( False, False, False ) ->
                    Loop (createBlock currentLine state)

                -- State 4: In block, non-empty content -> add line
                ( True, False, _ ) ->
                    Loop (addCurrentLine currentLine state)

                -- State 5: In block, empty line -> commit block
                ( True, True, _ ) ->
                    Loop (commitBlock currentLine state)



-- HELPER FUNCTIONS


{-| Advance to the next line.
-}
advance : Line -> State -> State
advance line state =
    let
        newPosition =
            state.position + String.length line.content + 1
    in
    { state
        | lines = List.drop 1 state.lines
        , lineNumber = state.lineNumber + 1
        , position = newPosition
    }


{-| Create a new block from the current line.
-}
createBlock : Line -> State -> State
createBlock line state =
    let
        -- Commit any existing block first
        newState =
            case state.currentBlock of
                Nothing ->
                    state

                Just block ->
                    { state
                        | blocks = finalize block :: state.blocks
                        , blocksCommitted = state.blocksCommitted + 1
                    }

        newBlock =
            blockFromLine line newState

        newPosition =
            state.position + String.length line.content + 1
    in
    { newState
        | currentBlock = Just newBlock
        , lines = List.drop 1 state.lines
        , lineNumber = state.lineNumber + 1
        , position = newPosition
        , inBlock = True
        , indent = line.indent
        , inVerbatim = isVerbatimLine line.content
        , inHeader = isBlockWithHeader newBlock
    }


{-| Create a PrimitiveBlock from a Line.
-}
blockFromLine : Line -> State -> PrimitiveBlock
blockFromLine line state =
    let
        headingData =
            getHeadingData line.content

        bodyLineNumber =
            case headingData.heading of
                Paragraph ->
                    line.lineNumber

                _ ->
                    line.lineNumber + 1

        -- True for blocks whose first source line is a discardable header
        -- (| name, || name, $$, ```). Detected via firstLine == "": those
        -- heading parsers store an empty firstLine because the raw heading
        -- line is not kept as block content. Paragraph blocks with an empty
        -- first line are excluded explicitly.
        hasHeaderLine =
            headingData.firstLine == "" && headingData.heading /= Paragraph

        contentBegin_ =
            if hasHeaderLine then
                line.position + String.length line.content + 1

            else
                line.position

        contentEnd_ =
            if hasHeaderLine then
                contentBegin_

            else
                line.position + String.length line.content

        meta : BlockMeta
        meta =
            { id = ""
            , position = line.position
            , lineNumber = line.lineNumber
            , bodyLineNumber = bodyLineNumber
            , numberOfLines = 1
            , begin = line.position
            , end = line.position + String.length line.content
            , contentBegin = contentBegin_
            , contentEnd = contentEnd_
            , messages = []
            , sourceText = line.content
            , error = Nothing
            }
    in
    { heading = headingData.heading
    , indent = line.indent
    , args = headingData.args
    , properties = headingData.properties
    , firstLine = headingData.firstLine
    , body = []
    , meta = meta
    , style = {}
    }


{-| Add the current line to the block being built.

Includes list coalescing: when consecutive item or numbered lines are found,
the block heading changes to itemList or numberedList respectively.

Also handles continuation lines for extended header syntax.

-}
addCurrentLine : Line -> State -> State
addCurrentLine line state =
    let
        newPosition =
            state.position + String.length line.content + 1

        -- Check if this is a continuation line for extended header syntax
        currentIsVerbatim =
            case Maybe.map .heading state.currentBlock of
                Just (Verbatim _) ->
                    True

                _ ->
                    False

        isContinuation =
            state.inHeader && isContinuationLine currentIsVerbatim line.content
    in
    if isContinuation then
        -- Merge continuation line's args/properties into the current block
        { state
            | currentBlock = Maybe.map (mergeContinuationLine line) state.currentBlock
            , lines = List.drop 1 state.lines
            , lineNumber = state.lineNumber + 1
            , position = newPosition
        }

    else
        -- Normal line processing (end of header, now in body)
        let
            -- Check if this line has the same list heading as current block
            lineHeading =
                inspectHeading line.content

            currentHeading =
                Maybe.map .heading state.currentBlock

            -- Coalesce lists: item -> itemList, numbered -> numberedList
            coalescedBlock =
                case ( currentHeading, lineHeading ) of
                    ( Just (Ordinary "item"), Just (Ordinary "item") ) ->
                        state.currentBlock
                            |> Maybe.map (\b -> { b | heading = Ordinary "itemList" })
                            |> Maybe.map (addListLineToBlock line)

                    ( Just (Ordinary "itemList"), Just (Ordinary "item") ) ->
                        state.currentBlock
                            |> Maybe.map (addListLineToBlock line)

                    ( Just (Ordinary "numbered"), Just (Ordinary "numbered") ) ->
                        state.currentBlock
                            |> Maybe.map (\b -> { b | heading = Ordinary "numberedList" })
                            |> Maybe.map (addListLineToBlock line)

                    ( Just (Ordinary "numberedList"), Just (Ordinary "numbered") ) ->
                        state.currentBlock
                            |> Maybe.map (addListLineToBlock line)

                    ( Just (Ordinary "itemList"), Nothing ) ->
                        -- Continuation of last item in list
                        state.currentBlock
                            |> Maybe.map (appendToLastListItem line)

                    ( Just (Ordinary "numberedList"), Nothing ) ->
                        -- Continuation of last numbered item in list
                        state.currentBlock
                            |> Maybe.map (appendToLastListItem line)

                    _ ->
                        state.currentBlock
                            |> Maybe.map (addLineToBlock line)
        in
        { state
            | currentBlock = coalescedBlock
            , lines = List.drop 1 state.lines
            , lineNumber = state.lineNumber + 1
            , position = newPosition
            , inHeader = False
        }


{-| Inspect a line to determine what heading it would produce.
-}
inspectHeading : String -> Maybe Heading
inspectHeading content =
    let
        trimmed =
            String.trim content
    in
    if String.startsWith "- " trimmed then
        Just (Ordinary "item")

    else if String.startsWith ". " trimmed then
        Just (Ordinary "numbered")

    else
        Nothing


{-| Add a list item line to a block, preserving indentation and list prefix.
-}
addListLineToBlock : Line -> PrimitiveBlock -> PrimitiveBlock
addListLineToBlock line block =
    let
        -- Preserve full line content including indentation and prefix
        -- This allows nested list items to be identified by their indent
        contentToAdd =
            line.content

        meta =
            block.meta
    in
    { block
        | body = contentToAdd :: block.body
        , meta = { meta | numberOfLines = meta.numberOfLines + 1 }
    }


{-| Append a continuation line to the last list item in a list block.
-}
appendToLastListItem : Line -> PrimitiveBlock -> PrimitiveBlock
appendToLastListItem line block =
    let
        contentToAdd =
            String.trim line.content

        meta =
            block.meta

        -- body is in reverse order, so first element is the last item
        updatedBody =
            case block.body of
                lastItem :: rest ->
                    (lastItem ++ " " ++ contentToAdd) :: rest

                [] ->
                    [ contentToAdd ]
    in
    { block
        | body = updatedBody
        , meta = { meta | numberOfLines = meta.numberOfLines + 1 }
    }


{-| Add a line to a block's body.
-}
addLineToBlock : Line -> PrimitiveBlock -> PrimitiveBlock
addLineToBlock line block =
    let
        -- Determine the content to add based on block type
        contentToAdd =
            if block.indent > 0 && line.indent >= block.indent then
                -- For indented blocks, drop the indent prefix
                String.dropLeft block.indent line.content

            else
                line.content

        meta =
            block.meta
    in
    { block
        | body = contentToAdd :: block.body -- prepend (will reverse later)
        , meta = { meta | numberOfLines = meta.numberOfLines + 1 }
    }


{-| Commit the current block and reset for the next one.
-}
commitBlock : Line -> State -> State
commitBlock line state =
    let
        newPosition =
            state.position + String.length line.content + 1

        committedBlocks =
            case state.currentBlock of
                Nothing ->
                    state.blocks

                Just block ->
                    let
                        finalBlock =
                            finalize block
                                |> setBlockId state.blocksCommitted
                    in
                    finalBlock :: state.blocks
    in
    { state
        | blocks = committedBlocks
        , currentBlock = Nothing
        , lines = List.drop 1 state.lines
        , lineNumber = state.lineNumber + 1
        , position = newPosition
        , inBlock = False
        , inVerbatim = False
        , blocksCommitted = state.blocksCommitted + 1
        , inHeader = False
    }


{-| Finalize a block by reversing the body and reconstructing sourceText.

For Paragraph blocks, firstLine is content (not a header), so it's prepended to body.
For Ordinary/Verbatim blocks, firstLine was the header line and body has the content.

-}
finalize : PrimitiveBlock -> PrimitiveBlock
finalize block =
    let
        reversedBody =
            List.reverse block.body

        -- For paragraphs, firstLine is content, not a header
        finalBody =
            case block.heading of
                Paragraph ->
                    if String.isEmpty block.firstLine then
                        reversedBody

                    else
                        block.firstLine :: reversedBody

                Ordinary "section" ->
                    if String.isEmpty block.firstLine then
                        reversedBody

                    else
                        block.firstLine :: reversedBody

                _ ->
                    reversedBody

        meta =
            block.meta

        -- Use `meta.sourceText` (the original raw heading line, captured at
        -- block construction) rather than `block.firstLine`, which for `|`,
        -- `||`, `$$`, and ``` blocks has been stripped of the heading.
        sourceText =
            if List.isEmpty reversedBody then
                meta.sourceText

            else
                meta.sourceText ++ "\n" ++ String.join "\n" reversedBody
    in
    { block
        | body = finalBody
        , meta =
            { meta
                | sourceText = sourceText
                , end = meta.begin + String.length sourceText
                , contentEnd = meta.begin + String.length sourceText
            }
    }


{-| Set the block ID.
-}
setBlockId : Int -> PrimitiveBlock -> PrimitiveBlock
setBlockId index block =
    let
        meta =
            block.meta

        id =
            String.fromInt meta.lineNumber ++ "-" ++ String.fromInt index
    in
    { block | meta = { meta | id = id } }



-- HEADING DATA


type alias HeadingData =
    { heading : Heading
    , args : List String
    , properties : Dict String String
    , firstLine : String
    }


{-| Extract heading data from a line.
-}
getHeadingData : String -> HeadingData
getHeadingData line =
    let
        trimmed =
            String.trim line
    in
    if String.startsWith "|| " trimmed then
        -- Verbatim block: || blockname -- LEGACY, eventually phase out?
        getVerbatimHeading trimmed

    else if String.startsWith "| " trimmed then
        -- Ordinary block: | blockname
        getHeading trimmed

    else if String.startsWith "```" trimmed then
        -- Code fence
        { heading = Verbatim "code"
        , args = []
        , properties = Dict.empty
        , firstLine = ""
        }

    else if String.startsWith "$$" trimmed then
        -- Math block
        { heading = Verbatim "math"
        , args = []
        , properties = Dict.empty
        , firstLine = ""
        }

    else if String.startsWith "# " trimmed then
        -- Markdown heading level 1
        { heading = Ordinary "section"
        , args = [ "1" ]
        , properties = Dict.singleton "level" "1"
        , firstLine = String.dropLeft 2 trimmed
        }

    else if String.startsWith "## " trimmed then
        -- Markdown heading level 2
        { heading = Ordinary "section"
        , args = [ "2" ]
        , properties = Dict.singleton "level" "2"
        , firstLine = String.dropLeft 3 trimmed
        }

    else if String.startsWith "### " trimmed then
        -- Markdown heading level 3
        { heading = Ordinary "section"
        , args = [ "3" ]
        , properties = Dict.singleton "level" "3"
        , firstLine = String.dropLeft 4 trimmed
        }

    else if String.startsWith "- " trimmed then
        -- List item (preserve full line including prefix)
        { heading = Ordinary "item"
        , args = []
        , properties = Dict.empty
        , firstLine = trimmed
        }

    else if String.startsWith ". " trimmed then
        -- Numbered item (preserve full line including prefix)
        { heading = Ordinary "numbered"
        , args = []
        , properties = Dict.empty
        , firstLine = trimmed
        }

    else
        -- Paragraph
        { heading = Paragraph
        , args = []
        , properties = Dict.empty
        , firstLine = line
        }


{-| Parse verbatim heading: || blockname arg1 arg2 ...
-}
getVerbatimHeading : String -> HeadingData
getVerbatimHeading line =
    let
        afterPrefix =
            String.dropLeft 3 line

        parts =
            String.words afterPrefix

        name =
            List.head parts |> Maybe.withDefault "code"

        ( args, properties ) =
            Tools.KV.argsAndPropertiesFromList (List.drop 1 parts)
    in
    { heading = Verbatim name
    , args = args
    , properties = properties
    , firstLine = ""
    }


{-| Parse ordinary heading: | blockname arg1 arg2 ...
-}
getHeading : String -> HeadingData
getHeading line =
    let
        afterPrefix : String
        afterPrefix =
            String.dropLeft 2 line

        parts =
            String.words afterPrefix

        name =
            List.head parts |> Maybe.withDefault "block"

        ( args, properties_ ) =
            Tools.KV.argsAndPropertiesFromList (List.drop 1 parts)

        properties =
            if name /= "section" then
                properties_

            else
                case List.head args of
                    Nothing ->
                        Dict.insert "level" "1" properties_

                    Just str ->
                        case String.toInt str of
                            Nothing ->
                                Dict.insert "level" "1" properties_

                            Just _ ->
                                Dict.insert "level" str properties_
    in
    { heading =
        if isVerbatimName name then
            Verbatim name

        else
            Ordinary name
    , args = args
    , properties = properties
    , firstLine = ""
    }


isVerbatimName : String -> Bool
isVerbatimName str =
    List.member str verbatimNames



-- VERBATIM DETECTION


{-| Check if a line starts a verbatim block.
-}
isVerbatimLine : String -> Bool
isVerbatimLine line =
    let
        trimmed =
            String.trim line
    in
    String.startsWith "|| " trimmed
        || String.startsWith "```" trimmed
        || String.startsWith "$$" trimmed



-- CONTINUATION LINE HANDLING


{-| List of known ordinary block names (not verbatim).
Used to distinguish continuation lines from new blocks.
-}
ordinaryNames : List String
ordinaryNames =
    [ "section"
    , "theorem"
    , "definition"
    , "lemma"
    , "corollary"
    , "proposition"
    , "proof"
    , "remark"
    , "example"
    , "exercise"
    , "note"
    , "problem"
    , "solution"
    , "question"
    , "answer"
    , "abstract"
    , "title"
    , "subtitle"
    , "author"
    , "date"
    , "contents"
    , "index"
    , "bibliography"
    , "quotation"
    , "item"
    , "numbered"
    , "heading"
    , "subheading"
    , "document"
    , "endnotes"
    , "set-key"
    ]


{-| Check if a block has a header (Ordinary or Verbatim, not Paragraph).
-}
isBlockWithHeader : PrimitiveBlock -> Bool
isBlockWithHeader block =
    case block.heading of
        Paragraph ->
            False

        _ ->
            True


{-| Check if a line is a continuation line (extends the header with more args/properties).
A continuation line:

1.  Starts with "| " (pipe + space)
2.  The first word after "| " is NOT a known block name (unless it contains a colon)

-}
isContinuationLine : Bool -> String -> Bool
isContinuationLine isVerbatim line =
    let
        trimmed =
            String.trim line
    in
    if String.startsWith "| " trimmed then
        let
            afterPrefix =
                String.dropLeft 2 trimmed

            firstWord =
                String.words afterPrefix |> List.head |> Maybe.withDefault ""
        in
        if isVerbatim then
            -- For verbatim blocks, only property lines (containing ":") are continuations
            String.contains ":" firstWord

        else
            -- For ordinary blocks, properties OR unknown names are continuations
            String.contains ":" firstWord
                || not (isKnownBlockName firstWord)

    else
        False


{-| Check if a name is a known block name (verbatim or ordinary).
-}
isKnownBlockName : String -> Bool
isKnownBlockName name =
    List.member name verbatimNames || List.member name ordinaryNames


{-| Merge a continuation line's args and properties into a block.
-}
mergeContinuationLine : Line -> PrimitiveBlock -> PrimitiveBlock
mergeContinuationLine line block =
    let
        trimmed =
            String.trim line.content

        afterPrefix =
            String.dropLeft 2 trimmed

        parts =
            String.words afterPrefix

        ( newArgs, newProps ) =
            Tools.KV.argsAndPropertiesFromList parts

        ( mergedArgs, mergedProps ) =
            Tools.KV.mergeArgsAndProperties ( block.args, block.properties ) ( newArgs, newProps )

        meta =
            block.meta
    in
    { block
        | args = mergedArgs
        , properties = mergedProps
        , meta = { meta | numberOfLines = meta.numberOfLines + 1, bodyLineNumber = meta.bodyLineNumber + 1 }
    }
