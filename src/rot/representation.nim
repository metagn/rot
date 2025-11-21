type
  RotKind* = enum
    Text, Symbol, Association, Phrase, Block
  Rot* = object
    case kind*: RotKind
    of Text: text*: string
    of Symbol: symbol*: string
    of Association: association*: RotAssociation
    of Phrase: phrase*: RotPhrase
    of Block: `block`*: RotBlock
  RotBlock* = object
    items*: seq[RotPhrase]
  RotPhrase* = object
    items*: seq[Rot]
  RotAssociation* = object
    items*: ref tuple[left, right: Rot]
