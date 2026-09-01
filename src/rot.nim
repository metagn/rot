import rot/[data, parser, reader], fleu/load_buffer
export data, parser, RotReader, initRotReader

proc parseRot*(str: sink string, format = defaultRotFormat()): RotBlock =
  var reader = initRotReader(str)
  result = parseFullBlock(format, reader)

when declared(File):
  proc parseRotFile*(path: string, format = defaultRotFormat()): RotBlock =
    var file = open(path, fmRead)
    defer: close(file)
    var reader = initRotReader(initLoadBuffer(file))
    result = parseFullBlock(format, reader)
