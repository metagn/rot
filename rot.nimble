# Package

version       = "0.1.0"
author        = "metagn"
description   = "data format"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.0.0"
requires "https://github.com/holo-nim/fleu"

task docs, "build docs for all modules":
  exec "nim r tasks/build_docs.nim"

task tests, "run tests for multiple backends and defines":
  exec "nim r tasks/run_tests.nim"
