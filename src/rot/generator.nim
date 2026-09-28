import ./data, fleu/[flush_writer, flush_buffer], std/streams

type RotWriter* = IndentFlushWriter

proc initRotWriter*(bufferCapacity = 16): RotWriter {.inline.} =
  result = initIndentFlushWriter()
  result.startWrite(bufferCapacity)

proc initRotWriter*(consumer: BufferConsumer, bufferCapacity = 16): RotWriter {.inline.} =
  result = initIndentFlushWriter()
  result.startWrite(consumer, bufferCapacity)

proc initRotWriter*(stream: Stream, bufferCapacity = 16): RotWriter {.inline.} =
  result = initIndentFlushWriter()
  result.startWrite(stream, bufferCapacity)

when declared(File):
  proc initRotWriter*(file: File, bufferCapacity = 16): RotWriter {.inline.} =
    ## `file` has to last as long as the writer
    result = initIndentFlushWriter()
    result.startWrite(file, bufferCapacity)

type
  PhraseSeparator* = enum Comma, Space, CommaSpace
  BlockSeparator* = enum Semicolon, Newline, SemicolonNewline
  RotGenFormat* = object
    indentBlocks*: bool
    betweenItems*: PhraseSeparator
    betweenPhrases*: BlockSeparator

const
  InlineRotGen* = RotGenFormat(indentBlocks: false, betweenItems: CommaSpace, betweenPhrases: Semicolon)
  CompactRotGen* = RotGenFormat(indentBlocks: false, betweenItems: Comma, betweenPhrases: Semicolon)
  ReadableRotGen* = RotGenFormat(indentBlocks: true, betweenItems: Space, betweenPhrases: Newline)
  VerboseRotGen* = RotGenFormat(indentBlocks: true, betweenItems: CommaSpace, betweenPhrases: SemicolonNewline)

proc addText*(writer: var RotWriter, s: string) =
  writer.write '"'
  let oldIndent = writer.state.level
  writer.state.level = 0
  for c in s:
    if c == '"':
      writer.write c
    writer.write c
  writer.state.level = oldIndent
  writer.write '"'

proc addSymbol*(writer: var RotWriter, s: string) =
  const SimpleChars = {'A'..'Z', 'a'..'z', '0'..'9', '_', '.', '-', '+'}
  var quoted = false
  for c in s:
    if c notin SimpleChars:
      quoted = true
      break
  if quoted:
    writer.write '`'
    for c in s:
      if c == '`':
        writer.write c
      writer.write c
    writer.write '`'
  else:
    writer.write s

proc addUnit*(writer: var RotWriter) =
  writer.write "()"

type ItemList* = object
  needsSeparator*: bool

type PhraseList* = object
  needsSeparator*: bool
  pendingIndent*: bool

proc maybeSeparateItem*(format: RotGenFormat, writer: var RotWriter, list: var ItemList) =
  if list.needsSeparator:
    case format.betweenItems
    of Comma: writer.write ','
    of Space: writer.write ' '
    of CommaSpace: writer.write ", "
  else:
    list.needsSeparator = true

proc maybeAssociateItem*(format: RotGenFormat, writer: var RotWriter, list: var ItemList) =
  doAssert list.needsSeparator
  if format.betweenItems in {Space, CommaSpace}:
    writer.write " = "
  else:
    writer.write '='

proc maybeSeparatePhrase*(format: RotGenFormat, writer: var RotWriter, list: var PhraseList) =
  if list.needsSeparator:
    case format.betweenPhrases
    of Semicolon:
      writer.write ';'
      if format.betweenItems in {Space, CommaSpace}:
        writer.write ' '
    of Newline: writer.write '\n'
    of SemicolonNewline: writer.write ";\n"
  else:
    list.needsSeparator = true
    if format.betweenPhrases in {Newline, SemicolonNewline}:
      if list.pendingIndent:
        writer.addIndent()
      writer.write '\n'

