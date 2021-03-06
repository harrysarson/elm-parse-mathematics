module StateParser exposing (ParserResult, StateParser, expression)

import Char
import Dict exposing (Dict)
import MathDebug
import MathExpression exposing (MathExpression)
import ParserError exposing (ParserError)
import ParserState exposing (ParserState)
import Set


type alias ParserResult =
    { expression : MathExpression String String
    , symbols : List ( String, Int )
    }


type alias StateParser =
    ParserState -> Result ParserError ParserResult


binaryOperatorsDict : List (Dict Char MathExpression.BinaryOperator)
binaryOperatorsDict =
    [ Dict.singleton '+' MathExpression.Add
        |> Dict.insert '-' MathExpression.Subtract
    , Dict.singleton '*' MathExpression.Multiply
        |> Dict.insert '/' MathExpression.Divide
    ]


exponentialOperatorDict : Dict Char MathExpression.BinaryOperator
exponentialOperatorDict =
    Dict.singleton '^' MathExpression.Exponentiate


unaryOperatorsDict : Dict Char MathExpression.UnaryOperator
unaryOperatorsDict =
    Dict.singleton '+' MathExpression.UnaryAdd
        |> Dict.insert '-' MathExpression.UnarySubtract


{-| Parse an expression.
-}
expression : StateParser
expression state =
    MathDebug.log "MathExpression" state
        |> expressionHelper
        |> Result.mapError
            (\({ parseStack } as parserError) ->
                { parserError
                    | parseStack =
                        ( ParserError.MathExpression
                        , state
                        )
                            :: parseStack
                }
            )


expressionHelper : StateParser
expressionHelper =
    let
        binaryParsers =
            List.map binaryOperators binaryOperatorsDict
    in
    ParserState.trimState
        >> List.foldr
            identity
            exponentialOperator
            binaryParsers


binaryOperators : Dict Char MathExpression.BinaryOperator -> StateParser -> StateParser
binaryOperators opDict nextParser =
    checkEmptyState (binaryOperatorsSkipping 0 opDict nextParser)


exponentialOperator : StateParser
exponentialOperator =
    checkEmptyState
        (\state ->
            case ParserState.splitStateSkipping 0 exponentialOperatorDict (MathDebug.log "^ binary operator" state) of
                Just ( lhs, MathExpression.Exponentiate, rhs ) ->
                    let
                        parsedLhsResult =
                            lhs
                                |> ParserState.trimState
                                |> congugateTranspose
                                |> Result.mapError
                                    (\parserError ->
                                        (case parserError.errorType of
                                            ParserError.EmptyString ->
                                                { parserError
                                                    | errorType = ParserError.MissingBinaryOperand ParserError.LeftHandSide
                                                    , parseStack = []
                                                }

                                            _ ->
                                                parserError
                                        )
                                            |> (\({ parseStack } as improvedParserError) ->
                                                    { improvedParserError
                                                        | parseStack =
                                                            ( ParserError.BinaryOperator MathExpression.Exponentiate ParserError.LeftHandSide
                                                            , lhs
                                                            )
                                                                :: parseStack
                                                    }
                                               )
                                    )

                        parsedRhsResult =
                            rhs
                                |> ParserState.trimState
                                |> unaryOperators
                                |> Result.mapError
                                    (\parserError ->
                                        (case parserError.errorType of
                                            ParserError.EmptyString ->
                                                { parserError
                                                    | errorType = ParserError.MissingBinaryOperand ParserError.LeftHandSide
                                                    , parseStack = []
                                                }

                                            _ ->
                                                parserError
                                        )
                                            |> (\({ parseStack } as improvedParserError) ->
                                                    { improvedParserError
                                                        | parseStack =
                                                            ( ParserError.BinaryOperator MathExpression.Exponentiate ParserError.LeftHandSide
                                                            , lhs
                                                            )
                                                                :: parseStack
                                                    }
                                               )
                                    )
                    in
                    Result.map2
                        (\parsedLhs parsedRhs ->
                            { expression = MathExpression.BinaryOperation parsedLhs.expression MathExpression.Exponentiate parsedRhs.expression
                            , symbols = parsedLhs.symbols ++ parsedRhs.symbols
                            }
                        )
                        parsedLhsResult
                        parsedRhsResult

                Just _ ->
                    unaryOperators state

                Nothing ->
                    unaryOperators state
        )


