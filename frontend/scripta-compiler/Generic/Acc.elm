module Generic.Acc exposing
    ( InitialAccumulatorData
    , initialData
    , transformAccumulate
    )

{-| The Accumulator module collects information from the AST during a
traversal pass, then uses that information to transform blocks.

**What the Accumulator tracks:**

  - Section/heading numbering (headingIndex vector)
  - Block numbering for theorems, equations, figures (blockCounter, counter dict)
  - Cross-reference dictionary (reference)
  - Term/index entries (terms)
  - Footnotes (footnotes, footnoteNumbers)
  - Math and text macro definitions (mathMacroDict, textMacroDict)
  - Bibliography entries (bibliography)
  - Q&A pairings (qAndAList, qAndADict)

**Main entry point:**

    transformAccumulate : InitialAccumulatorData -> Forest ExpressionBlock -> ( Accumulator, Forest ExpressionBlock )

This function does two things for each block:

1.  `updateAccumulator` - extracts info from the block (e.g., increments counters)
2.  `transformBlock` - adds info back to the block (e.g., sets "label" property with number)

**Numbering mechanisms:**

  - Sections: `headingIndex` vector, stored in block.properties["label"]
  - Theorems/numbered blocks: `blockCounter` int, stored in block.properties["label"]
  - Equations/figures: `counter` dict (keyed by "equation", "figure"), stored in block.properties

**Functions (54 total):**

  - Core (tree traversal)
      - initialData
      - init
      - transformAccumulate
      - transformAccumulateTree
      - transformAccumulateBlock
      - mapAccumulate
      - reverse
  - Block transformation
      - transformBlock
      - expand
      - vectorPrefix
  - Counters
      - getCounter
      - getCounterAsString
      - incrementCounter
      - reduceName
  - References
      - makeReferenceDatum
      - updateReference
      - updateReferenceWithBlock
      - getReferenceDatum
  - Accumulator updates (by block type)
      - updateAccumulator
      - updateWithOrdinarySectionBlock
      - updateWithOrdinaryDocumentBlock
      - updateWithOrdinaryBlock
      - updateWithVerbatimBlock
      - updateWithParagraph
      - verbatimBlockReference
      - nextInListState
  - Macros
      - updateWithTextMacros
      - updateWithMathMacros
      - makeMathMacroDict
      - macroParser
  - Terms (index entries)
      - addTermsFromContent
      - getTerms
      - extract
      - extractTermFromArgs
      - parseListAs
      - addTerm
      - getTextContent
      - getTextEnd
  - Citations/Bibliography
      - addCitesFromContent
      - getCiteKeys
      - extractCiteKey
  - Footnotes
      - getFootnotes
      - extractFootnote
      - addFootnote
      - addFootnoteLabel
      - addFootnotes
      - addFootnotesFromContent
  - Block helpers
      - getNameContentId
      - getNameContentIdTag
      - getNameFromHeading
      - getVerbatimContent
      - getMeta
      - getTag
      - normalizeLines

-}

import Dict exposing (Dict)
import ETeX.Transform
import Either exposing (Either(..))
import Generic.ASTTools
import Generic.BlockUtilities
import Generic.Settings
import Generic.TextMacro
import Generic.Vector as Vector exposing (Vector)
import Maybe.Extra
import Parser exposing ((|.), (|=), Parser)
import RoseTree.Tree as Tree exposing (Tree)
import Tools.String
import Tools.Utility as Utility
import V3.Types exposing (Accumulator, Expr(..), ExprMeta, Expression, ExpressionBlock, Heading(..), InListState(..), Macro, MathMacroDict, TermLoc, TermLoc2)


initialData : InitialAccumulatorData
initialData =
    { mathMacros = ""
    , textMacros = ""
    , vectorSize = 4
    , shiftAndSetCounter = Nothing
    , maxLevel = 0
    , chapterCounter = 0
    }


init : InitialAccumulatorData -> Accumulator
init data =
    { headingIndex =
        case data.shiftAndSetCounter of
            Nothing ->
                Vector.init data.vectorSize

            Just n ->
                Vector.init data.vectorSize |> Vector.set 0 (n + 1)
    , deltaLevel =
        case data.shiftAndSetCounter of
            Nothing ->
                0

            Just _ ->
                1
    , documentIndex = Vector.init data.vectorSize
    , inListState = NotInList
    , counter = Dict.empty
    , blockCounter = 0
    , chapterCounter = data.chapterCounter
    , itemVector = Vector.init data.vectorSize
    , numberedItemDict = Dict.empty
    , numberedBlockNames = Generic.Settings.numberedBlockNames
    , reference = Dict.empty
    , terms = Dict.empty
    , footnotes = Dict.empty
    , footnoteNumbers = Dict.empty
    , mathMacroDict = Dict.empty
    , textMacroDict = Dict.empty
    , keyValueDict = Dict.empty
    , qAndAList = []
    , qAndADict = Dict.empty
    , bibliography = Dict.empty
    , maxLevel = initialData.maxLevel
    }
        |> updateWithMathMacros data.mathMacros


transformAccumulate : InitialAccumulatorData -> List (Tree ExpressionBlock) -> ( Accumulator, List (Tree ExpressionBlock) )
transformAccumulate data forest =
    List.foldl (\tree ( acc_, ast_ ) -> transformAccumulateTree tree acc_ |> mapper ast_) ( init data, [] ) forest
        |> (\( acc_, ast_ ) -> ( acc_, List.reverse ast_ ))