proc initItemList*(#[format: RotGenFormat, writer: var RotWriter]#): ItemList {.inline.} =
  result = ItemList(needsSeparator: false)

proc initPhraseList*(indent: bool): PhraseList {.inline.} =
  result = PhraseList(needsSeparator: false, pendingIndent: indent)

proc finishPhraseList*(list: var PhraseList, format: RotGenFormat, writer: var RotWriter) {.inline.} =
  if list.needsSeparator and format.betweenPhrases in {Newline, SemicolonNewline}:
    writer.write '\n'
    if list.pendingIndent:
      writer.removeIndent()

template add*(list: var ItemList, format: RotGenFormat, writer: var RotWriter, body: typed) =
  maybeSeparateItem(format, writer, list)
  body

template associate*(list: var ItemList, format: RotGenFormat, writer: var RotWriter, body: typed) =
  maybeAssociateItem(format, writer, list)
  body

template add*(list: var PhraseList, format: RotGenFormat, writer: var RotWriter, body: typed) =
  maybeSeparatePhrase(format, writer, list)
  body

template closePhrase*(format: RotGenFormat, writer: var RotWriter, body: typed) =
  writer.write '('
  body
  writer.write ')'

template closePhraseBlock*(format: RotGenFormat, writer: var RotWriter, body: typed) =
  writer.write '['
  body
  writer.write ']'

template withItems*(list: var ItemList, format: RotGenFormat, writer: var RotWriter, body: typed) =
  list = initItemList()
  body

template closeBlock*(format: RotGenFormat, writer: var RotWriter, body: typed) =
  writer.write '{'
  body
  writer.write '}'

template withLevelPhrases*(list: var PhraseList, format: RotGenFormat, writer: var RotWriter, body: typed) =
  list = initPhraseList(indent = false)
  body
  finishPhraseList(list, format, writer)

template withIndentedPhrases*(list: var PhraseList, format: RotGenFormat, writer: var RotWriter, body: typed) =
  list = initPhraseList(indent = format.indentBlocks)
  body
  finishPhraseList(list, format, writer)

proc prettyPrint*(writer: var RotWriter, term: RotTerm, format: RotGenFormat = ReadableRotGen) {.gcsafe.}

proc prettyPrintEach*(writer: var RotWriter, phrase: RotPhrase, format: RotGenFormat = ReadableRotGen) =
  var list: ItemList
  list.withItems format, writer:
    for item in phrase.items:
      if item.associated:
        list.associate format, writer:
          prettyPrint(writer, item.term, format)
      else:
        list.add format, writer:
          prettyPrint(writer, item.term, format)

proc prettyPrintEach*(writer: var RotWriter, `block`: RotBlock, format: RotGenFormat = ReadableRotGen) =
  var list: PhraseList
  list.withLevelPhrases format, writer:
    for phrase in `block`.phrases:
      list.add format, writer:
        prettyPrintEach(writer, phrase, format)

proc prettyPrint*(writer: var RotWriter, term: RotTerm, format: RotGenFormat = ReadableRotGen) =
  case term.kind
  of Unit: writer.addUnit()
  of Text: writer.addText(term.text)
  of Symbol: writer.addSymbol(term.symbol)
  of Phrase:
    closePhrase format, writer:
      prettyPrintEach(writer, term.phrase, format)
  of Block:
    closeBlock format, writer:
      var list: PhraseList
      list.withIndentedPhrases format, writer:
        for phrase in term.block.phrases:
          list.add format, writer:
            prettyPrintEach(writer, phrase, format)

proc prettyPrint*(term: RotTerm, format: RotGenFormat = ReadableRotGen): string =
  var writer = initRotWriter()
  prettyPrint(writer, term, format)
  result = writer.finishWrite()

proc prettyPrintEach*(`block`: RotBlock, format: RotGenFormat = ReadableRotGen): string =
  var writer = initRotWriter()
  prettyPrintEach(writer, `block`, format)
  result = writer.finishWrite()

proc prettyPrintEach*(phrase: RotPhrase, format: RotGenFormat = ReadableRotGen): string =
  var writer = initRotWriter()
  prettyPrintEach(writer, phrase, format)
  result = writer.finishWrite()

proc prettyPrintUnwrap*(term: RotTerm, format: RotGenFormat = ReadableRotGen): string =
  var writer = initRotWriter()
  case term.kind
  of Block:
    prettyPrintEach(writer, term.block, format)
  of Phrase:
    prettyPrintEach(writer, term.phrase, format)
  else:
    prettyPrint(writer, term, format)
  result = writer.finishWrite()
