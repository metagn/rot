import rot/[representation, parser]
export representation

proc parseRot*(str: sink string = ""): RotBlock =
  var parser = initRotParser(str)
  result = parseFullBlock(parser)

proc parseRot*(loader: proc(): string): RotBlock =
  var parser = initRotParser(loader)
  result = parseFullBlock(parser)
