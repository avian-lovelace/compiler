module Parsing.Parser
  ( parseFile,
  )
where

import Control.Applicative
import Core.Errors
import Core.FilePositions
import Core.SyntaxTree
import Core.Utils
import Data.Foldable
import Data.Sequence (Seq (Empty, (:<|)), breakl, singleton, (<|))
import Lexing.Tokens
import Parsing.Parsing
import Parsing.SyntaxTree
import Sectioning.Sectioning (Section (ParenSection, TokenSection))

parseFile :: ParseFunction PFileScope
parseFile sections = FileScope () <$> foldrWithErrors (<|) Empty (parseStatements sections)

parseStatements :: Seq Section -> Seq (WithErrors PStatement)
parseStatements Empty = Empty
parseStatements sections = case breakl matchSemicolon sections of
  (statementSections, Empty) -> singleton $ Error [ExpectedToEndWithSemicolonError $ getRange statementSections]
  (statementSections, _semicolon :<| restTokens) -> parseStatement statementSections <| parseStatements restTokens

matchSemicolon :: Section -> Bool
matchSemicolon (TokenSection (SemicolonToken _)) = True
matchSemicolon _ = False

-- Statements

parseStatement :: ParseFunction PStatement
parseStatement Empty = singleError $ ShouldNotGetHereError "To be implemented"
parseStatement (currentSection :<| tailSections) = case currentSection of
  TokenSection (PrintToken _) -> parsePrintStatement currentSection tailSections
  TokenSection (LetToken _) -> parseVariableDeclarationStatement currentSection tailSections
  TokenSection (MutToken _) -> parseVariableMutationStatement currentSection tailSections
  _ -> singleError $ ShouldNotGetHereError "To be implemented"

parsePrintStatement :: Section -> ParseFunction PStatement
parsePrintStatement printTokenSection expressionSections = case expressionSections of
  Empty -> singleError $ PrintStatementEmptyExpressionError $ getRange printTokenSection
  _ -> PrintStatement statementRange <$> expressionOrErrors
    where
      statementRange = getRange (printTokenSection, seqTail expressionSections)
      expressionRange = getRange expressionSections
      expressionOrErrors = catchUnboundError (PrintStatementInvalidExpressionError expressionRange) $ runParserToEnd expressionParser expressionSections

parseVariableDeclarationStatement :: Section -> ParseFunction PStatement
parseVariableDeclarationStatement
  letTokenSection
  ((TokenSection (IdentifierToken _ _)) :<| (TokenSection (EqualsToken equalsRange)) :<| Empty) =
    singleError $ VariableDeclarationEmptyExpressionError $ getRange (letTokenSection, equalsRange)
parseVariableDeclarationStatement
  letTokenSection
  ((TokenSection (IdentifierToken identifierRange identifier)) :<| (TokenSection (EqualsToken _)) :<| expressionSections) =
    VariableDeclarationStatement statementRange variableName <$> expression
    where
      statementRange = getRange (letTokenSection, seqTail expressionSections)
      variableName = VariableName identifierRange identifier
      expression = catchUnboundError (VariableDeclarationInvalidExpressionError expressionRange) $ runParserToEnd expressionParser expressionSections
      expressionRange = getRange expressionSections
parseVariableDeclarationStatement letTokenSection restSections = singleError $ VariableDeclarationMalformedError (getRange (letTokenSection :<| restSections))

parseVariableMutationStatement :: Section -> ParseFunction PStatement
parseVariableMutationStatement
  mutTokenSection
  ((TokenSection (IdentifierToken _ _)) :<| (TokenSection (EqualsToken equalsRange)) :<| Empty) =
    singleError $ VariableMutationEmptyExpressionError $ getRange (mutTokenSection, equalsRange)
parseVariableMutationStatement
  mutTokenSection
  ((TokenSection (IdentifierToken identifierRange identifier)) :<| (TokenSection (EqualsToken _)) :<| expressionSections) =
    VariableMutationStatement statementRange variableName <$> expression
    where
      statementRange = getRange (mutTokenSection, seqTail expressionSections)
      variableName = VariableName identifierRange identifier
      expression = catchUnboundError (VariableMutationInvalidExpressionError expressionRange) $ runParserToEnd expressionParser expressionSections
      expressionRange = getRange expressionSections
parseVariableMutationStatement mutTokenSection restSections = singleError $ VariableDeclarationMalformedError (getRange (mutTokenSection :<| restSections))

-- Expressions

expressionParser :: Parser PExpression
expressionParser = logicalLevelExpressionParser

-- Logical level

logicalLevelExpressionParser :: Parser PExpression
logicalLevelExpressionParser = do
  leftExpression <- equalityLevelExpressionParser
  rightExpressions <- pZeroOrMore $ do
    operator <- pNext <&&> toLogicalExpression
    rightExpression <- equalityLevelExpressionParser
    return (operator, rightExpression)
  return $ foldl' makeExpression leftExpression rightExpressions
  where
    makeExpression left (operator, right) = operator (getRange (left, right)) left right

toLogicalExpression :: Section -> Maybe (Range -> PExpression -> PExpression -> PExpression)
toLogicalExpression (TokenSection (AndToken _)) = Just AndExpression
toLogicalExpression (TokenSection (OrToken _)) = Just OrExpression
toLogicalExpression _ = Nothing

-- Equality level

