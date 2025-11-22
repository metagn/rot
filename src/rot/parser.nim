import ./representation, std/strutils, hemodyne/syncvein

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
  RotOptions* = object
    colon*: SpecialCharacterStrategy
    bracket*: SpecialCharacterStrategy
    comment*: SpecialCharacterStrategy
    inlineSpace*, newline*: DelimiterStrategy
  RotParser* = object
    options*: RotOptions
    done*: bool
    vein*: Vein
    pos, previousPos: int
    line*, column*: int
    previousCol: int
    current: char
    recordLineIndent: bool
    currentLineIndent: int

proc defaultRotOptions*(): RotOptions =
  result = RotOptions(colon: EnableFeature, bracket: EnableFeature)

proc initRotParser*(str: sink string = "", options = defaultRotOptions()): RotParser =
  result = RotParser(vein: initVein(str), options: options)

proc initRotParser*(loader: proc(): string, options = defaultRotOptions()): RotParser =
  result = RotParser(vein: initVein(loader), options: options)

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
  ## updates line and column considering \r\n, tracks indent
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
    parser.recordLineIndent = true
    parser.currentLineIndent = 0
    parser.line += 1
    parser.column = 0
  else:
    if parser.recordLineIndent:
      if parser.current in Whitespace:
        inc parser.currentLineIndent
      else:
        parser.recordLineIndent = false
    parser.column += 1
  parser.vein.setFreeBefore(parser.previousPos)
  result = true

iterator rawChars*(parser: var RotParser): char =
  while parser.nextChar():
    yield parser.current

proc error*(parser: var RotParser, msg: string) =
  raiseAssert(msg)

iterator charsHandleComments*(parser: var RotParser): char =
  var comment = false
  for ch in parser.rawChars:
    case ch
    of '#':
      case parser.options.comment
      of DisableFeature:
        parser.error("comments disabled")
      of EnableFeature:
        comment = true
      of TreatAsSymbol:
        discard
    of Newlines:
      comment = false
    else: discard
    if not comment:
      yield ch

const DefaultSymbolDisallowedChars = {',', ';', ':', '=', '{', '}', '(', ')', '[', ']', '#'} + Whitespace

proc symbolDisallowedChars*(parser: var RotParser): set[char] =
  result = DefaultSymbolDisallowedChars
  if parser.options.colon == TreatAsSymbol:
    result.excl(':')
  if parser.options.bracket == TreatAsSymbol:
    result.excl({'[', ']'})
  if parser.options.comment == TreatAsSymbol:
    result.excl('#')
  if parser.options.inlineSpace == TreatAsSymbolStart:
    result.excl(Whitespace - Newlines)
  if parser.options.newline == TreatAsSymbolStart:
    result.excl(Newlines)

proc parseSymbol*(parser: var RotParser): string =
  result = ""
  let disallowedChars = parser.symbolDisallowedChars
  var concatChars: set[char] = {}
  if parser.options.inlineSpace == ConcatenateSymbol:
    concatChars.incl(Whitespace - Newlines)
  if parser.options.newline == ConcatenateSymbol:
    concatChars.incl(Newlines)
  var concat = ""
  for ch in parser.rawChars:
    if ch in disallowedChars:
      parser.resetPos()
      return
    elif ch in concatChars:
      concat.add ch
    else:
      if concat.len != 0:
        result.add concat
        concat = ""
      result.add ch

proc parseQuoted*(parser: var RotParser, quote: char): string =
  result = ""
  for ch in parser.rawChars:
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

proc parseColonString*(parser: var RotParser): string =
  result = ""
  let startIndent = parser.currentLineIndent
  var newline = false
  var finalIndent = startIndent
  # start:
  for ch in parser.rawChars: # no comments
    case ch
    of Whitespace - Newlines:
      discard
    of Newlines:
      newline = true
    else:
      finalIndent = parser.currentLineIndent
      parser.resetPos()
      break
  if newline:
    if finalIndent <= startIndent:
      return
    var currentLine = ""
    var newlineQueue = ""
    template addPrecedingNewlines() =
      if newlineQueue.len != 0:
        result.add(newlineQueue)
        newlineQueue = ""
    template addInLine(c: char) =
      addPrecedingNewlines()
      currentLine.add(ch)
    var recordIndent = false
    var indent = finalIndent
    for ch in parser.rawChars: # no comments
      case ch
      of Whitespace - Newlines:
        if indent >= finalIndent:
          addInLine(ch)
        if recordIndent:
          inc indent
          if indent == finalIndent:
            addPrecedingNewlines()
      of Newlines:
        result.add(currentLine)
        currentLine = ""
        newlineQueue.add(ch)
        recordIndent = true
        indent = 0
      else:
        if indent >= finalIndent:
          addInLine(ch)
        else:
          parser.resetPos()
          return
        recordIndent = false
    result.add(currentLine)
  else:
    for ch in parser.rawChars:
      case ch
      of Newlines:
        parser.resetPos() # don't consume newline
        return
      else:
        result.add(ch)