getCounter : String -> Dict String Int -> Int
getCounter name dict =
    Dict.get name dict |> Maybe.withDefault 0


getCounterAsString : String -> Dict String Int -> String
getCounterAsString name dict =
    Dict.get name dict |> Maybe.map String.fromInt |> Maybe.withDefault ""


incrementCounter : String -> Dict String Int -> Dict String Int
incrementCounter name dict =
    Dict.insert name (getCounter name dict + 1) dict


{-| Parse key-value pairs from a verbatim block body.
Each line should be in the format "key: value".
Used for book and article blocks.
-}
parseKeyValueBody : ExpressionBlock -> Dict String String
parseKeyValueBody block =
    case block.body of
        Left content ->
            content
                |> String.lines
                |> List.filterMap parseKeyValueLine
                |> Dict.fromList

        Right _ ->
            Dict.empty


{-| Parse a single "key: value" line.
-}
parseKeyValueLine : String -> Maybe ( String, String )
parseKeyValueLine line =
    case String.split ":" line of
        key :: rest ->
            let
                trimmedKey =
                    String.trim key

                value =
                    String.join ":" rest |> String.trim
            in
            if trimmedKey /= "" then
                Just ( trimmedKey, value )

            else
                Nothing

        _ ->
            Nothing


type alias InitialAccumulatorData =
    { mathMacros : String
    , textMacros : String
    , vectorSize : Int
    , shiftAndSetCounter : Maybe Int
    , maxLevel : Int
    , chapterCounter : Int
    }


mapper ast_ ( acc_, tree_ ) =
    ( acc_, tree_ :: ast_ )


transformAccumulateTree : Tree ExpressionBlock -> Accumulator -> ( Accumulator, Tree ExpressionBlock )
transformAccumulateTree tree acc =
    mapAccumulate transformAccumulateBlock acc tree


mapAccumulate : (s -> a -> ( s, b )) -> s -> Tree a -> ( s, Tree b )
mapAccumulate f s tree =
    let
        ( s_, value_ ) =
            f s (Tree.value tree)

        ( s__, children_ ) =
            List.foldl
                (\child ( accState, accChildren ) ->
                    let
                        ( newState, newChild ) =
                            mapAccumulate f accState child
                    in
                    ( newState, newChild :: accChildren )
                )
                ( s_, [] )
                (Tree.children tree)
    in
    ( s__, Tree.branch value_ (reverse children_) )


reverse : List a -> List a
reverse list =
    List.reverse list


{-|

    This function first updates the Accumulator with information from the ExpressionBlock
    (for example, the headingIndex, used to number sections), and then transforms the
    ExpressionBlock with information from the Accumulator (for example, the label property).

    The transformAccumulate block takes an Accumulator and an ExpressionBlock as
    arguments and returns a pair (Accumulator, ExpressionBlock) of the updated data.

-}
transformAccumulateBlock : Accumulator -> ExpressionBlock -> ( Accumulator, ExpressionBlock )
transformAccumulateBlock =
    \acc_ block_ ->
        let
            newAcc =
                updateAccumulator block_ acc_
        in
        ( newAcc, transformBlock newAcc block_ )


