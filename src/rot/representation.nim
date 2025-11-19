type
  RotKind* = enum
    Text, Symbol, Assignment, Phrase, Block
  Rot* = object
    case kind*: RotKind
    of Text: text*: string
    of Symbol: symbol*: string
    of Assignment: assignment*: RotAssignment
    of Phrase: phrase*: RotPhrase
    of Block: `block`*: RotBlock
  RotBlock* = object
    items*: seq[RotPhrase]
  RotPhrase* = object
    items*: seq[Rot]
  RotAssignment* = object
    items*: ref tuple[left, right: Rot]
