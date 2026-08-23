import ./data, std/strutils, fleu/load_buffer

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
    pipe*: SpecialCharacterStrategy
    bracket*: SpecialCharacterStrategy
    comment*: SpecialCharacterStrategy
    inlineSpace*, newline*: DelimiterStrategy
  RotParser* = object
    options*: RotOptions
    done*: bool
    buffer*: LoadBuffer
    pos*, previousPos: int
    filename*: string
    line*, column*: int
    previousCol: int
    current*: char
    recordLineIndent*: bool
    currentLineIndent*: int
  RotParseError* = object of CatchableError
    filename*: string
    line*, column*: int
    simpleMessage*: string

proc defaultRotOptions*(): RotOptions =
  result = RotOptions(
    colon: EnableFeature,
    pipe: EnableFeature,
    bracket: EnableFeature,
    comment: EnableFeature,
    inlineSpace: EnableDelimiter,
    newline: EnableDelimiter)

proc resetParser*(parser: var RotParser) =
  parser.done = false
  parser.pos = 0
  parser.line = 1
  parser.column = 0
  parser.previousPos = -1
  parser.previousCol = -1
  parser.recordLineIndent = false
  parser.currentLineIndent = 0

proc initRotParser*(str: sink string = "", options = defaultRotOptions()): RotParser =
  result = RotParser(buffer: initLoadBuffer(str), options: options)
  resetParser(result)

proc initRotParser*(loader: proc(): string, options = defaultRotOptions()): RotParser =
  result = RotParser(buffer: initLoadBuffer(loader), options: options)
  resetParser(result)

proc loadBufferOne(parser: var RotParser) =
  let remove = parser.buffer.loadOnce()
  parser.pos -= remove
  parser.previousPos -= remove

proc loadBufferBy(parser: var RotParser, n: int) =
  let remove = parser.buffer.loadBy(n)
  parser.pos -= remove
  parser.previousPos -= remove

proc peekCharOrZero*(parser: var RotParser): char =
  if parser.pos < parser.buffer.data.len:
    result = parser.buffer.data[parser.pos]
  else:
    parser.loadBufferOne()
    if parser.pos < parser.buffer.data.len:
      result = parser.buffer.data[parser.pos]
    else:
      result = '\0'

# finite lookahead:

proc peekStr*(parser: var RotParser, len: int, offset = 0): string =
  let minLen = parser.pos + offset + len
  let missingChars = minLen - parser.buffer.data.len
  if missingChars <= 0:
    result = parser.buffer.data[parser.pos + offset ..< minLen]
  else:
    parser.loadBufferBy(missingChars)
    if minLen <= parser.buffer.data.len:
      result = parser.buffer.data[parser.pos + offset ..< minLen]
    else:
      # only available chars
      result = parser.buffer.data[parser.pos + offset ..< parser.buffer.data.len]

proc peekStr*(parser: var RotParser, s: openArray[char], offset = 0): bool =
  let minLen = parser.pos + offset + s.len
  let missingChars = minLen - parser.buffer.data.len
  if missingChars <= 0:
    result = s == parser.buffer.data.toOpenArray(parser.pos + offset, minLen - 1)
  else:
    parser.loadBufferBy(missingChars)
    if minLen <= parser.buffer.data.len:
      result = s == parser.buffer.data.toOpenArray(parser.pos + offset, minLen - 1)
    else:
      result = false

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
    if parser.pos < parser.buffer.data.len:
      parser.buffer.data[parser.pos]
    else:
      parser.loadBufferOne()
      if parser.pos < parser.buffer.data.len:
        parser.buffer.data[parser.pos]
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
  #let saved =
  #  if parser.peekStart >= 0: parser.peekStart
  #  else: parser.previousPos
  parser.buffer.freeBefore = parser.previousPos
  result = true

iterator rawChars*(parser: var RotParser, skipFirst: static bool = true): char =
  when skipFirst:
    while parser.nextChar():
      yield parser.current
  else:
    while true:
      yield parser.current
      if not parser.nextChar():
        break

