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

type
  OpenKind* = enum
    OpenEmpty # with no trailing inline characters or indent
    OpenLine # just trailing inline characters
    OpenIndent # indented
  OpenStart* = object
    case kind*: OpenKind
    of OpenEmpty, OpenLine: discard
    of OpenIndent: minIndent*: int

proc startOpenRaw(format: RotFormat, reader: var RotReader): OpenStart =
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
      result = OpenStart(kind: OpenEmpty)
    else:
      result = OpenStart(kind: OpenIndent, minIndent: finalIndent)
  else:
    result = OpenStart(kind: OpenLine)

proc startOpenComments(format: RotFormat, reader: var RotReader): OpenStart =
  let startIndent = reader.currentLineIndent
  var newline = false
  var finalIndent = startIndent
  # start:
  for ch in format.charsHandleComments(reader):
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
      result = OpenStart(kind: OpenEmpty)
    else:
      result = OpenStart(kind: OpenIndent, minIndent: finalIndent)
  else:
    result = OpenStart(kind: OpenLine)

proc parseIndentedString(reader: var RotReader, minIndent: int): string =
  result = ""
  var currentLine = ""
  var newlineQueue = ""
  template addPrecedingNewlines() =
    if newlineQueue.len != 0:
      result.add(newlineQueue)
      newlineQueue.setLen(0)
  template addInLine(c: char) =
    addPrecedingNewlines()
    currentLine.add(ch)
  var recordIndent = false
  var indent = minIndent
  for ch in reader.rawChars: # no comments
    case ch
    of Whitespace - Newlines:
      if indent >= minIndent:
        addInLine(ch)
      if recordIndent:
        inc indent
        if indent == minIndent:
          addPrecedingNewlines()
    of Newlines:
      result.add(currentLine)
      currentLine.setLen(0)
      newlineQueue.add(ch)
      recordIndent = true
      indent = 0
    else:
      if indent >= minIndent:
        addInLine(ch)
      else:
        reader.resetPos()
        return
      recordIndent = false
  result.add(currentLine)

proc parseLineString(reader: var RotReader): string =
  result = ""
  for ch in reader.rawChars:
    case ch
    of Newlines:
      reader.resetPos() # don't consume newline
      return
    else:
      result.add(ch)

proc parseColonStringInner(format: RotFormat, reader: var RotReader): string =
  let open = startOpenRaw(format, reader)
  case open.kind
  of OpenEmpty:
    result = ""
  of OpenIndent:
    result = parseIndentedString(reader, open.minIndent)
  of OpenLine:
    result = parseLineString(reader)

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

proc parseColonBlockInner(format: RotFormat, reader: var RotReader): RotBlock =
  let open = startOpenComments(format, reader)
  case open.kind
  of OpenEmpty:
    result = RotBlock(items: @[])
  of OpenIndent:
    result = parseBlock(format, reader, indentContext(open.minIndent))
  of OpenLine:
    result = parseBlock(format, reader, LineContext)

proc parsePipeInner(format: RotFormat, reader: var RotReader): RotPhrase =
  let open = startOpenComments(format, reader)
  case open.kind
  of OpenEmpty:
    result = RotPhrase(items: @[])
  of OpenIndent:
    result = parsePhrase(format, reader, indentContext(open.minIndent))
  of OpenLine:
    result = parsePhrase(format, reader, LineContext)

type PhraseState* = object
  ended*: bool ## certain items can end the phrase
  currentlySensitive*: bool ## to escape newlines with commas
  expectingItem*: bool ## for requiring comma delimiters
  allowAssociation*: bool ## to prevent a phrase starting with an association or a comma being followed by one
  context*: WhitespaceContext

proc initPhraseState*(context: WhitespaceContext): PhraseState {.inline.} =
  PhraseState(
    context: context,
    currentlySensitive: context.sensitivity != Freeform,
    expectingItem: true,
    allowAssociation: false)

proc checkIndentDelim(format: RotFormat, reader: var RotReader, state: PhraseState): bool {.inline.} =
  result = state.context.sensitivity == IndentSensitive and
    state.currentlySensitive and # XXX never false for indent sensitive
    reader.currentLineIndent < state.context.minIndent