{-|

    Add labels to blocks, e.g. number sections and equations

-}
transformBlock : Accumulator -> ExpressionBlock -> ExpressionBlock
transformBlock acc block =
    case ( block.heading, block.args ) of
        ( Ordinary "section", _ ) ->
            let
                chapterPart =
                    if acc.chapterCounter > 0 then
                        String.fromInt acc.chapterCounter ++ "."

                    else
                        ""
            in
            { block
                | properties =
                    block.properties
                        |> Dict.insert "label" (chapterPart ++ Vector.toString acc.headingIndex)
                        |> Dict.insert "tag" (block.firstLine |> Tools.String.makeSlug)
            }

        ( Ordinary "chapter", _ ) ->
            let
                tag =
                    case block.body of
                        Left str ->
                            Tools.String.makeSlug str

                        Right expr ->
                            List.map Generic.ASTTools.getText expr |> Maybe.Extra.values |> String.join "-" |> Tools.String.makeSlug
            in
            { block
                | properties =
                    block.properties
                        |> Dict.insert "label" (String.fromInt acc.chapterCounter)
                        |> Dict.insert "tag" tag
                        |> Dict.insert "chapter-number" (String.fromInt acc.chapterCounter)
                        |> Dict.insert "level" "0"
            }

        ( Ordinary "quiver", _ ) ->
            { block | properties = Dict.insert "figure" (getCounterAsString "figure" acc.counter) block.properties }

        ( Ordinary "chart", _ ) ->
            { block | properties = Dict.insert "figure" (getCounterAsString "figure" acc.counter) block.properties }

        ( Ordinary "image", _ ) ->
            { block | properties = Dict.insert "figure" (getCounterAsString "figure" acc.counter) block.properties }

        ( Ordinary "iframe", _ ) ->
            { block | properties = Dict.insert "figure" (getCounterAsString "figure" acc.counter) block.properties }

        ( Ordinary "document", _ ) ->
            let
                title =
                    case block.body of
                        Left str ->
                            str

                        Right expr ->
                            List.map Generic.ASTTools.getText expr |> Maybe.Extra.values |> String.join " "

                label =
                    if List.member (title |> String.toLower) itemsNotNumbered then
                        ""

                    else
                        Vector.toString acc.documentIndex
            in
            { block | properties = Dict.insert "label" label block.properties }

        ( Verbatim "math", args ) ->
            -- Treat math blocks identically to equation blocks
            if Dict.member "label" block.properties then
                let
                    chapterPart =
                        if acc.chapterCounter > 0 then
                            String.fromInt acc.chapterCounter ++ "."

                        else
                            ""

                    sectionPart =
                        Vector.toStringWithLevel acc.maxLevel acc.headingIndex

                    punctuation =
                        if sectionPart /= "" then
                            "."

                        else
                            ""

                    equationProp =
                        chapterPart ++ sectionPart ++ punctuation ++ getCounterAsString "equation" acc.counter
                in
                { block | properties = Dict.insert "equation-number" equationProp block.properties }

            else
                block

        ( Verbatim "equation", args ) ->
            -- Only number equations that have a label property
            if Dict.member "label" block.properties then
                let
                    chapterPart =
                        if acc.chapterCounter > 0 then
                            String.fromInt acc.chapterCounter ++ "."

                        else
                            ""

                    sectionPart =
                        Vector.toStringWithLevel acc.maxLevel acc.headingIndex

                    punctuation =
                        if sectionPart /= "" then
                            "."

                        else
                            ""

                    equationProp =
                        chapterPart ++ sectionPart ++ punctuation ++ getCounterAsString "equation" acc.counter
                in
                { block | properties = Dict.insert "equation-number" equationProp block.properties }

            else
                block

        ( Verbatim "aligned", _ ) ->
            -- Only number aligned blocks that have a label property
            if Dict.member "label" block.properties then
                let
                    chapterPart =
                        if acc.chapterCounter > 0 then
                            String.fromInt acc.chapterCounter ++ "."

                        else
                            ""

                    sectionPart =
                        Vector.toStringWithLevel acc.maxLevel acc.headingIndex

                    punctuation =
                        if sectionPart /= "" then
                            "."

                        else
                            ""

                    equationProp =
                        chapterPart ++ sectionPart ++ punctuation ++ getCounterAsString "equation" acc.counter
                in
                { block | properties = Dict.insert "equation-number" equationProp block.properties }

            else
                block

        ( Verbatim "book", _ ) ->
            { block | properties = Dict.union (parseKeyValueBody block) block.properties }

        ( Verbatim "article", _ ) ->
            { block | properties = Dict.union (parseKeyValueBody block) block.properties }

        ( heading, _ ) ->
            -- TODO: not at all sure that the below is correct
            case getNameFromHeading heading of
                Nothing ->
                    block

                Just name ->
                    -- Insert the numerical counter, e.g,, equation number, in the arg list of the block
                    if name == "section" then
                        let
                            prefix =
                                Vector.toString acc.headingIndex

                            equationProp =
                                if prefix == "" then
                                    getCounterAsString "equation" acc.counter

                                else
                                    Vector.toString acc.headingIndex ++ "." ++ getCounterAsString "equation" acc.counter
                        in
                        { block
                            | properties = Dict.insert "label" equationProp block.properties
                        }

                    else
                        -- Default insertion of "label" property (used for block numbering)
                        let
                            chapterPart =
                                if acc.chapterCounter > 0 then
                                    String.fromInt acc.chapterCounter ++ "."

                                else
                                    ""

                            sectionPart =
                                Vector.toStringWithLevel acc.maxLevel acc.headingIndex

                            punctuation =
                                if sectionPart /= "" then
                                    "."

                                else
                                    ""

                            label =
                                chapterPart ++ sectionPart ++ punctuation ++ String.fromInt acc.blockCounter
                        in
                        (if List.member name Generic.Settings.numberedBlockNames then
                            { block
                                | properties =
                                    Dict.insert "label" label block.properties
                            }

                         else
                            block
                        )
                            |> expand acc.textMacroDict


vectorPrefix : Vector -> String
vectorPrefix vector =
    let
        prefix =
            Vector.toString vector
    in
    if prefix == "" then
        ""

    else
        Vector.toString vector ++ "."


vectorPrefixWithLevel : Int -> Vector -> String
vectorPrefixWithLevel lev vector =
    Vector.toStringWithLevel lev vector


{-| Returns the chapter prefix string for numbering.
If chapterCounter > 0, returns "N." where N is the chapter number.
If chapterCounter = 0, returns "" (no chapter prefix).
-}
chapterPrefix : Accumulator -> String
chapterPrefix acc =
    if acc.chapterCounter > 0 then
        String.fromInt acc.chapterCounter

    else
        ""


{-| Map name to name of counter
-}
reduceName : String -> String
reduceName str =
    if List.member str [ "equation", "aligned", "math" ] then
        "equation"

    else if str == "code" then
        "listing"

    else if List.member str [ "quiver", "image", "iframe", "chart", "textarray", "csvtable", "svg", "tikz", "iframe" ] then
        "figure"

    else
        str


expand : Dict String Macro -> ExpressionBlock -> ExpressionBlock
expand dict block =
    { block | body = Either.map (List.map (Generic.TextMacro.expand dict)) block.body }


{-| The first component of the return value (Bool, Maybe Vector) is the
updated inList.
-}
nextInListState : Heading -> InListState -> InListState
nextInListState heading state =
    case ( state, heading ) of
        ( NotInList, Ordinary "numbered" ) ->
            InList

        ( NotInList, _ ) ->
            NotInList

        ( InList, Ordinary "numbered" ) ->
            InList

        ( InList, _ ) ->
            NotInList


type alias ReferenceDatum =
    { id : String
    , tag : String
    , numRef : String
    }


makeReferenceDatum : String -> String -> String -> ReferenceDatum
makeReferenceDatum id tag numRef =
    { id = id
    , tag = tag
    , numRef = numRef
    }


