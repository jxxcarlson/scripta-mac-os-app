module LanguageTest exposing (suite)

import Expect
import Language exposing (Language(..))
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Language.fromPath"
        [ test "recognizes .scripta" <|
            \_ -> Expect.equal (Just Scripta) (Language.fromPath "notes/a.scripta")
        , test "recognizes .tex" <|
            \_ -> Expect.equal (Just MiniLaTeX) (Language.fromPath "a.tex")
        , test "recognizes .md" <|
            \_ -> Expect.equal (Just Markdown) (Language.fromPath "a.md")
        , test "is case-insensitive" <|
            \_ -> Expect.equal (Just Scripta) (Language.fromPath "A.SCRIPTA")
        , test "recognizes image extensions as Image" <|
            \_ ->
                Expect.equal [ Just Image, Just Image, Just Image, Just Image, Just Image ]
                    (List.map Language.fromPath [ "a.png", "b.jpg", "c.jpeg", "d.gif", "e.webp" ])
        , test "image extension is case-insensitive" <|
            \_ -> Expect.equal (Just Image) (Language.fromPath "PHOTO.JPG")
        , test "unknown extension is PlainText" <|
            \_ -> Expect.equal (Just PlainText) (Language.fromPath "a.xyz")
        , test "no extension is PlainText" <|
            \_ -> Expect.equal (Just PlainText) (Language.fromPath "README")
        , test "v1 supports only Scripta" <|
            \_ ->
                Expect.equal ( True, False, False )
                    ( Language.isSupported Scripta
                    , Language.isSupported MiniLaTeX
                    , Language.isSupported Markdown
                    )
        ]
