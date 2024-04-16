{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}

{-# HLINT ignore "Use tuple-section" #-}
module Sectioning.Sectioning where

import Core.Errors
import Core.FilePositions
import Core.Utils
import Data.Sequence (Seq)
import Lexing.Tokens

data Section
  = TokenSection Token
  | ParenSection Range (Seq Section)
  | BraceSection Range (Seq Section)
  deriving (Show)

instance WithRange Section where
  getRange (TokenSection token) = getRange token
  getRange (ParenSection range _) = range
  getRange (BraceSection range _) = range

instance Pretty Section where
  pretty (TokenSection token) = pretty token
  pretty (ParenSection _ inner) = "( " ++ foldMap (\section -> pretty section ++ " ") inner ++ ")"
  pretty (BraceSection _ inner) = "{ " ++ foldMap (\section -> pretty section ++ " ") inner ++ "}"

newtype SectioningParser a = SectioningParser {runParser :: Seq Token -> (Seq Token, WithErrors a)}

instance Functor SectioningParser where
  fmap f parser = SectioningParser $ \tokens ->
    case runParser parser tokens of
      (restTokens, Success a) -> (restTokens, Success $ f a)
      (restTokens, Error e) -> (restTokens, Error e)

instance Applicative SectioningParser where
  pure a = SectioningParser $ \tokens -> (tokens, Success a)
  (<*>) parserF parserA = SectioningParser $ \tokens ->
    case runParser parserF tokens of
      (restTokens, Success f) -> runParser (fmap f parserA) restTokens
      (restTokens, Error e) -> (restTokens, Error e)

instance Monad SectioningParser where
  parserA >>= makeParserB = SectioningParser $ \tokens ->
    case runParser parserA tokens of
      (restTokens, Success a) -> runParser (makeParserB a) restTokens
      (restTokens, Error e) -> (restTokens, Error e)