{-| Update the references dictionary: add a key-value pair where the
key is defined as in the examples \\label{foo} or [label foo],
and where value is a record with an id and a "numerical" reference,
e.g, "2" or "2.3"
-}
updateReference : Vector -> ReferenceDatum -> Accumulator -> Accumulator
updateReference headingIndex referenceDatum acc =
    -- Update the accumulator.reference dictionary with new reference data:
    -- Namely, insert a new key-value pair where the key is the tag of the
    -- reference, e.g., "foo" in \\label{foo} or [label foo], and where the
    -- value is a record with an id and a "numerical" reference, e.g, "2" or "2.3"
    --  TODO: review!
    if referenceDatum.tag /= "" then
        { acc
            | reference =
                Dict.insert referenceDatum.tag
                    { id = referenceDatum.id, numRef = referenceDatum.numRef }
                    acc.reference
        }

    else
        acc



-- Simplify this function:
--   - take the tag from block.properties with key "tag"
--   - set the numRef to acc.headingIndex . acc.blockCounter


updateReferenceWithBlock : ExpressionBlock -> Accumulator -> Accumulator
updateReferenceWithBlock block acc =
    case getReferenceDatum acc block of
        Just referenceDatum ->
            updateReference acc.headingIndex referenceDatum acc

        Nothing ->
            acc


getNameContentId : ExpressionBlock -> Maybe { name : String, content : Either String (List Expression), id : String }
getNameContentId block =
    let
        name : Maybe String
        name =
            getNameFromHeading block.heading

        content : Maybe (Either String (List Expression))
        content =
            Just block.body

        id =
            Just block.meta.id
    in
    case ( name, content, id ) of
        ( Just name_, Just content_, Just id_ ) ->
            Just { name = name_, content = content_, id = id_ }

        _ ->
            Nothing


getNameContentIdTag : ExpressionBlock -> Maybe { name : String, content : Either String (List Expression), id : String, tag : String }
getNameContentIdTag block =
    let
        name =
            Dict.get "name" block.properties

        content : Either String (List Expression)
        content =
            block.body

        id =
            block.meta.id

        tag =
            Dict.get "tag" block.properties |> Maybe.withDefault id
    in
    case name of
        Nothing ->
            Nothing

        Just name_ ->
            Just { name = name_, content = block.body, id = id, tag = tag }


getReferenceDatum : Accumulator -> ExpressionBlock -> Maybe ReferenceDatum
getReferenceDatum acc block =
    let
        id : String
        id =
            block.meta.id

        tag =
            Dict.get "tag" block.properties |> Maybe.withDefault id

        chapterPart =
            if acc.chapterCounter > 0 then
                String.fromInt acc.chapterCounter ++ "."

            else
                ""

        sectionPart =
            acc.headingIndex |> Vector.toStringWithLevel acc.maxLevel

        punctuation =
            if sectionPart /= "" then
                "."

            else
                ""

        numRef =
            chapterPart ++ sectionPart ++ punctuation ++ (acc.blockCounter |> String.fromInt)
    in
    Just { id = id, tag = tag, numRef = numRef }


