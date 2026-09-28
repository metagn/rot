import ./[common, data, reader], std/strutils

proc buildErrorMessage*(error: var RotParseError) =
  error.msg = ""
  when not rotDisableLineColumn:
    if error.filename.len != 0:
      error.msg.add(error.filename)
    error.msg.add('(')
    error.msg.addInt(error.line)
    error.msg.add(", ")
    error.msg.addInt(error.column)
    error.msg.add(") ")
  else:
    if error.filename.len != 0:
      error.msg.add(error.filename)
      error.msg.add(": ")
  error.msg.add(error.simpleMessage)

proc error*(reader: var RotReader, msg: string) =
  var err = RotParseError(
    filename: reader.filename,
    simpleMessage: msg)
  when not rotDisableLineColumn:
    err.line = reader.state.line
    err.column = reader.state.column
  buildErrorMessage(err)
  var errRef = new(RotParseError)
  errRef[] = err
  raise errRef

# actual reader behavior:

iterator charsHandleComments*(format: RotFormat, reader: var RotReader): char =
  var comment = false
  for ch in reader.rawChars:
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

proc parseUnquotedSymbol*(format: RotFormat, reader: var RotReader): string =
  result = ""
  let disallowedChars = format.symbolDisallowedChars
  let concatChars = format.symbolConcatChars
  var concat = ""
  for ch in reader.rawChars:
    if ch in disallowedChars:
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
  var lastWasQuote = false
  for ch in reader.rawChars:
    if lastWasQuote:
      if ch == quote:
        result.add ch
        lastWasQuote = false
      else:
        return
    elif ch == quote:
      lastWasQuote = true
    else:
      result.add ch
  if not lastWasQuote:
    reader.error("expected closing quote for " & $quote)

const TextQuote* = '"'
const SymbolQuote* = '`'

proc parseQuotedText*(format: RotFormat, reader: var RotReader): string =
  if not reader.nextChar() or reader.state.current != TextQuote:
    raise newException(RotValueError, "expected quote character for text")
  result = parseQuotedInner(format, reader, TextQuote)

proc parseQuotedSymbol*(format: RotFormat, reader: var RotReader): string =
  if not reader.nextChar() or reader.state.current != SymbolQuote:
    raise newException(RotValueError, "expected quote character for symbol")
  result = parseQuotedInner(format, reader, SymbolQuote)

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
  let startIndent = reader.state.currentLineIndent
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
      finalIndent = reader.state.currentLineIndent
      break
  if newline:
    if finalIndent <= startIndent:
      result = OpenStart(kind: OpenEmpty)
    else:
      result = OpenStart(kind: OpenIndent, minIndent: finalIndent)
  else:
    result = OpenStart(kind: OpenLine)

proc startOpenComments(format: RotFormat, reader: var RotReader): OpenStart =
  let startIndent = reader.state.currentLineIndent
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
      finalIndent = reader.state.currentLineIndent
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
        return
      recordIndent = false
  result.add(currentLine)

proc parseLineString(reader: var RotReader): string =
  result = ""
  for ch in reader.rawChars:
    case ch
    of Newlines:
      # don't consume newline
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

proc parsePhrase*(format: RotFormat, reader: var RotReader, context: WhitespaceContext): RotPhrase {.gcsafe.}
proc parseBlock*(format: RotFormat, reader: var RotReader, context: WhitespaceContext = FreeContext): RotBlock {.gcsafe.}

proc phraseToBlock*(p: RotPhrase): RotBlock =
  result = RotBlock()
  result.phrases = newSeqOfCap[RotPhrase](p.items.len)
  for item in p.items:
    if item.associated:
      result.phrases[^1].items.add RotItem(associated: true, term: item.term)
    else:
      result.phrases.add RotPhrase(items: @[RotItem(associated: false, term: item.term)])

proc parseColonBlockInner(format: RotFormat, reader: var RotReader): RotBlock =
  let open = startOpenComments(format, reader)
  case open.kind
  of OpenEmpty:
    result = RotBlock(phrases: @[])
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
    reader.state.currentLineIndent < state.context.minIndent

