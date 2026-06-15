module Library.Forest exposing (makeForest)

import Library.Tree
import RoseTree.Tree exposing (Tree)
import Tools.Loop exposing (Step(..), loop)


makeForest : (a -> Int) -> List a -> List (Tree a)
makeForest getLevel input =
    input
        |> toListList getLevel
        |> List.filterMap (Library.Tree.makeTree getLevel)


init : (a -> Int) -> List a -> State a
init getLevel input =
    case List.head input of
        Nothing ->
            { currentLevel = 0
            , rootLevel = 0
            , input = []
            , currentList = []
            , output = []
            }

        Just item ->
            { currentLevel = getLevel item
            , rootLevel = getLevel item
            , input = input
            , currentList = []
            , output = []
            }


toListList : (a -> Int) -> List a -> List (List a)
toListList getLevel input =
    let
        initialState =
            init getLevel input
    in
    loop initialState (nextStep getLevel)


nextStep : (a -> Int) -> State a -> Step (State a) (List (List a))
nextStep getLevel state =
    case state.input of
        [] ->
            Done (List.reverse state.currentList :: state.output |> List.reverse)

        x :: xs ->
            let
                level =
                    getLevel x
            in
            if level == state.rootLevel then
                Loop
                    { state
                        | input = xs
                        , currentLevel = level
                        , currentList = [ x ]
                        , output =
                            if List.isEmpty state.currentList then
                                state.output

                            else
                                List.reverse state.currentList :: state.output
                    }

            else
                -- new item at higher than root leve, push it onto the current list
                Loop { state | input = xs, currentLevel = level, currentList = x :: state.currentList }


-- PRINTING


print : (a -> String) -> List (Tree a) -> String
print toText list =
    List.map (Library.Tree.print toText) list |> String.join "\n"



-- INTERNALS


type alias State a =
    { currentLevel : Int
    , rootLevel : Int
    , currentList : List a
    , input : List a
    , output : List (List a)
    }



-- UTILITIES


depths : List (Tree a) -> List Int
depths =
    List.map Library.Tree.depth