{-|

    Update the accumulator with data from a block, e.g., update the
    headingIndex, a vector of integers that is used to number the sections

-}
updateAccumulator : ExpressionBlock -> Accumulator -> Accumulator
updateAccumulator ({ heading, indent, args, body, meta, properties } as block) accumulator =
    -- Update the accumulator for expression blocks with selected name
    case heading of
        -- provide numbering for sections
        -- reference : Dict String { id : String, numRef : String }
        Verbatim "settings" ->
            { accumulator | keyValueDict = Dict.union properties accumulator.keyValueDict }

        Ordinary "q" ->
            { accumulator
              -- set the qAndAList to  [(id, "??")]
              -- where id is the id of the question block
                | qAndAList = [ ( block.meta.id, "??" ) ]
                , blockCounter = accumulator.blockCounter + 1
            }
                |> updateReferenceWithBlock block

        Ordinary "a" ->
            case List.head accumulator.qAndAList of
                Just ( idQ, "??" ) ->
                    -- Assumption: the qAndAList consists of a single pair
                    -- (qId, "??") where qId is the id of the question block.
                    -- We now insert (qId, aId), where aId is the id o
                    -- the answer block now being processed in the qAndADict
                    -- Then we clear the qAndAList (set it to empty)
                    { accumulator
                        | qAndAList = []
                        , qAndADict = Dict.insert idQ block.meta.id accumulator.qAndADict
                    }
                        |> updateReferenceWithBlock block

                _ ->
                    accumulator

        Ordinary "set-key" ->
            case args of
                key :: value :: rest ->
                    { accumulator | keyValueDict = Dict.insert key value accumulator.keyValueDict }

                _ ->
                    accumulator

        Ordinary "list" ->
            { accumulator | itemVector = Vector.init accumulator.headingIndex.size }

        Ordinary "chapter" ->
            let
                newChapterCounter =
                    accumulator.chapterCounter + 1

                chapterTag =
                    Dict.get "label" block.properties
                        |> Maybe.withDefault block.meta.id

                referenceDatum =
                    makeReferenceDatum block.meta.id chapterTag (String.fromInt newChapterCounter)
            in
            { accumulator
                | chapterCounter = newChapterCounter
                , headingIndex = Vector.init accumulator.headingIndex.size
                , blockCounter = 0
                , counter = Dict.insert "equation" 0 accumulator.counter
            }
                |> updateReference accumulator.headingIndex referenceDatum

        Ordinary "section" ->
            let
                level : String
                level =
                    Dict.get "level" properties |> Maybe.withDefault "1"
            in
            case getNameContentId block of
                Just { name, content, id } ->
                    updateWithOrdinarySectionBlock accumulator (Just name) content level id
                        |> updateReferenceWithBlock block

                Nothing ->
                    accumulator |> updateReferenceWithBlock block

        Ordinary "document" ->
            let
                level =
                    List.head args |> Maybe.withDefault "1"
            in
            case getNameContentId block of
                Just { name, content, id } ->
                    updateWithOrdinaryDocumentBlock accumulator (Just name) content level id

                _ ->
                    accumulator

        Ordinary "title" ->
            -- Only reset headingIndex if it wasn't set by shiftAndSetCounter (deltaLevel == 1)
            let
                -- Store number-to-level from title properties in keyValueDict
                newKeyValueDict =
                    case Dict.get "number-to-level" block.properties of
                        Just ntl ->
                            Dict.insert "number-to-level" ntl accumulator.keyValueDict

                        Nothing ->
                            accumulator.keyValueDict
            in
            if accumulator.deltaLevel == 1 then
                -- Preserve the headingIndex set by shiftAndSetCounter
                { accumulator | keyValueDict = newKeyValueDict }

            else
                let
                    vecSize =
                        accumulator.headingIndex.size

                    headingIndex =
                        case Dict.get "first-section" block.properties of
                            Nothing ->
                                Vector.init vecSize

                            Just firstSection_ ->
                                case String.toInt firstSection_ of
                                    Just n ->
                                        Vector.init vecSize |> Vector.set 0 (max (n - 1) 0)

                                    Nothing ->
                                        Vector.init vecSize
                in
                { accumulator | headingIndex = headingIndex, keyValueDict = newKeyValueDict }

        Ordinary "setcounter" ->
            let
                n =
                    List.head args |> Maybe.andThen String.toInt |> Maybe.withDefault 1
            in
            { accumulator | headingIndex = Vector.init accumulator.headingIndex.size |> Vector.set 0 n }

        Ordinary "shiftandsetcounter" ->
            let
                n =
                    List.head args |> Maybe.andThen String.toInt |> Maybe.withDefault 1
            in
            { accumulator | headingIndex = Vector.init accumulator.headingIndex.size |> Vector.set 0 n, deltaLevel = 1 }

        Ordinary "bibitem" ->
            updateBibItemBlock accumulator args block.meta.id

        Ordinary _ ->
            updateWithOrdinaryBlock block accumulator
                |> updateReferenceWithBlock block

        -- provide for numbering of equations
        Verbatim "mathmacros" ->
            case getVerbatimContent block of
                Nothing ->
                    accumulator

                Just str ->
                    updateWithMathMacros str accumulator

        Verbatim "textmacros" ->
            case getVerbatimContent block of
                Nothing ->
                    accumulator

                Just str ->
                    updateWithTextMacros str accumulator

        Verbatim name_ ->
            case block.body of
                Left str ->
                    updateWithVerbatimBlock block accumulator

                Right _ ->
                    accumulator

        Paragraph ->
            case getNameContentIdTag block of
                Nothing ->
                    { accumulator | inListState = nextInListState block.heading accumulator.inListState }
                        |> updateWithParagraph block
                        |> updateReferenceWithBlock block

                Just { name, content, id, tag } ->
                    accumulator |> updateWithParagraph block |> updateReferenceWithBlock block


normalizeLines : List String -> List String
normalizeLines lines =
    List.map (\line -> String.trim line) lines |> List.filter (\line -> line /= "")


updateWithOrdinarySectionBlock : Accumulator -> Maybe String -> Either String (List Expression) -> String -> String -> Accumulator
updateWithOrdinarySectionBlock accumulator name content level id =
    let
        titleWords =
            case content of
                Left str ->
                    [ Utility.compressWhitespace str ]

                Right expr ->
                    List.map Generic.ASTTools.getText expr |> Maybe.Extra.values |> List.map Utility.compressWhitespace

        sectionTag =
            -- TODO: the below is a bad solution
            titleWords |> List.map (String.toLower >> String.trim >> String.replace " " "-") |> String.concat

        delta =
            case Dict.get "has-chapters" accumulator.keyValueDict of
                Nothing ->
                    0

                Just "yes" ->
                    1

                _ ->
                    0

        levelAsInt =
            String.toInt level |> Maybe.withDefault 1

        headingIndex =
            Vector.increment (String.toInt level |> Maybe.withDefault 1 |> (\x -> x - 1 + delta + accumulator.deltaLevel)) accumulator.headingIndex

        blockCounter =
            if levelAsInt <= accumulator.maxLevel then
                0

            else
                accumulator.blockCounter

        chapterPart =
            if accumulator.chapterCounter > 0 then
                String.fromInt accumulator.chapterCounter ++ "."

            else
                ""

        referenceDatum =
            makeReferenceDatum id sectionTag (chapterPart ++ Vector.toString headingIndex)

        newCounter =
            if levelAsInt <= accumulator.maxLevel then
                Dict.insert "equation" 0 accumulator.counter

            else
                accumulator.counter
    in
    -- TODO: take care of numberedItemIndex = 0 here and elsewhere
    { accumulator
        | headingIndex = headingIndex
        , blockCounter = blockCounter
        , counter = newCounter
    }
        |> updateReference accumulator.headingIndex referenceDatum


itemsNotNumbered =
    [ "preface", "introduction", "appendix", "references", "index", "scratch" ]


