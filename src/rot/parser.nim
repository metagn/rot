import ./[data, reader], std/strutils

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
  RotFormat* = object
    colon*: SpecialCharacterStrategy
    pipe*: SpecialCharacterStrategy
    bracket*: SpecialCharacterStrategy
    comment*: SpecialCharacterStrategy
    inlineSpace*, newline*: DelimiterStrategy
  RotParseError* = object of CatchableError
    filename*: string
    line*, column*: int
    simpleMessage*: string

proc defaultRotFormat*(): RotFormat =
  result = RotFormat(
    colon: EnableFeature,
    pipe: EnableFeature,
    bracket: EnableFeature,
    comment: EnableFeature,
    inlineSpace: EnableDelimiter,
    newline: EnableDelimiter)

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

proc error*(reader: var RotReader, msg: string) =
  var err = (ref RotParseError)(
    filename: reader.filename,
    line: reader.line, column: reader.column,
    simpleMessage: msg)
  buildErrorMessage(err[])
  raise err

# actual reader behavior:

iterator charsHandleComments*(format: RotFormat, reader: var RotReader, skipFirst: static bool = true): char =
  var comment = false
  for ch in reader.rawChars(skipFirst):
    case ch
    of '#':
      case format.comment
      of DisableFeature:
        reader.error("comments disabled")
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

proc symbolDisallowedChars*(options: RotFormat): set[char] =
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

proc parseUnquotedSymbol*(format: RotFormat, reader: var RotReader): string =
  result = ""
  let disallowedChars = format.symbolDisallowedChars
  var concatChars: set[char] = {}
  if format.inlineSpace == ConcatenateSymbol:
    concatChars.incl(Whitespace - Newlines)
  if format.newline == ConcatenateSymbol:
    concatChars.incl(Newlines)
  var concat = ""
  for ch in reader.rawChars:
    if ch in disallowedChars:
      reader.resetPos()
      return
    elif ch in concatChars:
      concat.add ch
    else:
      if concat.len != 0:
        result.add concat
        concat = ""
      result.add ch

proc parseQuotedInner*(format: RotFormat, reader: var RotReader, quote: char): string =
  result = ""
  for ch in reader.rawChars:
    if ch == quote:
      if reader.peekCharOrZero() == quote:
        let gotNext = reader.nextChar()
        assert gotNext
        result.add(quote)
      else:
        return
    else:
      result.add(ch)
  reader.error("expected closing quote for " & $quote)

proc parseQuotedText*(format: RotFormat, reader: var RotReader): string =
  const quote = '"'
  if not reader.nextChar() or reader.current != quote:
    raise newException(RotValueError, "expected quote character for text")
  result = parseQuotedInner(format, reader, quote)

proc parseText*(format: RotFormat, reader: var RotReader): string {.inline.} =
  result = parseQuotedText(format, reader)

proc parseQuotedSymbol*(format: RotFormat, reader: var RotReader): string =
  const quote = '`'
  if not reader.nextChar() or reader.current != quote:
    raise newException(RotValueError, "expected quote character for symbol")
  result = parseQuotedInner(format, reader, quote)

proc parseSymbol*(format: RotFormat, reader: var RotReader): string =
  const quote = '`'
  if reader.peekCharOrZero() == quote:
    result = parseQuotedSymbol(format, reader)
  else:
    result = parseUnquotedSymbol(format, reader)

proc parseColonString*(format: RotFormat, reader: var RotReader): string =
  result = ""
  let startIndent = reader.currentLineIndent
  var newline = false
  var finalIndent = startIndent
  # start:
  for ch in reader.rawChars: # no comments
    case ch
    of Whitespace - Newlines:
      discard
    of Newlines:
      newline = true
    else:
      finalIndent = reader.currentLineIndent
      reader.resetPos()
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
    for ch in reader.rawChars: # no comments
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
          reader.resetPos()
          return
        recordIndent = false
    result.add(currentLine)
  else:
    for ch in reader.rawChars:
      case ch
      of Newlines:
        reader.resetPos() # don't consume newline
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

proc parseInlineTermInner*(format: RotFormat, reader: var RotReader, start: char): RotTerm
proc parseColonBlock*(format: RotFormat, reader: var RotReader): RotBlock
proc parsePipeInner*(format: RotFormat, reader: var RotReader): RotPhrase

proc phraseToBlock*(p: RotPhrase): RotBlock =
  result = RotBlock()
  result.items = newSeqOfCap[RotPhrase](p.items.len)
  for item in p.items:
    if item.associated:
      result.items[^1].items.add RotArgument(associated: true, term: item.term)
    else:
      result.items.add RotPhrase(items: @[RotArgument(associated: false, term: item.term)])

