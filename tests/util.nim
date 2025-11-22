import rot

proc t*(s: string): Rot = Rot(kind: Text, text: s)
proc s*(s: string): Rot = Rot(kind: Symbol, symbol: s)

proc a*(a, b: Rot): Rot =
  result = Rot(kind: Association, association: RotAssociation())
  new(result.association.items)
  result.association.items.left = a
  result.association.items.right = b

proc p*(args: varargs[Rot]): Rot =
  result = Rot(kind: Phrase, phrase: RotPhrase(items: @[]))
  for a in args:
    result.phrase.items.add a

proc b*(args: varargs[Rot]): Rot =
  result = Rot(kind: Block, `block`: RotBlock(items: @[]))
  for a in args:
    if a.kind == Phrase:
      result.block.items.add a.phrase
    else:
      result.block.items.add RotPhrase(items: @[a])

proc `==`*(a, b: Rot): bool {.noSideEffect.} =
  if a.kind != b.kind: return false
  case a.kind
  of Unit: result = true
  of Text: result = a.text == b.text
  of Symbol: result = a.symbol == b.symbol
  of Association:
    if system.`==`(a.association.items, b.association.items):
      return true
    if a.association.items.isNil:
      return false
    result = a.association.items.left == b.association.items.left and
      a.association.items.right == b.association.items.right
  of Phrase:
    result = a.phrase.items == b.phrase.items
  of Block:
    result = a.block.items == b.block.items

proc `$`*(a: Rot): string =
  case a.kind
  of Unit: result = "()"
  of Symbol: result = a.symbol
  of Text:
    result = ""
    result.addQuoted(a.text)
  of Association:
    result = $a.association.items.left & " = " & $a.association.items.right
  of Phrase:
    result = "("
    for i, a in a.phrase.items:
      if i != 0: result.add ", "
      result.add $a
    result.add ")"
  of Block:
    result = "{"
    for i, a in a.block.items:
      if i != 0: result.add "; "
      for j, b in a.items:
        if j != 0: result.add ", "
        result.add $b
    result.add "}"

template match*(s: string, b: Rot) =
  checkpoint s
  let parsed = parseRot(s)
  let a = Rot(kind: Block, `block`: parsed)
  check a == b

template match*(arr: openarray[(string, Rot)]) =
  for (s, b) in arr.items:
    match s, b