{-| Update the accumulator with data from a document block, e.g., update the
documentIndex, a vector of integers that is used to number the documents in a collection
-}
updateWithOrdinaryDocumentBlock : Accumulator -> Maybe String -> Either String (List Expression) -> String -> String -> Accumulator
updateWithOrdinaryDocumentBlock accumulator name content level id =
    let
        title =
            case content of
                Left str ->
                    str

                Right expr ->
                    List.map Generic.ASTTools.getText expr |> Maybe.Extra.values |> String.join " "

        sectionTag =
            title |> String.toLower |> String.replace " " "-"

        documentIndex =
            if List.member (String.toLower title) itemsNotNumbered then
                accumulator.documentIndex

            else
                Vector.increment (String.toInt level |> Maybe.withDefault 0) accumulator.documentIndex

        referenceDatum : ReferenceDatum
        referenceDatum =
            if List.member (String.toLower title) itemsNotNumbered then
                makeReferenceDatum id sectionTag (Vector.toString documentIndex)

            else
                makeReferenceDatum id sectionTag ""
    in
    -- TODO: take care of numberedItemIndex = 0 here and elsewhere
    { accumulator | documentIndex = documentIndex } |> updateReference accumulator.headingIndex referenceDatum


updateBibItemBlock accumulator args id =
    case List.head args of
        Nothing ->
            accumulator

        Just label ->
            let
                -- Count how many bibliography entries already have numbers
                nextNumber =
                    accumulator.bibliography
                        |> Dict.values
                        |> List.filterMap identity
                        |> List.length
                        |> (+) 1

                -- Update bibliography: set the number for this entry (insert if not present)
                newBibliography =
                    Dict.insert label (Just nextNumber) accumulator.bibliography
            in
            { accumulator
                | reference = Dict.insert label { id = id, numRef = String.fromInt nextNumber } accumulator.reference
                , bibliography = newBibliography
            }


updateWithOrdinaryBlock : ExpressionBlock -> Accumulator -> Accumulator
updateWithOrdinaryBlock block accumulator =
    case Generic.BlockUtilities.getExpressionBlockName block of
        Just "setcounter" ->
            case block.body of
                Left _ ->
                    accumulator

                Right exprs ->
                    let
                        ctr =
                            case exprs of
                                [ Text val _ ] ->
                                    String.toInt val |> Maybe.withDefault 1

                                _ ->
                                    1

                        headingIndex =
                            Vector.init accumulator.headingIndex.size |> Vector.set 0 (ctr - 1)
                    in
                    { accumulator | headingIndex = headingIndex }

        Just "numbered" ->
            let
                level =
                    block.indent // Generic.Settings.indentationQuantum

                itemVector =
                    case accumulator.inListState of
                        InList ->
                            Vector.increment level accumulator.itemVector

                        NotInList ->
                            Vector.init accumulator.itemVector.size |> Vector.increment 0

                index =
                    Vector.get level itemVector

                numberedItemDict =
                    Dict.insert block.meta.id { level = level, index = index } accumulator.numberedItemDict

                referenceDatum =
                    makeReferenceDatum block.meta.id (getTag block) (String.fromInt (Vector.get level itemVector))
            in
            { accumulator
                | inListState = nextInListState block.heading accumulator.inListState
                , itemVector = itemVector
                , numberedItemDict = numberedItemDict
            }
                |> updateReference accumulator.headingIndex referenceDatum

        Just "item" ->
            let
                level =
                    block.indent // Generic.Settings.indentationQuantum
            in
            { accumulator | inListState = nextInListState block.heading accumulator.inListState }

        Just name_ ->
            if List.member name_ [ "title", "contents", "banner", "a" ] then
                accumulator

            else if List.member name_ Generic.Settings.numberedBlockNames then
                let
                    newBlockCounter =
                        accumulator.blockCounter + 1

                    chapterPart =
                        if accumulator.chapterCounter > 0 then
                            String.fromInt accumulator.chapterCounter ++ "."

                        else
                            ""

                    sectionPart =
                        Vector.toStringWithLevel accumulator.maxLevel accumulator.headingIndex

                    punctuation =
                        if sectionPart /= "" then
                            "."

                        else
                            ""

                    numRef =
                        chapterPart ++ sectionPart ++ punctuation ++ String.fromInt newBlockCounter

                    referenceDatum =
                        makeReferenceDatum block.meta.id (getTag block) numRef
                in
                { accumulator
                    | inListState = nextInListState block.heading accumulator.inListState
                    , blockCounter = newBlockCounter
                }
                    |> updateReference accumulator.headingIndex referenceDatum

            else
                { accumulator | inListState = nextInListState block.heading accumulator.inListState }

        _ ->
            accumulator


updateWithTextMacros : String -> Accumulator -> Accumulator
updateWithTextMacros content accumulator =
    { accumulator | textMacroDict = Generic.TextMacro.buildDictionary (String.lines content |> normalizeLines) }


updateWithMathMacros : String -> Accumulator -> Accumulator
updateWithMathMacros content accumulator =
    let
        definitions : String
        definitions =
            content
                |> String.replace "\\begin{mathmacros}" ""
                |> String.replace "\\end{mathmacros}" ""
                |> String.replace "end" ""
                |> (\str -> str ++ "\nbracket: {[ #1 ]}")
                |> String.trim

        mathMacroDict =
            makeMathMacroDict (String.trim definitions)
    in
    { accumulator | mathMacroDict = mathMacroDict }



