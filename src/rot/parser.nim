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

proc symbolDisallowedChars*(format: RotFormat): set[char] =
  result = DefaultSymbolDisallowedChars
  if format.colon == TreatAsSymbol:
    result.excl(':')
  if format.pipe == TreatAsSymbol:
    result.excl('|')
  if format.bracket == TreatAsSymbol:
    result.excl({'[', ']'})
  if format.comment == TreatAsSymbol:
    result.excl('#')
  if format.inlineSpace == TreatAsSymbolStart:
    result.excl(Whitespace - Newlines)
  if format.newline == TreatAsSymbolStart:
    result.excl(Newlines)

proc symbolConcatChars*(format: RotFormat): set[char] =
  result = {}
  if format.inlineSpace == ConcatenateSymbol:
    result.incl(Whitespace - Newlines)
  if format.newline == ConcatenateSymbol:
    result.incl(Newlines)

proc parseUnquotedSymbol*(format: RotFormat, reader: var RotReader): string =
  result = ""
  let disallowedChars = format.symbolDisallowedChars
  let concatChars = format.symbolConcatChars
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

proc parseQuotedSymbol*(format: RotFormat, reader: var RotReader): string =
  const quote = '`'
  if not reader.nextChar() or reader.current != quote:
    raise newException(RotValueError, "expected quote character for symbol")
  result = parseQuotedInner(format, reader, quote)

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
  WhitespaceSensitivity* = enum
    Freeform, NewlineSensitive, IndentSensitive
  WhitespaceContext* = object
    case sensitivity*: WhitespaceSensitivity
    of Freeform, NewlineSensitive: discard
    of IndentSensitive:
      minIndent*: int

const
  FreeContext* = WhitespaceContext(sensitivity: Freeform)
  LineContext* = WhitespaceContext(sensitivity: NewlineSensitive)

proc indentContext*(minIndent: int): WhitespaceContext {.inline.} =
  WhitespaceContext(sensitivity: IndentSensitive, minIndent: minIndent)

proc parsePhrase*(format: RotFormat, reader: var RotReader, context: WhitespaceContext): RotPhrase
proc parseBlock*(format: RotFormat, reader: var RotReader, context: WhitespaceContext = FreeContext): RotBlock

proc phraseToBlock*(p: RotPhrase): RotBlock =
  result = RotBlock()
  result.items = newSeqOfCap[RotPhrase](p.items.len)
  for item in p.items:
    if item.associated:
      result.items[^1].items.add RotArgument(associated: true, term: item.term)
    else:
      result.items.add RotPhrase(items: @[RotArgument(associated: false, term: item.term)])

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
    result = parseBlock(format, reader, indentContext(finalIndent))
  else:
    result = parseBlock(format, reader, LineContext)

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
    result = parsePhrase(format, reader, indentContext(finalIndent))
  else:
    result = parsePhrase(format, reader, LineContext)

type PhraseState* = object
  ended: bool ## certain items can end the phrase
  currentlySensitive: bool ## to escape newlines with commas
  expectingItem: bool ## for requiring comma delimiters
  allowAssociation: bool ## to prevent a phrase starting with an association or a comma being followed by one

proc initPhraseState*(context: WhitespaceContext): PhraseState {.inline.} =
  PhraseState(
    currentlySensitive: context.sensitivity != Freeform,
    expectingItem: true,
    allowAssociation: false)

proc checkIndentDelim(format: RotFormat, reader: var RotReader, state: PhraseState, context: WhitespaceContext): bool {.inline.} =
  result = context.sensitivity == IndentSensitive and
    state.currentlySensitive and # XXX never false for indent sensitive
    reader.currentLineIndent < context.minIndent