proc parseItemInner(format: RotFormat, reader: var RotReader, state: var PhraseState, start: char): RotArgument =
  ## mirrored with `ItemContent` code below
  case start
  of ':':
    case format.colon
    of DisableFeature:
      reader.error("colon syntax disabled")
    of EnableFeature:
      if state.context.sensitivity == Freeform: # and format.newline == EnableDelimiter
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
        let b = parseColonBlockInner(format, reader)
        result = RotArgument(associated: associate, term: RotTerm(kind: Block, `block`: b))
      else:
        let s = parseColonStringInner(format, reader)
        result = RotArgument(associated: associate, term: RotTerm(kind: Text, text: s))
      state.ended = state.context.sensitivity != IndentSensitive
    of TreatAsSymbol:
      reader.resetPos()
      let s = parseUnquotedSymbol(format, reader)
      result = RotArgument(associated: false, term: RotTerm(kind: Symbol, symbol: s))
  of '|':
    case format.colon
    of DisableFeature:
      reader.error("pipe syntax disabled")
    of EnableFeature:
      if state.context.sensitivity == Freeform: # and format.newline == EnableDelimiter
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
      state.ended = state.context.sensitivity != IndentSensitive
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
    let right = parseItemInner(format, reader, state, start2)
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

proc enterItem(format: RotFormat, reader: var RotReader, state: var PhraseState) {.inline.} =
  if not state.expectingItem:
    reader.error("expected comma delimiter between phrase terms")

proc exitItem(format: RotFormat, reader: var RotReader, state: var PhraseState) {.inline.} =
  state.currentlySensitive = state.context.sensitivity != Freeform
  state.allowAssociation = true
  if format.inlineSpace != EnableDelimiter:
    # no character also counts as inline space delimiter
    state.expectingItem = false

proc parseFullItemInner(format: RotFormat, reader: var RotReader, state: var PhraseState, start: char): RotArgument =
  ## mirrored with `ItemContent` code below
  enterItem(format, reader, state)
  result = parseItemInner(format, reader, state, start)
  exitItem(format, reader, state)

template checkPhraseItem(format: RotFormat, reader: var RotReader, ch: char, state: var PhraseState, onItem: untyped) =
  case ch
  of ',':
    if checkIndentDelim(format, reader, state):
      reader.resetPos()
      break
    else:
      if state.context.sensitivity == NewlineSensitive:
        # maybe also allow breaking indent sensitivity, but this would have to track if a newline was encountered
        state.currentlySensitive = false
      state.expectingItem = true
      state.allowAssociation = false
  of ';':
    reader.resetPos() # don't consume semicolon
    break
  of Whitespace - Newlines:
    if format.inlineSpace == TreatAsSymbolStart:
      if checkIndentDelim(format, reader, state):
        reader.resetPos()
        break
      else:
        onItem()
  of Newlines:
    case format.newline
    of TreatAsSymbolStart:
      if checkIndentDelim(format, reader, state):
        reader.resetPos()
        break
      else:
        onItem()
    of EnableDelimiter:
      if state.context.sensitivity == NewlineSensitive and state.currentlySensitive:
        reader.resetPos() # don't consume newline
        break
    else: discard
  of ')', '}':
    # other context
    reader.resetPos()
    break
  of ']':
    if format.bracket == TreatAsSymbol:
      if checkIndentDelim(format, reader, state):
        reader.resetPos()
        break
      else:
        onItem()
    else:
      # other context
      reader.resetPos()
      break
  else:
    if checkIndentDelim(format, reader, state):
      reader.resetPos()
      break
    else:
      onItem()

proc findPhraseItem*(format: RotFormat, reader: var RotReader, state: var PhraseState): bool =
  ## moves through reader looking for phrase item, false if phrase ended
  if state.ended:
    return false
  result = false
  for ch in format.charsHandleComments(reader):
    template foundItem() =
      reader.resetPos()
      return true
    checkPhraseItem(format, reader, ch, state, foundItem)

proc parsePhraseItem*(format: RotFormat, reader: var RotReader, state: var PhraseState): RotArgument =
  if not reader.nextChar():
    raise newException(RotValueError, "expected phrase item")
  result = parseFullItemInner(format, reader, state, reader.current)