proc parsePhraseItemInner*(format: RotFormat, reader: var RotReader, start: char, associationAllowed: bool, context: PhraseContext, terminate: var bool): RotArgument =
  case start
  of ':':
    case format.colon
    of DisableFeature:
      reader.error("colon syntax disabled")
    of EnableFeature:
      if context.sensitivity == Freeform: # and format.newline == EnableDelimiter
        reader.error("colon syntax not allowed outside of block context")
      let colonBlock = reader.peekCharOrZero() == ':'
      if colonBlock:
        let gotNext = reader.nextChar()
        assert gotNext
      let associate = reader.peekCharOrZero() == '='
      if associate:
        if associationAllowed:
          let gotNext = reader.nextChar()
          assert gotNext
        else:
          reader.error("expected lhs for colon association")
      if colonBlock:
        let b = parseColonBlock(format, reader)
        result = RotArgument(associated: associate, term: RotTerm(kind: Block, `block`: b))
      else:
        let s = parseColonString(format, reader)
        result = RotArgument(associated: associate, term: RotTerm(kind: Text, text: s))
      terminate = context.sensitivity != IndentSensitive
      return
    of TreatAsSymbol:
      result = RotArgument(associated: false, term: parseInlineTermInner(format, reader, start))
  of '|':
    case format.colon
    of DisableFeature:
      reader.error("pipe syntax disabled")
    of EnableFeature:
      if context.sensitivity == Freeform: # and format.newline == EnableDelimiter
        reader.error("pipe syntax not allowed outside of block context")
      let pipeBlock = reader.peekCharOrZero() == '|'
      if pipeBlock:
        let gotNext = reader.nextChar()
        assert gotNext
      let associate = reader.peekCharOrZero() == '='
      if associate:
        if associationAllowed:
          let gotNext = reader.nextChar()
          assert gotNext
        else:
          reader.error("expected lhs for pipe association")
      let p = parsePipeInner(format, reader)
      if pipeBlock:
        let b = phraseToBlock(p)
        result = RotArgument(associated: associate, term: RotTerm(kind: Block, `block`: b))
      else:
        result = RotArgument(associated: associate, term: RotTerm(kind: Phrase, phrase: p))
      terminate = context.sensitivity != IndentSensitive
      return
    of TreatAsSymbol:
      result = RotArgument(associated: false, term: parseInlineTermInner(format, reader, start))
  of '=':
    if not associationAllowed:
      reader.error("expected lhs for association")
    var start2: char
    for ch2 in format.charsHandleComments(reader):
      if ch2 notin Whitespace:
        # skips newlines too
        start2 = ch2
        break
    if reader.done:
      reader.error("expected rhs for association, got end of file")
    let right = parsePhraseItemInner(format, reader, start2, associationAllowed = false, context, terminate)
      # temporary until the above are handled as normal terms
    assert not right.associated
    result = RotArgument(associated: true, term: right.term)
  else:
    result = RotArgument(associated: false, term: parseInlineTermInner(format, reader, start))

type PhraseState* = object
  currentlySensitive: bool
  expectingItem: bool
  allowAssociation: bool

proc checkIndentDelim(format: RotFormat, reader: var RotReader, state: PhraseState, context: PhraseContext): bool {.inline.} =
  result = context.sensitivity == IndentSensitive and
    state.currentlySensitive and
    reader.currentLineIndent < context.minIndent

type PhraseItemResult* = object
  endedPhrase*: bool
  # phrase can end with item
  case hasItem*: bool
  of true: item*: RotArgument
  of false: discard

proc parseItem(format: RotFormat, reader: var RotReader, ch: char, state: var PhraseState, context: PhraseContext): PhraseItemResult =
  if checkIndentDelim(format, reader, state, context):
    reader.resetPos()
    return PhraseItemResult(endedPhrase: true, hasItem: false)
  if not state.expectingItem:
    reader.error("expected comma delimiter between phrase terms")
  var terminated = false
  let item = parsePhraseItemInner(format, reader, ch, state.allowAssociation, context, terminated) # true for indent sensitive?
  result = PhraseItemResult(hasItem: true, item: item, endedPhrase: terminated)
  state.currentlySensitive = context.sensitivity != Freeform
  state.allowAssociation = true
  if format.inlineSpace != EnableDelimiter:
    # no character also counts as inline space delimiter
    state.expectingItem = false

proc initPhraseState*(context: PhraseContext): PhraseState {.inline.} =
  PhraseState(
    currentlySensitive: context.sensitivity != Freeform,
    expectingItem: true,
    allowAssociation: false)