proc buildErrorMessage*(error: var RotParseError) =
  error.msg = ""
  if error.filename.len != 0:
    error.msg.add(error.filename)
  error.msg.add('(')
  error.msg.addInt(error.line)
  error.msg.add(", ")
  error.msg.addInt(error.column)
  error.msg.add(") ")
  error.msg.add(error.simpleMessage)

proc error*(parser: var RotParser, msg: string) =
  var err = (ref RotParseError)(
    filename: parser.filename,
    line: parser.line, column: parser.column,
    simpleMessage: msg)
  buildErrorMessage(err[])
  raise err

iterator charsHandleComments*(parser: var RotParser, skipFirst: static bool = true): char =
  var comment = false
  for ch in parser.rawChars(skipFirst):
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

const DefaultSymbolDisallowedChars = {',', ';', ':', '|', '=', '{', '}', '(', ')', '[', ']', '#'} + Whitespace

proc symbolDisallowedChars*(options: RotOptions): set[char] =
  result = DefaultSymbolDisallowedChars
  if options.colon == TreatAsSymbol:
    result.excl(':')
  if options.pipe == TreatAsSymbol:
    result.excl('|')
  if options.bracket == TreatAsSymbol:
    result.excl({'[', ']'})
  if options.comment == TreatAsSymbol:
    result.excl('#')
  if options.inlineSpace == TreatAsSymbolStart:
    result.excl(Whitespace - Newlines)
  if options.newline == TreatAsSymbolStart:
    result.excl(Newlines)

proc parseUnquotedSymbol*(parser: var RotParser): string =
  result = ""
  let disallowedChars = parser.options.symbolDisallowedChars
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

proc parseQuotedInner*(parser: var RotParser, quote: char): string =
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

proc parseQuotedText*(parser: var RotParser): string =
  const quote = '"'
  if not parser.nextChar() or parser.current != quote:
    raise newException(RotValueError, "expected quote character for text")
  result = parseQuotedInner(parser, quote)

proc parseText*(parser: var RotParser): string {.inline.} =
  result = parseQuotedText(parser)

proc parseQuotedSymbol*(parser: var RotParser): string =
  const quote = '`'
  if not parser.nextChar() or parser.current != quote:
    raise newException(RotValueError, "expected quote character for symbol")
  result = parseQuotedInner(parser, quote)

proc parseSymbol*(parser: var RotParser): string =
  const quote = '`'
  if parser.peekCharOrZero() == quote:
    result = parseQuotedSymbol(parser)
  else:
    result = parseUnquotedSymbol(parser)

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

type
  PhraseSensitivity* = enum
    Freeform, NewlineSensitive, IndentSensitive
  PhraseContext* = object
    case sensitivity*: PhraseSensitivity
    of Freeform, NewlineSensitive: discard
    of IndentSensitive:
      minIndent*: int

const
  FreePhraseContext* = PhraseContext(sensitivity: Freeform)
  LinePhraseContext* = PhraseContext(sensitivity: NewlineSensitive)

proc parseInlineTermInner*(parser: var RotParser, start: char): RotTerm
proc parseColonBlock*(parser: var RotParser): RotBlock
proc parsePipeInner*(parser: var RotParser): RotPhrase

proc nextStr(parser: var RotParser, s: openArray[char], offset = 0): bool {.inline.} =
  result = parser.peekStr(s, offset)
  if result:
    for _ in 0 ..< s.len:
      let moved = parser.nextChar()
      assert moved

