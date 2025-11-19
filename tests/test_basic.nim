when (compiles do: import nimbleutils/bridge):
  import nimbleutils/bridge
else:
  import unittest

import rot, util

test "block equivalents":
  let tests = {
    "": b(),
    "abc": b(s("abc")),
    "abc def": b(p(s"abc", s"def")),
    """
abc
def
""": b(p(s("abc")), p(s("def"))),
    """
abc
def ghi
""": b(p(s("abc")), p(s("def"), s("ghi"))),
    """
"abc"
def "ghi jkl" mno
"pqr""stu" "vwx"
""": b(
      p(t"abc"),
      p(s"def", t"ghi jkl", s"mno"),
      p(t("pqr\"stu"), t"vwx")),
    "\"abc\"def": b(p(t("abc"), s("def"))),
    "{}": b(b()),
    "{{}}": b(b(b())),
    "{}\n{}": b(b(), b()),
    "{{}}\n{{}}\n{{}}": b(b(b()), b(b()), b(b())),
    """
a = "b"
c = "d"
e = {f = "g"
h = "i"}
j = "k"
l = {
  m = {
    n = "o"
  }}
p = "q"
""": b(
      a(s"a", t"b"),
      a(s"c", t"d"),
      a(s"e", b(
        a(s"f", t"g"),
        a(s"h", t"i"))),
      a(s"j", t"k"),
      a(s"l", b(
        a(s"m", b(
          a(s"n", t"o"))))),
      a(s"p", t"q"))
  }

  for (s, b) in tests.items:
    checkpoint s
    let parsed = parseRot(s)
    let a = Rot(kind: Block, `block`: parsed)
    check a == b
