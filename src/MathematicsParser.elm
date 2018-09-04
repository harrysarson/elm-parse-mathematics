module MathematicsParser exposing
    ( expression
    , MathematicsParser
    )

{-| This library allows simple mathematical expressions to be parsed in elm.
A string expression is converted into an abstract syntax tree.


# Mathematics Parsers

@docs MathematicsParser#
@docs expression

-}

import Char
import Expression exposing (Expression)
import MaDebug
import ParseError exposing (ParseError)
import ParseResult exposing (ParseResult)
import Set
import StateParser


{-| A parser that converts a string into a mathematical expression.
-}
type alias MathematicsParser =
    String -> Result ParseError ParseResult


{-| }
} Parse an expression.
-}
expression : MathematicsParser
expression str =
    { source = str
    , start = 0
    }
        |> StateParser.expression



-- Parsers --
