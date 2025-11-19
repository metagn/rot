import ./representation, std/strutils, hemodyne/syncvein

type RotParser* = object
  done*: bool
  vein*: Vein
  pos, previousPos: int
  line*, column*: int
  previousCol: int
  current: char

proc initRotParser*(str: sink string = ""): RotParser =
  result = RotParser(vein: initVein(str))

proc initRotParser*(loader: proc(): string): RotParser =
  result = RotParser(vein: initVein(loader))

proc extendBufferOne(parser: var RotParser) =
  let remove = parser.vein.extendBufferOne()
  parser.pos -= remove
  parser.previousPos -= remove

proc peekCharOrZero(parser: var RotParser): char =
  if parser.pos < parser.vein.buffer.len:
    result = parser.vein.buffer[parser.pos]
  else:
    parser.extendBufferOne()
    if parser.pos < parser.vein.buffer.len:
      result = parser.vein.buffer[parser.pos]
    else:
      result = '\0'

proc resetPos*(parser: var RotParser) =
  assert parser.previousPos != -1, "no previous position to reset to"
  parser.pos = parser.previousPos
  parser.previousPos = -1
  parser.column = parser.previousCol
  if parser.current == '\n':
    dec parser.line

proc nextChar*(parser: var RotParser): bool =
  ## updates line and column considering \r\n
  parser.previousPos = parser.pos
  parser.previousCol = parser.column
  let c =
    if parser.pos < parser.vein.buffer.len:
      parser.vein.buffer[parser.pos]
    else:
      parser.extendBufferOne()
      if parser.pos < parser.vein.buffer.len:
        parser.vein.buffer[parser.pos]
      else:
        parser.done = true
        return false
  parser.current = c
  inc parser.pos
  if parser.current == '\n' or
      (parser.current == '\r' and (inc parser.pos;
        parser.peekCharOrZero() != '\n' and
          (dec parser.pos; true))):
    parser.line += 1
    parser.column = 0
  else:
    parser.column += 1
  parser.vein.setFreeBefore(parser.previousPos)
  result = true

iterator chars*(parser: var RotParser): char =
  while parser.nextChar():
    yield parser.current

proc error*(parser: var RotParser, msg: string) =
  raiseAssert(msg)

const SymbolDisallowedChars = {',', ';', ':', '=', '{', '}', '(', ')'} + Whitespace

proc parseSymbol*(parser: var RotParser): string =
  result = ""
  for ch in parser.chars:
    case ch
    of SymbolDisallowedChars:
      parser.resetPos()
      return
    else:
      result.add ch

proc parseQuoted*(parser: var RotParser, quote: char): string =
  result = ""
  for ch in parser.chars:
    if ch == quote:
      if parser.peekCharOrZero() == quote:
        let gotNext = parser.nextChar()
        assert gotNext
        result.add(quote)
      else:
        return
    else:
      result.add(ch)
  parser.error("expected closing quote for " & $quote)

proc parseTerm*(parser: var RotParser, start: char): Rot

proc parsePhraseItem*(parser: var RotParser, start: char, newlineSensitive: bool): Rot =
  result = parseTerm(parser, start)
  for ch in parser.chars:
    case ch
    of Whitespace - Newlines:
      # could also make removing newlines conditional on newlineSensitive
      discard
    of '=':
      for ch2 in parser.chars:
        if ch2 notin Whitespace:
          break
      if parser.done:
        parser.error("expected phrase term, got end of file")
      let right = parseTerm(parser, parser.current)
      var assignment = RotAssignment()
      new(assignment.items)
      assignment.items.left = result
      assignment.items.right = right
      result = Rot(kind: Assignment, assignment: assignment)
    else:
      parser.resetPos()
      return

proc parsePhrase*(parser: var RotParser, newlineSensitive: bool): RotPhrase =
  result = RotPhrase(items: @[])
  var currentlyNewlineSensitive = newlineSensitive
  for ch in parser.chars:
    case ch
    of ',':
      currentlyNewlineSensitive = false
    of ';':
      #parser.resetPos()
      return
    of Whitespace - Newlines:
      discard
    of Newlines:
      if currentlyNewlineSensitive:
        return
    of ')', '}':
      # other context
      parser.resetPos()
      return
    #of ':': XXX implement
    else:
      let item = parsePhraseItem(parser, ch, currentlyNewlineSensitive)
      result.items.add item
  if result.items.len == 0:
    parser.error("phrase cannot be empty")
    # should not happen in block, only () case

proc parseBlock*(parser: var RotParser): RotBlock =
  result = RotBlock(items: @[])
  for ch in parser.chars:
    case ch
    of ')', '}':
      # other context
      parser.resetPos()
      return
    of Whitespace:
      discard
    of ';':
      discard
    else:
      parser.resetPos()
      let phrase = parsePhrase(parser, newlineSensitive = true)
      result.items.add phrase

proc parseTerm*(parser: var RotParser, start: char): Rot =
  case start
  of '"':
    let s = parseQuoted(parser, start)
    assert parser.current == start
    #if not parser.nextChar():
    #  parser.error("expected closing quote for " & $start)
    result = Rot(kind: Text, text: s)
  of '`':
    let s = parseQuoted(parser, start)
    assert parser.current == start
    #if not parser.nextChar():
    #  parser.error("expected closing quote for " & $start)
    result = Rot(kind: Symbol, symbol: s)
  of '(':
    let p = parsePhrase(parser, newlineSensitive = false)
    let gotNext = parser.nextChar()
    if gotNext and parser.current == ')':
      discard
    else:
      parser.error("expected ) for enclosed phrase")
    result = Rot(kind: Phrase, phrase: p)
  of '{':
    let b = parseBlock(parser)
    let gotNext = parser.nextChar()
    if gotNext and parser.current == '}':
      discard
    else:
      parser.error("expected } for enclosed block")
    result = Rot(kind: Block, `block`: b)
  #of '[': XXX decide if to implement, maybe not a bad idea
  else:
    if start in SymbolDisallowedChars:
      parser.error("expected phrase term, got " & $start)
    else:
      parser.resetPos()
      let s = parseSymbol(parser)
      result = Rot(kind: Symbol, symbol: s)

proc parseFullBlock*(parser: var RotParser): RotBlock =
  result = parseBlock(parser)
  if not parser.done:
    parser.error("block finished before input: " & $parser.current)

proc nextPhrase*(parser: var RotParser; phrase: var RotPhrase): bool =
  if parser.done:
    return false
  if parser.current in Whitespace + {';'}:
    while parser.current in Whitespace + {';'}:
      if not parser.nextChar():
        return false
    parser.resetPos()
  phrase = parsePhrase(parser, newlineSensitive = true)
  result = true