proc parsePhrase*(parser: var RotParser, newlineSensitive: bool): RotPhrase

proc parseColonBlock*(parser: var RotParser): RotBlock =
  result = RotBlock(items: @[])
  let startIndent = parser.currentLineIndent
  var newline = false
  var finalIndent = startIndent
  # start:
  for ch in parser.charsHandleComments:
    case ch
    of Whitespace - Newlines: discard
    of Newlines:
      newline = true
    else:
      finalIndent = parser.currentLineIndent
      parser.resetPos()
      break
  if newline:
    if finalIndent <= startIndent:
      return
    for ch in parser.charsHandleComments:
      case ch
      of Whitespace - Newlines:
        discard
      of Newlines:
        discard
      of ';':
        if parser.currentLineIndent < finalIndent:
          parser.resetPos()
          return
      else:
        if parser.currentLineIndent < finalIndent:
          parser.resetPos()
          return
        else:
          parser.resetPos()
          let p = parsePhrase(parser, newlineSensitive = true)
          assert p.items.len != 0
          result.items.add p
  else:
    for ch in parser.charsHandleComments:
      case ch
      of Newlines:
        parser.resetPos() # don't consume newline
        return
      of ';':
        discard
      else:
        parser.resetPos()
        let p = parsePhrase(parser, newlineSensitive = true)
        assert p.items.len != 0
        result.items.add p

proc parseTerm*(parser: var RotParser, start: char): Rot

proc parsePhraseItem*(parser: var RotParser, start: char, newlineSensitive: bool): Rot =
  result = parseTerm(parser, start)
  for ch in parser.charsHandleComments:
    case ch
    of Whitespace - Newlines:
      # could also make removing newlines conditional on newlineSensitive
      discard
    of '=':
      for ch2 in parser.charsHandleComments:
        if ch2 notin Whitespace:
          break
      if parser.done:
        parser.error("expected phrase term, got end of file")
      let right = parseTerm(parser, parser.current)
      var association = RotAssociation()
      new(association.items)
      association.items.left = result
      association.items.right = right
      result = Rot(kind: Association, association: association)
    else:
      parser.resetPos()
      return

proc parsePhrase*(parser: var RotParser, newlineSensitive: bool): RotPhrase =
  result = RotPhrase(items: @[])
  var currentlyNewlineSensitive = newlineSensitive
  var expectingItem = true
  template parseItem() =
    if not expectingItem:
      parser.error("expected comma delimiter between phrase terms")
    let item = parsePhraseItem(parser, ch, currentlyNewlineSensitive)
    result.items.add item
    currentlyNewlineSensitive = newlineSensitive
    if parser.options.inlineSpace != EnableDelimiter:
      # no character also counts as inline space delimiter
      expectingItem = false
  for ch in parser.charsHandleComments:
    case ch
    of ',':
      currentlyNewlineSensitive = false
      expectingItem = true
    of ';':
      parser.resetPos() # don't consume semicolon
      return
    of Whitespace - Newlines:
      if parser.options.inlineSpace == TreatAsSymbolStart:
        parseItem()
    of Newlines:
      case parser.options.newline
      of TreatAsSymbolStart:
        parseItem()
      of EnableDelimiter:
        if currentlyNewlineSensitive:
          parser.resetPos() # don't consume newline
          return
      else: discard
    of ')', '}':
      # other context
      parser.resetPos()
      return
    of ']':
      if parser.options.bracket == TreatAsSymbol:
        parseItem()
      else:
        # other context
        parser.resetPos()
        return
    of ':':
      case parser.options.colon
      of DisableFeature:
        parser.error("colon syntax disabled")
      of EnableFeature:
        if not newlineSensitive: # and parser.options.newline == EnableDelimiter
          parser.error("colon syntax not allowed outside of block context")
        let colonBlock = parser.peekCharOrZero() == ':'
        if colonBlock:
          let gotNext = parser.nextChar()
          assert gotNext
        let associate = parser.peekCharOrZero() == '='
        if associate:
          if result.items.len != 1:
            parser.error("expected single lhs for colon association")
          let gotNext = parser.nextChar()
          assert gotNext
        var rhs: Rot
        if colonBlock:
          let b = parseColonBlock(parser)
          rhs = Rot(kind: Block, `block`: b)
        else:
          let s = parseColonString(parser)
          rhs = Rot(kind: Text, text: s)
        if associate:
          let lhs =
            if result.items.len == 1: result.items[0]
            else: Rot(kind: Phrase, phrase: result)
          var assoc = RotAssociation()
          new(assoc.items)
          assoc.items.left = lhs
          assoc.items.right = rhs
          result = RotPhrase(items: @[Rot(kind: Association, association: assoc)])
        else:
          result.items.add(rhs)
        return
      of TreatAsSymbol:
        parseItem()
    else:
      parseItem()

