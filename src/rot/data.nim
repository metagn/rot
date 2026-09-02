type
  RotKind* = enum
    Unit, Text, Symbol, Phrase, Block
  RotTerm* {.acyclic.} = object
    case kind*: RotKind
    of Unit: discard
    of Text: text*: string
    of Symbol: symbol*: string
    of Phrase: phrase*: RotPhrase
    of Block: `block`*: RotBlock
  RotBlock* = object
    items*: seq[RotPhrase]
  RotArgument* = object
    associated*: bool
      ## associated with the last term (i.e. is `= <term>`)
    term*: RotTerm
  RotPhrase* = object
    items*: seq[RotArgument]
      ## has to be nonempty and first one cannot be associated but this is better for type recursion
  RotValueError* = object of CatchableError

proc rotUnit*(): RotTerm {.inline.} =
  result = RotTerm(kind: Unit)

proc rotText*(s: sink string): RotTerm {.inline.} =
  result = RotTerm(kind: Text, text: s)

proc rotSymbol*(s: sink string): RotTerm {.inline.} =
  result = RotTerm(kind: Symbol, symbol: s)

type RotAssociated* = distinct RotTerm

proc associated*(a: sink RotTerm): RotAssociated {.inline.} =
  result = RotAssociated(a)

proc toArgument*(a: sink RotTerm): RotArgument {.inline.} =
  result = RotArgument(associated: false, term: a)

proc toArgument*(a: sink RotAssociated): RotArgument {.inline.} =
  result = RotArgument(associated: true, term: RotTerm(a))

proc rotPhrase*(head: sink RotTerm, tail: varargs[RotArgument, toArgument]): RotTerm {.inline.} =
  var phrase = RotPhrase()
  newSeq(phrase.items, tail.len + 1)
  phrase.items[0] = toArgument(head)
  for i in 0 ..< tail.len:
    phrase.items[i + 1] = tail[i]
  result = RotTerm(kind: Phrase, phrase: phrase)

proc rotPhrase*(terms: openArray[RotTerm]): RotTerm {.inline.} =
  var items = newSeqOfCap[RotArgument](terms.len)
  for term in terms:
    items.add toArgument(term)
  result = RotTerm(kind: Phrase, phrase: RotPhrase(items: items))

proc head*(phrase: RotPhrase): lent RotTerm {.inline.} =
  phrase.items[0].term

proc head*(phrase: var RotPhrase): var RotTerm {.inline.} =
  phrase.items[0].term

template arguments*(phrase: RotPhrase): openArray[RotArgument] =
  phrase.items.toOpenArray(1, phrase.items.len - 1)

proc rotBlock*(items: sink seq[RotPhrase]): RotTerm {.inline.} =
  result = RotTerm(kind: Block, `block`: RotBlock(items: items))

proc rotBlock*(items: varargs[RotPhrase]): RotTerm {.inline.} =
  rotBlock(@items)

proc `==`*(a, b: RotTerm): bool {.noSideEffect.} =
  if a.kind != b.kind: return false
  case a.kind
  of Unit: result = true
  of Text: result = a.text == b.text
  of Symbol: result = a.symbol == b.symbol
  of Phrase:
    result = a.phrase.items == b.phrase.items
  of Block:
    result = a.block.items == b.block.items

proc addRotQuoted*(result: var string, s: string) =
  result.add '"'
  for c in s:
    if c == '"':
      result.add c
    result.add c
  result.add '"'

proc addRotSymbol*(result: var string, s: string) =
  const SimpleChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-', '+'}
  var quoted = false
  for c in s:
    if c notin SimpleChars:
      quoted = true
      break
  if quoted:
    result.add '`'
    for c in s:
      if c == '`':
        result.add c
      result.add c
    result.add '`'
  else:
    result.add s

proc uglyPrint*(result: var string; a: RotTerm)

proc uglyPrint*(result: var string; a: RotPhrase) {.inline.} =
  result.uglyPrint(a.head)
  for item in a.arguments:
    if item.associated:
      result.add '='
    else:
      result.add ','
    result.uglyPrint(item.term)

proc uglyPrint*(result: var string; a: RotBlock) {.inline.} =
  for i, phrase in a.items:
    if i != 0: result.add ';'
    result.uglyPrint(phrase)

proc uglyPrint*(result: var string; a: RotTerm) =
  case a.kind
  of Unit:
    result.add "()"
  of Symbol:
    result.addRotSymbol(a.symbol)
  of Text:
    result.addRotQuoted(a.text)
  of Phrase:
    result.add '('
    result.uglyPrint(a.phrase)
    result.add ')'
  of Block:
    result.add '{'
    result.uglyPrint(a.block)
    result.add '}'

proc uglyPrint*(a: RotTerm): string {.inline.} =
  result = ""
  result.uglyPrint(a)

proc `$`*(a: RotTerm): string {.inline.} =
  result = uglyPrint(a)

proc getString*(a: RotTerm, str: var string): bool =
  case a.kind
  of Text:
    result = true
    str = a.text
  of Symbol:
    result = true
    str = a.symbol
  else:
    result = false
