when (compiles do: import nimbleutils/bridge):
  import nimbleutils/bridge
else:
  import unittest

import rot, util

var allTests: seq[(string, RotTerm)] = @[]

template doMatch(tests: openArray[(string, RotTerm)]) =
  match tests
  allTests.add tests

let basicTests = {
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

test "block equivalents":
  for (s, b) in basicTests.items:
    checkpoint s
    let parsed = parseRot(s)
    let a = RotTerm(kind: Block, `block`: parsed)
    check a == b
  allTests.add basicTests

let colonStringTests = {
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
  """
a:
  b c
  
# whitespace up to indentation level above
""": b(p(s"a", t("b c\n"))),
}

test "colon syntax string":
  doMatch colonStringTests

let colonBlockTests = {
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

test "colon syntax block":
  doMatch colonBlockTests

let bracketTests = {
  "a = [123, 456 789, abc = \"def\" ghi]": b(p(a(s"a", b(
    p(s"123"),
    p(s"456"),
    p(s"789"),
    p(a(s"abc", t"def")),
    p(s"ghi")))))
}

test "bracket syntax":
  doMatch bracketTests

let pipePhraseTests = {
  """
abc | def ghi
jkl | mno pqr stu, and another,
and yet another
vwx |= yza bcd
efg = (hij klm)
""": b(
    p(s"abc", p(s"def", s"ghi")),
    p(s"jkl", p(
      s"mno", s"pqr", s"stu",
      s"and", s"another",
      s"and", s"yet", s"another")),
    p(a(s"vwx", p(s"yza", s"bcd"))),
    p(a(s"efg", p(s"hij", s"klm")))),
  """
abc |
  def ghi
  jkl mno |
    pqr stu
vwx |
  yza bcd |
    efg, hij |
      klm nop
    |
      second
      phrase
  qrs tuv
wxy |=
  zab cde""": b(
    p(s"abc", p(
      s"def", s"ghi",
      s"jkl", s"mno", p(
        s"pqr", s"stu"))),
    p(s"vwx", p(
      s"yza", s"bcd", p(
        s"efg", s"hij", p(
          s"klm", s"nop"),
        p(s"second", s"phrase")),
      s"qrs", s"tuv")),
    p(a(s"wxy", p(s"zab", s"cde")))),
  """
abc |
  def ghi
  jkl mno |

    pqr stu

vwx |
  yza bcd |

    efg, hij |
      klm nop
    |
      second
      phrase
  qrs tuv

wxy |=

  zab cde""": b(
    p(s"abc", p(
      s"def", s"ghi",
      s"jkl", s"mno", p(
        s"pqr", s"stu"))),
    p(s"vwx", p(
      s"yza", s"bcd", p(
        s"efg", s"hij", p(
          s"klm", s"nop"),
        p(s"second", s"phrase")),
      s"qrs", s"tuv")),
    p(a(s"wxy", p(s"zab", s"cde")))),
}

test "pipe syntax single phrase":
  doMatch pipePhraseTests

let pipeBlockTests = {
  """
abc || def ghi
jkl || mno pqr stu, and another,
and yet another
vwx ||= yza bcd
efg = [hij klm]
""": b(
    p(s"abc", b(p(s"def"), p(s"ghi"))),
    p(s"jkl", b(
      p s"mno", p s"pqr", p s"stu",
      p s"and", p s"another",
      p s"and", p s"yet", p s"another")),
    p(a(s"vwx", b(p s"yza", p s"bcd"))),
    p(a(s"efg", b(p s"hij", p s"klm")))),
  """
abc ||
  def ghi
  jkl mno ||
    pqr stu
vwx ||
  yza bcd ||
    efg, hij ||
      klm nop
    ||
      second
      phrase
  qrs tuv
wxy ||=
  zab cde""": b(
    p(s"abc", b(
      p s"def", p s"ghi",
      p s"jkl", p s"mno", p b(
        p s"pqr", p s"stu"))),
    p(s"vwx", b(
      p s"yza", p s"bcd", p b(
        p s"efg", p s"hij", b(
          p s"klm", p s"nop"),
        b(p s"second", p s"phrase")),
      p s"qrs", p s"tuv")),
    p(a(s"wxy", b(p s"zab", p s"cde")))),
  """
abc ||
  def ghi
  jkl mno ||

    pqr stu

vwx ||
  yza bcd ||

    efg, hij ||
      klm nop
    ||
      second
      phrase
  qrs tuv

wxy ||=

  zab cde""": b(
    p(s"abc", b(
      p s"def", p s"ghi",
      p s"jkl", p s"mno", p b(
        p s"pqr", p s"stu"))),
    p(s"vwx", b(
      p s"yza", p s"bcd", p b(
        p s"efg", p s"hij", b(
          p s"klm", p s"nop"),
        b(p s"second", p s"phrase")),
      p s"qrs", p s"tuv")),
    p(a(s"wxy", b(p s"zab", p s"cde")))),
}

test "pipe syntax block":
  doMatch pipeBlockTests

let commentTests = {
  """abc # def
ghi :: # jkl
    # mnop
  qrs tuv # wxy
# zab
  cde fgh
    # ijk
lmn # op
still: in # strings
"in # strings"
`in # strings`
""": b(
    p(s"abc"),
    p(s"ghi", b(
      p(s"qrs", s"tuv"),
      p(s"cde", s"fgh"))),
    p(s"lmn"),
    p(s"still", t"in # strings"),
    p(t"in # strings"),
    p(s"in # strings"))
}

test "comments":
  doMatch commentTests

let specTests = {
  # strings:
  """
"abc"
"abc def"
"abc def
ghi jkl" # => abc def<newline>ghi jkl
"abc "" def" # => abc " def
""" & "\n\"\"\"abc def\"\"\" # => \"abc def\"": b(
    p(t"abc"),
    p(t"abc def"),
    p(t("abc def\nghi jkl")),
    p(t"abc "" def"),
    p(t("\"abc def\""))),
  # symbols:
  """
abc
abc123
123abc
123
123.456
`abc def`
`abc `` def
ghi jkl`
""": b(
    p(s"abc"),
    p(s"abc123"),
    p(s"123abc"),
    p(s"123"),
    p(s"123.456"),
    p(s"abc def"),
    p(s("abc ` def\nghi jkl"))),
  # phrases:
  """
abc "def ghi" jkl
abc, "def ghi", jkl
abc "def ghi",jkl
abc,"def ghi" jkl
abc,
"def ghi",

jkl
a, (b, "c d",
  e), f""": b(
    p(s"abc", t"def ghi", s"jkl"),
    p(s"abc", t"def ghi", s"jkl"),
    p(s"abc", t"def ghi", s"jkl"),
    p(s"abc", t"def ghi", s"jkl"),
    p(s"abc", t"def ghi", s"jkl"),
    p(s"a", p(s"b", t"c d", s"e"), s"f")),
  # associations:
  """
abc = "def", ghi = (jkl, mnop)
""": b(p(a(s"abc", t"def"), a(s"ghi", p(s"jkl", s"mnop")))),
  # blocks:
  """
abc "def" # phrase (abc, "def")
ghi = "jkl" # phrase (ghi = "jkl")
"mnop" # phrase ("mnop")
abc "def" {
  ghi = {"jkl"; "mnop"}
  "qrs tuv"
}
""": b(
    p(s"abc", t"def"),
    p(a(s"ghi", t"jkl")),
    p(t"mnop"),
    p(s"abc", t"def", b(
      p(a(s"ghi", b(p(t"jkl"), p(t"mnop")))),
      p(t"qrs tuv"))))
}

test "spec":
  doMatch specTests

let specAdditionalSyntaxTests = {
  # comments
  """
# comment
abc = "def" # comment
"this is # not a comment"
""": b(p(a(s"abc", t"def")), p(t"this is # not a comment")),
    """
abc: def ghi
abc:
  def ghi
    jkl mno

      pqr stu
    
  vwx

"break indent"

  abc:
def:
   ghi:
  jkl:

abc ::
  def ghi ::
    jkl mno ::

      pqr stu ::
    
  vwx

a :=
  b c
  d

a ::=
  b c
  d
""": b(
    p(s"abc", t"def ghi"),
    p(s"abc", t"""def ghi
  jkl mno

    pqr stu
  
vwx"""),
    p(t"break indent"),
    p(s"abc", t""),
    p(s"def", t"ghi:"),
    p(s"jkl", t""),
    p(s"abc", b(
      p(s"def", s"ghi", b(
        p(s"jkl", s"mno", b(
          p(s"pqr", s"stu", b())
        ))
      )),
      p(s"vwx")
    )),
    p(a(s"a", t("b c\nd"))),
    p(a(s"a", b(p(s"b", s"c"), p(s"d"))))
  ),
  # brackets:
  """abc = [def, "ghi jkl" mnop
, (nested "phrase")]""": b(p(a(s"abc", b(p(s"def"), p(t"ghi jkl"), p(s"mnop"), p(p(s"nested", t"phrase")))))),
  # pipes:
  """abc | def, "ghi jkl" mnop
abc |
  def, "ghi jkl"
    mnop
  (nested "phrase")""": b(
    p(s"abc", p(s"def", t"ghi jkl", s"mnop")),
    p(s"abc", p(s"def", t"ghi jkl", s"mnop", p(s"nested", t"phrase"))),
    ),
  """abc || def, "ghi jkl" mnop
abc ||
  def, "ghi jkl"
    mnop
  (nested "phrase")""": b(
    p(s"abc", b(p s"def", p t"ghi jkl", p s"mnop")),
    p(s"abc", b(p s"def", p t"ghi jkl", p s"mnop", p p(s"nested", t"phrase")))),
  """abc |
  def |=
    ghi ||
      jkl
  mno: qrs
  tuv :: wxyz""": b(p(s"abc", p(a(s"def", p(s"ghi", b(p s"jkl"))), s"mno", t"qrs", s"tuv", b(p(s"wxyz")))))
}

test "spec additional syntax":
  doMatch specAdditionalSyntaxTests

test "ugly print equivalence":
  for a, b in allTests.items:
    checkpoint a
    let parsed = parseRot(a)
    let uglyPrinted = uglyPrint(RotTerm(kind: Block, `block`: parsed))
    checkpoint uglyPrinted
    let parsedAgain = parseRot(uglyPrinted)
    check parsedAgain.items.len == 1
    check parsedAgain.items[0].items.len == 1
    check parsedAgain.items[0].items[0].kind == Block
    check parsedAgain.items[0].items[0].block == parsed