unaryOperators : StateParser
unaryOperators =
    checkEmptyState
        (\state ->
            let
                label =
                    unaryOperatorsDict
                        |> Dict.keys
                        |> List.map String.fromChar
                        |> String.join ", "
                        |> String.append "UnaryOperators "

                { source, start } =
                    MathDebug.log label state
            in
            case String.uncons source of
                Just ( opChar, rhs ) ->
                    case Dict.get opChar unaryOperatorsDict of
                        Just op ->
                            let
                                rhsState =
                                    { state
                                        | source = rhs
                                        , start = start + 1
                                    }
                                        |> ParserState.trimState

                                parsedRhs =
                                    rhsState
                                        |> congugateTranspose
                                        |> Result.mapError
                                            (\parserError ->
                                                case parserError.errorType of
                                                    ParserError.EmptyString ->
                                                        { position = start
                                                        , errorType = ParserError.MissingUnaryOperand
                                                        , parseStack = []
                                                        }

                                                    _ ->
                                                        parserError
                                            )
                                        |> Result.mapError
                                            (\({ parseStack } as parserError) ->
                                                { parserError
                                                    | parseStack =
                                                        ( ParserError.UnaryOperator op
                                                        , rhsState
                                                        )
                                                            :: parseStack
                                                }
                                            )
                            in
                            Result.map
                                (\parseResult ->
                                    { parseResult | expression = MathExpression.UnaryOperation op parseResult.expression }
                                )
                                parsedRhs

                        Nothing ->
                            congugateTranspose state

                Nothing ->
                    congugateTranspose state
        )


congugateTranspose : StateParser
congugateTranspose =
    checkEmptyState
        (\state ->
            let
                { source, start } =
                    MathDebug.log "congugateTranspose" state
            in
            case
                source
                    |> String.reverse
                    |> String.uncons
            of
                Just ( apostrophe, lhsReversed ) ->
                    if apostrophe == '\'' then
                        { state
                            | source = String.reverse lhsReversed
                            , start = start + 1
                        }
                            |> ParserState.trimState
                            |> parenthesis
                            |> Result.map
                                (\parseResult ->
                                    { parseResult | expression = MathExpression.ConjugateTranspose parseResult.expression }
                                )
                            |> Result.mapError
                                (\parserError ->
                                    case parserError.errorType of
                                        ParserError.EmptyString ->
                                            { position = start
                                            , errorType = ParserError.MissingConjugateTransposeOperand
                                            , parseStack = []
                                            }

                                        _ ->
                                            parserError
                                )
                            |> Result.mapError
                                (\({ parseStack } as parserError) ->
                                    { parserError
                                        | parseStack =
                                            ( ParserError.ConjugateTranspose
                                            , state
                                            )
                                                :: parseStack
                                    }
                                )

                    else
                        parenthesis state

                Nothing ->
                    parenthesis state
        )


parenthesis : StateParser
parenthesis =
    checkEmptyState
        (\state ->
            let
                { source, start } =
                    MathDebug.log "Parenthesis" state
            in
            case String.uncons source of
                Just ( possiblyOpenParenthesis, rest ) ->
                    if possiblyOpenParenthesis == '(' then
                        if String.endsWith ")" rest then
                            rest
                                |> String.dropRight 1
                                |> (\parenthesisContent ->
                                        let
                                            parenContentState =
                                                { state
                                                    | source = parenthesisContent
                                                    , start = start + 1
                                                }
                                        in
                                        parenContentState
                                            |> expressionHelper
                                            |> Result.mapError
                                                (\parserError ->
                                                    case parserError.errorType of
                                                        ParserError.EmptyString ->
                                                            { position = start + 1
                                                            , errorType = ParserError.EmptyParentheses
                                                            , parseStack = []
                                                            }

                                                        _ ->
                                                            parserError
                                                )
                                            |> Result.mapError
                                                (\({ parseStack } as parserError) ->
                                                    { parserError
                                                        | parseStack =
                                                            ( ParserError.Parentheses
                                                            , parenContentState
                                                            )
                                                                :: parseStack
                                                    }
                                                )
                                   )

                        else
                            Err
                                { errorType = ParserError.MissingClosingParenthesis
                                , position = start + String.length source - 1
                                , parseStack =
                                    [ ( ParserError.Parentheses
                                      , { state
                                            | source = rest
                                            , start = start + 1
                                        }
                                      )
                                    ]
                                }

                    else
                        symbolOrFunction state

                Nothing ->
                    symbolOrFunction state
        )