proc parseItemInner(format: RotFormat, reader: var RotReader, state: var PhraseState, start: char): RotItem =
  ## mirrored with `ItemContent` code below
  case start
  of ':':
    case format.colon
    of DisableFeature:
      reader.advance()
      reader.error("colon syntax disabled")
    of EnableFeature:
      reader.advance()
      if state.context.sensitivity == Freeform: # and format.newline == EnableDelimiter
        reader.error("colon syntax not allowed outside of block context")
      let colonBlock = reader.peekCharOrZero() == ':'
      if colonBlock: reader.advance()
      let associate = reader.peekCharOrZero() == '='
      if associate:
        reader.advance()
        if not state.allowAssociation:
          reader.error("expected lhs for colon association")
      if colonBlock:
        let b = parseColonBlockInner(format, reader)
        result = RotItem(associated: associate, term: RotTerm(kind: Block, `block`: b))
      else:
        let s = parseColonStringInner(format, reader)
        result = RotItem(associated: associate, term: RotTerm(kind: Text, text: s))
      state.ended = state.context.sensitivity == NewlineSensitive
    of TreatAsSymbol:
      let s = parseUnquotedSymbol(format, reader)
      result = RotItem(associated: false, term: RotTerm(kind: Symbol, symbol: s))
  of '|':
    case format.colon
    of DisableFeature:
      reader.advance()
      reader.error("pipe syntax disabled")
    of EnableFeature:
      reader.advance()
      if state.context.sensitivity == Freeform: # and format.newline == EnableDelimiter
        reader.error("pipe syntax not allowed outside of block context")
      let pipeBlock = reader.peekCharOrZero() == '|'
      if pipeBlock: reader.advance()
      let associate = reader.peekCharOrZero() == '='
      if associate:
        reader.advance()
        if not state.allowAssociation:
          reader.error("expected lhs for pipe association")
      let p = parsePipeInner(format, reader)
      if pipeBlock:
        let b = phraseToBlock(p)
        result = RotItem(associated: associate, term: RotTerm(kind: Block, `block`: b))
      else:
        result = RotItem(associated: associate, term: RotTerm(kind: Phrase, phrase: p))
      state.ended = state.context.sensitivity == NewlineSensitive
    of TreatAsSymbol:
      let s = parseUnquotedSymbol(format, reader)
      result = RotItem(associated: false, term: RotTerm(kind: Symbol, symbol: s))
  of '=':
    reader.advance()
    if not state.allowAssociation:
      reader.error("expected lhs for association")
    var start2: char
    for ch2 in format.charsHandleComments(reader):
      if ch2 notin Whitespace:
        # skips newlines too
        start2 = ch2
        break
    if reader.state.done:
      reader.error("expected rhs for association, got end of file")
    state.allowAssociation = false
    let right = parseItemInner(format, reader, state, start2)
    assert not right.associated
    result = RotItem(associated: true, term: right.term)
  of '"':
    reader.advance()
    let s = parseQuotedInner(format, reader, start)
    result = RotItem(associated: false, term: RotTerm(kind: Text, text: s))
  of '`':
    reader.advance()
    let s = parseQuotedInner(format, reader, start)
    result = RotItem(associated: false, term: RotTerm(kind: Symbol, symbol: s))
  of '(':
    reader.advance()
    let p = parsePhrase(format, reader, FreeContext)
    let gotNext = reader.nextChar()
    if gotNext and reader.state.current == ')':
      discard
    else:
      reader.error("expected ) for enclosed phrase")
    if p.items.len == 0:
      result = RotItem(associated: false, term: RotTerm(kind: Unit))
    else:
      result = RotItem(associated: false, term: RotTerm(kind: Phrase, phrase: p))
  of '{':
    reader.advance()
    let b = parseBlock(format, reader)
    let gotNext = reader.nextChar()
    if gotNext and reader.state.current == '}':
      discard
    else:
      reader.error("expected } for enclosed block")
    result = RotItem(associated: false, term: RotTerm(kind: Block, `block`: b))
  of '[':
    case format.bracket
    of DisableFeature:
      reader.advance()
      reader.error("bracket syntax disabled")
    of EnableFeature:
      reader.advance()
      let p = parsePhrase(format, reader, FreeContext)
      let gotNext = reader.nextChar()
      if gotNext and reader.state.current == ']':
        discard
      else:
        reader.error("expected ] for enclosed block")
      let b = phraseToBlock(p)
      result = RotItem(associated: false, term: RotTerm(kind: Block, `block`: b))
    of TreatAsSymbol:
      let s = parseUnquotedSymbol(format, reader)
      result = RotItem(associated: false, term: RotTerm(kind: Symbol, symbol: s))
  else:
    if start in format.symbolDisallowedChars:
      reader.advance()
      reader.error("expected phrase term, got " & $start)
    else:
      let s = parseUnquotedSymbol(format, reader)
      result = RotItem(associated: false, term: RotTerm(kind: Symbol, symbol: s))

