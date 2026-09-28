## rudimentary mapping with nim data types, unfinished and unsafe

import ./data, std/[strutils, typetraits]

# XXX current structure is not streaming

type
  RotValueKind* = enum Scalar, Vector
  RotValue* = object
    case kind*: RotValueKind
    of Scalar: atom*: RotTerm
    of Vector: compound*: RotPhrase

proc scalar*(term: RotTerm): RotValue {.inline.} =
  RotValue(kind: Scalar, atom: term)

proc vector*(phrase: RotPhrase): RotValue {.inline.} =
  RotValue(kind: Vector, compound: phrase)

proc getScalar*(value: RotValue): RotTerm {.inline.} =
  case value.kind
  of Scalar: result = value.atom
  of Vector:
    if value.compound.hasTail:
      raise newException(ValueError, "expected scalar")
    result = value.compound.head

proc getVector*(value: RotValue): RotPhrase {.inline.} =
  case value.kind
  of Scalar:
    if value.atom.kind != Phrase:
      raise newException(ValueError, "expected vector")
    result = value.atom.phrase
  of Vector:
    result = value.compound

proc asTerm*(value: RotValue): RotTerm {.inline.} =
  case value.kind
  of Scalar: result = value.atom
  of Vector: result = asTerm(value.compound)

# for now no format argument

proc into*[T: SomeInteger](value: T, result: var RotValue) {.inline.} =
  result = scalar rotSymbol($value)

proc into*[T: SomeInteger](value: RotValue, result: var T) {.inline.} =
  let term = getScalar(value)
  if term.kind != Symbol:
    raise newException(ValueError, "expected symbol for integer")
  result = T(parseBiggestInt(term.symbol))

proc into*[T: SomeUnsignedInt](value: T, result: var RotValue) {.inline.} =
  result = scalar rotSymbol($value)

proc into*[T: SomeUnsignedInt](value: RotValue, result: var T) {.inline.} =
  let term = getScalar(value)
  if term.kind != Symbol:
    raise newException(ValueError, "expected symbol for unsigned integer")
  result = T(parseBiggestUInt(term.symbol))

proc into*[T: SomeFloat](value: T, result: var RotValue) {.inline.} =
  result = scalar rotSymbol($value)

proc into*[T: SomeFloat](value: RotValue, result: var T) {.inline.} =
  let term = getScalar(value)
  if term.kind != Symbol:
    raise newException(ValueError, "expected symbol for float")
  result = T(parseFloat(term.symbol))

proc into*[T: enum](value: T, result: var RotValue) {.inline.} =
  result = scalar rotSymbol($value)

proc into*[T: enum](value: RotValue, result: var T) {.inline.} =
  let term = getScalar(value)
  if term.kind != Symbol:
    raise newException(ValueError, "expected symbol for enum")
  result = parseEnum[T](term.symbol)

proc into*[T: bool](value: T, result: var RotValue) {.inline.} =
  result = scalar rotSymbol($value)

proc into*[T: bool](value: RotValue, result: var T) {.inline.} =
  let term = getScalar(value)
  if term.kind != Symbol:
    raise newException(ValueError, "expected symbol for bool")
  result = parseBool(term.symbol)

proc into*(value: char, result: var RotValue) {.inline.} =
  result = scalar rotText($value)

proc into*(value: RotValue, result: var char) {.inline.} =
  let term = getScalar(value)
  if term.kind != Text:
    raise newException(ValueError, "expected text for char")
  if term.text.len != 1:
    raise newException(ValueError, "expected single character for char")
  result = term.text[0]

proc into*(value: string, result: var RotValue) {.inline.} =
  result = scalar rotText(value)

proc into*(value: RotValue, result: var string) {.inline.} =
  let term = getScalar(value)
  if term.kind != Text:
    raise newException(ValueError, "expected text for string")
  result = term.text

proc into*(value: cstring, result: var RotValue) {.inline.} =
  result = scalar rotText($value)

proc into*(value: RotValue, result: var cstring) {.inline.} =
  let term = getScalar(value)
  case term.kind
  of Text:
    result = cstring(term.text)
  of Symbol:
    if term.symbol == "nil":
      result = nil
    else:
      raise newException(ValueError, "expected cstring")
  else:
    raise newException(ValueError, "expected cstring")

