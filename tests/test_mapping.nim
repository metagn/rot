import rot, rot/[mapping, generator], std/math

proc echoMaps[T](val: T) {.used.} =
  let repr = toRotTerm(val)
  let ser = prettyPrintUnwrap(repr)
  echo ser

proc maps[T](val: T, expected: string) =
  let repr = toRotTerm(val)
  let ser = prettyPrintUnwrap(repr)
  doAssert ser == expected
  let deser = parseRotTerm(ser)
  doAssert repr == deser
  let deserVal = fromRotTerm(T, deser)
  doAssert deserVal == val, $(deserVal, val)

type Basic = object
  a: int
  b: string
  c: float

block:
  maps Basic(a: 123, b: "abc", c: 4.56), "123 \"abc\" 4.56"

type
  Kind = enum
    k1, k2, k3, k4, k5, k6
  Nested = object
    a: string
    case kind: Kind
    of k1: b: int
    of k2..k4: c: seq[Nested]
    of k5: d: float
    of k6: e: bool

proc `==`(x, y: Nested): bool {.noSideEffect.} =
  result = x.a == y.a and x.kind == y.kind
  if result:
    case x.kind
    of k1: result = x.b == y.b
    of k2..k4: result = x.c == y.c
    of k5: result = (isNan(x.d) and isNan(y.d)) or x.d == y.d
    of k6: result = x.e == y.e

block:
  maps Nested(a: "abc", kind: k2, c: @[
    Nested(a: "def", kind: k3, c: @[
      Nested(a: "ghi", kind: k4, c: @[]),
      Nested(a: "jkl", kind: k5, d: NaN)]),
    Nested(a: "ghi", kind: k6, e: true)]), """"abc" k2 {
  "def" k3 {
    "ghi" k4 {}
    "jkl" k5 nan
  }
  "ghi" k6 true
}"""
