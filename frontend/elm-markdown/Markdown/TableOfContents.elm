module Markdown.TableOfContents
    exposing
        ( ToCItem(..)
        , children
        , fromBlocks
        , heading
        , headingId
        , level
        , size
        , toHtml
        )

{-| Table of Contents generation from parsed Markdown blocks.


# Model

@docs ToCItem


# Building

@docs fromBlocks


# Rendering

@docs toHtml, headingId


# Accessors

@docs level, heading, children, size

-}

import Html exposing (Html, a, li, nav, text, ul)
import Html.Attributes exposing (class, href)
import Markdown.Block as Block exposing (Block(..))
import Markdown.Inline as Inline exposing (Inline)
import Regex exposing (Regex)


{-| A tree node representing a heading and its sub-headings.
-}
type ToCItem
    = Item Int String (List ToCItem)


{-| Get the heading level (1–6).
-}
level : ToCItem -> Int
level (Item lvl _ _) =
    lvl


{-| Get the heading text.
-}
heading : ToCItem -> String
heading (Item _ str _) =
    str


{-| Get the child items.
-}
children : ToCItem -> List ToCItem
children (Item _ _ kids) =
    kids


{-| Total number of headings across all levels of nesting.
-}
size : List ToCItem -> Int
size items =
    List.foldl (\(Item _ _ kids) acc -> 1 + acc + size kids) 0 items


{-| Extract headings from parsed blocks and organize into a nested tree.
-}
fromBlocks : List (Block b i) -> List ToCItem
fromBlocks blocks =
    List.concatMap (Block.query getHeading) blocks
        |> List.foldl organizeHeadings []
        |> List.reverse
        |> List.map reverseToCItem


getHeading : Block b i -> List ( Int, String )
getHeading block =
    case block of
        Heading _ lvl inlines ->
            [ ( lvl, Inline.extractText inlines ) ]

        _ ->
            []


organizeHeadings : ( Int, String ) -> List ToCItem -> List ToCItem
organizeHeadings ( lvl, str ) items =
    case items of
        [] ->
            [ Item lvl str [] ]

        (Item lvl_ str_ kids) :: tail ->
            if lvl <= lvl_ then
                Item lvl str [] :: items

            else
                Item lvl_ str_ (organizeHeadings ( lvl, str ) kids)
                    :: tail


reverseToCItem : ToCItem -> ToCItem
reverseToCItem (Item lvl str kids) =
    List.reverse kids
        |> List.map reverseToCItem
        |> Item lvl str


{-| Render a list of ToCItems as a `<nav class="toc">` with nested lists
and anchor links.
-}
toHtml : List ToCItem -> Html msg
toHtml items =
    nav [ class "toc" ]
        [ listView items ]


listView : List ToCItem -> Html msg
listView items =
    ul [] (List.map itemView items)


itemView : ToCItem -> Html msg
itemView (Item _ str kids) =
    if List.isEmpty kids then
        li [] [ tocLink str ]

    else
        li []
            [ tocLink str
            , listView kids
            ]


tocLink : String -> Html msg
tocLink str =
    a [ href ("#" ++ headingId str) ] [ text str ]


{-| Convert a heading string to a URL-friendly slug for use as an element id.

    headingId "Hello World" == "hello-world"

-}
headingId : String -> String
headingId =
    String.toLower >> Regex.replace oneOrMoreSpaces (always "-")


oneOrMoreSpaces : Regex
oneOrMoreSpaces =
    Regex.fromString "\\s+"
        |> Maybe.withDefault Regex.never