equalityLevelExpressionParser :: Parser PExpression
equalityLevelExpressionParser = do
  leftExpression <- comparisonLevelExpressionParser
  rightSide <- pZeroOrOne $ do
    operator <- pNext <&&> toEqualityExpression
    rightExpression <- comparisonLevelExpressionParser
    return (operator, rightExpression)
  return $ case rightSide of
    Nothing -> leftExpression
    Just (operator, rightExpression) -> operator (getRange (leftExpression, rightExpression)) leftExpression rightExpression

toEqualityExpression :: Section -> Maybe (Range -> PExpression -> PExpression -> PExpression)
toEqualityExpression (TokenSection (EqualEqualToken _)) = Just EqualExpression
toEqualityExpression (TokenSection (NotEqualToken _)) = Just NotEqualExpression
toEqualityExpression _ = Nothing

-- Comparison level

comparisonLevelExpressionParser :: Parser PExpression
comparisonLevelExpressionParser = do
  leftExpression <- additionLevelExpressionParser
  rightSide <- pZeroOrOne $ do
    operator <- pNext <&&> toComparisonExpression
    rightExpression <- additionLevelExpressionParser
    return (operator, rightExpression)
  return $ case rightSide of
    Nothing -> leftExpression
    Just (operator, rightExpression) -> operator (getRange (leftExpression, rightExpression)) leftExpression rightExpression

toComparisonExpression :: Section -> Maybe (Range -> PExpression -> PExpression -> PExpression)
toComparisonExpression (TokenSection (GreaterToken _)) = Just GreaterExpression
toComparisonExpression (TokenSection (LessToken _)) = Just LessExpression
toComparisonExpression (TokenSection (GreaterEqualToken _)) = Just GreaterEqualExpression
toComparisonExpression (TokenSection (LessEqualToken _)) = Just LessEqualExpression
toComparisonExpression _ = Nothing

-- Addition/subtraction level

additionLevelExpressionParser :: Parser PExpression
additionLevelExpressionParser = do
  leftExpression <- multiplicationLevelExpressionParser
  rightExpressions <- pZeroOrMore $ do
    operator <- pNext <&&> toAddSubtractExpression
    rightExpression <- multiplicationLevelExpressionParser
    return (operator, rightExpression)
  return $ foldl' makeExpression leftExpression rightExpressions
  where
    makeExpression left (operator, right) = operator (getRange (left, right)) left right

toAddSubtractExpression :: Section -> Maybe (Range -> PExpression -> PExpression -> PExpression)
toAddSubtractExpression (TokenSection (PlusToken _)) = Just AddExpression
toAddSubtractExpression (TokenSection (MinusToken _)) = Just SubtractExpression
toAddSubtractExpression _ = Nothing

-- Multiplication/division/modulo level

multiplicationLevelExpressionParser :: Parser PExpression
multiplicationLevelExpressionParser = do
  leftExpression <- unaryExpressionParser
  rightExpressions <- pZeroOrMore $ do
    operator <- pNext <&&> toMultiplyDivideExpression
    rightExpression <- unaryExpressionParser
    return (operator, rightExpression)
  return $ foldl' makeExpression leftExpression rightExpressions
  where
    makeExpression left (operator, right) = operator (getRange (left, right)) left right

toMultiplyDivideExpression :: Section -> Maybe (Range -> PExpression -> PExpression -> PExpression)
toMultiplyDivideExpression (TokenSection (StarToken _)) = Just MultiplyExpression
toMultiplyDivideExpression (TokenSection (SlashToken _)) = Just DivideExpression
toMultiplyDivideExpression (TokenSection (PercentToken _)) = Just ModuloExpression
toMultiplyDivideExpression _ = Nothing

-- Unary level

-- unaryExpressionParser :: Parser Expression
unaryExpressionParser :: Parser PExpression
unaryExpressionParser = do
  operators <- pZeroOrMore $ pNext <&&> toUnaryExpressionAndRange
  primary <- primaryExpressionParser
  return $ foldr makeExpression primary operators
  where
    makeExpression (operator, range) innerExpression = operator (range <> getRange innerExpression) innerExpression

toUnaryExpressionAndRange :: Section -> Maybe (Range -> PExpression -> PExpression, Range)
toUnaryExpressionAndRange (TokenSection (MinusToken range)) = Just (NegateExpression, range)
toUnaryExpressionAndRange (TokenSection (BangToken range)) = Just (NotExpression, range)
toUnaryExpressionAndRange _ = Nothing

-- Primary level

primaryExpressionParser :: Parser PExpression
primaryExpressionParser = literalOrVariableExpressionParser <|> parenthesesExpressionParser

literalOrVariableExpressionParser :: Parser PExpression
literalOrVariableExpressionParser = pNext <&&> toLiteralExpression

toLiteralExpression :: Section -> Maybe PExpression
toLiteralExpression (TokenSection (IntLiteralToken range value)) = Just $ IntLiteralExpression range value
toLiteralExpression (TokenSection (DoubleLiteralToken range value)) = Just $ DoubleLiteralExpression range value
toLiteralExpression (TokenSection (BoolLiteralToken range value)) = Just $ BoolLiteralExpression range value
toLiteralExpression (TokenSection (IdentifierToken range value)) = Just $ VariableExpression range (VariableName range value)
toLiteralExpression _ = Nothing

parenthesesExpressionParser :: Parser PExpression
parenthesesExpressionParser = do
  (range, innerSections) <- pNext <&&> matchParenSection
  innerExpression <- returnWithErrors $ catchUnboundError (ExpectedExpressionInParensError range) $ runParserToEnd expressionParser innerSections
  return innerExpression

matchParenSection :: Section -> Maybe (Range, Seq Section)
matchParenSection (ParenSection range innerSections) = Just (range, innerSections)
matchParenSection _ = Nothing