proc into*[T](value: openArray[T], result: var RotValue) {.gcsafe.}
proc into*[T](value: RotValue, result: var seq[T]) {.gcsafe.}
proc into*[I, T](value: RotValue, result: var array[I, T]) {.gcsafe.}
proc into*[T: tuple](value: T, result: var RotValue) {.inline, gcsafe.}
proc into*[T: tuple](value: RotValue, result: var T) {.inline, gcsafe.}
proc into*[T: object](value: T, result: var RotValue) {.inline, gcsafe.}
proc into*[T: object](value: RotValue, result: var T) {.inline, gcsafe.}
proc into*[T: distinct](value: T, result: var RotValue) {.inline, gcsafe.}
proc into*[T: distinct](value: RotValue, result: var T) {.inline, gcsafe.}

proc into*[T](value: openArray[T], result: var RotValue) =
  mixin into
  var phrases = newSeq[RotPhrase](value.len)
  for i in 0 ..< value.len:
    var item: RotValue
    into(value[i], item)
    case item.kind
    of Vector:
      phrases[i] = item.compound
    of Scalar:
      phrases[i] = RotPhrase(items: @[toItem(item.atom)])
  result = scalar rotBlock(phrases)
  # could also be a compound that includes the length

proc dumpOpenarrayImpl[T](term: RotTerm, result: var openArray[T]) {.inline.} =
  mixin into
  for i, phrase in term.block.phrases:
    into(vector(phrase), result[i])

proc into*[T](value: RotValue, result: var seq[T]) =
  # custom behavior would go here if length is added as said above:
  let term = getScalar(value)
  if term.kind != Block:
    raise newException(ValueError, "expected block for seq")
  result = newSeq[T](term.block.phrases.len)
  dumpOpenarrayImpl(term, result)

proc into*[I, T](value: RotValue, result: var array[I, T]) =
  # custom behavior would go here if length is added as said above:
  let term = getScalar(value)
  if term.kind != Block:
    raise newException(ValueError, "expected block for array")
  if term.block.phrases.len != len(result):
    raise newException(ValueError, "got block of length " & $term.block.phrases.len & " for array of length " & len(result))
  dumpOpenarrayImpl(term, result)

proc into*[T: tuple](value: T, result: var RotValue) {.inline.} =
  mixin into
  # XXX optional field names
  when tupleLen(value) == 0:
    result = scalar rotUnit()
  else:
    var items = newSeq[RotItem](tupleLen(value))
    var i = 0
    for field in fields(value):
      var item: RotValue
      into(field, item)
      items[i] = toItem(asTerm(item))
      inc i
    result = vector RotPhrase(items: items)

proc into*[T: tuple](value: RotValue, result: var T) {.inline.} =
  mixin into
  # XXX optional field names
  when tupleLen(result) == 0:
    let term = getScalar(value)
    if term.kind != Unit:
      raise newException(ValueError, "expected unit for empty tuple")
  else:
    let phrase = getVector(value)
    var i = 0
    for field in fields(result):
      # XXX check for associations
      into(scalar phrase.items[i].term, field)
      inc i

proc into*[T: object](value: T, result: var RotValue) {.inline.} =
  mixin into
  # XXX optional field names
  # unfortunately need to decide to generate unit after the fact here
  var items = newSeq[RotItem]()
  for field in fields(value):
    var item: RotValue
    into(field, item)
    items.add toItem(asTerm(item))
  if items.len == 0:
    result = scalar rotUnit()
  else:
    result = vector RotPhrase(items: items)

proc into*[T: object](value: RotValue, result: var T) {.inline.} =
  mixin into
  # XXX optional field names
  var phrase: RotPhrase
  case value.kind
  of Scalar:
    case value.atom.kind
    of Phrase: phrase = value.atom.phrase
    of Unit:
      result = T()
      return
    else:
      raise newException(ValueError, "expected unit or phrase for object")
  of Vector: phrase = value.compound
  var i = 0
  for field in fields(result):
    # XXX check for associations
    {.cast(uncheckedAssign).}:
      into(scalar phrase.items[i].term, field)
    inc i

proc into*[T: distinct](value: T, result: var RotValue) {.inline.} =
  mixin into
  into(distinctBase(T)(value), result)

proc into*[T: distinct](value: RotValue, result: var T) {.inline.} =
  mixin into
  var inner: distinctBase(T)
  into(value, inner)
  result = T(inner)

proc toRotValue*[T](value: T): RotValue {.inline.} =
  mixin into
  into(value, result)

proc toRotTerm*[T](value: T): RotTerm {.inline.} =
  asTerm(toRotValue(value))

proc fromRotValue*[T](_: typedesc[T], value: RotValue): T {.inline.} =
  mixin into
  into(value, result)

proc fromRotTerm*[T](_: typedesc[T], value: RotTerm): T {.inline.} =
  fromRotValue(T, scalar value)
