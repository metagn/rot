when (compiles do: import nimbleutils/bridge):
  import nimbleutils/bridge
else:
  import unittest

import rot, rot/reader, fleu/load_buffer, util, std/strutils

proc lineLoader(s: string): BufferLoader =
  when nimvm:
    var lines = splitLines(s, keepEol = true)
    var i = 0
    result = proc(): string =
      if i < lines.len:
        result = lines[i]
        inc i
      else:
        result = ""
  else:
    let iter = iterator (): string =
      for line in splitLines(s, keepEol = true):
        yield line
    result = proc(): string =
      result = iter()

let s = """
a = "b"
c = {
d= "e";

f   ="g"

}; h =

"i"
j = "k"
"""
let format = DefaultRotFormat

test "line stream":
  var reader = initRotReader(lineLoader(s))
  var blockState = initBlockState(FreeContext)
  var phrases: seq[RotPhrase] = @[]
  var phrase: RotPhrase
  check format.findPhrase(reader, blockState)
  phrase = format.parsePhrase(reader, blockState)
  check phrase == p(s"a", a t"b").phrase
  phrases.add phrase
  check format.findPhrase(reader, blockState)
  phrase = format.parsePhrase(reader, blockState)
  check phrase == p(s"c", a b(
    p(s"d", a t"e"),
    p(s"f", a t"g")
  )).phrase
  phrases.add phrase
  check format.findPhrase(reader, blockState)
  phrase = format.parsePhrase(reader, blockState)
  check phrase == p(s"h", a t"i").phrase
  phrases.add phrase
  check format.findPhrase(reader, blockState)
  phrase = format.parsePhrase(reader, blockState)
  check phrase == p(s"j", a t"k").phrase
  phrases.add phrase
  check not format.findPhrase(reader, blockState)

  let fullParsed = parseRotBlock(s)
  check phrases == fullParsed.phrases

test "nested parsing":
  var reader = initRotReader(lineLoader(s))
  var top = startBlock()
  # first phrase:
  check format.findPart(reader, top)
  var p1 = format.startPart(reader, top)
  check format.findPart(reader, p1)
  var item = format.parsePart(reader, p1)
  check item == toItem s"a"
  check format.findPart(reader, p1)
  item = format.parsePart(reader, p1)
  check item == toItem a t"b"
  check not format.findPart(reader, p1)
  format.finishPart(reader, top, p1)
  # second phrase:
  check format.findPart(reader, top)
  p1 = format.startPart(reader, top)
  check format.findPart(reader, p1)
  item = format.parsePart(reader, p1)
  check item == toItem s"c"
  # second phrase block:
  check format.findPart(reader, p1)
  var i1 = format.startPart(reader, p1)
  check i1.associated
  check i1.term.kind == Block
  # first phrase of second phrase block:
  check format.findPart(reader, i1.term.block)
  var p2 = format.startPart(reader, i1.term.block)
  check format.findPart(reader, p2)
  item = format.parsePart(reader, p2)
  check item == toItem s"d"
  check format.findPart(reader, p2)
  item = format.parsePart(reader, p2)
  check item == toItem a t"e"
  check not format.findPart(reader, p2)
  format.finishPart(reader, i1.term.block, p2)
  # second phrase of second phrase block:
  check format.findPart(reader, i1.term.block)
  p2 = format.startPart(reader, i1.term.block)
  check format.findPart(reader, p2)
  item = format.parsePart(reader, p2)
  check item == toItem s"f"
  check format.findPart(reader, p2)
  item = format.parsePart(reader, p2)
  check item == toItem a t"g"
  check not format.findPart(reader, p2)
  format.finishPart(reader, i1.term.block, p2)
  # end of second phrase block:
  check not format.findPart(reader, i1.term.block)
  format.finishPart(reader, p1, i1)
  # third phrase:
  check format.findPart(reader, top)
  p1 = format.startPart(reader, top)
  check format.findPart(reader, p1)
  item = format.parsePart(reader, p1)
  check item == toItem s"h"
  check format.findPart(reader, p1)
  item = format.parsePart(reader, p1)
  check item == toItem a t"i"
  check not format.findPart(reader, p1)
  format.finishPart(reader, top, p1)
  # fourth phrase:
  check format.findPart(reader, top)
  p1 = format.startPart(reader, top)
  check format.findPart(reader, p1)
  item = format.parsePart(reader, p1)
  check item == toItem s"j"
  check format.findPart(reader, p1)
  item = format.parsePart(reader, p1)
  check item == toItem a t"k"
  check not format.findPart(reader, p1)
  format.finishPart(reader, top, p1)
  # end:
  check not format.findPart(reader, top)
