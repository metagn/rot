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
    phrases*: seq[RotPhrase]
  RotItem* = object
    associated*: bool
      ## associated with the last term (i.e. is `= <term>`)
    term*: RotTerm
  RotPhrase* = object
    items*: seq[RotItem]
      ## has to be nonempty and first one cannot be associated but this is better for type recursion
  RotArgument* = object
    ## equivalent representation for phrase items, but not appropriate for streamed parsing
    term*: RotTerm
    associated*: seq[RotTerm]
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

proc toItem*(a: sink RotTerm): RotItem {.inline.} =
  result = RotItem(associated: false, term: a)

proc toItem*(a: sink RotAssociated): RotItem {.inline.} =
  result = RotItem(associated: true, term: RotTerm(a))

proc rotPhrase*(head: sink RotTerm, tail: varargs[RotItem, toItem]): RotTerm {.inline.} =
  var phrase = RotPhrase()
  newSeq(phrase.items, tail.len + 1)
  phrase.items[0] = toItem(head)
  for i in 0 ..< tail.len:
    phrase.items[i + 1] = tail[i]
  result = RotTerm(kind: Phrase, phrase: phrase)

proc rotPhrase*(terms: openArray[RotTerm]): RotTerm {.inline.} =
  var items = newSeqOfCap[RotItem](terms.len)
  for term in terms:
    items.add toItem(term)
  result = RotTerm(kind: Phrase, phrase: RotPhrase(items: items))

proc head*(phrase: RotPhrase): lent RotTerm {.inline.} =
  phrase.items[0].term

proc head*(phrase: var RotPhrase): var RotTerm {.inline.} =
  phrase.items[0].term

template tail*(phrase: RotPhrase): openArray[RotItem] =
  phrase.items.toOpenArray(1, phrase.items.len - 1)

iterator arguments*(phrase: RotPhrase): RotArgument =
  var current = RotArgument(term: phrase.items[0].term)
  for item in phrase.tail:
    if item.associated:
      current.associated.add item.term
    else:
      yield current
      current = RotArgument(term: item.term)
  yield current

proc toArgument*(term: RotTerm, associated: varargs[RotTerm]): RotArgument {.inline.} =
  RotArgument(term: term, associated: @associated)

proc rotPhrase*(arguments: openArray[RotArgument]): RotTerm {.inline.} =
  var items = newSeqOfCap[RotItem](arguments.len)
  for arg in arguments:
    items.add toItem(arg.term)
    for associated in arg.associated:
      items.add RotItem(associated: true, term: associated)
  result = RotTerm(kind: Phrase, phrase: RotPhrase(items: items))

proc rotBlock*(phrases: sink seq[RotPhrase]): RotTerm {.inline.} =
  result = RotTerm(kind: Block, `block`: RotBlock(phrases: phrases))

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
    result = a.block.phrases == b.block.phrases

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
  for item in a.tail:
    if item.associated:
      result.add '='
    else:
      result.add ','
    result.uglyPrint(item.term)

proc uglyPrint*(result: var string; a: RotBlock) {.inline.} =
  for i, phrase in a.phrases:
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
