import rot/[representation, parser]
export representation, defaultRotOptions, RotOptions, SpecialCharacterStrategy

proc parseRot*(str: sink string = "", options = defaultRotOptions()): RotBlock =
  var parser = initRotParser(str, options)
  result = parseFullBlock(parser)

proc parseRot*(loader: proc(): string, options = defaultRotOptions()): RotBlock =
  var parser = initRotParser(loader, options)
  result = parseFullBlock(parser)
