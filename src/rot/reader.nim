import fleu/load_buffer, std/[strutils, streams]

const rotDisableLineColumn* {.booldefine.} = false
  ## disables line/column tracking, lowers reader size but shouldn't affect speed otherwise

# maybe disable indents too but at that point might as well write a separate parser

type
  RotReadState* = object
    pos*: int
    done*: bool
    recordLineIndent*: bool
    when not rotDisableLineColumn:
      line*, column*: int32
    currentLineIndent*: int32
  RotReader* = object
    buffer*: LoadBuffer
    bufferLocks*: int
    state*: RotReadState
    filename*: string

proc initReadState*(): RotReadState {.inline.} =
  result = RotReadState(done: false,
    pos: 0,
    recordLineIndent: false,
    currentLineIndent: 0)
  when not rotDisableLineColumn:
    result.line = 1
    result.column = 0

proc saveState*(reader: var RotReader): RotReadState {.inline.} =
  result = reader.state
  inc reader.bufferLocks

proc releaseState*(reader: var RotReader, state: sink RotReadState) {.inline.} =
  dec reader.bufferLocks

proc restoreState*(reader: var RotReader, state: sink RotReadState) {.inline.} =
  reader.state = state
  dec reader.bufferLocks

proc resetReader*(reader: var RotReader) {.inline.} =
  reader.state = initReadState()

proc initRotReader*(str: sink string = "", filename = ""): RotReader =
  result = RotReader(buffer: initLoadBuffer(str), filename: filename)
  resetReader(result)

proc initRotReader*(loader: LoadBuffer, filename = ""): RotReader =
  result = RotReader(buffer: loader, filename: filename)
  resetReader(result)

proc initRotReader*(loader: BufferLoader, bufferCapacity = 32, filename = ""): RotReader =
  result = RotReader(buffer: initLoadBuffer(loader), filename: filename)
  resetReader(result)

proc initRotReader*(stream: Stream, loadAmount = 16, bufferCapacity = 32, filename = ""): RotReader =
  result = RotReader(buffer: initLoadbuffer(stream, loadAmount, bufferCapacity), filename: filename)
  resetReader(result)

when declared(File):
  proc initRotReader*(file: File, loadAmount = 16, bufferCapacity = 32, filename = ""): RotReader =
    result = RotReader(buffer: initLoadBuffer(file, loadAmount, bufferCapacity), filename: filename)
    resetReader(result)

{.push checks: off, stacktrace: off.}

proc loadBufferOne(reader: var RotReader) {.inline.} =
  let remove = reader.buffer.loadOnce()
  reader.state.pos -= remove

proc loadBufferBy(reader: var RotReader, n: int) {.inline.} =
  let remove = reader.buffer.loadBy(n)
  reader.state.pos -= remove

proc peekCharOrZero*(reader: var RotReader): char {.inline.} =
  if reader.state.pos < reader.buffer.data.len:
    result = reader.buffer.data[reader.state.pos]
  else:
    reader.loadBufferOne()
    if reader.state.pos < reader.buffer.data.len:
      result = reader.buffer.data[reader.state.pos]
    else:
      result = '\0'

proc peekChar*(reader: var RotReader, c: var char): bool {.inline.} =
  if reader.state.pos < reader.buffer.data.len:
    c = reader.buffer.data[reader.state.pos]
    result = true
  else:
    reader.loadBufferOne()
    if reader.state.pos < reader.buffer.data.len:
      c = reader.buffer.data[reader.state.pos]
      result = true
    else:
      result = false

# finite lookahead:

proc peekStr*(reader: var RotReader, len: int, offset = 0): string =
  let minLen = reader.state.pos + offset + len
  let missingChars = minLen - reader.buffer.data.len
  if missingChars <= 0:
    result = reader.buffer.data[reader.state.pos + offset ..< minLen]
  else:
    reader.loadBufferBy(missingChars)
    if minLen <= reader.buffer.data.len:
      result = reader.buffer.data[reader.state.pos + offset ..< minLen]
    else:
      # only available chars
      result = reader.buffer.data[reader.state.pos + offset ..< reader.buffer.data.len]

proc peekMatch*(reader: var RotReader, s: openArray[char], offset = 0): bool =
  let minLen = reader.state.pos + offset + s.len
  let missingChars = minLen - reader.buffer.data.len
  if missingChars <= 0:
    result = s == reader.buffer.data.toOpenArray(reader.state.pos + offset, minLen - 1)
  else:
    reader.loadBufferBy(missingChars)
    if minLen <= reader.buffer.data.len:
      result = s == reader.buffer.data.toOpenArray(reader.state.pos + offset, minLen - 1)
    else:
      result = false

proc peekMatch*(reader: var RotReader, c: char, offset = 0): bool =
  let pos = reader.state.pos + offset
  if pos < reader.buffer.data.len:
    result = c == reader.buffer.data[pos]
  else:
    reader.loadBufferBy(offset + 1)
    if pos < reader.buffer.data.len:
      result = c == reader.buffer.data[pos]
    else:
      result = false

proc advance(reader: var RotReader, c: char) =
  ## updates line and column considering \r\n, tracks indent
  let prevPos = reader.state.pos
  inc reader.state.pos
  if c == '\n' or
      (c == '\r' and (inc reader.state.pos;
        reader.peekCharOrZero() != '\n' and
          (dec reader.state.pos; true))):
    reader.state.recordLineIndent = true
    reader.state.currentLineIndent = 0
    when not rotDisableLineColumn:
      reader.state.line += 1
      reader.state.column = 0
  else:
    if reader.state.recordLineIndent:
      if c in Whitespace:
        inc reader.state.currentLineIndent
      else:
        reader.state.recordLineIndent = false
    when not rotDisableLineColumn:
      reader.state.column += 1
  if reader.bufferLocks == 0:
    reader.buffer.freeBefore = prevPos

proc advance*(reader: var RotReader) {.inline.} =
  var c: char
  let worked = peekChar(reader, c)
  assert worked
  advance(reader, c)

proc nextChar*(reader: var RotReader, c: var char): bool {.inline.} =
  ## updates line and column considering \r\n, tracks indent
  c =
    if reader.state.pos < reader.buffer.data.len:
      reader.buffer.data[reader.state.pos]
    else:
      reader.loadBufferOne()
      if reader.state.pos < reader.buffer.data.len:
        reader.buffer.data[reader.state.pos]
      else:
        reader.state.done = true
        return false
  advance(reader, c)
  result = true

proc nextChar*(reader: var RotReader): bool {.inline.} =
  var c: char
  result = nextChar(reader, c)

proc nextMatch*(reader: var RotReader, s: openArray[char], offset = 0): bool {.inline.} =
  result = reader.peekMatch(s, offset)
  if result:
    for _ in 0 ..< s.len: reader.advance()

iterator rawChars*(reader: var RotReader): char =
  var c: char
  while reader.peekChar(c):
    yield c
    reader.advance(c)

{.pop.}
