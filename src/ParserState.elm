module ParserState exposing
    ( ParserState
    , splitStateSkipping, trimState
    )

{-| Definition of state used for parsing and functions to manipulate this state.


# Definition

@docs ParserState


# Functions

@docs splitStateSkipping trimState

-}

import Dict exposing (Dict)


{-| The state of a partially parsed expression.

  - `source`: the string to be parsed.
  - `start`: position of source in the original string input.
  - `flags`: list of flags to influence the parsing.

-}
type alias ParserState =
    { source : String
    , start : Int
    }


{-| Split state on a character returning a tuple containing:

1.  The state the the left of the character.
2.  The character the state was split on
3.  The state to the right of the character.

The state will be split on any of the list characters provided.
The first `n` occurrences are ignored.

`Nothing` is returned if `(n + 1)` characters from the list are not contained within the
source of the state.

-}
splitStateSkipping :
    Int
    -> Dict Char a
    -> ParserState
    -> Maybe ( ParserState, a, ParserState )
splitStateSkipping n chars ({ start, source } as state) =
    findNthOneOfHelper
        n
        chars
        { round = 0, square = 0 }
        ""
        state.source
        0
        |> Maybe.map
            (\{ left, splitChar, right, leftSize } ->
                ( { state
                    | source = left
                    , start = start
                  }
                , splitChar
                , { state
                    | source = right
                    , start = start + leftSize + 1
                  }
                )
            )


{-| Remove whitespace and newlines from the beginning and end of state.

Should always trim in the same way as `String.trim` and will update `start` with the number of characters trimmed.

-}
trimState : ParserState -> ParserState
trimState =
    trimStart >> trimEnd


findClosingParenthesis : String -> String -> Int -> Maybe ( String, Int )
findClosingParenthesis previousReversed source index =
    String.uncons source
        |> Maybe.andThen
            (\( possiblyCloseParenthesis, rest ) ->
                if possiblyCloseParenthesis == ')' then
                    Just ( String.reverse previousReversed, index )

                else
                    findClosingParenthesis (String.cons possiblyCloseParenthesis previousReversed) rest (index + 1)
            )



-- todo: missing open or closing parenthesis
-- todo: rename type and function


type alias FindResult a =
    { left : String
    , splitChar : a
    , right : String
    , leftSize : Int
    }


findNthOneOfHelper :
    Int
    -> Dict Char a
    -> { round : Int, square : Int }
    -> String
    -> String
    -> Int
    -> Maybe (FindResult a)
findNthOneOfHelper n chars closesRequired previousReversed source index =
    String.uncons source
        |> Maybe.andThen
            (\( first, rest ) ->
                if closesRequired.round == 0 && closesRequired.square == 0 then
                    if first == '(' then
                        findNthOneOfHelper
                            n
                            chars
                            { round = 1, square = 0 }
                            (String.cons first previousReversed)
                            rest
                            (index + 1)

                    else if first == '[' then
                        findNthOneOfHelper
                            n
                            chars
                            { round = 0, square = 1 }
                            (String.cons first previousReversed)
                            rest
                            (index + 1)

                    else
                        case Dict.get first chars of
                            Just splitChar ->
                                if n == 0 then
                                    Just
                                        { left = String.reverse previousReversed
                                        , splitChar = splitChar
                                        , right = rest
                                        , leftSize = index
                                        }

                                else
                                    findNthOneOfHelper
                                        (n - 1)
                                        chars
                                        { round = 0, square = 0 }
                                        (String.cons first previousReversed)
                                        rest
                                        (index + 1)

                            Nothing ->
                                findNthOneOfHelper
                                    n
                                    chars
                                    { round = 0, square = 0 }
                                    (String.cons first previousReversed)
                                    rest
                                    (index + 1)

                else
                    case first of
                        ')' ->
                            findNthOneOfHelper
                                n
                                chars
                                { closesRequired | round = closesRequired.round - 1 }
                                (String.cons first previousReversed)
                                rest
                                (index + 1)

                        '(' ->
                            findNthOneOfHelper
                                n
                                chars
                                { closesRequired | round = closesRequired.round + 1 }
                                (String.cons first previousReversed)
                                rest
                                (index + 1)

                        ']' ->
                            findNthOneOfHelper
                                n
                                chars
                                { closesRequired | square = closesRequired.square - 1 }
                                (String.cons first previousReversed)
                                rest
                                (index + 1)

                        '[' ->
                            findNthOneOfHelper
                                n
                                chars
                                { closesRequired | square = closesRequired.square + 1 }
                                (String.cons first previousReversed)
                                rest
                                (index + 1)

                        _ ->
                            findNthOneOfHelper
                                n
                                chars
                                closesRequired
                                (String.cons first previousReversed)
                                rest
                                (index + 1)
            )


trimStart : ParserState -> ParserState
trimStart ({ source, start } as state) =
    case String.uncons source of
        Nothing ->
            state

        Just ( ' ', rest ) ->
            trimStart
                { state
                    | source = rest
                    , start = start + 1
                }

        Just ( '\n', rest ) ->
            trimStart
                { state
                    | source = rest
                    , start = start + 1
                }

        Just ( '\u{000D}', rest ) ->
            trimStart
                { state
                    | source = rest
                    , start = start + 1
                }

        Just ( '\t', rest ) ->
            trimStart
                { state
                    | source = rest
                    , start = start + 1
                }

        Just ( first, rest ) ->
            state


trimEnd : ParserState -> ParserState
trimEnd ({ source, start } as state) =
    { state
        | source = String.trimRight source
    }
