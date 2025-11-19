when (compiles do: import nimbleutils/bridge):
  import nimbleutils/bridge
else:
  import unittest

import rot, rot/parser, util, std/strutils

proc lineLoader(s: string): proc(): string =
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
  var parser = initRotParser(lineLoader(s))
  var phrases: seq[RotPhrase] = @[]
  var phrase = RotPhrase()
  check parser.nextPhrase(phrase)
  check phrase == p(a(s"a", t"b")).phrase
  phrases.add phrase
  check parser.nextPhrase(phrase)
  check phrase == p(a(s"c", b(
    a(s"d", t"e"),
    a(s"f", t"g")
  ))).phrase
  phrases.add phrase
  check parser.nextPhrase(phrase)
  check phrase == p(a(s"h", t"i")).phrase
  phrases.add phrase
  check parser.nextPhrase(phrase)
  check phrase == p(a(s"j", t"k")).phrase
  phrases.add phrase
  check not parser.nextPhrase(phrase)

  let fullParsed = parseRot(s)
  check phrases == fullParsed.items
