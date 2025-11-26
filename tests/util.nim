import rot

proc t*(s: string): RotTerm = RotTerm(kind: Text, text: s)
proc s*(s: string): RotTerm = RotTerm(kind: Symbol, symbol: s)

proc a*(a, b: RotTerm): RotTerm =
  result = RotTerm(kind: Association, association: (ref RotAssociation)(left: a, right: b))

proc p*(args: varargs[RotTerm]): RotTerm =
  result = RotTerm(kind: Phrase, phrase: RotPhrase(items: @[]))
  for a in args:
    result.phrase.items.add a

proc b*(args: varargs[RotTerm]): RotTerm =
  result = RotTerm(kind: Block, `block`: RotBlock(items: @[]))
  for a in args:
    if a.kind == Phrase:
      result.block.items.add a.phrase
    else:
      result.block.items.add RotPhrase(items: @[a])

template match*(s: string, b: RotTerm) =
  checkpoint s
  let parsed = parseRot(s)
  let a = RotTerm(kind: Block, `block`: parsed)
  check a == b

template match*(arr: openarray[(string, RotTerm)]) =
  for (s, b) in arr.items:
    match s, b