proc enterItem(format: RotFormat, reader: var RotReader, state: var PhraseState) {.inline.} =
  if not state.expectingItem:
    reader.error("expected comma delimiter between phrase terms")

proc exitItem(format: RotFormat, reader: var RotReader, state: var PhraseState) {.inline.} =
  state.currentlySensitive = state.context.sensitivity != Freeform
  state.allowAssociation = true
  if format.inlineSpace != EnableDelimiter:
    # no character also counts as inline space delimiter
    state.expectingItem = false

proc parseFullItemInner(format: RotFormat, reader: var RotReader, state: var PhraseState, start: char): RotItem =
  ## mirrored with `ItemContent` code below
  enterItem(format, reader, state)
  result = parseItemInner(format, reader, state, start)
  exitItem(format, reader, state)

proc findItem*(format: RotFormat, reader: var RotReader, state: var PhraseState): bool =
  ## moves through reader looking for phrase item, false if phrase ended
  if state.ended:
    return false
  result = false
  for ch in format.charsHandleComments(reader):
    template foundItem() =
      return true
    case ch
    of ',':
      if checkIndentDelim(format, reader, state):
        break
      else:
        if state.context.sensitivity == NewlineSensitive:
          # maybe also allow breaking indent sensitivity, but this would have to track if a newline was encountered
          state.currentlySensitive = false
        state.expectingItem = true
        state.allowAssociation = false
    of ';':
      # don't consume semicolon
      break
    of Whitespace - Newlines:
      if format.inlineSpace == TreatAsSymbolStart:
        if checkIndentDelim(format, reader, state):
          break
        else:
          foundItem()
    of Newlines:
      case format.newline
      of TreatAsSymbolStart:
        if checkIndentDelim(format, reader, state):
          break
        else:
          foundItem()
      of EnableDelimiter:
        if state.context.sensitivity == NewlineSensitive and state.currentlySensitive:
          # don't consume newline
          break
      else: discard
    of ')', '}':
      # other context
      break
    of ']':
      if format.bracket == TreatAsSymbol:
        if checkIndentDelim(format, reader, state):
          break
        else:
          foundItem()
      else:
        # other context
        break
    else:
      if checkIndentDelim(format, reader, state):
        break
      else:
        foundItem()

proc parseItem*(format: RotFormat, reader: var RotReader, state: var PhraseState): RotItem =
  var c: char
  if not reader.peekChar(c):
    raise newException(RotValueError, "expected phrase item")
  result = parseFullItemInner(format, reader, state, c)

iterator parsePhraseItems*(format: RotFormat, reader: var RotReader, context: WhitespaceContext): RotItem =
  var state = initPhraseState(context)
  while format.findItem(reader, state):
    yield format.parseItem(reader, state)

proc parsePhrase*(format: RotFormat, reader: var RotReader, context: WhitespaceContext): RotPhrase =
  result = RotPhrase(items: @[])
  for item in parsePhraseItems(format, reader, context):
    result.items.add item

type BlockState* = object
  ended*: bool
  context*: WhitespaceContext

proc initBlockState*(context: WhitespaceContext): BlockState =
  BlockState(context: context)

proc findPhrase*(format: RotFormat, reader: var RotReader, state: BlockState): bool =
  ## moves through reader looking for block phrase, false if phrase ended
  if state.ended:
    return false
  result = false
  for ch in format.charsHandleComments(reader):
    template foundItem() =
      return true
    case ch
    of ')', '}':
      # other context
      break
    of ']':
      if format.bracket == TreatAsSymbol:
        foundItem()
      else:
        # other context
        break
    of Whitespace - Newlines:
      if format.inlineSpace == TreatAsSymbolStart and not
          # inline whitespace ignored if part of indent
          (state.context.sensitivity == IndentSensitive and reader.state.currentLineIndent <= state.context.minIndent):
        foundItem()
    of Newlines:
      case state.context.sensitivity
      of Freeform:
        if format.newline == TreatAsSymbolStart:
          foundItem()
      of NewlineSensitive:
        break
      of IndentSensitive:
        # default newline behavior necessary for indent sensitivity to function
        discard
    of ';':
      if state.context.sensitivity == IndentSensitive and
          reader.state.currentLineIndent < state.context.minIndent:
        break
    else:
      if state.context.sensitivity == IndentSensitive and
          reader.state.currentLineIndent < state.context.minIndent:
        break
      else:
        foundItem()

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
  result = RotBlock(phrases: @[])
  for phrase in parseBlockPhrases(format, reader, context):
    result.phrases.add phrase