template checkPhraseItem(format: RotFormat, reader: var RotReader, ch: char, state: var PhraseState, context: PhraseContext, onPhraseItem: untyped) =
  case ch
  of ',':
    if checkIndentDelim(format, reader, state, context):
      reader.resetPos()
      break
    else:
      if context.sensitivity == NewlineSensitive:
        # maybe also allow breaking indent sensitivity, but this would have to track if a newline was encountered
        state.currentlySensitive = false
      state.expectingItem = true
      state.allowAssociation = false
  of ';':
    reader.resetPos() # don't consume semicolon
    break
  of Whitespace - Newlines:
    if format.inlineSpace == TreatAsSymbolStart:
      onPhraseItem()
  of Newlines:
    case format.newline
    of TreatAsSymbolStart:
      onPhraseItem()
    of EnableDelimiter:
      if context.sensitivity == NewlineSensitive and state.currentlySensitive:
        reader.resetPos() # don't consume newline
        break
    else: discard
  of ')', '}':
    # other context
    reader.resetPos()
    break
  of ']':
    if format.bracket == TreatAsSymbol:
      onPhraseItem()
    else:
      # other context
      reader.resetPos()
      break
  else:
    onPhraseItem()

proc findPhraseItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, context: PhraseContext): bool =
  ## moves through reader looking for phrase item, false if phrase ended
  result = false
  for ch in format.charsHandleComments(reader):
    template foundItem() =
      reader.resetPos()
      return true
    checkPhraseItem(format, reader, ch, state, context, foundItem)

proc parsePhraseItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, context: PhraseContext): PhraseItemResult =
  for ch in format.charsHandleComments(reader):
    result = parseItem(format, reader, ch, state, context)
    return

iterator parsePhraseItems*(format: RotFormat, reader: var RotReader, context: PhraseContext): RotArgument =
  var state = initPhraseState(context)
  for ch in format.charsHandleComments(reader):
    var itemResult = PhraseItemResult(hasItem: false, endedPhrase: false)
    template onItem() =
      itemResult = parseItem(format, reader, ch, state, context)
    checkPhraseItem(format, reader, ch, state, context, onItem)
    if itemResult.hasItem:
      yield itemResult.item
    if itemResult.endedPhrase:
      break

proc parsePhrase*(format: RotFormat, reader: var RotReader, context: PhraseContext): RotPhrase =
  result = RotPhrase(items: @[])
  for item in parsePhraseItems(format, reader, context):
    result.items.add item

proc parseColonBlock*(format: RotFormat, reader: var RotReader): RotBlock =
  result = RotBlock(items: @[])
  let startIndent = reader.currentLineIndent
  var newline = false
  var finalIndent = startIndent
  # start:
  for ch in format.charsHandleComments(reader):
    case ch
    of Whitespace - Newlines: discard
    of Newlines:
      newline = true
    else:
      finalIndent = reader.currentLineIndent
      reader.resetPos()
      break
  # can be moved to parseBlock like phrases but simple enough
  if newline:
    if finalIndent <= startIndent:
      return
    for ch in format.charsHandleComments(reader):
      case ch
      of Whitespace - Newlines:
        discard
      of Newlines:
        discard
      of ';':
        if reader.currentLineIndent < finalIndent:
          reader.resetPos()
          return
      else:
        if reader.currentLineIndent < finalIndent:
          reader.resetPos()
          return
        else:
          reader.resetPos()
          let p = parsePhrase(format, reader, LinePhraseContext)
          assert p.items.len != 0
          result.items.add p
  else:
    for ch in format.charsHandleComments(reader):
      case ch
      of Whitespace - Newlines:
        discard
      of Newlines:
        reader.resetPos() # don't consume newline
        return
      of ';':
        discard
      else:
        reader.resetPos()
        let p = parsePhrase(format, reader, LinePhraseContext)
        assert p.items.len != 0
        result.items.add p

proc parsePipeInner*(format: RotFormat, reader: var RotReader): RotPhrase =
  result = RotPhrase(items: @[])
  let startIndent = reader.currentLineIndent
  var newline = false
  var finalIndent = startIndent
  # start:
  for ch in format.charsHandleComments(reader):
    case ch
    of Whitespace - Newlines: discard
    of Newlines:
      newline = true
    else:
      finalIndent = reader.currentLineIndent
      reader.resetPos()
      break
  if newline:
    if finalIndent <= startIndent:
      return
    result = parsePhrase(format, reader, PhraseContext(sensitivity: IndentSensitive, minIndent: finalIndent))
  else:
    result = parsePhrase(format, reader, LinePhraseContext)

