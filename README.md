# AutoHotkey v2 Lisp-like interpreter

A small embeddable interpreter implemented in AutoHotkey v2. The main implementation is `Interpreter.ahk`.

This interpreter is intended for reading and processing data supplied through its environment.

```autohotkey
#Requires AutoHotkey v2.0
#Include Interpreter.ahk

lisp := Interpreter()
env := Map("name", "Ada", "count", 3, "enabled", true)

lisp.Eval('(if (and t (> 5 2)) (concat "hello" " world") "no")') ; "hello world"
lisp.Eval('(if $enabled $name "guest")', env) ; "Ada"
lisp.Eval('(+ $count 1)', env) ; 4

lisp.Eval('(copy-to-clipboard "hello")') ; copies and returns a NoResult marker

lisp.Eval(["+", 1, ["*", 2, 3]]) ; 7, evaluates the array directly
```

## Syntax

- Forms use Lisp syntax with parentheses: `(+ 1 2)`.
- A form's evaluated operator must be a string naming a registered operator; a number or other value in operator position is not callable.
- Source syntax can construct arrays with the `array` operator; map literals are not supported. Pass other collections through the environment and read them with `get`, `length`, `contains`, or `in`.
- Each interpreter caches parsed forms for up to 256 distinct source expressions by default. Configure the limit with the constructor argument, such as `Interpreter(64)`; `0` disables caching. Repeated calls reuse parsed syntax but always reevaluate against the current environment.
- Strings can use double quotes or backticks as delimiters. Backtick escapes in double-quoted strings support `` `n``, `` `r``, and `` `t``; doubled delimiters represent a literal delimiter inside either string form.
- Atoms include numbers (including decimals and exponents), `t` (true), `nil` (false), strings, and symbols. Only atoms beginning with `$` are symbols; all other unquoted non-numeric atoms are string values. Use `""` for the empty string.
- Numbers, strings, `t`, and `nil` are self-evaluating; `$`-prefixed symbols are looked up in the evaluation environment. Dotted symbols traverse nested maps, object properties, or arrays; array indices in dotted symbols are 1-based, matching AutoHotkey arrays (for example, `$user.name` or `$items.1`).
- `$?name` and `$?user.name` are shorthand for `(or $name nil)` and `(or $user.name nil)`. They return `nil` for lookup errors and falsey values, including `0` and `""`.
- `if`, `when`, `and`, `or`, and `not` use AutoHotkey v2 truthiness: `false`, `0`, and `""` are false; other values are true. `and` and `or` short-circuit and return operand values.
- `Eval(sourceOrExpression, env)` accepts Lisp source text or a nested expression array, plus an optional `Map` or native object environment. In expression arrays, each non-empty array is a form: its first string is the operator and subsequent strings are literal values; nested arrays are nested forms. A one-element string array is parsed as Lisp source, including when nested in another expression array. A `cond` clause may also be provided as a Lisp source string beginning with `(`. Maps and objects can be nested in the environment and passed through to results.
- Booleans follow AutoHotkey's native representation: `false` is numeric `0`, and `true` is numeric `1`. The interpreter does not preserve a type distinction between booleans and those numbers; use `number?` or `integer?` to inspect them.
- Interpreter failures throw `EvaluationError` (defined in `Interpreter.ahk`), which extends AutoHotkey's `Error`. For source-string input, errors with a known location include 1-based `position`, `sourceLine`, and `sourceColumn` properties; the message also includes line and column plus the full source expression, available as `sourceExpression`. The failing parsed expression is exposed as `expr` when available.

## Operators

| Form | Behavior |
| --- | --- |
| `(+ a b ...)` | Adds numbers. |
| `(- a b ...)` | Subtracts numbers; unary `-` negates. |
| `(* a b ...)` | Multiplies numbers. |
| `(/ a b ...)` | Divides numbers. |
| `(% a b)` | Returns the remainder. |
| `(= a b)` | Compares values for equality. |
| `(!= a b)` | Compares values for inequality. `<>` is an alias. |
| `(== a b)` | Alias for `=`. |
| `(< a b)` | Tests whether `a` is less than `b`. |
| `(<= a b)` | Tests whether `a` is less than or equal to `b`. |
| `(> a b)` | Tests whether `a` is greater than `b`. |
| `(>= a b)` | Tests whether `a` is greater than or equal to `b`. |
| `(number? value)` | Returns true for integer or float values (including AHK booleans, which are integers). |
| `(integer? value)` | Returns true for integer values (including AHK booleans). |
| `(float? value)` | Returns true for float values. |
| `(string? value)` | Returns true for string values, including numeric strings. |
| `(and a b ...)` | Short-circuits and returns operand values. |
| `(or a b ...)` | Short-circuits and returns operand values. A missing variable is treated as absent so a later operand can serve as its fallback. A missing variable with no later operand raises an error. |
| `(not a)` | Performs boolean negation. |
| `(if test then else)` | Conditional expression. Any expression is valid as the test; `nil` and numeric `0` are false. Only the selected branch is evaluated. |
| `(cond (test body ...) ...)` | Evaluates clauses in order and runs the body of the first truthy test. A `t` clause can serve as the fallback; returns `nil` when no clause matches. A test-only matching clause returns the test value. |
| `(when test body ...)` | Evaluates body expressions in order only when the test is true; returns the last result, or `nil` when false or with no body. |
| `(do expression ...)` | Evaluates expressions in order and returns the last result, or `nil` when empty. |
| `(let (name value ...) body ...)` | Evaluates alternating names and values in the outer environment, then evaluates the body in a local scope containing those bindings. Local names shadow outer values; returns `nil` with no body. |
| `(func (parameter ...) body ...)` | Creates a lexically scoped function. Call it with `((func (x) (+ $x 1)) 2)` or bind it with `let` and invoke it as `($function 2)`. |
| `(set (name value) ...)` | Evaluates and assigns bindings in order in the current environment. Returns `nil`. |
| `(concat a b ...)` | Concatenates values as strings. |
| `(join separator value ...)` | Joins values as strings using the required string separator. With no values, returns an empty string. |
| `(array value ...)` | Creates an array from the evaluated values. With no values, returns an empty array. |
| `(copy-to-clipboard value)` | Copies a value to the Windows clipboard and returns a `NoResult` marker instead of a printable value. |
| `(match text regex)` | Returns true when the regular expression matches the text (`RegExMatch`). |
| `(strip-prefix text prefix)` | Removes a matching prefix; otherwise returns the original string. |
| `(strip-suffix text suffix)` | Removes a matching suffix; otherwise returns the original string. |
| `(length value)` | String length, array length, or map entry count. |
| `(substr text start [length])` | Returns a substring using AutoHotkey's 1-based `SubStr` indexing; negative positions count from the end. |
| `(upper text)` | Converts a string to uppercase. |
| `(lower text)` | Converts a string to lowercase. |
| `(trim text [omit-characters])` | Trims the specified characters from both ends. By default, trims spaces, tabs, carriage returns, and line feeds. |
| `(replace text search replacement)` | Replaces all case-sensitive occurrences of a non-empty search string. |
| `(starts-with text prefix)` | Performs a case-sensitive prefix check. An empty prefix matches. |
| `(ends-with text suffix)` | Performs a case-sensitive suffix check. An empty suffix matches. |
| `(index-of text search)` | Returns the 1-based position of the first case-sensitive match, or `0` when not found. |
| `(get value key-or-path)` | Retrieves an environment or map key, native object property, or 1-based array index. Dot-separated paths traverse nested values. Missing values raise an error. |
| `(contains array value)` | Tests array membership. Also supports map keys and substring checks. |
| `(in array value)` | Alias for `contains`. |

There is no `boolean?` predicate because AutoHotkey stores `false`/`true` as the same integer values as `0`/`1`; those values satisfy the corresponding integer and number predicates.

Pass a `Map` directly as the environment. Nested collections remain ordinary AutoHotkey values:

```autohotkey
env := Map(
    "name", "Ada",
    "count", 0,
    "enabled", false,
    "user", Map("profile", Map("name", "Grace")),
    "items", ["tea", "coffee"]
)
lisp.Eval('(if $enabled "yes" $name)', env)
lisp.Eval("$user.profile.name", env)
lisp.Eval('(get $items 2)', env)
```

Use `array` to construct arrays in source. Both `get` and dotted symbol paths use AutoHotkey's 1-based array indexing:

```lisp
(let (items (array "tea" "coffee"))
  (concat $items.1 " and " (get $items 2)))
```

Use `set` to assign variables in the current environment:

```autohotkey
context := Map()
lisp.Eval('(set (name "Ada") (greeting (concat "Hello, " $name)))', context)
lisp.Eval('(concat $greeting "!")', context) ; "Hello, Ada!"
```

Bindings are evaluated and assigned sequentially, so each value can reference earlier assignments. A supplied Map or plain object is modified in place; without one, assignments last only for the current evaluation. Existing names are overwritten. Assignments made before an error remain in the environment. `let` and function bodies use local copies, so their assignments do not modify the outer environment. Values can be any AutoHotkey value, including nested maps and arrays.

Use `let` for temporary local bindings and `func` for functions that capture their surrounding values:

```lisp
(let (factor 3
      scale (func (value) (* $value $factor)))
  (scale 7))
```

`let` bindings are written as alternating names and value expressions without a separate pair of parentheses around every binding. Initializers are evaluated in the environment outside the new bindings. Lambda parameters and local bindings are referenced with `$`, just like environment variables.

Use `or` to look up an environment variable or nested path and optionally supply a fallback. The fallback is one expression:

```lisp
(or $name "guest")
(or $user.name "guest")
(or $count 0)
```

Without a fallback, a missing variable raises an error. In a larger expression, use `or` as an expression, for example `(concat "Hello, " (or $user.name "guest"))`.

When the fallback is `nil`, use the optional lookup shorthand:

```lisp
$?name              ; (or $name nil)
$?user.profile.name ; (or $user.profile.name nil)
```

Like `or`, this also returns `nil` for falsey values and for lookup errors such as a missing key or an invalid path through a scalar.

## Implementation

`Eval` is the only evaluation method exposed by an `Interpreter` instance. Its parser, evaluator, cache, and builtin registry are held in closures rather than a separately constructible engine class. Special forms (`if`, `cond`, `when`, `and`, `or`, `not`, `do`, `let`, `func`, `set`, and `get`) control evaluation directly; other operators are dispatched through the builtin registry. Interpreter failures use `EvaluationError`, with the failed expression available in its `expr` property when evaluation has begun.

<font color="red">**Important:** `copy-to-clipboard` returns an instance of `NoResult`, not a printable value. Check with `result is NoResult` before displaying an evaluation result.</font>

## Benchmarking

Run `.\measure-expressions.ps1 -Expression '(> 1 1)'` to measure repeated evaluations of the supplied Lisp expression. Use `-Iterations` and `-Rounds` to adjust the workload. AutoHotkey v2 must be installed or provided with `-AutoHotkeyPath`.
