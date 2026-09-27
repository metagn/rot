import fleu/[flush_writer, flush_buffer], std/streams

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
  RotGeneratorFormat* = object
    indentBlocks*: bool
    betweenItems*: PhraseSeparator
    betweenPhrases*: BlockSeparator

const
  DefaultRotGen* = RotGeneratorFormat(indentBlocks: false, betweenItems: CommaSpace, betweenPhrases: Semicolon)
  PrettyRotGen* = RotGeneratorFormat(indentBlocks: true, betweenItems: Space, betweenPhrases: Newline)

proc addText*(writer: var RotWriter, s: string) =
  let oldIndent = writer.state.level
  writer.state.level = 0
  writer.write '"'
  for c in s:
    if c == '"':
      writer.write c
    writer.write c
  writer.write '"'
  writer.state.level = oldIndent

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

type ItemList* = object
  needsSeparator*: bool

type PhraseList* = object
  needsSeparator*: bool
  pendingIndent*: bool

proc maybeSeparateItem*(format: RotGeneratorFormat, writer: var RotWriter, list: var ItemList) =
  if list.needsSeparator:
    case format.betweenItems
    of Comma: writer.write ','
    of Space: writer.write ' '
    of CommaSpace: writer.write ", "
  else:
    list.needsSeparator = true

proc maybeAssociateItem*(format: RotGeneratorFormat, writer: var RotWriter, list: var ItemList) =
  doAssert list.needsSeparator
  if format.betweenItems in {Space, CommaSpace}:
    writer.write " = "
  else:
    writer.write '='

proc maybeSeparatePhrase*(format: RotGeneratorFormat, writer: var RotWriter, list: var PhraseList) =
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

proc initItemList*(#[format: RotGeneratorFormat, writer: var RotWriter]#): ItemList {.inline.} =
  result = ItemList(needsSeparator: false)

proc initPhraseList*(indent: bool): PhraseList {.inline.} =
  result = PhraseList(needsSeparator: false, pendingIndent: indent)

template add*(list: var ItemList, format: RotGeneratorFormat, writer: var RotWriter, body: typed) =
  maybeSeparateItem(format, writer, list.needsSeparator)
  body

template associate*(list: var ItemList, format: RotGeneratorFormat, writer: var RotWriter, body: typed) =
  maybeAssociateItem(format, writer, list.needsSeparator)
  body

template add*(list: var PhraseList, format: RotGeneratorFormat, writer: var RotWriter, body: typed) =
  maybeSeparatePhrase(format, writer, list.needsSeparator)

template addClosedPhrase*(list: var ItemList, format: RotGeneratorFormat, writer: var RotWriter, body: typed) =
  writer.write '('
  list = initItemList()
  body
  writer.write ')'

template addClosedPhraseBlock*(list: var ItemList, format: RotGeneratorFormat, writer: var RotWriter, body: typed) =
  writer.write '['
  list = initItemList()
  body
  writer.write ']'

template addOpenPhrase*(list: var ItemList, format: RotGeneratorFormat, writer: var RotWriter, body: typed) =
  list = initItemList()
  body

template addClosedBlock*(list: var PhraseList, format: RotGeneratorFormat, writer: var RotWriter, body: typed) =
  writer.write '{'
  list = initPhraseList(indent = format.indentBlocks)
  body
  if list.needsSeparator and format.betweenPhrases in {Newline, SemicolonNewline}:
    if list.pendingIndent:
      writer.removeIndent()
    writer.write '\n'
  writer.write '}'

template addOpenBlock*(list: var PhraseList, format: RotGeneratorFormat, writer: var RotWriter, body: typed) =
  list = initPhraseList(indent = false)
  body
