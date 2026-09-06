import fleu/load_buffer, std/strutils

type
  RotReadState* = object
    done*: bool
    pos*, previousPos: int
    line*, column*: int
    previousCol: int
    current*: char
    recordLineIndent*: bool
    currentLineIndent*: int
  RotReader* = object
    buffer*: LoadBuffer
    #bufferLocks*: int
    filename*: string
    state*: RotReadState

proc initReadState*(): RotReadState {.inline.} =
  RotReadState(done: false,
    pos: 0,
    line: 1,
    column: 0,
    previousPos: -1,
    previousCol: -1,
    recordLineIndent: false,
    currentLineIndent: 0)

when false:
  proc saveState*(reader: var RotReader): RotReadState {.inline.} =
    result = reader.state
    inc reader.bufferLocks

  proc releaseState*(reader: var RotReader) {.inline.} =
    dec reader.bufferLocks

  proc restoreState*(reader: var RotReader, state: RotReadState) {.inline.} =
    reader.state = state
    releaseState(reader)

proc resetReader*(reader: var RotReader) {.inline.} =
  reader.state = initReadState()

proc initRotReader*(str: sink string = "", filename = ""): RotReader =
  result = RotReader(buffer: initLoadBuffer(str), filename: filename)
  resetReader(result)

proc initRotReader*(loader: LoadBuffer, filename = ""): RotReader =
  result = RotReader(buffer: loader, filename: filename)
  resetReader(result)

proc loadBufferOne(reader: var RotReader) =
  let remove = reader.buffer.loadOnce()
  reader.state.pos -= remove
  reader.state.previousPos -= remove

proc loadBufferBy(reader: var RotReader, n: int) =
  let remove = reader.buffer.loadBy(n)
  reader.state.pos -= remove
  reader.state.previousPos -= remove

proc peekCharOrZero*(reader: var RotReader): char =
  if reader.state.pos < reader.buffer.data.len:
    result = reader.buffer.data[reader.state.pos]
  else:
    reader.loadBufferOne()
    if reader.state.pos < reader.buffer.data.len:
      result = reader.buffer.data[reader.state.pos]
    else:
      result = '\0'

proc peekChar*(reader: var RotReader, c: var char): bool =
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

proc peekStr*(reader: var RotReader, s: openArray[char], offset = 0): bool =
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

proc resetPos*(reader: var RotReader) =
  assert reader.state.previousPos != -1, "no previous position to reset to"
  reader.state.pos = reader.state.previousPos
  reader.state.previousPos = -1
  reader.state.column = reader.state.previousCol
  if reader.state.current == '\n':
    dec reader.state.line

proc nextChar*(reader: var RotReader): bool =
  ## updates line and column considering \r\n, tracks indent
  reader.state.previousPos = reader.state.pos
  reader.state.previousCol = reader.state.column
  let c =
    if reader.state.pos < reader.buffer.data.len:
      reader.buffer.data[reader.state.pos]
    else:
      reader.loadBufferOne()
      if reader.state.pos < reader.buffer.data.len:
        reader.buffer.data[reader.state.pos]
      else:
        reader.state.done = true
        return false
  reader.state.current = c
  inc reader.state.pos
  if reader.state.current == '\n' or
      (reader.state.current == '\r' and (inc reader.state.pos;
        reader.peekCharOrZero() != '\n' and
          (dec reader.state.pos; true))):
    reader.state.recordLineIndent = true
    reader.state.currentLineIndent = 0
    reader.state.line += 1
    reader.state.column = 0
  else:
    if reader.state.recordLineIndent:
      if reader.state.current in Whitespace:
        inc reader.state.currentLineIndent
      else:
        reader.state.recordLineIndent = false
    reader.state.column += 1
  #let saved =
  #  if reader.peekStart >= 0: reader.peekStart
  #  else: reader.state.previousPos
  #if reader.bufferLocks == 0:
  reader.buffer.freeBefore = reader.state.previousPos
  result = true

proc nextStr*(reader: var RotReader, s: openArray[char], offset = 0): bool {.inline.} =
  result = reader.peekStr(s, offset)
  if result:
    for _ in 0 ..< s.len:
      let moved = reader.nextChar()
      assert moved

iterator rawChars*(reader: var RotReader, skipFirst: static bool = true): char =
  when skipFirst:
    while reader.nextChar():
      yield reader.state.current
  else:
    while true:
      yield reader.state.current
      if not reader.nextChar():
        break
