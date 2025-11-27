# rot

Yet another plaintext data format, inspired by CSV, YAML, and Groovy/Kotlin DSLs. Focuses on text/strings and structure.

So there are no surprises, the biggest caveats right away are:

* No numbers or booleans, as in, they are not distinguished from strings. But they should not be horrible to deal with.
* No escape sequences. Characters are treated literally including newlines, and unicode characters are not specially handled.
* Inline whitespace is a delimiter and separates unquoted strings by default.
* Other unusual syntax.

See [the spec](https://github.com/metagn/rot/blob/master/doc/spec.md) for more info and some reasoning.

## Use cases vs. other formats

* CSV: Allows nested structure. Otherwise slightly more inconvenient if anything.
* JSON: Less clunky structure (e.g. easier to stream) and leaner syntax, while still giving the option of well-defined boundaries and form.
* YAML: Simpler to parse, no ambiguity with data types, while keeping some of the convenience.
* XML: More human oriented, similar flexibility, although not a markup language.
* S-expressions: More human oriented.
* INI/TOML/HOCON: Not as convenient for configuration, but allows for more flexibility.

[NestedText](https://nestedtext.org/) apparently has a similar philosophy but bases its structure on YAML, whereas this format has structure more similar to XML or S-expressions. [KDL](https://kdl.dev/), [SDLang](https://sdlang.org/), [Confetti](https://confetti.hgs3.me/), [HUML](https://huml.io/) also have similar goals but obviously we need yet another standard.
