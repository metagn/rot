when (compiles do: import nimbleutils/bridge):
  import nimbleutils/bridge
else:
  import unittest

import rot, rot/reader, fleu/load_buffer, util, std/strutils

proc lineLoader(s: string): proc(): string =
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

test "line stream":
  let s = """
a = "b"
c = {
  d= "e";

  f   ="g"

  }; h =
  
  "i"
j = "k"
"""
  let format = defaultRotFormat()
  var reader = initRotReader(initLoadBuffer(lineLoader(s)))
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

  let fullParsed = parseRot(s)
  check phrases == fullParsed.items
