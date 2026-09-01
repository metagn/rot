import fleu/load_buffer, std/strutils

type
  RotReader* = object
    done*: bool
    buffer*: LoadBuffer
    pos*, previousPos: int
    filename*: string
    line*, column*: int
    previousCol: int
    current*: char
    recordLineIndent*: bool
    currentLineIndent*: int

proc resetReader*(reader: var RotReader) =
  reader.done = false
  reader.pos = 0
  reader.line = 1
  reader.column = 0
  reader.previousPos = -1
  reader.previousCol = -1
  reader.recordLineIndent = false
  reader.currentLineIndent = 0

proc initRotReader*(str: sink string = "", filename = ""): RotReader =
  result = RotReader(buffer: initLoadBuffer(str), filename: filename)
  resetReader(result)

proc initRotReader*(loader: LoadBuffer, filename = ""): RotReader =
  result = RotReader(buffer: loader, filename: filename)
  resetReader(result)

proc loadBufferOne(reader: var RotReader) =
  let remove = reader.buffer.loadOnce()
  reader.pos -= remove
  reader.previousPos -= remove

proc loadBufferBy(reader: var RotReader, n: int) =
  let remove = reader.buffer.loadBy(n)
  reader.pos -= remove
  reader.previousPos -= remove

proc peekCharOrZero*(reader: var RotReader): char =
  if reader.pos < reader.buffer.data.len:
    result = reader.buffer.data[reader.pos]
  else:
    reader.loadBufferOne()
    if reader.pos < reader.buffer.data.len:
      result = reader.buffer.data[reader.pos]
    else:
      result = '\0'

proc peekChar*(reader: var RotReader, c: var char): bool =
  if reader.pos < reader.buffer.data.len:
    c = reader.buffer.data[reader.pos]
    result = true
  else:
    reader.loadBufferOne()
    if reader.pos < reader.buffer.data.len:
      c = reader.buffer.data[reader.pos]
      result = true
    else:
      result = false

# finite lookahead:

proc peekStr*(reader: var RotReader, len: int, offset = 0): string =
  let minLen = reader.pos + offset + len
  let missingChars = minLen - reader.buffer.data.len
  if missingChars <= 0:
    result = reader.buffer.data[reader.pos + offset ..< minLen]
  else:
    reader.loadBufferBy(missingChars)
    if minLen <= reader.buffer.data.len:
      result = reader.buffer.data[reader.pos + offset ..< minLen]
    else:
      # only available chars
      result = reader.buffer.data[reader.pos + offset ..< reader.buffer.data.len]

proc peekStr*(reader: var RotReader, s: openArray[char], offset = 0): bool =
  let minLen = reader.pos + offset + s.len
  let missingChars = minLen - reader.buffer.data.len
  if missingChars <= 0:
    result = s == reader.buffer.data.toOpenArray(reader.pos + offset, minLen - 1)
  else:
    reader.loadBufferBy(missingChars)
    if minLen <= reader.buffer.data.len:
      result = s == reader.buffer.data.toOpenArray(reader.pos + offset, minLen - 1)
    else:
      result = false

proc resetPos*(reader: var RotReader) =
  assert reader.previousPos != -1, "no previous position to reset to"
  reader.pos = reader.previousPos
  reader.previousPos = -1
  reader.column = reader.previousCol
  if reader.current == '\n':
    dec reader.line

proc nextChar*(reader: var RotReader): bool =
  ## updates line and column considering \r\n, tracks indent
  reader.previousPos = reader.pos
  reader.previousCol = reader.column
  let c =
    if reader.pos < reader.buffer.data.len:
      reader.buffer.data[reader.pos]
    else:
      reader.loadBufferOne()
      if reader.pos < reader.buffer.data.len:
        reader.buffer.data[reader.pos]
      else:
        reader.done = true
        return false
  reader.current = c
  inc reader.pos
  if reader.current == '\n' or
      (reader.current == '\r' and (inc reader.pos;
        reader.peekCharOrZero() != '\n' and
          (dec reader.pos; true))):
    reader.recordLineIndent = true
    reader.currentLineIndent = 0
    reader.line += 1
    reader.column = 0
  else:
    if reader.recordLineIndent:
      if reader.current in Whitespace:
        inc reader.currentLineIndent
      else:
        reader.recordLineIndent = false
    reader.column += 1
  #let saved =
  #  if reader.peekStart >= 0: reader.peekStart
  #  else: reader.previousPos
  reader.buffer.freeBefore = reader.previousPos
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
      yield reader.current
  else:
    while true:
      yield reader.current
      if not reader.nextChar():
        break