proc parseFullBlock*(format: RotFormat, reader: var RotReader): RotBlock =
  result = parseBlock(format, reader)
  var c: char
  if reader.peekChar(c):
    reader.error("block finished before input: " & $c)

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
    PhraseOpen ## |
    #PhraseSingleItem ## single item inside a phrase block
  PhraseContent* = object
    case kind*: PhraseKind
    of PhraseClosed, PhraseOpen:
      state*: PhraseState
    #of PhraseSingleItem:
    #  singleItem*: ref ItemContent
  BlockKind* = enum
    BlockClosed ## {}
    BlockOpen ## ::
    PhraseBlockClosed ## []
    PhraseBlockOpen ## ||
  BlockContent* = object
    case kind*: BlockKind
    of BlockClosed, BlockOpen:
      blockState*: BlockState
    of PhraseBlockClosed, PhraseBlockOpen:
      phraseBlockState*: PhraseState
  TermContent* = object
    case kind*: RotKind
    of Unit: discard
    of Symbol: symbol*: SymbolContent
    of Text: text*: TextContent
    of Phrase: phrase*: PhraseContent
    of Block: `block`*: BlockContent
  ItemContent* = object
    ## iterator for item content
    associated*: bool
    term*: TermContent

proc startBlock*(context: WhitespaceContext = FreeContext): BlockContent {.inline.} =
  result = BlockContent(kind: BlockOpen, blockState: initBlockState(context))

proc startPhrase*(context: WhitespaceContext = LineContext): PhraseContent {.inline.} =
  result = PhraseContent(kind: PhraseOpen, state: initPhraseState(context))

proc startSymbol*(): SymbolContent {.inline.} =
  SymbolContent(kind: SymbolUnquoted)

proc parseItemStartInner(format: RotFormat, reader: var RotReader, allowAssociation: bool, context: WhitespaceContext, start: char): ItemContent =
  ## mirrored with `parseItemInner` above
  result = ItemContent(associated: false, term: TermContent(kind: Unit))
  case start
  of ':':
    case format.colon
    of DisableFeature:
      reader.advance()
      reader.error("colon syntax disabled")
    of EnableFeature:
      reader.advance()
      if context.sensitivity == Freeform: # and format.newline == EnableDelimiter
        reader.error("colon syntax not allowed outside of block context")
      let colonBlock = reader.peekCharOrZero() == ':'
      if colonBlock: reader.advance()
      let associate = reader.peekCharOrZero() == '='
      if associate:
        reader.advance()
        if not allowAssociation:
          reader.error("expected lhs for colon association")
      result.associated = associate
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
        result.term = TermContent(kind: Block,
          `block`: BlockContent(kind: BlockOpen, blockState: b))
      else:
        let open = startOpenRaw(format, reader)
        result.term = TermContent(kind: Text,
          text: TextContent(kind: TextOpen, open: open))
      #state.ended = context.sensitivity != IndentSensitive
    of TreatAsSymbol:
      result.term = TermContent(kind: Symbol, symbol: SymbolContent(kind: SymbolUnquoted))
  of '|':
    case format.colon
    of DisableFeature:
      reader.advance()
      reader.error("pipe syntax disabled")
    of EnableFeature:
      reader.advance()
      if context.sensitivity == Freeform: # and format.newline == EnableDelimiter
        reader.error("pipe syntax not allowed outside of block context")
      let pipeBlock = reader.peekCharOrZero() == '|'
      if pipeBlock: reader.advance()
      let associate = reader.peekCharOrZero() == '='
      if associate:
        reader.advance()
        if not allowAssociation:
          reader.error("expected lhs for pipe association")
      result.associated = associate
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
        result.term = TermContent(kind: Block,
          `block`: BlockContent(kind: PhraseBlockOpen, phraseBlockState: p))
      else:
        result.term = TermContent(kind: Phrase,
          phrase: PhraseContent(kind: PhraseOpen, state: p))
      #state.ended = context.sensitivity != IndentSensitive
    of TreatAsSymbol:
      result.term = TermContent(kind: Symbol, symbol: SymbolContent(kind: SymbolUnquoted))
  of '=':
    reader.advance()
    if not allowAssociation:
      reader.error("expected lhs for association")
    var start2: char
    for ch2 in format.charsHandleComments(reader):
      if ch2 notin Whitespace:
        # skips newlines too
        start2 = ch2
        break
    if reader.state.done:
      reader.error("expected rhs for association, got end of file")
    result = parseItemStartInner(format, reader, allowAssociation = false, context, start2)
    assert not result.associated
    result.associated = true
  of '"':
    reader.advance()
    result.term = TermContent(kind: Text, text: TextContent(kind: TextQuoted))
  of '`':
    reader.advance()
    result.term = TermContent(kind: Symbol, symbol: SymbolContent(kind: SymbolQuoted))
  of '(':
    reader.advance()
    let p = initPhraseState(FreeContext)
    result.term = TermContent(kind: Phrase, phrase: PhraseContent(kind: PhraseClosed, state: p))
  of '{':
    reader.advance()
    let b = initBlockState(FreeContext)
    result.term = TermContent(kind: Block, `block`: BlockContent(kind: BlockClosed, blockState: b))
  of '[':
    case format.bracket
    of DisableFeature:
      reader.advance()
      reader.error("bracket syntax disabled")
    of EnableFeature:
      reader.advance()
      let p = initPhraseState(FreeContext)
      result.term = TermContent(kind: Block, `block`: BlockContent(kind: PhraseBlockClosed, phraseBlockState: p))
    of TreatAsSymbol:
      result.term = TermContent(kind: Symbol, symbol: SymbolContent(kind: SymbolUnquoted))
  else:
    if start in format.symbolDisallowedChars:
      reader.advance()
      reader.error("expected phrase term, got " & $start)
    else:
      result.term = TermContent(kind: Symbol, symbol: SymbolContent(kind: SymbolUnquoted))