proc parseBlock*(format: RotFormat, reader: var RotReader): RotBlock =
  result = RotBlock(items: @[])
  for ch in format.charsHandleComments(reader):
    case ch
    of ')', '}':
      # other context
      reader.resetPos()
      return
    of Whitespace - Newlines:
      if format.inlineSpace == TreatAsSymbolStart:
        reader.resetPos()
        let phrase = parsePhrase(format, reader, LinePhraseContext)
        assert phrase.items.len != 0
        result.items.add phrase
    of Newlines:
      if format.newline == TreatAsSymbolStart:
        reader.resetPos()
        let phrase = parsePhrase(format, reader, LinePhraseContext)
        assert phrase.items.len != 0
        result.items.add phrase
    of ';':
      discard
    else:
      reader.resetPos()
      let phrase = parsePhrase(format, reader, LinePhraseContext)
      assert phrase.items.len != 0
      result.items.add phrase

proc parseInlineTermInner*(format: RotFormat, reader: var RotReader, start: char): RotTerm =
  case start
  of '"':
    let s = parseQuotedInner(format, reader, start)
    assert reader.current == start
    result = RotTerm(kind: Text, text: s)
  of '`':
    let s = parseQuotedInner(format, reader, start)
    assert reader.current == start
    result = RotTerm(kind: Symbol, symbol: s)
  of '(':
    let p = parsePhrase(format, reader, FreePhraseContext)
    let gotNext = reader.nextChar()
    if gotNext and reader.current == ')':
      discard
    else:
      reader.error("expected ) for enclosed phrase")
    if p.items.len == 0:
      result = RotTerm(kind: Unit)
    else:
      result = RotTerm(kind: Phrase, phrase: p)
  of '{':
    let b = parseBlock(format, reader)
    let gotNext = reader.nextChar()
    if gotNext and reader.current == '}':
      discard
    else:
      reader.error("expected } for enclosed block")
    result = RotTerm(kind: Block, `block`: b)
  of '[':
    case format.bracket
    of DisableFeature:
      reader.error("bracket syntax disabled")
    of EnableFeature:
      let p = parsePhrase(format, reader, FreePhraseContext)
      let gotNext = reader.nextChar()
      if gotNext and reader.current == ']':
        discard
      else:
        reader.error("expected ] for enclosed block")
      let b = phraseToBlock(p)
      result = RotTerm(kind: Block, `block`: b)
    of TreatAsSymbol:
      reader.resetPos()
      let s = parseUnquotedSymbol(format, reader)
      result = RotTerm(kind: Symbol, symbol: s)
  else:
    if start in format.symbolDisallowedChars:
      reader.error("expected phrase term, got " & $start)
    else:
      reader.resetPos()
      let s = parseUnquotedSymbol(format, reader)
      result = RotTerm(kind: Symbol, symbol: s)

proc parseInlineTerm*(format: RotFormat, reader: var RotReader): RotTerm =
  if not reader.nextChar():
    raise newException(RotValueError, "expected term")
  result = parseInlineTermInner(format, reader, reader.current)

type TermStartKind* = enum
  Invalid,
  QuotedText,
  QuotedSymbol,
  EnclosedPhraseOrUnit,
  EnclosedBlock,
  EnclosedPhraseBlock,
  UnquotedSymbol

proc termStartKind*(start: char, format = defaultRotFormat()): TermStartKind =
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
    case format.bracket
    of DisableFeature:
      result = Invalid
    of EnableFeature:
      result = EnclosedPhraseBlock
    of TreatAsSymbol:
      result = UnquotedSymbol
  else:
    if start in format.symbolDisallowedChars:
      result = Invalid
    else:
      result = UnquotedSymbol

proc peekTermStart*(format: RotFormat, reader: var RotReader): TermStartKind =
  var start: char
  if reader.peekChar(start):
    result = termStartKind(start, format)
  else:
    result = Invalid

proc parseFullBlock*(format: RotFormat, reader: var RotReader): RotBlock =
  result = parseBlock(format, reader)
  if not reader.done:
    reader.error("block finished before input: " & $reader.current)

proc nextPhraseStart*(format: RotFormat, reader: var RotReader): bool =
  if reader.done:
    return false
  var blockIgnored = Whitespace + {';'}
  if format.inlineSpace == TreatAsSymbolStart:
    blockIgnored.excl(Whitespace - Newlines)
  if format.newline == TreatAsSymbolStart:
    blockIgnored.excl(Newlines)
  for ch in format.charsHandleComments(reader, #[skipFirst = false]#):
    if ch notin blockIgnored:
      reader.resetPos()
      return true
  # input finished
  return false

proc nextPhrase*(format: RotFormat, reader: var RotReader; phrase: var RotPhrase, context = LinePhraseContext): bool =
  if not nextPhraseStart(format, reader):
    return false
  phrase = parsePhrase(format, reader, context)
  result = true
