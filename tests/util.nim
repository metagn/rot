import rot

proc t*(s: string): RotTerm = RotTerm(kind: Text, text: s)
proc s*(s: string): RotTerm = RotTerm(kind: Symbol, symbol: s)

proc a*(a: RotTerm): RotAssociated =
  result = associated(a)

proc a*(a, b: RotTerm): RotTerm =
  result = rotPhrase(a, associated(b))

proc p*(args: varargs[RotItem, toItem]): RotTerm =
  result = RotTerm(kind: Phrase, phrase: RotPhrase(items: @[]))
  for a in args:
    result.phrase.items.add a

proc b*(args: varargs[RotTerm]): RotTerm =
  result = RotTerm(kind: Block, `block`: RotBlock(phrases: @[]))
  for a in args:
    if a.kind == Phrase:
      result.block.phrases.add a.phrase
    else:
      result.block.phrases.add RotPhrase(items: @[toItem(a)])

template match*(s: string, b: RotTerm) =
  checkpoint s
  let parsed = parseRot(s)
  let a = RotTerm(kind: Block, `block`: parsed)
  check a == b

template match*(arr: openarray[(string, RotTerm)]) =
  for (s, b) in arr.items:
    match s, b
