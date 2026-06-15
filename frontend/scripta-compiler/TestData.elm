module TestData exposing (..)

import Parser.Pipeline
import Parser.PrimitiveBlock
import V3.Types


q : String -> List V3.Types.ExpressionBlock
q str =
    str
        |> String.lines
        |> Parser.PrimitiveBlock.parse
        |> List.map Parser.Pipeline.toExpressionBlock


{-| Parse a string to primitive blocks.
-}
p : String -> List V3.Types.PrimitiveBlock
p str =
    str
        |> String.lines
        |> Parser.PrimitiveBlock.parse


defaultCompilerParameters : V3.Types.CompilerParameters
defaultCompilerParameters =
    { filter = V3.Types.NoFilter
    , windowWidth = 600
    , theme = V3.Types.Dark
    , editCount = 0
    , width = 600
    , showTOC = False
    , sizing = { baseFontSize = 14.0, paragraphSpacing = 18.0, marginLeft = 0.0, marginRight = 0.0, indentation = 20.0, indentUnit = 2, scale = 1.0 }
    , maxLevel = 1
    }



-- ppb str =  Parser.PrimitiveBlock.parse (String.words str)


str1 =
    """
This is a test:
One two three

| equation
a^2 + b^2 = c^2

| Theorem
There are infintelty many primes.

$$
int_0^1 x^n dx = frac(1,n+1)

"""


cl1 =
    "- One\n- Two\n- Three\n"


cl2 =
    """
. One
. Two
. Three
"""


imgStr =
    """
| image
https://foo.com/yada.jpg
"""


imgStr2 =
    """
| image width:400 caption:Captain Yada
https://foo.com/yada.jpg
"""



-- Multi-line header test data


multiLineHeader1 =
    """
| image width:400
| caption:A beautiful sunset
| alt:Sunset over mountains
https://example.com/sunset.jpg
"""


multiLineHeader2 =
    """
| theorem numbered
| label:main-theorem
| title:Main Result
There are infinitely many primes.
"""


multiLineHeader3 =
    """
| code lang:elm
| highlight:1-5
module Main exposing (..)
"""


multiLineArgs =
    """
| block arg1 arg2
| arg3 arg4
Body content
"""


multiLineMixed =
    """
| theorem numbered
| label:pythagoras
| title:Pythagorean Theorem
For a right triangle with legs a and b and hypotenuse c:
a^2 + b^2 = c^2
"""


{-| Test case from user: block name on first line with no args,
then continuation lines for args and properties.
-}
userTestCase =
    """
| theorem
| foo bar
| title:Pythagorean theorem
| label:pyth
a^2 + b^2 = c^2
"""


{-| Code block whose first body line starts with "| " followed by
an unknown block name. Should be treated as body content,
not as a header continuation.
-}
codeWithPipeInBody =
    """
| code
  | bibitem einstein1905a
  Albert Einstein, blah blah
"""


{-| Code block whose first body line starts with "| " followed by
an unknown word (no colon). Should be body content.
-}
codeWithPipeInBodyNoIndent =
    """
| code
| foo bar
yada yada
"""


{-| Verbatim block with valid property continuation (has colon)
followed by body content starting with "|".
-}
codeWithPropertyThenPipeBody =
    """
| code lang:elm
| highlight:1-5
| bibitem foo
module Main exposing (..)
"""
