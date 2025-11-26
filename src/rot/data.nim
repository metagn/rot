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
  RotValueError* = object of CatchableError

proc rotUnit*(): RotTerm {.inline.} =
  result = RotTerm(kind: Unit)

proc rotText*(s: sink string): RotTerm {.inline.} =
  result = RotTerm(kind: Text, text: s)

proc rotSymbol*(s: sink string): RotTerm {.inline.} =
  result = RotTerm(kind: Symbol, symbol: s)

proc rotAssociation*(a, b: sink RotTerm): RotTerm {.inline.} =
  result = RotTerm(kind: Association, association: (ref RotAssociation)(left: a, right: b))

proc rotPhrase*(head: sink RotTerm, tail: varargs[RotTerm]): RotTerm {.inline.} =
  var phrase = RotPhrase()
  newSeq(phrase.items, tail.len + 1)
  phrase.items[0] = head
  for i in 0 ..< tail.len:
    phrase.items[i + 1] = tail[i]
  result = RotTerm(kind: Phrase, phrase: phrase)

proc rotPhrase*(items: openArray[RotTerm]): RotTerm {.inline.} =
  result = RotTerm(kind: Phrase, phrase: RotPhrase(items: @items))

proc rotBlock*(items: varargs[RotPhrase]): RotTerm {.inline.} =
  result = RotTerm(kind: Block, `block`: RotBlock(items: @items))

proc `==`*(a, b: RotTerm): bool {.noSideEffect.} =
  if a.kind != b.kind: return false
  case a.kind
  of Unit: result = true
  of Text: result = a.text == b.text
  of Symbol: result = a.symbol == b.symbol
  of Association:
    if system.`==`(a.association, b.association):
      return true
    if a.association.isNil:
      return false
    result = a.association.left == b.association.left and
      a.association.right == b.association.right
  of Phrase:
    result = a.phrase.items == b.phrase.items
  of Block:
    result = a.block.items == b.block.items

proc uglyPrint*(result: var string; a: RotTerm) =
  case a.kind
  of Unit:
    result.add "()"
  of Symbol:
    const SimpleChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-', '+'}
    var quoted = false
    for c in a.symbol:
      if c notin SimpleChars:
        quoted = true
        break
    if quoted:
      result.add '`'
      for c in a.symbol:
        if c == '`':
          result.add c
        result.add c
      result.add '`'
    else:
      result.add a.symbol
  of Text:
    result.add '"'
    for c in a.text:
      if c == '"':
        result.add c
      result.add c
    result.add '"'
  of Association:
    result.uglyPrint(a.association.left)
    result.add '='
    result.uglyPrint(a.association.right)
  of Phrase:
    result.add '('
    for i, item in a.phrase.items:
      if i != 0: result.add ','
      result.uglyPrint(item)
    result.add ')'
  of Block:
    result.add '{'
    for i, phrase in a.block.items:
      if i != 0: result.add ';'
      for j, item in phrase.items:
        if j != 0: result.add ','
        result.uglyPrint(item)
    result.add '}'

proc uglyPrint*(a: RotTerm): string {.inline.} =
  result = ""
  result.uglyPrint(a)

proc `$`*(a: RotTerm): string {.inline.} =
  result = uglyPrint(a)