proc startItemInner(format: RotFormat, reader: var RotReader, state: var PhraseState, start: char): ItemContent =
  enterItem(format, reader, state)
  result = parseItemStartInner(format, reader, state.allowAssociation, state.context, start)

proc startItem*(format: RotFormat, reader: var RotReader, state: var PhraseState): ItemContent =
  var c: char
  if not reader.peekChar(c):
    reader.error("expected phrase item start")
  result = startItemInner(format, reader, state, c)

# XXX maybe allow iterating over symbol/text characters too

proc parseAll*(format: RotFormat, reader: var RotReader, content: var SymbolContent): string =
  case content.kind
  of SymbolUnquoted:
    result = parseUnquotedSymbol(format, reader)
  of SymbolQuoted:
    result = parseQuotedInner(format, reader, SymbolQuote)

proc parseAll*(format: RotFormat, reader: var RotReader, content: var TextContent): string =
  case content.kind
  of TextQuoted:
    result = parseQuotedInner(format, reader, TextQuote)
  of TextOpen:
    case content.open.kind
    of OpenEmpty:
      result = ""
    of OpenIndent:
      result = parseIndentedString(reader, content.open.minIndent)
    of OpenLine:
      result = parseLineString(reader)

proc findPart*(format: RotFormat, reader: var RotReader, content: var PhraseContent): bool {.inline.} =
  result = findItem(format, reader, content.state)

proc startPart*(format: RotFormat, reader: var RotReader, content: var PhraseContent): ItemContent {.inline.} =
  result = startItem(format, reader, content.state)

proc parsePart*(format: RotFormat, reader: var RotReader, content: var PhraseContent): RotItem =
  result = parseItem(format, reader, content.state)

proc parseAll*(format: RotFormat, reader: var RotReader, content: var PhraseContent): RotTerm =
  ## phrase or unit
  var p = RotPhrase(items: @[])
  while findPart(format, reader, content):
    p.items.add parsePart(format, reader, content)
  if p.items.len == 0:
    result = RotTerm(kind: Unit)
  else:
    result = RotTerm(kind: Phrase, phrase: p)

proc findPart*(format: RotFormat, reader: var RotReader, content: var BlockContent): bool {.inline.} =
  case content.kind
  of BlockOpen, BlockClosed:
    result = findPhrase(format, reader, content.blockState)
  of PhraseBlockOpen, PhraseBlockClosed:
    result = findItem(format, reader, content.phraseBlockState)

proc startPart*(format: RotFormat, reader: var RotReader, content: var BlockContent): PhraseContent {.inline.} =
  case content.kind
  of BlockOpen, BlockClosed:
    result = startPhrase(LineContext)
  of PhraseBlockOpen, PhraseBlockClosed:
    raise newException(RotParseError, "nested parsing not supported for phrase blocks")
    #result = PhraseContent(kind: PhraseSingleItem)
    #new(result.singleItem)
    #result.singleItem[] = startItem(format, reader, content.phraseBlockState)

