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
123_456
abc.def
```

Can also be surrounded by backticks to allow all characters. Again, repeating backticks allows to use them in the string.

```
`abc def`
`abc `` def
ghi jkl`
```

Allowed characters are (for now): Every character that is not used in the data format, except quote characters, and optionally the additional features that can be disabled (whether or not the character is usable is separately configurable). Right now these are the following characters: `,;={}()` (default), `:[]|#` (from optional features), and whitespace (optionally disabled, see section).

See the rationale section for the idea behind this syntax.

### Phrase (and unit)

A phrase is a "row" of data, i.e. a collection of data values that cannot be empty (see rationale section for why). Items of a phrase are delimited by inline whitespace or commas (`,`). (these are interchangeable, see rationale section for why)

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

A phrase can be wrapped in parentheses (`()`) to nest inside other phrases. Using this syntax, newlines also delineate phrase terms like inline whitespace.

```
a, (b, "c d",
  e), f
```

If there are no terms wrapped inside parentheses, then it is treated as a separate "unit" data type.

```
() # unit
```

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

### Indented/line-terminated strings and blocks with colons

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

Author note: I am not sure about the "exactly 1 term" part, maybe it should just associate the last term, but I don't know the use for this as it would always terminate the phrase.

### Brackets

A phrase surrounded by square brackets (`[]`) represents a block with each of the phrase's terms as the items. Each term is added to the block as a phrase containing the term as the only item.

```
abc = [def, "ghi jkl" mnop
, (nested "phrase")] # same as {def; "ghi jkl"; mnop; (nested "phrase")}, nested phrase not unwrapped
```

Author note: I am really not sure about this syntax, the syntax being different but representing the same thing as curly brackets would need a better reason than "semicolons are ugly" (although they are also guaranteed to have unary phrases). It could be its own data type like "phrase that can be empty" (provided `()` is disallowed) but then there is no good indented version for it, which clashes IMO with it being an "array". The point of `{}` is not to be a syntax for "records" anyway.

### Indented/line-terminated phrases and bracket blocks with pipes

Similar to the colon syntax for strings/blocks, the pipe character (`|`) can be used as an indented or line-terminated syntax for phrases and bracket blocks.

```
abc | def, "ghi jkl" mnop
abc |
  def, "ghi jkl"
    mnop
  (nested "phrase")

# same as
abc, (def, "ghi jkl", mnop)
abc, (def, "ghi jkl", mnop, (nested, "phrase"))
```

A second pipe character (`||`) turns the parsed phrase into a block like the bracket syntax.

```
abc || def, "ghi jkl" mnop
abc ||
  def, "ghi jkl"
    mnop
  (nested "phrase")

# same as
abc, {def; "ghi jkl"; mnop}
abc, {def; "ghi jkl"; mnop; (nested, "phrase")}
```

`=` can also be added to create an association like colons.

Can be nested, and in general allows multiple indent-sensitive syntax terms.

```
abc |
  def |=
    ghi ||
      jkl
  mno: qrs
  tuv :: wxyz

# same as
abc, (def = (ghi, {jkl}), mno, "qrs", tuv, {wxyz})
```

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

### Why symbols, and why no numbers or booleans?

I was not sure if these should be different from strings at first (even before the backtick quotes), but it seems more useful to me that something differentiated by syntax also represents something else semantically, after which it can also be extended to make full use of the distinction (i.e. "no whitespaces" is not a particularly useful distinction for data, so they can be quoted as well). In the end it is allowed to treat them as the same anyway.

One way to make sense of the distinction might be that normal strings represent arbitrary text, while symbols represent a finite or pre-defined set of strings. These can be things like `null`, `true`/`false`, `NaN`, enum symbols, field/variable names, or even integers or real numbers. Distinguishing these from arbitrary text can be annoying, so arbitrary text is relegated to a separate syntax. But there is nothing wrong with using the syntax for arbitrary text for these values either.

The idea with booleans and numbers is that since they are such fundamental types, it is likely trivial for the user to validate and parse them themselves, and even to distinguish them from other symbols if they want. And they can usually be interpreted in different ways, i.e. `on`/`off`, `yes`/`no`, `Y`/`N` can be allowed for booleans, `1e6` can be allowed as an integer or only treated as a float, arbitrary or fixed precision may be allowed. So it is not made any harder for these different options to be expressed than specifically what the format would allow if it treated them differently.

I also prefer things like `123abc` working unquoted.

### Why no escape sequences, and why are quoted strings only multiline?

Escape sequences complicate the syntax by taking up a whole character, usually preventing that character from being used by itself in strings. I would rather the exact escaping scheme be separate from the structure handling parser, which doesn't need an escape character. Escaping quotes in quoted strings is done by repeating the character, escaping newlines for phrase terms is done with `,`. By not giving `\` special behavior inside quotes, a custom escape scheme can still be used in any string.

Similarly a separate syntax for multiline strings seems unnecessarily complex. Something like `"""` conflicts with the quote escaping syntax which is worth the tradeoff IMO, and adding a character like `'` that prohibits newlines seems pointless especially without an escape scheme.

Problems like encoding limitations, platform-specific newlines can make "raw" text difficult to work with. But this doesn't have to take away from applications that don't care about these problems.

### Why are whitespace and commas interchangeable as phrase term delimiters?

