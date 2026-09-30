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
let format = DefaultRot

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
  check top.findPhrase(format, reader)
  var p1 = top.startPhrase(format, reader)
  check p1.findItem(format, reader)
  var item = p1.parseItem(format, reader)
  check item == toItem s"a"
  check p1.findItem(format, reader)
  item = p1.parseItem(format, reader)
  check item == toItem a t"b"
  check not p1.findItem(format, reader)
  top.finishPhrase(p1, format, reader)
  # second phrase:
  check top.findPhrase(format, reader)
  p1 = top.startPhrase(format, reader)
  check p1.findItem(format, reader)
  item = p1.parseItem(format, reader)
  check item == toItem s"c"
  # second phrase block:
  check p1.findItem(format, reader)
  var i1 = p1.startItem(format, reader)
  check i1.associated
  check i1.term.kind == Block
  # first phrase of second phrase block:
  check i1.term.block.findPhrase(format, reader)
  var p2 = i1.term.block.startPhrase(format, reader)
  check p2.findItem(format, reader)
  item = p2.parseItem(format, reader)
  check item == toItem s"d"
  check p2.findItem(format, reader)
  item = p2.parseItem(format, reader)
  check item == toItem a t"e"
  check not p2.findItem(format, reader)
  i1.term.block.finishPhrase(p2, format, reader)
  # second phrase of second phrase block:
  check i1.term.block.findPhrase(format, reader)
  p2 = i1.term.block.startPhrase(format, reader)
  check p2.findItem(format, reader)
  item = p2.parseItem(format, reader)
  check item == toItem s"f"
  check p2.findItem(format, reader)
  item = p2.parseItem(format, reader)
  check item == toItem a t"g"
  check not p2.findItem(format, reader)
  i1.term.block.finishPhrase(p2, format, reader)
  # end of second phrase block:
  check not i1.term.block.findPhrase(format, reader)
  p1.finishItem(i1, format, reader)
  # third phrase:
  check top.findPhrase(format, reader)
  p1 = top.startPhrase(format, reader)
  check p1.findItem(format, reader)
  item = p1.parseItem(format, reader)
  check item == toItem s"h"
  # use findAssociation this time:
  check p1.findAssociation(format, reader)
  item = p1.parseItem(format, reader)
  check item == toItem a t"i"
  check not p1.findItem(format, reader)
  top.finishPhrase(p1, format, reader)
  # fourth phrase:
  check top.findPhrase(format, reader)
  p1 = top.startPhrase(format, reader)
  check p1.findItem(format, reader)
  item = p1.parseItem(format, reader)
  check item == toItem s"j"
  # and this time:
  check p1.findAssociation(format, reader)
  item = p1.parseItem(format, reader)
  check item == toItem a t"k"
  check not p1.findItem(format, reader)
  top.finishPhrase(p1, format, reader)
  # end:
  check not top.findPhrase(format, reader)
