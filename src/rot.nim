import rot/[common, data, parser, reader], fleu/load_buffer
export common, data, parser, RotReader, initRotReader

proc parseRotBlock*(str: sink string, format = DefaultRotFormat): RotBlock =
  var reader = initRotReader(str)
  result = parseFullBlock(format, reader)

proc parseRotTerm*(str: sink string, format = DefaultRotFormat): RotTerm =
  let b = parseRotBlock(str, format)
  if b.phrases.len == 1:
    if not b.phrases[0].hasTail:
      result = b.phrases[0].head
    else:
      result = asTerm(b.phrases[0])
  else:
    result = asTerm(b)

when declared(File):
  proc parseRotFile*(path: string, format = DefaultRotFormat): RotBlock =
    var file = open(path, fmRead)
    defer: close(file)
    var reader = initRotReader(initLoadBuffer(file))
    result = parseFullBlock(format, reader)
