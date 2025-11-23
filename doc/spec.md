# Description

Document content can be represented by a few data types. By default, a full document parses into a block, but the parser can be invoked to parse one of each type at a time.

Like XML and S-expressions, the data format is designed to allow interpreting it in different ways, so an ideal application is to handle it as if processing a "language".

## Data types

### Text (string)

Any string surrounded by double quotes.

```
"abc"
"abc def"
```

Newlines are allowed.

```
"abc def
ghi jkl" # => abc def<newline>ghi jkl
```

The double quote character itself can be included in the string by repeating it once.

```
"abc "" def" # => abc " def
"""abc def""" # => "abc def"
```

Author note: Single quotes could also be added, and what they do could be configurable as well as for other quotes, but this is simple and good enough for now.

### Symbol

A string of characters that have no function of "separating" data in the format (see below), and that are not surrounded by double quotes.

```
abc
abc123
123abc
123
123.456
```

Can also be surrounded by backticks to allow all characters. Again, repeating backticks allows to use them in the string.

```
`abc def`
`abc `` def
ghi jkl`
```

Allowed characters are (for now): Every character that is not used in the data format, except quote characters, and optionally the additional features that can be disabled (whether or not the character is usable is separately configurable). Right now these are the following characters: `,;={}()` (default), `:[]#` (from optional features), and whitespace (optionally disabled, see section).

Author note: I was not sure if these should be different from strings at first (even before the backtick quotes), but it seems more useful to me that something differentiated by syntax also represents something else semantically, after which it can also be extended to make full use of the distinction ("no whitespaces" is not a particularly useful distinction for data). In the end it is allowed to treat them as the same anyway.
One way to make sense of the distinction might be that normal strings represent arbitrary text, while symbols represent a finite or pre-defined set of strings. These can be things like `null`, `true`/`false`, `NaN`, enum symbols, field/variable names, or even integers or real numbers. Distinguishing these from arbitrary text can be annoying, so arbitrary text is relegated to a separate syntax. But there is nothing wrong with using the syntax for arbitrary text for these values either.

### Phrase (and unit)

A phrase is a "row" of data, i.e. a collection of data values that cannot be empty (see author note 2). Items of a phrase are delimited by inline whitespace or commas (`,`). (see author note 1)

```
abc "def ghi" jkl
abc, "def ghi", jkl
abc "def ghi",jkl
abc,"def ghi" jkl
```

The use of a comma allows for newlines to be used up to the next phrase term as well.

```
abc,
"def ghi",

jkl
```

Author note 1: Whitespace and commas being interchangeable is unintuitive, but it is the most reasonable choice to me by process of elimination. Only using whitespace seems too inflexible and may require a separate "newline escape" character, and commas ideally have some meaning in the language as they pretty clearly delineate information. Only using commas opens up the question of what `abc "def ghi"` by itself means. Allowing both but only one at a time per phrase/document seems like an arbitrary restriction.
- Addendum: Since this was written, whitespace as delimiters can be optionally disabled in the parser to become part of unquoted strings, see section in additional features.

A phrase can be wrapped in parentheses (`()`) to nest inside other phrases. Using this syntax, newlines also delineate phrase terms like inline whitespace.

```
a, (b, "c d",
  e), f
```

If there are no terms wrapped inside parentheses, then it is treated as a separate "unit" data type.

```
() # unit
```

Author note 2: The reason phrases cannot be empty is that there is no good syntax for an empty phrase inside a block. Otherwise `()` being an empty phrase is fine, but it would be bad for it to "fold" into an empty phrase inside a block, rather than just be a phrase containing an empty phrase. So `()` is treated as a special syntax for a "unit" type instead.

### Association

An association is the pairing of a phrase term with another using the `=` character in between.

```
abc = "def", ghi = (jkl, mnop)
```

Similar to commas, newlines after the `=` character are treated as inline whitespace.

An association can only be the item of a phrase. They cannot be nested inside other associations.

Author note: I don't have a good rationalization for this syntax. I would think it is a natively supported shorthand for `= abc "def"` but I guess that would be too general to deal with. I am fine with only having one infix operator though, and one that doesn't have a left/right precedence.

### Block

Blocks are collections of phrases, and can be empty. Phrases in blocks are delimited by newlines (unless they are allowed by the phrase) or semicolons (`;`).

```
abc "def" # phrase (abc, "def")
ghi = "jkl" # phrase (ghi = "jkl")
"mnop" # phrase ("mnop")
```