proc parseItemInner(format: RotFormat, reader: var RotReader, state: var PhraseState, context: WhitespaceContext, start: char): RotArgument =
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
        if state.allowAssociation:
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
      state.ended = context.sensitivity != IndentSensitive
    of TreatAsSymbol:
      reader.resetPos()
      let s = parseUnquotedSymbol(format, reader)
      result = RotArgument(associated: false, term: RotTerm(kind: Symbol, symbol: s))
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
        if state.allowAssociation:
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
      state.ended = context.sensitivity != IndentSensitive
    of TreatAsSymbol:
      reader.resetPos()
      let s = parseUnquotedSymbol(format, reader)
      result = RotArgument(associated: false, term: RotTerm(kind: Symbol, symbol: s))
  of '=':
    if not state.allowAssociation:
      reader.error("expected lhs for association")
    var start2: char
    for ch2 in format.charsHandleComments(reader):
      if ch2 notin Whitespace:
        # skips newlines too
        start2 = ch2
        break
    if reader.done:
      reader.error("expected rhs for association, got end of file")
    state.allowAssociation = false
    let right = parseItemInner(format, reader, state, context, start2)
    assert not right.associated
    result = RotArgument(associated: true, term: right.term)
  of '"':
    let s = parseQuotedInner(format, reader, start)
    assert reader.current == start
    result = RotArgument(associated: false, term: RotTerm(kind: Text, text: s))
  of '`':
    let s = parseQuotedInner(format, reader, start)
    assert reader.current == start
    result = RotArgument(associated: false, term: RotTerm(kind: Symbol, symbol: s))
  of '(':
    let p = parsePhrase(format, reader, FreeContext)
    let gotNext = reader.nextChar()
    if gotNext and reader.current == ')':
      discard
    else:
      reader.error("expected ) for enclosed phrase")
    if p.items.len == 0:
      result = RotArgument(associated: false, term: RotTerm(kind: Unit))
    else:
      result = RotArgument(associated: false, term: RotTerm(kind: Phrase, phrase: p))
  of '{':
    let b = parseBlock(format, reader)
    let gotNext = reader.nextChar()
    if gotNext and reader.current == '}':
      discard
    else:
      reader.error("expected } for enclosed block")
    result = RotArgument(associated: false, term: RotTerm(kind: Block, `block`: b))
  of '[':
    case format.bracket
    of DisableFeature:
      reader.error("bracket syntax disabled")
    of EnableFeature:
      let p = parsePhrase(format, reader, FreeContext)
      let gotNext = reader.nextChar()
      if gotNext and reader.current == ']':
        discard
      else:
        reader.error("expected ] for enclosed block")
      let b = phraseToBlock(p)
      result = RotArgument(associated: false, term: RotTerm(kind: Block, `block`: b))
    of TreatAsSymbol:
      reader.resetPos()
      let s = parseUnquotedSymbol(format, reader)
      result = RotArgument(associated: false, term: RotTerm(kind: Symbol, symbol: s))
  else:
    if start in format.symbolDisallowedChars:
      reader.error("expected phrase term, got " & $start)
    else:
      reader.resetPos()
      let s = parseUnquotedSymbol(format, reader)
      result = RotArgument(associated: false, term: RotTerm(kind: Symbol, symbol: s))

proc parseFullItemInner(format: RotFormat, reader: var RotReader, state: var PhraseState, context: WhitespaceContext, start: char): RotArgument =
  if not state.expectingItem:
    reader.error("expected comma delimiter between phrase terms")
  result = parseItemInner(format, reader, state, context, start)
  state.currentlySensitive = context.sensitivity != Freeform
  state.allowAssociation = true
  if format.inlineSpace != EnableDelimiter:
    # no character also counts as inline space delimiter
    state.expectingItem = false

template checkPhraseItem(format: RotFormat, reader: var RotReader, ch: char, state: var PhraseState, context: WhitespaceContext, onItem: untyped) =
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
      if checkIndentDelim(format, reader, state, context):
        reader.resetPos()
        break
      else:
        onItem()
  of Newlines:
    case format.newline
    of TreatAsSymbolStart:
      if checkIndentDelim(format, reader, state, context):
        reader.resetPos()
        break
      else:
        onItem()
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
      if checkIndentDelim(format, reader, state, context):
        reader.resetPos()
        break
      else:
        onItem()
    else:
      # other context
      reader.resetPos()
      break
  else:
    if checkIndentDelim(format, reader, state, context):
      reader.resetPos()
      break
    else:
      onItem()

proc findPhraseItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, context: WhitespaceContext): bool =
  ## moves through reader looking for phrase item, false if phrase ended
  if state.ended: return false
  result = false
  for ch in format.charsHandleComments(reader):
    template foundItem() =
      reader.resetPos()
      return true
    checkPhraseItem(format, reader, ch, state, context, foundItem)