proc parsePhraseItemInner*(parser: var RotParser, start: char, context: PhraseContext, terminate: var bool): RotTerm =
  case start
  of ':':
    case parser.options.colon
    of DisableFeature:
      parser.error("colon syntax disabled")
    of EnableFeature:
      if context.sensitivity == Freeform: # and parser.options.newline == EnableDelimiter
        parser.error("colon syntax not allowed outside of block context")
      let colonBlock = parser.peekCharOrZero() == ':'
      if colonBlock:
        let gotNext = parser.nextChar()
        assert gotNext
      if parser.peekCharOrZero() == '=':
        parser.error("expected lhs for colon association")
      if colonBlock:
        let b = parseColonBlock(parser)
        result = RotTerm(kind: Block, `block`: b)
      else:
        let s = parseColonString(parser)
        result = RotTerm(kind: Text, text: s)
      terminate = context.sensitivity != IndentSensitive
      return
    of TreatAsSymbol:
      result = parseInlineTermInner(parser, start)
  of '|':
    case parser.options.colon
    of DisableFeature:
      parser.error("pipe syntax disabled")
    of EnableFeature:
      if context.sensitivity == Freeform: # and parser.options.newline == EnableDelimiter
        parser.error("pipe syntax not allowed outside of block context")
      let pipeBlock = parser.peekCharOrZero() == '|'
      if pipeBlock:
        let gotNext = parser.nextChar()
        assert gotNext
      if parser.peekCharOrZero() == '=':
        parser.error("expected lhs for pipe association")
      let p = parsePipeInner(parser)
      if pipeBlock:
        var b = RotBlock()
        newSeq(b.items, p.items.len)
        for i in 0 ..< p.items.len:
          b.items[i] = RotPhrase(items: @[p.items[i]])
        result = RotTerm(kind: Block, `block`: b)
      else:
        result = RotTerm(kind: Phrase, phrase: p)
      terminate = context.sensitivity != IndentSensitive
      return
    of TreatAsSymbol:
      result = parseInlineTermInner(parser, start)
  else:
    result = parseInlineTermInner(parser, start)
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
      let right = parsePhraseItemInner(parser, parser.current, context, terminate)
      result = rotAssociation(result, right)
    of ':':
      case parser.options.colon
      of DisableFeature:
        parser.error("colon syntax disabled")
      of EnableFeature:
        if context.sensitivity == Freeform: # and parser.options.newline == EnableDelimiter
          parser.error("colon syntax not allowed outside of block context")
        # multi char lookahead:
        if parser.nextStr(":="):
          let b = parseColonBlock(parser)
          let rhs = RotTerm(kind: Block, `block`: b)
          result = rotAssociation(result, rhs)
          terminate = context.sensitivity != IndentSensitive
        elif parser.nextStr("="):
          let s = parseColonString(parser)
          let rhs = RotTerm(kind: Text, text: s)
          result = rotAssociation(result, rhs)
          terminate = context.sensitivity != IndentSensitive
        else:
          parser.resetPos()
        return
      of TreatAsSymbol:
        parser.resetPos()
        return
    of '|':
      case parser.options.colon
      of DisableFeature:
        parser.error("pipe syntax disabled")
      of EnableFeature:
        if context.sensitivity == Freeform: # and parser.options.newline == EnableDelimiter
          parser.error("pipe syntax not allowed outside of block context")
        # multi char lookahead:
        if parser.nextStr("|="):
          let p = parsePipeInner(parser)
          var b = RotBlock()
          newSeq(b.items, p.items.len)
          for i in 0 ..< p.items.len:
            b.items[i] = RotPhrase(items: @[p.items[i]])
          let rhs = RotTerm(kind: Block, `block`: b)
          result = rotAssociation(result, rhs)
          terminate = context.sensitivity != IndentSensitive
        elif parser.nextStr("="):
          let p = parsePipeInner(parser)
          let rhs = RotTerm(kind: Phrase, phrase: p)
          result = rotAssociation(result, rhs)
          terminate = context.sensitivity != IndentSensitive
        else:
          parser.resetPos()
        return
      of TreatAsSymbol:
        parser.resetPos()
        return
    else:
      parser.resetPos()
      return

type PhraseState* = object
  currentlySensitive: bool
  expectingItem: bool