proc parseBlock*(parser: var RotParser): RotBlock =
  result = RotBlock(items: @[])
  for ch in parser.charsHandleComments:
    case ch
    of ')', '}':
      # other context
      parser.resetPos()
      return
    of Whitespace - Newlines:
      if parser.options.inlineSpace == TreatAsSymbolStart:
        parser.resetPos()
        let phrase = parsePhrase(parser, newlineSensitive = true)
        assert phrase.items.len != 0
        result.items.add phrase
    of Newlines:
      if parser.options.newline == TreatAsSymbolStart:
        parser.resetPos()
        let phrase = parsePhrase(parser, newlineSensitive = true)
        assert phrase.items.len != 0
        result.items.add phrase
    of ';':
      discard
    else:
      parser.resetPos()
      let phrase = parsePhrase(parser, newlineSensitive = true)
      assert phrase.items.len != 0
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
    if p.items.len == 0:
      result = Rot(kind: Unit)
    else:
      result = Rot(kind: Phrase, phrase: p)
  of '{':
    let b = parseBlock(parser)
    let gotNext = parser.nextChar()
    if gotNext and parser.current == '}':
      discard
    else:
      parser.error("expected } for enclosed block")
    result = Rot(kind: Block, `block`: b)
  of '[':
    case parser.options.bracket
    of DisableFeature:
      parser.error("bracket syntax disabled")
    of EnableFeature:
      let p = parsePhrase(parser, newlineSensitive = false)
      let gotNext = parser.nextChar()
      if gotNext and parser.current == ']':
        discard
      else:
        parser.error("expected ] for enclosed block")
      var b = RotBlock()
      newSeq(b.items, p.items.len)
      for i in 0 ..< p.items.len:
        b.items[i] = RotPhrase(items: @[p.items[i]])
      result = Rot(kind: Block, `block`: b)
    of TreatAsSymbol:
      parser.resetPos()
      let s = parseSymbol(parser)
      result = Rot(kind: Symbol, symbol: s)
  else:
    if start in parser.symbolDisallowedChars:
      parser.error("expected phrase term, got " & $start)
    else:
      parser.resetPos()
      let s = parseSymbol(parser)
      result = Rot(kind: Symbol, symbol: s)

proc parseFullBlock*(parser: var RotParser): RotBlock =
  result = parseBlock(parser)
  if not parser.done:
    parser.error("block finished before input: " & $parser.current)

proc nextPhraseStart*(parser: var RotParser): bool =
  if parser.done:
    return false
  var blockIgnored = Whitespace + {';'}
  if parser.options.inlineSpace == TreatAsSymbolStart:
    blockIgnored.excl(Whitespace - Newlines)
  if parser.options.newline == TreatAsSymbolStart:
    blockIgnored.excl(Newlines)
  if parser.current in blockIgnored:
    while parser.current in blockIgnored:
      if not parser.nextChar():
        return false
    parser.resetPos()
  result = true

proc nextPhrase*(parser: var RotParser; phrase: var RotPhrase, newlineSensitive = true): bool =
  if not nextPhraseStart(parser):
    return false
  phrase = parsePhrase(parser, newlineSensitive = newlineSensitive)
  result = true

proc nextPhraseItemStart*(parser: var RotParser, newlineSensitive: var bool): bool =
  if parser.done:
    return false
  var phraseIgnored = Whitespace + {','}
  if parser.options.inlineSpace == TreatAsSymbolStart:
    phraseIgnored.excl(Whitespace - Newlines)
  if parser.options.newline == TreatAsSymbolStart:
    phraseIgnored.excl(Newlines)
  if parser.current in phraseIgnored:
    while parser.current in phraseIgnored:
      case parser.current
      of ',':
        newlineSensitive = true
      of Newlines:
        if newlineSensitive:
          parser.resetPos()
          return false
      else: discard
      if not parser.nextChar():
        return false
    parser.resetPos()
  result = true

proc nextPhraseItem*(parser: var RotParser; item: var Rot; newlineSensitive = true): bool =
  var newlineSensitive = newlineSensitive
  if not nextPhraseItemStart(parser, newlineSensitive):
    return false
  item = parsePhraseItem(parser, parser.current, newlineSensitive)
  result = true