proc parsePhraseItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, context: WhitespaceContext): RotArgument =
  if not reader.nextChar():
    raise newException(RotValueError, "expected phrase item")
  result = parseFullItemInner(format, reader, state, context, reader.current)

iterator parsePhraseItems*(format: RotFormat, reader: var RotReader, context: WhitespaceContext): RotArgument =
  when true:
    var state = initPhraseState(context)
    for ch in format.charsHandleComments(reader):
      var gotItem = false
      var item: RotArgument
      template onItem() =
        gotItem = true
        item = parseFullItemInner(format, reader, state, context, ch)
      checkPhraseItem(format, reader, ch, state, context, onItem)
      if gotItem:
        yield item
      if state.ended:
        break
  else:
    var state = initPhraseState(context)
    while format.findPhraseItem(reader, state, context):
      yield format.parsePhraseItem(reader, state, context)

proc parsePhrase*(format: RotFormat, reader: var RotReader, context: WhitespaceContext): RotPhrase =
  result = RotPhrase(items: @[])
  for item in parsePhraseItems(format, reader, context):
    result.items.add item

template checkBlockPhrase(format: RotFormat, reader: var RotReader, ch: char, context: WhitespaceContext, onPhrase: untyped) =
  case ch
  of ')', '}':
    # other context
    reader.resetPos()
    break
  of ']':
    if format.bracket == TreatAsSymbol:
      onPhrase()
    else:
      # other context
      reader.resetPos()
      break
  of Whitespace - Newlines:
    if format.inlineSpace == TreatAsSymbolStart and not
        # inline whitespace ignored if part of indent
        (context.sensitivity == IndentSensitive and reader.currentLineIndent <= context.minIndent):
      onPhrase()
  of Newlines:
    case context.sensitivity
    of Freeform:
      if format.newline == TreatAsSymbolStart:
        onPhrase()
    of NewlineSensitive:
      reader.resetPos()
      break
    of IndentSensitive:
      # default newline behavior necessary for indent sensitivity to function
      discard
  of ';':
    if context.sensitivity == IndentSensitive and
        reader.currentLineIndent < context.minIndent:
      reader.resetPos()
      break
  else:
    if context.sensitivity == IndentSensitive and
        reader.currentLineIndent < context.minIndent:
      reader.resetPos()
      break
    else:
      onPhrase()

proc findBlockPhrase*(format: RotFormat, reader: var RotReader, context: WhitespaceContext = FreeContext): bool =
  ## moves through reader looking for block phrase, false if phrase ended
  result = false
  for ch in format.charsHandleComments(reader):
    template foundItem() =
      reader.resetPos()
      return true
    checkBlockPhrase(format, reader, ch, context, foundItem)

proc parseBlockPhrase*(format: RotFormat, reader: var RotReader, context: WhitespaceContext = FreeContext): RotPhrase =
  result = parsePhrase(format, reader, LineContext)
  assert result.items.len != 0

iterator parseBlockPhrases*(format: RotFormat, reader: var RotReader, context: WhitespaceContext = FreeContext): RotPhrase =
  while format.findBlockPhrase(reader, context):
    let phrase = parseBlockPhrase(format, reader, context)
    yield phrase

proc parseBlock*(format: RotFormat, reader: var RotReader, context: WhitespaceContext = FreeContext): RotBlock =
  result = RotBlock(items: @[])
  for ch in format.charsHandleComments(reader):
    template onPhraseStart() =
      reader.resetPos()
      let phrase = parsePhrase(format, reader, LineContext)
      assert phrase.items.len != 0
      result.items.add phrase
    checkBlockPhrase(format, reader, ch, context, onPhraseStart)

proc parseFullBlock*(format: RotFormat, reader: var RotReader): RotBlock =
  result = parseBlock(format, reader)
  if not reader.done:
    reader.error("block finished before input: " & $reader.current)

type
  TermKind* = enum
    NoTerm
    SymbolUnquoted ## <word>
    TextQuoted ## "
    SymbolQuoted ## `
    PhraseOrUnitClosed ## ()
    BlockClosed ## {}
    PhraseBlockClosed ## []
    TextOpen # :
    BlockOpen # ::
    PhraseOpen # |
    PhraseBlockOpen # ||