This looks unintuitive, but it is the most reasonable choice to me by process of elimination. Only using whitespace seems too inflexible and may require a separate "newline escape" character, and commas ideally have some meaning in the language as they pretty clearly delineate information. Only using commas opens up the question of what `abc "def ghi"` by itself means. Allowing both but only one at a time per phrase/document seems like an arbitrary restriction.
- Addendum: Since this was written, whitespace as delimiters can be optionally disabled in the parser to become part of unquoted strings, see section in additional features.

I think there is still a way to interpret it that does not necessarily break intuition, explained in the next section.

### Why do phrases have both table row and shell command syntax?

Example:

```
abc "def"
abc "def" ghi="jkl"
# same as
abc, "def"
abc, "def", ghi="jkl"

abc = "def" # assignment
abc = "def", ghi = "jlk" # record?

{ "abc"; "def"; "ghi" } # list?
{ abc; def; ghi } # command block?
```

The idea is that shell commands can be considered a "row". Their first column represents the action, and the remaining columns are the arguments. So a command like:

```
abc "def"
```

Can be equivalent to:

```
action = abc, arg1 = "def"
```

in contexts that allow such commands, and just `column1 = abc, column2 = "def"` in others.

But we do not have to be strict with the use of `=` for this, i.e. it does not just have to denote the column name. We can treat the first column differently depending on if it can be interpreted as an action.

```
abc = "def"
abc = "def", ghi = "jkl"
```

One could interpret the initial association as the action like before:

```
action = (abc = "def")
action = (abc = "def"), ghi = "jkl"
```

But "acting" on an association doesn't make much sense. If anything, the action is setting `abc` to `"def"`, i.e. it is more like:

```
action = `=`, left = abc, right = "def"
# this can stay as the interpretation, but there are probably not many uses for it:
action = `=`, left = abc, right = "def", ghi = "jkl"
```

Since the command `abc "def"` can also be used to mean "set `abc` to `"def"`", the interpretation can optionally be simplified to this as well. Then `ghi = "jkl"` would become another argument to the `abc` command again.

How we treat the first column can also be generalized to all arbitrary structures, discussed in the next section.

### How is a "command" or "call" phrase distinguished from a value?

```
abc # command?
"abc" # value?
{ "abc" } # list value?
{ abc } # command value?
```

Usually it will not make sense to allow values in a context where only commands are expected, but it might make sense to allow commands where values are expected, i.e. `field = (concat "abc " variable " def")`). The way to distinguish these is that instead of interpreting a "command" structure, i.e. `action = ..., arg1 = ..., arg2 = ...`, we can interpret a separate "value" or "entry" structure, like `value = ...`. This can be done by looking at the first column as in the previous section.

```
abc # if `abc` is a valid action, becomes:
action = abc

"abc" # becomes:
value = "abc"

{ ... }
# in a value context, becomes:
value = { ... }
# in a command context, becomes:
action = { ... }
# which just executes everything inside as a command, or has some other behavior
```

A value phrase can also still have multiple terms:

```
"abc" "def"
```

Using the entry interpretation, we can treat this as something like an entry to a hash table.

```
table = {
  "abc" "def"
  "ghi", "jkl"
}
# becomes
table = {
  key = "abc", value = "def";
  key = "ghi", value = "jkl";
}
```

In Lisp for example, any "list" in a program (`(abc def)`, `(abc)`, even `(123)`) is interpreted as a command. Lists that are meant to be data have to be quoted like `'(abc def)`. However, quoted list data can still be interpreted as code, and run as a program. The point being that how data is interpreted can change and is not always decided by the data. This data format was not made with the goal of being syntax for a programming language, but I think it can still make for fairly expressive DSLs.

Although the difference with S-expressions is that "lists" (blocks) cannot contain "scalars" (singular terms), these scalars have to be wrapped in an "entry" structure, and this structure usually has to be interpreted without named fields to stay expressive. I might still add a special syntax for "denoting" structures with information, like a type. In YAML this is the "tag" feature (`!!seq`, `!invoice` etc).

### Why can phrases not be empty?

Because there is no good syntax for an empty phrase inside a block. Otherwise `()` being an empty phrase is fine, but it would be bad for it to "fold" into an empty phrase inside a block, rather than just be a phrase containing an empty phrase. So `()` is treated as a special syntax for a "unit" type instead.

### Why can blocks only contain phrases?

This is a consequence of the format being 2 dimensional by default, i.e. dividing into lines, and further dividing inside those lines. It is like this because lines as divided units happens to be easily understood by people, because our screens are 2 dimensional, etc.

### Character choice in the syntax

For the most part as little "special" characters as possible are chosen. This mostly affects what characters are allowed in symbols.

The characters for forming structure are almost ubiquitously used in regular language/programming to "separate" terms. So characters like `,`, `;`, all forms of brackets, whitespace, `=`. `:` and `|` are a bit more iffy but for the most part are still used like this. Characters like `/`, `-`, `+`, `>` are either ambiguous in their use of separating things, or straight up represent "joining" things together, and so are not used and are allowed in symbols.

Double quotes (`"`) are pretty ubiquitous for strings in programming, and only really used in full sentences rather than specific words in natural language. Single quotes (`'`) are used in natural language inside words and sometimes in programming like the "prime" symbol in math (`a = 1, a' = a + 1`), among other things. Not that this is the main reason it wasn't used, but it's a relevant caveat if it is used. Backticks (`` ` ``) are less commonly used as quotes but are still used as such, and are uncommon in natural language by themselves.

`#` is the comment character, and does not really fit with any of the ideas here other than the fact that this is a common use for it. Most substitutes would be either too commonly used normally or too unconvential. `~` maybe. Changing it would likely cause more pain.