iterator parsePhraseItems*(format: RotFormat, reader: var RotReader, context: WhitespaceContext): RotArgument =
  when true:
    var state = initPhraseState(context)
    for ch in format.charsHandleComments(reader):
      var gotItem = false
      var item: RotArgument
      template onItem() =
        gotItem = true
        item = parseFullItemInner(format, reader, state, ch)
      checkPhraseItem(format, reader, ch, state, onItem)
      if gotItem:
        yield item
      if state.ended:
        break
  else:
    var state = initPhraseState(context)
    while format.findPhraseItem(reader, state):
      yield format.parsePhraseItem(reader, state)

proc parsePhrase*(format: RotFormat, reader: var RotReader, context: WhitespaceContext): RotPhrase =
  result = RotPhrase(items: @[])
  for item in parsePhraseItems(format, reader, context):
    result.items.add item

type BlockState* = object
  ended*: bool
  context*: WhitespaceContext

proc initBlockState*(context: WhitespaceContext): BlockState =
  BlockState(context: context)

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

proc findPhrase*(format: RotFormat, reader: var RotReader, state: BlockState): bool =
  ## moves through reader looking for block phrase, false if phrase ended
  if state.ended:
    return false
  result = false
  for ch in format.charsHandleComments(reader):
    template foundItem() =
      reader.resetPos()
      return true
    checkBlockPhrase(format, reader, ch, state.context, foundItem)

proc findPhrase*(format: RotFormat, reader: var RotReader, context: WhitespaceContext): bool =
  var state = initBlockState(context)
  result = findPhrase(format, reader, state)

proc parsePhrase*(format: RotFormat, reader: var RotReader, state: BlockState): RotPhrase =
  result = parsePhrase(format, reader, LineContext)
  assert result.items.len != 0

iterator parseBlockPhrases*(format: RotFormat, reader: var RotReader, context: WhitespaceContext = FreeContext): RotPhrase =
  var state = initBlockState(context)
  while format.findPhrase(reader, state):
    let phrase = parsePhrase(format, reader, state)
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
  SymbolKind* = enum
    SymbolUnquoted ## <word>
    SymbolQuoted ## `
  SymbolContent* = object
    kind*: SymbolKind
  TextKind* = enum
    TextQuoted ## "
    TextOpen # :
  TextContent* = object
    case kind*: TextKind
    of TextQuoted: discard
    of TextOpen: open*: OpenStart
  PhraseKind* = enum
    ## can also result in unit, it is just the same kind of phrase iterator
    PhraseClosed ## ()
    PhraseOpen # |
  PhraseContent* = object
    case kind*: PhraseKind
    of PhraseClosed, PhraseOpen:
      state*: PhraseState
  BlockKind* = enum
    BlockClosed ## {}
    BlockOpen # ::
    PhraseBlockClosed ## []
    PhraseBlockOpen # ||
  BlockContent* = object
    case kind*: BlockKind
    of BlockClosed, BlockOpen:
      blockState*: BlockState
    of PhraseBlockClosed, PhraseBlockOpen:
      phraseBlockState*: PhraseState
  ItemContent* = object
    ## iterator for item content
    associated*: bool
    case kind*: RotKind
    of Unit: discard
    of Symbol: symbol*: SymbolContent
    of Text: text*: TextContent
    of Phrase: phrase*: PhraseContent
    of Block: `block`*: BlockContent