symbol : StateParser
symbol =
    checkEmptyState
        (\({ source, start } as state) ->
            case symbolHelper (MathDebug.log "Symbol" state) of
                Nothing ->
                    Ok <|
                        { expression = MathExpression.Symbol source
                        , symbols = [ ( source, start ) ]
                        }

                Just error ->
                    Err
                        { error
                            | parseStack = [ ( ParserError.Symbol, state ) ]
                        }
        )


symbolOrFunction : StateParser
symbolOrFunction =
    checkEmptyState
        (\({ source, start } as state) ->
            case String.split "[" source of
                funcName :: rest0 :: rest ->
                    let
                        bodyAndClosing =
                            String.join "]" (rest0 :: rest)

                        parensStart =
                            start + String.length funcName + 1
                    in
                    if String.endsWith "]" bodyAndClosing then
                        bodyAndClosing
                            |> String.dropRight 1
                            |> (\parenthesisContent ->
                                    let
                                        parenContentState =
                                            { state
                                                | source = parenthesisContent
                                                , start = parensStart
                                            }
                                    in
                                    parenContentState
                                        |> expressionHelper
                                        |> Result.mapError
                                            (\parserError ->
                                                case parserError.errorType of
                                                    ParserError.EmptyString ->
                                                        { position = parenContentState.start
                                                        , errorType = ParserError.EmptyParentheses
                                                        , parseStack = []
                                                        }

                                                    _ ->
                                                        parserError
                                            )
                                        |> Result.mapError
                                            (\({ parseStack } as parserError) ->
                                                { parserError
                                                    | parseStack =
                                                        ( ParserError.Function
                                                        , parenContentState
                                                        )
                                                            :: parseStack
                                                }
                                            )
                                        |> Result.map
                                            (\parseResult ->
                                                { parseResult
                                                    | expression = MathExpression.Function funcName parseResult.expression
                                                }
                                            )
                               )

                    else
                        Err
                            { errorType = ParserError.MissingClosingParenthesis
                            , position = start + String.length source - 1
                            , parseStack =
                                [ ( ParserError.Function
                                  , { state
                                        | source = bodyAndClosing
                                        , start = parensStart
                                    }
                                  )
                                ]
                            }

                _ ->
                    symbol state
        )



-- Helper Functions --


checkEmptyState : StateParser -> StateParser
checkEmptyState parser ({ source, start } as state) =
    case source of
        "" ->
            Err
                { position = start
                , errorType = ParserError.EmptyString
                , parseStack = []
                }

        _ ->
            parser state


binaryOperatorsSkipping : Int -> Dict Char MathExpression.BinaryOperator -> StateParser -> StateParser
binaryOperatorsSkipping numToSkip opDict nextParser ({ source, start } as state) =
    let
        opChars =
            Dict.keys opDict

        label =
            opChars
                |> List.map String.fromChar
                |> String.join ", "
                |> String.append ("BinaryOperators (skipping " ++ String.fromInt numToSkip ++ ") ")
    in
    case ParserState.splitStateSkipping numToSkip opDict (MathDebug.log label state) of
        Just ( lhs, op, rhsAndMore ) ->
            let
                lhsState =
                    ParserState.trimState lhs

                parsedLhsResult =
                    lhsState
                        |> nextParser
                        |> Result.mapError
                            (\parserError ->
                                (case parserError.errorType of
                                    ParserError.EmptyString ->
                                        { parserError
                                            | errorType = ParserError.MissingBinaryOperand ParserError.LeftHandSide
                                            , parseStack = []
                                        }

                                    _ ->
                                        parserError
                                )
                                    |> (\({ parseStack } as improvedParserError) ->
                                            { improvedParserError
                                                | parseStack =
                                                    ( ParserError.BinaryOperator op ParserError.LeftHandSide
                                                    , lhs
                                                    )
                                                        :: parseStack
                                            }
                                       )
                            )
            in
            case parsedLhsResult of
                Ok parsedLhs ->
                    binaryOpRhsHelper 0 opDict nextParser parsedLhs op (ParserState.trimState rhsAndMore)

                Err parserError ->
                    case parserError.errorType of
                        ParserError.MissingBinaryOperand _ ->
                            if isOperatorAlsoUnary op then
                                binaryOperatorsSkipping (numToSkip + 1) opDict nextParser state

                            else
                                Err parserError

                        _ ->
                            Err parserError

        Nothing ->
            nextParser state


