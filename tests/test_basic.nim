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

test "colon syntax string":
  let tests = {
    """
abc: def ghi
jkl : mno pqr stu
vwx := yza bcd
efg = "hij klm"
""": b(
      p(s"abc", t"def ghi"),
      p(s"jkl", t"mno pqr stu"),
      p(a(s"vwx", t"yza bcd")),
      p(a(s"efg", t"hij klm"))),
    """
abc:
  def ghi
  jkl mno
    pqr stu
vwx:
  yza bcd
    efg hij
      klm nop
  qrs tuv
wxy :=
  zab cde""": b(
      p(s"abc", t"""
def ghi
jkl mno
  pqr stu"""),
      p(s"vwx", t"""
yza bcd
  efg hij
    klm nop
qrs tuv"""),
      p(a(s"wxy", t"zab cde"))),
    """
abc:
  def ghi
  jkl mno
    pqr stu

vwx:
  yza bcd
    efg hij
      klm nop
  qrs tuv

wxy :=
  zab cde
""": b(
      p(s"abc", t"""
def ghi
jkl mno
  pqr stu"""),
      p(s"vwx", t"""
yza bcd
  efg hij
    klm nop
qrs tuv"""),
      p(a(s"wxy", t"zab cde"))),
  }

  match tests

test "colon syntax block":
  let tests = {
    """
abc:: def ghi
jkl :: mno pqr stu; and another; and yet another
vwx ::= yza bcd
efg = {hij klm}
""": b(
      p(s"abc", b(p(s"def", s"ghi"))),
      p(s"jkl", b(
        p(s"mno", s"pqr", s"stu"),
        p(s"and", s"another"),
        p(s"and", s"yet", s"another"))),
      p(a(s"vwx", b(p(s"yza", s"bcd")))),
      p(a(s"efg", b(p(s"hij", s"klm"))))),
    """
abc::
  def ghi
  jkl mno ::
    pqr stu ::
vwx ::
  yza bcd ::
    efg hij ::
      klm nop ::
  qrs tuv
wxy ::=
  zab cde ::""": b(
      p(s"abc", b(
        p(s"def", s"ghi"),
        p(s"jkl", s"mno", b(
          p(s"pqr", s"stu", b()))))),
      p(s"vwx", b(
        p(s"yza", s"bcd", b(
          p(s"efg", s"hij", b(
            p(s"klm", s"nop", b()))))),
        p(s"qrs", s"tuv"))),
      p(a(s"wxy", b(p(s"zab", s"cde", b()))))),
    """
abc::
  def ghi
  jkl mno ::

    pqr stu ::

vwx ::
  yza bcd ::

    efg hij ::
      klm nop ::
  qrs tuv

wxy ::=

  zab cde ::""": b(
      p(s"abc", b(
        p(s"def", s"ghi"),
        p(s"jkl", s"mno", b(
          p(s"pqr", s"stu", b()))))),
      p(s"vwx", b(
        p(s"yza", s"bcd", b(
          p(s"efg", s"hij", b(
            p(s"klm", s"nop", b()))))),
        p(s"qrs", s"tuv"))),
      p(a(s"wxy", b(p(s"zab", s"cde", b()))))),
  }

  match tests

test "bracket syntax":
  match "a = [123, 456 789, abc = \"def\" ghi]",
    b(p(a(s"a", b(
      p(s"123"),
      p(s"456"),
      p(s"789"),
      p(a(s"abc", t"def")),
      p(s"ghi")))))
