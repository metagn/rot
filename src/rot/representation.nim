type
  RotKind* = enum
    Unit, Text, Symbol, Association, Phrase, Block
  RotTerm* = object
    case kind*: RotKind
    of Unit: discard
    of Text: text*: string
    of Symbol: symbol*: string
    of Association: association*: ref RotAssociation
    of Phrase: phrase*: RotPhrase
    of Block: `block`*: RotBlock
  RotBlock* = object
    items*: seq[RotPhrase]
  RotPhrase* = object
    items*: seq[RotTerm]
  RotAssociation* = object
    left*, right*: RotTerm
