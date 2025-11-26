import rot/[data, parser]
export data, defaultRotOptions, RotOptions, SpecialCharacterStrategy, DelimiterStrategy

proc parseRot*(str: sink string, options = defaultRotOptions()): RotBlock =
  var parser = initRotParser(str, options)
  result = parseFullBlock(parser)

proc parseRot*(loader: proc(): string, options = defaultRotOptions()): RotBlock =
  var parser = initRotParser(loader, options)
  result = parseFullBlock(parser)