{-

   Update the accumulator with data from a verbatim block. In particular,
   if it has a label property, then update the reference dictionary.
-}


updateWithVerbatimBlock : ExpressionBlock -> Accumulator -> Accumulator
updateWithVerbatimBlock block accumulator =
    case block.body of
        Right _ ->
            accumulator

        Left _ ->
            let
                name =
                    Generic.BlockUtilities.getExpressionBlockName block |> Maybe.withDefault ""

                updateAccumulatorWithLabel =
                    case Dict.get "label" block.properties of
                        Just tag ->
                            let
                                referenceDatum =
                                    makeReferenceDatum block.meta.id
                                        tag
                                        (verbatimBlockReference isSimple accumulator.headingIndex name newCounter accumulator)
                            in
                            \acc -> updateReference accumulator.headingIndex referenceDatum acc

                        Nothing ->
                            identity

                --Dict.get "label" dict |> Maybe.withDefault body
                isSimple =
                    List.member name [ "quiver", "image" ]

                -- Increment the appropriate counter, e.g., "equation" and "aligned"
                -- reduceName maps these both to "equation"
                -- Counter increments when block has a label property (for numbered equations)
                hasLabel =
                    Dict.member "label" block.properties

                newCounter =
                    if List.member name accumulator.numberedBlockNames && hasLabel then
                        incrementCounter (reduceName name) accumulator.counter

                    else
                        accumulator.counter
            in
            { accumulator | inListState = nextInListState block.heading accumulator.inListState, counter = newCounter }
                |> updateAccumulatorWithLabel


verbatimBlockReference : Bool -> Vector -> String -> Dict String Int -> Accumulator -> String
verbatimBlockReference isSimple headingIndex name newCounter acc =
    let
        chapterPart =
            if acc.chapterCounter > 0 then
                String.fromInt acc.chapterCounter ++ "."

            else
                ""

        sectionPart =
            Vector.toStringWithLevel acc.maxLevel headingIndex

        punctuation =
            if sectionPart /= "" then
                "."

            else
                ""

        eqNum =
            getCounter (reduceName name) newCounter |> String.fromInt
    in
    if isSimple then
        eqNum

    else
        chapterPart ++ sectionPart ++ punctuation ++ eqNum


updateWithParagraph : ExpressionBlock -> Accumulator -> Accumulator
updateWithParagraph block accumulator =
    let
        ( footnotes, footnoteNumbers ) =
            addFootnotesFromContent block ( accumulator.footnotes, accumulator.footnoteNumbers )

        bibliography =
            addCitesFromContent block accumulator.bibliography
    in
    { accumulator
        | inListState = nextInListState block.heading accumulator.inListState
        , footnotes = footnotes
        , footnoteNumbers = footnoteNumbers
        , terms = addTermsFromContent block accumulator.terms
        , bibliography = bibliography
    }


addTermsFromContent : ExpressionBlock -> Dict String TermLoc -> Dict String TermLoc
addTermsFromContent block_ dict =
    let
        newTerms : List TermData
        newTerms =
            getTerms block_.meta.id block_.body

        folder : TermData -> Dict String TermLoc -> Dict String TermLoc
        folder termData dict_ =
            addTerm termData dict_
    in
    List.foldl folder dict newTerms


{-| Extract cite keys from block content and add them to bibliography with Nothing value.
Only adds if key doesn't already exist (preserves existing numbered entries).
-}
addCitesFromContent : ExpressionBlock -> Dict String (Maybe Int) -> Dict String (Maybe Int)
addCitesFromContent block dict =
    let
        citeKeys =
            getCiteKeys block.body
    in
    List.foldl
        (\key d ->
            if Dict.member key d then
                d

            else
                Dict.insert key Nothing d
        )
        dict
        citeKeys


{-| Extract cite keys from block body content.
-}
getCiteKeys : Either String (List Expression) -> List String
getCiteKeys content =
    case content of
        Right expressionList ->
            Generic.ASTTools.filterExpressionsOnName_ "cite" expressionList
                |> List.filterMap extractCiteKey

        Left _ ->
            []


{-| Extract the key from a cite expression like [cite einstein1905].
-}
extractCiteKey : Expression -> Maybe String
extractCiteKey expr =
    case expr of
        Fun "cite" [ Text key _ ] _ ->
            Just (String.trim key)

        _ ->
            Nothing



--|> updateReference tag id tag


type alias TermData =
    { term : String, loc : TermLoc }


type alias TermData2 =
    { term : String, loc : TermLoc2 }


getTerms : String -> Either String (List Expression) -> List TermData
getTerms id content_ =
    case content_ of
        Right expressionList ->
            let
                termExprs =
                    Generic.ASTTools.filterExpressionsOnName_ "index" expressionList

                termHiddenExprs =
                    Generic.ASTTools.filterExpressionsOnName_ "term_" expressionList
            in
            (termExprs ++ termHiddenExprs)
                |> List.map (extract id)
                |> Maybe.Extra.values

        Left _ ->
            []



-- TERMS: [Expression "term" [Text "group" { begin = 19, end = 23, index = 4 }] { begin = 13, end = 13, index = 1 }]


extract : String -> Expression -> Maybe TermData
extract id expr =
    case expr of
        Fun "index" args _ ->
            extractTermFromArgs id args

        Fun "term_" args _ ->
            extractTermFromArgs id args

        _ ->
            Nothing


