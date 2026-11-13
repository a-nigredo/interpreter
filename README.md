# AutoHotkey v2 Lisp-like interpreter

A small embeddable interpreter implemented in AutoHotkey v2. The main implementation is `Interpreter.ahk`.

This interpreter is intended for reading and processing data supplied through its environment. Pass values such as arrays, maps, and objects into `Eval` through `env`, then use expressions to inspect or process them.

```autohotkey
#Requires AutoHotkey v2.0
#Include Interpreter.ahk

lisp := Interpreter()
env := Map("user", Map("name", "Ada"), "items", [1, 2, 3])

lisp.Eval('(if (and t (> 5 2)) (concat "hello" " world") "no")') ; "hello world"
lisp.Eval('(get $user "name")', env) ; "Ada"
lisp.Eval('(contains $items 2)', env) ; true

lisp.Eval('(copy-to-clipboard "hello")') ; copies and returns a NoResult marker

lisp.Eval(["+", 1, ["*", 2, 3]]) ; 7, evaluates the array directly
```

## Syntax

- Forms use Lisp syntax with parentheses: `(+ 1 2)`.
- A form's evaluated operator must be a string naming a registered operator; a number or other value in operator position is not callable.
- Source syntax does not construct arrays or maps. Pass collections through the environment and read them with `get`, `length`, `contains`, or `in`.
- Each interpreter caches parsed forms for up to 256 distinct source expressions by default. Configure the limit with the constructor argument, such as `Interpreter(64)`; `0` disables caching. Repeated calls reuse parsed syntax but always reevaluate against the current environment.
- Strings can use double quotes or backticks as delimiters. Backtick escapes in double-quoted strings support `` `n``, `` `r``, and `` `t``; doubled delimiters represent a literal delimiter inside either string form.
- Atoms include numbers (including decimals and exponents), `t` (true), `nil` (false), strings, and symbols. Only atoms beginning with `$` are symbols; all other unquoted non-numeric atoms are string values. Use `""` for the empty string.
- Numbers, strings, `t`, and `nil` are self-evaluating; `$`-prefixed symbols are looked up in the evaluation environment. Dotted symbols traverse nested maps or object properties (for example, `$user.name`).
- `if` accepts any valid expression as its condition. Only `nil` is false; numbers (including `0`), strings (including `""`), and all other non-`nil` values are true. `and` and `or` short-circuit and return operand values, as in Lisp.
- `Eval(sourceOrExpression, env)` accepts Lisp source text or a nested expression array, plus an optional `Map` of variable names to values. In expression arrays, each non-empty array is a form: its first string is the operator and subsequent strings are literal values; nested arrays are nested forms. A one-element string array is parsed as Lisp source, including when nested in another expression array. Native AutoHotkey arrays, maps, and objects can also be passed in the environment.
- AutoHotkey represents `false` as numeric `0`, so use `Interpreter.False` in expression arrays or environments when you need an explicit Lisp `nil`; use `Interpreter.True` for an explicit Lisp `t`. `Eval` converts Lisp booleans back to native booleans in its final result.
- Interpreter failures throw `EvaluationError` (defined in `Interpreter.ahk`), which extends AutoHotkey's `Error`. For source-string input, errors with a known location include 1-based `position`, `sourceLine`, and `sourceColumn` properties; the message also includes line and column. The failing expression is exposed as `expr` when available.

## Operators

| Form | Behavior |
| --- | --- |
| `(+ a b ...)`, `(- a b ...)`, `(* a b ...)`, `(/ a b ...)`, `(% a b)` | Numeric arithmetic; unary `-` negates. |
| `(= a b)`, `(!= a b)`, `(< a b)`, `(<= a b)`, `(> a b)`, `(>= a b)` | Comparisons. `==` and `<>` are aliases for `=` and `!=`. |
| `(and a b ...)`, `(or a b ...)`, `(not a)` | Boolean operations; `and` and `or` short circuit and return operand values. `or` treats a missing variable as absent so a later operand can serve as its fallback. A missing variable with no later operand raises an error. |
| `(if test then else)` | Conditional expression. Any expression is valid as the test; only `nil` is false. Only the selected branch is evaluated. |
| `(make-env (name value) ...)` | Evaluates each value in order, making earlier bindings and the input environment available to later values. Returns a `Map` containing only the declared variables. |
| `(concat a b ...)` | Concatenates values as strings. |
| `(join separator value ...)` | Joins values as strings using the required string separator. With no values, returns an empty string. |
| `(copy-to-clipboard value)` | Copies a value to the Windows clipboard and returns a `NoResult` marker instead of a printable value. |
| `(match text regex)` | True when the regular expression matches the text (`RegExMatch`). |
| `(strip-prefix text prefix)`, `(strip-suffix text suffix)` | Removes a matching prefix or suffix; otherwise returns the original string. |
| `(length value)` | String length, array length, or map entry count. |
| `(substr text start [length])` | Returns a substring using AutoHotkey's 1-based `SubStr` indexing; negative positions count from the end. |
| `(upper text)`, `(lower text)` | Converts a string to uppercase or lowercase. |
| `(trim text [omit-characters])` | Trims the specified characters from both ends. By default, trims spaces, tabs, carriage returns, and line feeds. |
| `(replace text search replacement)` | Replaces all case-sensitive occurrences of a non-empty search string. |
| `(starts-with text prefix)`, `(ends-with text suffix)` | Case-sensitive prefix/suffix checks. An empty prefix or suffix matches. |
| `(index-of text search)` | Returns the 1-based position of the first case-sensitive match, or `0` when not found. |
| `(get value key-or-path)` | Retrieves a map key, native object property, or 1-based array index. Dot-separated paths traverse nested values. Missing values raise an error. |
| `(contains array value)` / `(in array value)` | Tests array membership. Also supports map-key and substring checks. |

An environment can be used to pass native AutoHotkey values:

```autohotkey
env := Map("user", Map("name", "Ada"), "items", ["tea", "coffee"])
lisp.Eval('(get $user "name")', env)
lisp.Eval('(get $items 2)', env)
lisp.Eval('(or $user.name "guest")', env)
lisp.Eval('(contains $items "tea")', env)
```

Use `make-env` to compute context once and pass its returned map to later calls:

```autohotkey
context := lisp.Eval('(make-env (name "Ada") (greeting (concat "Hello, " $name)))')
lisp.Eval('(concat $greeting "!")', context) ; "Hello, Ada!"
```

Bindings are evaluated sequentially, so each value can reference earlier names. When an input environment is supplied, its map entries or object properties are visible while computing the bindings, but are not copied into the returned map.

Use `or` to look up an environment variable or nested path and optionally supply a fallback. The fallback is one expression:

```lisp
(or $name "guest")
(or $user.name "guest")
(or $count 0)
```

Without a fallback, a missing variable raises an error. In a larger expression, use `or` as an expression, for example `(concat "Hello, " (or $user.name "guest"))`.

## Implementation

`Eval` is the interpreter's public evaluation entry point. Parsing, evaluation, and builtin helpers use a leading underscore to mark them as internal implementation methods. Special forms (`if`, `and`, `or`, and `not`) are handled directly so they can control evaluation; other operators are dispatched through the interpreter's builtin registry. Interpreter failures use `EvaluationError`, with the failed expression available in its `expr` property when evaluation has begun.

`copy-to-clipboard` returns an instance of `NoResult`, allowing callers to distinguish a side-effect-only result from ordinary values such as `false` (the interpreter's `nil`). Check with `result is NoResult` when deciding whether to display an evaluation result.

## Benchmarking

Run `.\measure-expressions.ps1 -Expression '(> 1 1)'` to measure repeated evaluations of the supplied Lisp expression. Use `-Iterations` and `-Rounds` to adjust the workload. AutoHotkey v2 must be installed or provided with `-AutoHotkeyPath`.