proc parsePart*(format: RotFormat, reader: var RotReader, content: var BlockContent): RotPhrase =
  case content.kind
  of BlockOpen, BlockClosed:
    result = parsePhrase(format, reader, content.blockState)
  of PhraseBlockOpen, PhraseBlockClosed:
    let item = parseItem(format, reader, content.phraseBlockState)
    # XXX associations do not link together here as in `phraseToBlock`,
    # a way to do it is to get the next item start here and store it
    # for next time if it isnt an association
    result = RotPhrase(items: @[item])

proc parseAll*(format: RotFormat, reader: var RotReader, content: var BlockContent): RotBlock =
  ## phrase or unit
  result = RotBlock(phrases: @[])
  while findPart(format, reader, content):
    result.phrases.add parsePart(format, reader, content)

proc parseAll*(format: RotFormat, reader: var RotReader, content: var TermContent): RotTerm =
  case content.kind
  of Unit: discard
  of Symbol:
    let s = parseAll(format, reader, content.symbol)
    result = RotTerm(kind: Symbol, symbol: s)
  of Text:
    let t = parseAll(format, reader, content.text)
    result = RotTerm(kind: Text, text: t)
  of Phrase:
    let p = parseAll(format, reader, content.phrase)
    result = p
  of Block:
    let b = parseAll(format, reader, content.block)
    result = RotTerm(kind: Block, `block`: b)

proc parseAll*(format: RotFormat, reader: var RotReader, content: var ItemContent): RotItem =
  result = RotItem(associated: content.associated, term: parseAll(format, reader, content.term))

proc finishItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, itemContent: SymbolContent) {.inline.} =
  exitItem(format, reader, state)

proc finishItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, itemContent: TextContent) {.inline.} =
  exitItem(format, reader, state)

proc finishItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, itemContent: PhraseContent) =
  case itemContent.kind
  of PhraseClosed:
    let gotNext = reader.nextChar()
    if gotNext and reader.state.current == ')':
      discard
    else:
      reader.error("expected ) for enclosed phrase")
  of PhraseOpen:
    state.ended = state.context.sensitivity == NewlineSensitive
  exitItem(format, reader, state)

proc finishItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, itemContent: BlockContent) =
  case itemContent.kind
  of BlockClosed:
    let gotNext = reader.nextChar()
    if gotNext and reader.state.current == '}':
      discard
    else:
      reader.error("expected } for enclosed block")
  of PhraseBlockClosed:
    let gotNext = reader.nextChar()
    if gotNext and reader.state.current == ']':
      discard
    else:
      reader.error("expected ] for enclosed phrase block")
  of BlockOpen, PhraseBlockOpen:
    state.ended = state.context.sensitivity == NewlineSensitive
  exitItem(format, reader, state)

proc finishItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, itemContent: TermContent) {.inline.} =
  case itemContent.kind
  of Unit: exitItem(format, reader, state)
  of Symbol: finishItem(format, reader, state, itemContent.symbol)
  of Text: finishItem(format, reader, state, itemContent.text)
  of Phrase: finishItem(format, reader, state, itemContent.phrase)
  of Block: finishItem(format, reader, state, itemContent.block)

proc finishItem*(format: RotFormat, reader: var RotReader, state: var PhraseState, itemContent: ItemContent) {.inline.} =
  finishItem(format, reader, state, itemContent.term)

proc finishPart*(format: RotFormat, reader: var RotReader, content: var PhraseContent, part: ItemContent) {.inline.} =
  case content.kind
  of PhraseOpen, PhraseClosed:
    finishItem(format, reader, content.state, part)

proc finishPart*(format: RotFormat, reader: var RotReader, content: var BlockContent, part: PhraseContent) {.inline.} =
  case content.kind
  of BlockOpen, BlockClosed:
    discard
  of PhraseBlockOpen, PhraseBlockClosed:
    discard#finishItem(format, reader, content.phraseBlockState, part.singleItem[])

iterator eachPart*(format: RotFormat, reader: var RotReader, content: var PhraseContent): var ItemContent =
  while findPart(format, reader, content):
    var itemContent = startPart(format, reader, content)
    yield (addr itemContent)[]
    finishPart(format, reader, content, itemContent)

iterator eachPart*(format: RotFormat, reader: var RotReader, content: var BlockContent): var PhraseContent =
  while findPart(format, reader, content):
    var itemContent = startPart(format, reader, content)
    yield (addr itemContent)[]
    finishPart(format, reader, content, itemContent)