A block can be wrapped in curly brackets (`{}`) to nest inside other structures.

```
abc "def" {
  ghi = {"jkl"; "mnop"}
  "qrs tuv"
}
```

## Additional syntax (optional)

As of now in the implementation parser these are on by default and can be optionally disabled. The special characters used can also be allowed in symbols with a separate option each.

### Comments

Comments begin from the `#` character and last until the end of a line, outside of a quoted string/symbol.

```
# comment
abc = "def" # comment
"this is # not a comment"
```

Author note: No idea for multiline comments yet.

### Whitespace sensitive syntax with colons

Colons can be used to delimit any data with specific forms of whitespace, either up to the end of the current line or inside an indented block. Indentation is referring to the number of inline whitespace characters in a line before a non-space character, tabs and spaces both count as 1.

A single colon, followed by inline whitespace up to a non-space character, will record text from the first non-space character to the end of the line (not including the line) and add it to the phrase.

```
abc: def ghi
# same as:
abc "def ghi"
```

If the first non-space character is on a new line and is higher in indentation than the line the colon was used on, text will be recorded from the start of the first non-space character until a non-space character with an indentation lower than or equal to the first line. Whitespace will only be included in the string if it is on the indentation level required of non-space characters. Newlines are included only up to the last indented line (so just indented spaces and nothing after at the end of the string denotes a trailing newline).

```
abc:
  def ghi
    jkl mno

      pqr stu
    
  vwx

# parses as:
abc "def ghi
  jkl mno

    pqr stu
  
vwx"
```

```
  abc:
def:
   ghi:
  jkl:

# parses as:
abc ""
def "ghi:"
jkl ""
```

Author note: The `def:` block in the example above might not be intuitive, maybe a "lowest common indent" would be more convenient. But this makes the parser less simple. 

When 2 colons are used (`::`), similar rules apply, but a block is recorded instead of a string. Phrases with a starting character on a line that is indented as required will be parsed inside the block, otherwise the block will end.

```
abc ::
  def ghi ::
    jkl mno ::

      pqr stu ::
    
  vwx

# parses as
abc {
  def ghi {
    jkl mno {
      pqr stu {}
    }
  }
  vwx
}
```

An `=` character following the colons (i.e. `:=`, `::=`) will create an association rather than adding the string/block to the phrase. This requires that the phrase has exactly 1 term before the colon.

```
a :=
  b c
  d

a ::=
  b c
  d

# same as
a = "b c
d"
a = {
  b c
  d
}
```

### Brackets

A phrase surrounded by square brackets (`[]`) represents a block with each of the phrase's terms as the items. Each term is added to the block as a phrase containing the term as the only item.

```
abc = [def, "ghi jkl" mnop
, (nested "phrase")] # same as {def; "ghi jkl"; mnop; (nested "phrase")}, nested phrase not unwrapped
```

Author note: I am really not sure about this syntax, the syntax being different but representing the same thing as curly brackets would need a better reason than "semicolons are ugly". It could be its own data type like "phrase that can be empty" (provided `()` is disallowed) but then there is no good indented version for it, which clashes IMO with it being an "array". The point of `{}` is not to be a syntax for "records" anyway.

### Disabled whitespace delimiters

Whitespace delimiters such as inline spaces for phrase items, and newlines for phrases in blocks, can be disabled to require the use of the punctuation delimiters instead, `,` and `;` respectively.

```
a = "b", c = "d";
e = "f", g = "h"
i = "j" # errors with expected delimiter
```

They can also be configured to be part of symbols (unquoted strings) in 2 ways:

1. As concatenating characters: if they are encountered between two symbols, both symbols are joined with the whitespace characters in between and considered a single symbol.

```
# inline whitespace only:
abc, def ghi  , jkl   mno
# same as:
abc, `def ghi`, `jkl   mno`

# all spaces disabled: 
  abc def
ghi   jkl   , name = "def";
# same as:
`abc def
ghi   jkl`, name = "def";
```

2. As any other character allowed in symbols, treated as the start of a symbol when they are encountered and as part of it after.

```
# inline whitespace only:
abc def,   ghi
  jkl   ;
# same as:
`abc def`, `   ghi`;
` jkl   `;

# all spaces disabled:
  abc def
ghi jkl,name="abc";
# same as:
` abc def
ghi jkl`,name="abc"
```

# Rationale

todo: escape sequences ("escaped" is a separate format), why no numbers, more?
