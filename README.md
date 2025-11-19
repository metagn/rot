tentative spec:

some sort of data format like csv or yaml inspired by groovy/kotlin dsls

data types:
* only strings, no numbers or booleans, so 123abc is valid
  * optionally identifiers separate from strings
* phrases, like tuples that can contain any other data type including other phrases, but cannot be empty
* blocks, can only contain phrases, can be empty
* assignments: like a phrase, but can only have 2 arguments

grammar:

```
# by default a block is parsed with newlines separating phrases
abc # single identifier token, abc: interpreted as a phrase containing abc
abc def # 2 identifier tokens, abc, def: interpreted as a phrase containing abc and def
"abc def" # 1 string token

abc = def # single assignment
abc def = ghi # phrase of 1 identifier token, 1 assignment
abc = def ghi # phrase of 1 assignment, 1 identifier token
abc = "def ghi"

abc, def # in block context: a phrase containing abc and def
abc; def # in block context, 2 phrases, each containing abc and def

{ ... } # block
( ... ) # wrapped phrase, ; is disallowed
[ ... ] # block, but with phrase syntax, i.e. ; is disallowed, space and , still separate items
# ^ bad that the syntax is distinct but the data is equivalent

"double quote is
multiline by itself"
'single quote is forced single line?'

# whitespace sensitive alternative syntaxes:

# alternative for block:
abc ::
  ...
# parses as:
abc { ... }

abc: this part is a string probably ignoring initial white spaces # dont know about comments
# parses as:
abc "..."

abc:
  this part is also a string
  and multiline because of indent and dedented

abc: "dont know if this ignores the quotes"

abc = "this requires the quotes though"

abc def="ghi": this adds a string to the end of the phrase
# parses as:
abc def="ghi" "..."

abc ::
  maybe this is assignment version of : instead

abc := or this
abc ::=
  "block version"

abc =
  "dont know how to treat this, maybe require := otherwise parse error"
```