proc parseItemStartInner(format: RotFormat, reader: var RotReader, allowAssociation: bool, context: WhitespaceContext, start: char): ItemContent =
  ## mirrored with `parseItemInner` above
  result = ItemContent(associated: false, kind: Unit)
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
        if allowAssociation:
          let gotNext = reader.nextChar()
          assert gotNext
        else:
          reader.error("expected lhs for colon association")
      if colonBlock:
        let open = startOpenComments(format, reader)
        var b: BlockState
        case open.kind
        of OpenEmpty:
          b = BlockState(ended: true)
        of OpenIndent:
          b = initBlockState(indentContext(open.minIndent))
        of OpenLine:
          b = initBlockState(LineContext)
        result = ItemContent(associated: associate, kind: Block,
          `block`: BlockContent(kind: BlockOpen, blockState: b))
      else:
        let open = startOpenRaw(format, reader)
        result = ItemContent(associated: associate, kind: Text,
          text: TextContent(kind: TextOpen, open: open))
      #state.ended = context.sensitivity != IndentSensitive
    of TreatAsSymbol:
      reader.resetPos()
      result = ItemContent(associated: false, kind: Symbol, symbol: SymbolContent(kind: SymbolUnquoted))
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
        if allowAssociation:
          let gotNext = reader.nextChar()
          assert gotNext
        else:
          reader.error("expected lhs for pipe association")
      let open = startOpenComments(format, reader)
      var p: PhraseState
      case open.kind
      of OpenEmpty:
        p = PhraseState(ended: true)
      of OpenIndent:
        p = initPhraseState(indentContext(open.minIndent))
      of OpenLine:
        p = initPhraseState(LineContext)
      if pipeBlock:
        result = ItemContent(associated: associate, kind: Block,
          `block`: BlockContent(kind: PhraseBlockOpen, phraseBlockState: p))
      else:
        result = ItemContent(associated: associate, kind: Phrase,
          phrase: PhraseContent(kind: PhraseOpen, state: p))
      #state.ended = context.sensitivity != IndentSensitive
    of TreatAsSymbol:
      reader.resetPos()
      result = ItemContent(associated: false, kind: Symbol, symbol: SymbolContent(kind: SymbolUnquoted))
  of '=':
    if not allowAssociation:
      reader.error("expected lhs for association")
    var start2: char
    for ch2 in format.charsHandleComments(reader):
      if ch2 notin Whitespace:
        # skips newlines too
        start2 = ch2
        break
    if reader.done:
      reader.error("expected rhs for association, got end of file")
    result = parseItemStartInner(format, reader, allowAssociation = false, context, start2)
    assert not result.associated
    result.associated = true
  of '"':
    result = ItemContent(associated: false, kind: Text, text: TextContent(kind: TextQuoted))
  of '`':
    result = ItemContent(associated: false, kind: Symbol, symbol: SymbolContent(kind: SymbolQuoted))
  of '(':
    let p = initPhraseState(FreeContext)
    result = ItemContent(associated: false, kind: Phrase, phrase: PhraseContent(kind: PhraseClosed, state: p))
  of '{':
    let b = initBlockState(FreeContext)
    result = ItemContent(associated: false, kind: Block, `block`: BlockContent(kind: BlockClosed, blockState: b))
  of '[':
    case format.bracket
    of DisableFeature:
      reader.error("bracket syntax disabled")
    of EnableFeature:
      let p = initPhraseState(FreeContext)
      result = ItemContent(associated: false, kind: Block, `block`: BlockContent(kind: PhraseBlockClosed, phraseBlockState: p))
    of TreatAsSymbol:
      reader.resetPos()
      result = ItemContent(associated: false, kind: Symbol, symbol: SymbolContent(kind: SymbolUnquoted))
  else:
    if start in format.symbolDisallowedChars:
      reader.error("expected phrase term, got " & $start)
    else:
      reader.resetPos()
      result = ItemContent(associated: false, kind: Symbol, symbol: SymbolContent(kind: SymbolUnquoted))

proc startItemInner(format: RotFormat, reader: var RotReader, state: var PhraseState, start: char): ItemContent =
  enterItem(format, reader, state)
  result = parseItemStartInner(format, reader, state.allowAssociation, state.context, start)

proc startItem*(format: RotFormat, reader: var RotReader, state: var PhraseState): ItemContent =
  if not reader.nextChar():
    reader.error("expected phrase item start")
  result = startItemInner(format, reader, state, reader.current)

# XXX maybe allow iterating over symbol/text characters too

proc parseAllContent*(format: RotFormat, reader: var RotReader, start: var SymbolContent): string =
  case start.kind
  of SymbolUnquoted:
    result = parseUnquotedSymbol(format, reader)
  of SymbolQuoted:
    result = parseQuotedSymbol(format, reader)

proc parseAllContent*(format: RotFormat, reader: var RotReader, start: var TextContent): string =
  case start.kind
  of TextQuoted:
    result = parseQuotedText(format, reader)
  of TextOpen:
    case start.open.kind
    of OpenEmpty:
      result = ""
    of OpenIndent:
      result = parseIndentedString(reader, start.open.minIndent)
    of OpenLine:
      result = parseLineString(reader)

