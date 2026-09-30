import std/strutils

type
  SpecialCharacterStrategy* = enum
    EnableFeature,
    DisableFeature,
    TreatAsSymbol # implies disabled
  DelimiterStrategy* = enum
    EnableDelimiter,
    DisableDelimiter,
    ConcatenateSymbol, # implies disabled
    TreatAsSymbolStart # implies disabled
  Rot* = object
    ## rot syntax options
    colon*: SpecialCharacterStrategy
    pipe*: SpecialCharacterStrategy
    bracket*: SpecialCharacterStrategy
    comment*: SpecialCharacterStrategy
    inlineSpace*, newline*: DelimiterStrategy
  RotParseError* = object of CatchableError
    filename*: string
    line*, column*: int
    simpleMessage*: string

const DefaultRot* = Rot(
  colon: EnableFeature,
  pipe: EnableFeature,
  bracket: EnableFeature,
  comment: EnableFeature,
  inlineSpace: EnableDelimiter,
  newline: EnableDelimiter)

const DefaultSymbolDisallowedChars = {',', ';', ':', '|', '=', '{', '}', '(', ')', '[', ']', '#'} + Whitespace

proc symbolDisallowedChars*(format: Rot): set[char] =
  result = DefaultSymbolDisallowedChars
  if format.colon == TreatAsSymbol:
    result.excl(':')
  if format.pipe == TreatAsSymbol:
    result.excl('|')
  if format.bracket == TreatAsSymbol:
    result.excl({'[', ']'})
  if format.comment == TreatAsSymbol:
    result.excl('#')
  if format.inlineSpace == TreatAsSymbolStart:
    result.excl(Whitespace - Newlines)
  if format.newline == TreatAsSymbolStart:
    result.excl(Newlines)

proc symbolConcatChars*(format: Rot): set[char] =
  result = {}
  if format.inlineSpace == ConcatenateSymbol:
    result.incl(Whitespace - Newlines)
  if format.newline == ConcatenateSymbol:
    result.incl(Newlines)