proc checkIndentDelim(parser: var RotParser, state: PhraseState, context: PhraseContext): bool {.inline.} =
  result = context.sensitivity == IndentSensitive and
    state.currentlySensitive and
    parser.currentLineIndent < context.minIndent

type PhraseItemResult* = object
  endedPhrase*: bool
  case hasTerm*: bool
  of true: term*: RotTerm
  of false: discard

proc parseItem(parser: var RotParser, ch: char, state: var PhraseState, context: PhraseContext): PhraseItemResult =
  ## returns false if phrase is terminated
  if checkIndentDelim(parser, state, context):
    parser.resetPos()
    return PhraseItemResult(endedPhrase: true, hasTerm: false)
  if not state.expectingItem:
    parser.error("expected comma delimiter between phrase terms")
  var terminated = false
  let item = parsePhraseItemInner(parser, ch, context #[newlineSensitive = state.currentlySensitive]#, terminated) # true for indent sensitive?
  result = PhraseItemResult(hasTerm: true, term: item, endedPhrase: terminated)
  state.currentlySensitive = context.sensitivity != Freeform
  if parser.options.inlineSpace != EnableDelimiter:
    # no character also counts as inline space delimiter
    state.expectingItem = false

proc initPhraseState*(context: PhraseContext): PhraseState {.inline.} =
  PhraseState(
    currentlySensitive: context.sensitivity != Freeform,
    expectingItem: true)

template checkPhraseItem(parser: var RotParser, ch: char, state: var PhraseState, context: PhraseContext, onPhraseItem: untyped) =
  case ch
  of ',':
    if checkIndentDelim(parser, state, context):
      parser.resetPos()
      break
    else:
      if context.sensitivity == NewlineSensitive:
        # maybe also allow breaking indent sensitivity, but this would have to track if a newline was encountered
        state.currentlySensitive = false
      state.expectingItem = true
  of ';':
    parser.resetPos() # don't consume semicolon
    break
  of Whitespace - Newlines:
    if parser.options.inlineSpace == TreatAsSymbolStart:
      onPhraseItem()
  of Newlines:
    case parser.options.newline
    of TreatAsSymbolStart:
      onPhraseItem()
    of EnableDelimiter:
      if context.sensitivity == NewlineSensitive and state.currentlySensitive:
        parser.resetPos() # don't consume newline
        break
    else: discard
  of ')', '}':
    # other context
    parser.resetPos()
    break
  of ']':
    if parser.options.bracket == TreatAsSymbol:
      onPhraseItem()
    else:
      # other context
      parser.resetPos()
      break
  else:
    onPhraseItem()

proc findPhraseItem*(parser: var RotParser, state: var PhraseState, context: PhraseContext): bool =
  ## moves through parser looking for phrase item, false if phrase ended
  result = false
  for ch in parser.charsHandleComments:
    template foundItem() =
      parser.resetPos()
      return true
    checkPhraseItem(parser, ch, state, context, foundItem)

proc parsePhraseItem*(parser: var RotParser, state: var PhraseState, context: PhraseContext): PhraseItemResult =
  for ch in parser.charsHandleComments:
    result = parseItem(parser, ch, state, context)
    return

iterator parsePhraseItems*(parser: var RotParser, context: PhraseContext): RotTerm =
  var state = initPhraseState(context)
  for ch in parser.charsHandleComments:
    var itemResult = PhraseItemResult(hasTerm: false, endedPhrase: false)
    template onItem() =
      itemResult = parseItem(parser, ch, state, context)
    checkPhraseItem(parser, ch, state, context, onItem)
    if itemResult.hasTerm:
      yield itemResult.term
    if itemResult.endedPhrase:
      break

proc parsePhrase*(parser: var RotParser, context: PhraseContext): RotPhrase =
  result = RotPhrase(items: @[])
  for item in parsePhraseItems(parser, context):
    result.items.add item

proc parsePhrase*(parser: var RotParser, newlineSensitive: bool): RotPhrase =
  result = parsePhrase(parser, PhraseContext(sensitivity: if newlineSensitive: NewlineSensitive else: Freeform))

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
  # can be moved to parseBlock like phrases but simple enough
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
      of Whitespace - Newlines:
        discard
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

proc parsePipeInner*(parser: var RotParser): RotPhrase =
  result = RotPhrase(items: @[])
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
    result = parsePhrase(parser, PhraseContext(sensitivity: IndentSensitive, minIndent: finalIndent))
  else:
    result = parsePhrase(parser, newlineSensitive = true)

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

proc parseInlineTermInner*(parser: var RotParser, start: char): RotTerm =
  case start
  of '"':
    let s = parseQuotedInner(parser, start)
    assert parser.current == start
    result = RotTerm(kind: Text, text: s)
  of '`':
    let s = parseQuotedInner(parser, start)
    assert parser.current == start
    result = RotTerm(kind: Symbol, symbol: s)
  of '(':
    let p = parsePhrase(parser, newlineSensitive = false)
    let gotNext = parser.nextChar()
    if gotNext and parser.current == ')':
      discard
    else:
      parser.error("expected ) for enclosed phrase")
    if p.items.len == 0:
      result = RotTerm(kind: Unit)
    else:
      result = RotTerm(kind: Phrase, phrase: p)
  of '{':
    let b = parseBlock(parser)
    let gotNext = parser.nextChar()
    if gotNext and parser.current == '}':
      discard
    else:
      parser.error("expected } for enclosed block")
    result = RotTerm(kind: Block, `block`: b)
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
      result = RotTerm(kind: Block, `block`: b)
    of TreatAsSymbol:
      parser.resetPos()
      let s = parseUnquotedSymbol(parser)
      result = RotTerm(kind: Symbol, symbol: s)
  else:
    if start in parser.options.symbolDisallowedChars:
      parser.error("expected phrase term, got " & $start)
    else:
      parser.resetPos()
      let s = parseUnquotedSymbol(parser)
      result = RotTerm(kind: Symbol, symbol: s)

proc parseInlineTerm*(parser: var RotParser): RotTerm =
  if not parser.nextChar():
    raise newException(RotValueError, "expected term")
  result = parseInlineTermInner(parser, parser.current)

type TermStartKind* = enum
  Invalid,
  QuotedText,
  QuotedSymbol,
  EnclosedPhraseOrUnit,
  EnclosedBlock,
  EnclosedPhraseBlock,
  UnquotedSymbol

proc termStartKind*(start: char, options = defaultRotOptions()): TermStartKind =
  case start
  of '"':
    result = QuotedText
  of '`':
    result = QuotedSymbol
  of '(':
    result = EnclosedPhraseOrUnit
  of '{':
    result = EnclosedBlock
  of '[':
    case options.bracket
    of DisableFeature:
      result = Invalid
    of EnableFeature:
      result = EnclosedPhraseBlock
    of TreatAsSymbol:
      result = UnquotedSymbol
  else:
    if start in options.symbolDisallowedChars:
      result = Invalid
    else:
      result = UnquotedSymbol

proc peekTermStart*(parser: var RotParser): TermStartKind =
  if parser.pos < parser.buffer.data.len:
    result = termStartKind(parser.buffer.data[parser.pos], parser.options)
  else:
    parser.loadBufferOne()
    if parser.pos < parser.buffer.data.len:
      result = termStartKind(parser.buffer.data[parser.pos], parser.options)
    else:
      result = Invalid # eof

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
  for ch in parser.charsHandleComments(#[skipFirst = false]#):
    if ch notin blockIgnored:
      parser.resetPos()
      return true
  # input finished
  return false

proc nextPhrase*(parser: var RotParser; phrase: var RotPhrase, newlineSensitive = true): bool =
  if not nextPhraseStart(parser):
    return false
  phrase = parsePhrase(parser, newlineSensitive = newlineSensitive)
  result = true