proc findContent*(format: RotFormat, reader: var RotReader, start: var PhraseContent): bool {.inline.} =
  result = findPhraseItem(format, reader, start.state)

proc parseSingleContent*(format: RotFormat, reader: var RotReader, start: var PhraseContent): RotArgument =
  result = parsePhraseItem(format, reader, start.state)

proc parseAllContent*(format: RotFormat, reader: var RotReader, start: var PhraseContent): RotTerm =
  ## phrase or unit
  var p = RotPhrase(items: @[])
  while findContent(format, reader, start):
    p.items.add parseSingleContent(format, reader, start)
  if p.items.len == 0:
    result = RotTerm(kind: Unit)
  else:
    result = RotTerm(kind: Phrase, phrase: p)

proc findContent*(format: RotFormat, reader: var RotReader, start: var BlockContent): bool {.inline.} =
  case start.kind
  of BlockOpen, BlockClosed:
    result = findPhrase(format, reader, start.blockState)
  of PhraseBlockOpen, PhraseBlockClosed:
    result = findPhraseItem(format, reader, start.phraseBlockState)

proc parseSingleContent*(format: RotFormat, reader: var RotReader, start: var BlockContent): RotPhrase =
  case start.kind
  of BlockOpen, BlockClosed:
    result = parsePhrase(format, reader, start.blockState)
  of PhraseBlockOpen, PhraseBlockClosed:
    let item = parsePhraseItem(format, reader, start.phraseBlockState)
    # XXX associations do not link together here as in `phraseToBlock`,
    # a way to do it is to get the next item start here and store it
    # for next time if it isnt an association
    result = RotPhrase(items: @[item])

proc parseAllContent*(format: RotFormat, reader: var RotReader, start: var BlockContent): RotBlock =
  ## phrase or unit
  result = RotBlock(items: @[])
  while findContent(format, reader, start):
    result.items.add parseSingleContent(format, reader, start)

proc parseAllContent*(format: RotFormat, reader: var RotReader, start: var ItemContent): RotArgument =
  result = RotArgument(associated: start.associated)
  case start.kind
  of Unit: discard
  of Symbol:
    let s = parseAllContent(format, reader, start.symbol)
    result.term = RotTerm(kind: Symbol, symbol: s)
  of Text:
    let t = parseAllContent(format, reader, start.text)
    result.term = RotTerm(kind: Text, text: t)
  of Phrase:
    let p = parseAllContent(format, reader, start.phrase)
    result.term = p
  of Block:
    let b = parseAllContent(format, reader, start.block)
    result.term = RotTerm(kind: Block, `block`: b)

proc finishItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, start: SymbolContent) {.inline.} =
  exitItem(format, reader, state)

proc finishItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, start: TextContent) {.inline.} =
  exitItem(format, reader, state)

proc finishItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, start: PhraseContent) =
  case start.kind
  of PhraseClosed:
    let gotNext = reader.nextChar()
    if gotNext and reader.current == ')':
      discard
    else:
      reader.error("expected ) for enclosed phrase")
  of PhraseOpen:
    state.ended = state.context.sensitivity != IndentSensitive
  exitItem(format, reader, state)

proc finishItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, start: BlockContent) =
  case start.kind
  of BlockClosed:
    let gotNext = reader.nextChar()
    if gotNext and reader.current == '}':
      discard
    else:
      reader.error("expected } for enclosed block")
  of PhraseBlockClosed:
    let gotNext = reader.nextChar()
    if gotNext and reader.current == ']':
      discard
    else:
      reader.error("expected ] for enclosed phrase block")
  of BlockOpen, PhraseBlockOpen:
    state.ended = state.context.sensitivity != IndentSensitive
  exitItem(format, reader, state)

proc finishItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, start: ItemContent) {.inline.} =
  case start.kind
  of Unit: exitItem(format, reader, state)
  of Symbol: finishItem(format, reader, state, start.symbol)
  of Text: finishItem(format, reader, state, start.text)
  of Phrase: finishItem(format, reader, state, start.phrase)
  of Block: finishItem(format, reader, state, start.block)