binaryOpRhsHelper :
    Int
    -> Dict Char MathExpression.BinaryOperator
    -> StateParser
    -> ParserResult
    -> MathExpression.BinaryOperator
    -> StateParser
binaryOpRhsHelper numToSkip opDict nextParser lhs op rhsAndMore =
    case ParserState.splitStateSkipping numToSkip opDict rhsAndMore of
        Just ( nextRhs, nextOp, moreRhs ) ->
            let
                parsedRhs =
                    nextRhs
                        |> ParserState.trimState
                        |> nextParser
                        |> Result.mapError
                            (\({ parseStack } as parserError) ->
                                { parserError
                                    | parseStack =
                                        ( ParserError.BinaryOperator op ParserError.RightHandSide
                                        , nextRhs
                                        )
                                            :: parseStack
                                }
                            )
            in
            case parsedRhs of
                Ok rhs ->
                    binaryOpRhsHelper
                        0
                        opDict
                        nextParser
                        { expression = MathExpression.BinaryOperation lhs.expression op rhs.expression
                        , symbols = lhs.symbols ++ rhs.symbols
                        }
                        nextOp
                        moreRhs

                Err parserError ->
                    case parserError.errorType of
                        ParserError.MissingBinaryOperand ParserError.RightHandSide ->
                            binaryOpRhsHelper
                                (numToSkip + 1)
                                opDict
                                nextParser
                                lhs
                                op
                                rhsAndMore

                        ParserError.EmptyString ->
                            binaryOpRhsHelper
                                (numToSkip + 1)
                                opDict
                                nextParser
                                lhs
                                op
                                rhsAndMore

                        _ ->
                            Err parserError

        Nothing ->
            rhsAndMore
                |> ParserState.trimState
                |> nextParser
                |> Result.mapError
                    (\parserError ->
                        (case parserError.errorType of
                            ParserError.EmptyString ->
                                { parserError
                                    | errorType = ParserError.MissingBinaryOperand ParserError.RightHandSide
                                    , parseStack = []
                                    , position = parserError.position - 1
                                }

                            _ ->
                                parserError
                        )
                            |> (\({ parseStack } as improvedParserError) ->
                                    { improvedParserError
                                        | parseStack =
                                            ( ParserError.BinaryOperator op ParserError.RightHandSide
                                            , rhsAndMore
                                            )
                                                :: parseStack
                                    }
                               )
                    )
                |> Result.map
                    (\rhs ->
                        { expression = MathExpression.BinaryOperation lhs.expression op rhs.expression
                        , symbols = lhs.symbols ++ rhs.symbols
                        }
                    )


isOperatorAlsoUnary : MathExpression.BinaryOperator -> Bool
isOperatorAlsoUnary op =
    case op of
        MathExpression.Add ->
            True

        MathExpression.Subtract ->
            True

        MathExpression.Multiply ->
            False

        MathExpression.Divide ->
            False

        MathExpression.Exponentiate ->
            False


symbolHelper : ParserState -> Maybe ParserError
symbolHelper ({ source, start } as state) =
    String.uncons source
        |> Maybe.andThen
            (\( firstChar, rest ) ->
                if isValidSymbolChar firstChar then
                    symbolHelper
                        { state
                            | source = rest
                            , start = start + 1
                        }

                else
                    Just
                        { position = start
                        , errorType = ParserError.InvalidChar firstChar
                        , parseStack = []
                        }
            )


isValidSymbolChar : Char -> Bool
isValidSymbolChar charToTest =
    let
        isNumber =
            isCharInRange '0' '9'

        isLowerEnglish =
            isCharInRange 'a' 'z'

        isUpperEnglish =
            isCharInRange 'A' 'Z'

        isPeriod =
            (==) '.'
    in
    isNumber charToTest
        || isLowerEnglish charToTest
        || isUpperEnglish charToTest
        || isPeriod charToTest


isCharInRange : Char -> Char -> Char -> Bool
isCharInRange lower upper char =
    let
        lowerNum =
            Char.toCode lower

        upperNum =
            Char.toCode upper

        charNum =
            Char.toCode char
    in
    charNum >= lowerNum && charNum <= upperNum
