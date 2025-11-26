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

proc rotUnit*(): RotTerm {.inline.} =
  result = RotTerm(kind: Unit)

proc rotText*(s: string): RotTerm {.inline.} =
  result = RotTerm(kind: Text, text: s)

proc rotSymbol*(s: string): RotTerm {.inline.} =
  result = RotTerm(kind: Symbol, symbol: s)

proc rotAssociation*(a, b: RotTerm): RotTerm {.inline.} =
  result = RotTerm(kind: Association, association: (ref RotAssociation)(left: a, right: b))

proc rotPhrase*(items: varargs[RotTerm]): RotTerm {.inline.} =
  result = RotTerm(kind: Phrase, phrase: RotPhrase(items: @items))

proc rotBlock*(items: varargs[RotPhrase]): RotTerm {.inline.} =
  result = RotTerm(kind: Block, `block`: RotBlock(items: @items))
