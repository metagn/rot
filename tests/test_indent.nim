when (compiles do: import nimbleutils/bridge):
  import nimbleutils/bridge
else:
  import unittest

import rot, util

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

  for (s, b) in tests.items:
    checkpoint s
    let parsed = parseRot(s)
    let a = Rot(kind: Block, `block`: parsed)
    check a == b

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

  for (s, b) in tests.items:
    checkpoint s
    let parsed = parseRot(s)
    let a = Rot(kind: Block, `block`: parsed)
    check a == b