{-| Extract term data from function arguments, handling both single and multi-word terms.
Supports optional list-as: property for custom index display.
Example: [term change color list-as:color, change]
-}
extractTermFromArgs : String -> List Expression -> Maybe TermData
extractTermFromArgs id args =
    case args of
        [ Text name { begin, end } ] ->
            -- Single word term, possibly with show-as:
            let
                ( termName, displayAs ) =
                    parseListAs name
            in
            Just { term = termName, loc = { begin = begin, end = end, id = id, displayAs = displayAs } }

        (Text firstWord { begin }) :: rest ->
            -- Multi-word term: join all text nodes
            let
                allWords =
                    firstWord :: List.filterMap getTextContent rest

                fullText =
                    String.join " " allWords

                ( termName, displayAs ) =
                    parseListAs fullText

                lastEnd =
                    rest
                        |> List.reverse
                        |> List.head
                        |> Maybe.andThen getTextEnd
                        |> Maybe.withDefault begin
            in
            Just { term = termName, loc = { begin = begin, end = lastEnd, id = id, displayAs = displayAs } }

        _ ->
            Nothing


{-| Parse a term string to extract the list-as: property if present.
Returns (termName, Maybe displayAs).
Example: "change color list-as:color, change" -> ("change color", Just "color, change")
-}
parseListAs : String -> ( String, Maybe String )
parseListAs text =
    case String.split "list-as:" text of
        [ termPart, displayPart ] ->
            ( String.trim termPart, Just (String.trim displayPart) )

        _ ->
            ( text, Nothing )


getTextContent : Expression -> Maybe String
getTextContent expr =
    case expr of
        Text str _ ->
            Just str

        _ ->
            Nothing


getTextEnd : Expression -> Maybe Int
getTextEnd expr =
    case expr of
        Text _ { end } ->
            Just end

        _ ->
            Nothing


addTerm : TermData -> Dict String TermLoc -> Dict String TermLoc
addTerm termData dict =
    Dict.insert termData.term termData.loc dict



-- FOOTNOTES


getFootnotes : Maybe String -> String -> Either String (List Expression) -> List TermData2
getFootnotes mBlockId id content_ =
    case content_ of
        Right expressionList ->
            Generic.ASTTools.filterExpressionsOnName_ "footnote" expressionList
                |> List.map (extractFootnote mBlockId id)
                |> Maybe.Extra.values

        Left _ ->
            []


extractFootnote : Maybe String -> String -> Expression -> Maybe TermData2
extractFootnote _ blockMetaId expr =
    case expr of
        Fun "footnote" [ Text content { begin, end, index, id } ] _ ->
            Just { term = content, loc = { begin = begin, end = end, id = id, mSourceId = Just blockMetaId } }

        _ ->
            Nothing



-- EXTRACT ??


addFootnote : TermData2 -> Dict String TermLoc2 -> Dict String TermLoc2
addFootnote footnoteData dict =
    Dict.insert footnoteData.term footnoteData.loc dict


addFootnoteLabel : TermData2 -> Dict String Int -> Dict String Int
addFootnoteLabel footnoteData dict =
    Dict.insert footnoteData.loc.id (Dict.size dict + 1) dict


addFootnotes : List TermData2 -> ( Dict String TermLoc2, Dict String Int ) -> ( Dict String TermLoc2, Dict String Int )
addFootnotes termDataList ( dict1, dict2 ) =
    List.foldl (\data ( d1, d2 ) -> ( addFootnote data d1, addFootnoteLabel data d2 )) ( dict1, dict2 ) termDataList


addFootnotesFromContent : ExpressionBlock -> ( Dict String TermLoc2, Dict String Int ) -> ( Dict String TermLoc2, Dict String Int )
addFootnotesFromContent block ( dict1, dict2 ) =
    let
        blockId =
            case block.body of
                Left _ ->
                    Nothing

                Right expr ->
                    Maybe.map getMeta (expr |> List.head) |> Maybe.map .id
    in
    addFootnotes (getFootnotes blockId block.meta.id block.body) ( dict1, dict2 )



-- PARSER STUFF


macroParser : String -> Parser String
macroParser name =
    Parser.succeed (\start end source -> String.slice start end source)
        |. Parser.chompUntil ("\\" ++ name ++ "{")
        |. Parser.symbol ("\\" ++ name ++ "{")
        |= Parser.getOffset
        |. Parser.chompUntil "}"
        |= Parser.getOffset
        |= Parser.getSource


getMacroArg name str =
    Parser.run (macroParser name) str


getTag : ExpressionBlock -> String
getTag block =
    case Dict.get "label" block.properties of
        Just label ->
            label

        Nothing ->
            case Dict.get "tag" block.properties of
                Just tag ->
                    tag

                Nothing ->
                    block.meta.id



-- HELPER FUNCTIONS (moved from Generic.Language)


getNameFromHeading : Heading -> Maybe String
getNameFromHeading heading =
    case heading of
        Paragraph ->
            Nothing

        Ordinary name ->
            Just name

        Verbatim name ->
            Just name


getVerbatimContent : ExpressionBlock -> Maybe String
getVerbatimContent block =
    case block.body of
        Left str ->
            Just str

        Right _ ->
            Nothing


getMeta : Expression -> ExprMeta
getMeta expr =
    case expr of
        Fun _ _ meta ->
            meta

        VFun _ _ meta ->
            meta

        Text _ meta ->
            meta

        ExprList _ _ meta ->
            meta


{-| Create math macro dictionary from mathmacros block content.
Supports both ETeX format (name: body) and LaTeX format (\\newcommand{...}).
-}
makeMathMacroDict : String -> MathMacroDict
makeMathMacroDict content =
    ETeX.Transform.makeMacroDict content
