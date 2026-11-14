# AutoHotkey v2 Lisp-like interpreter

A small embeddable interpreter implemented in AutoHotkey v2. The main implementation is `Interpreter.ahk`.

This interpreter is intended for reading and processing data supplied through its environment.

```autohotkey
#Requires AutoHotkey v2.0
#Include Interpreter.ahk

lisp := Interpreter()
env := Environment()
env.AddString("name", "Ada")
env.AddNumber("count", 3)
env.AddBoolean("enabled", true)

lisp.Eval('(if (and t (> 5 2)) (concat "hello" " world") "no")') ; "hello world"
lisp.Eval('(if $enabled $name "guest")', env) ; "Ada"
lisp.Eval('(+ $count 1)', env) ; 4

lisp.Eval('(copy-to-clipboard "hello")') ; copies and returns a NoResult marker

lisp.Eval(["+", 1, ["*", 2, 3]]) ; 7, evaluates the array directly
```

## Syntax

- Forms use Lisp syntax with parentheses: `(+ 1 2)`.
- A form's evaluated operator must be a string naming a registered operator; a number or other value in operator position is not callable.
<font color="red">**Important:** Source syntax does not construct arrays or maps. Pass collections through the environment and read them with `get`, `length`, `contains`, or `in`.</font>
- Each interpreter caches parsed forms for up to 256 distinct source expressions by default. Configure the limit with the constructor argument, such as `Interpreter(64)`; `0` disables caching. Repeated calls reuse parsed syntax but always reevaluate against the current environment.
- Strings can use double quotes or backticks as delimiters. Backtick escapes in double-quoted strings support `` `n``, `` `r``, and `` `t``; doubled delimiters represent a literal delimiter inside either string form.
- Atoms include numbers (including decimals and exponents), `t` (true), `nil` (false), strings, and symbols. Only atoms beginning with `$` are symbols; all other unquoted non-numeric atoms are string values. Use `""` for the empty string.
- Numbers, strings, `t`, and `nil` are self-evaluating; `$`-prefixed symbols are looked up in the evaluation environment. Dotted symbols traverse nested maps or object properties (for example, `$user.name`).
- `if` and `when` accept any valid expression as their condition. `nil` and numeric `0` are false; strings (including `""`) are true. `when` evaluates its body expressions in order only when the condition is true, returning the last result or `nil` when false or when there is no body. `and` and `or` short-circuit and return operand values.
- `Eval(sourceOrExpression, env)` accepts Lisp source text or a nested expression array, plus an optional `Environment`. In expression arrays, each non-empty array is a form: its first string is the operator and subsequent strings are literal values; nested arrays are nested forms. A one-element string array is parsed as Lisp source, including when nested in another expression array. A `Map` or native object environment is also accepted for passing collections.
- AutoHotkey represents `false` as numeric `0`, so use `env.AddBoolean` to preserve booleans in an `Environment`. For expression arrays or native environments, use `Interpreter.Boolean(false)` for explicit Lisp `nil` and `Interpreter.Boolean(true)` for Lisp `t`. `Interpreter.False` and `Interpreter.True` are also available. `Eval` converts Lisp booleans back to native booleans in its final result.
- Interpreter failures throw `EvaluationError` (defined in `Interpreter.ahk`), which extends AutoHotkey's `Error`. For source-string input, errors with a known location include 1-based `position`, `sourceLine`, and `sourceColumn` properties; the message also includes line and column. The failing expression is exposed as `expr` when available.

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
| `(and a b ...)` | Short-circuits and returns operand values. |
| `(or a b ...)` | Short-circuits and returns operand values. A missing variable is treated as absent so a later operand can serve as its fallback. A missing variable with no later operand raises an error. |
| `(not a)` | Performs boolean negation. |
| `(if test then else)` | Conditional expression. Any expression is valid as the test; `nil` and numeric `0` are false. Only the selected branch is evaluated. |
| `(when test body ...)` | Evaluates body expressions in order only when the test is true; returns the last result, or `nil` when false or with no body. |
| `(make-env (name value) ...)` | Evaluates bindings in order. Returns an `Environment` containing the declared variables; values must be booleans, numbers, or strings. |
| `(concat a b ...)` | Concatenates values as strings. |
| `(join separator value ...)` | Joins values as strings using the required string separator. With no values, returns an empty string. |
| `(copy-to-clipboard value)` | Copies a value to the Windows clipboard and returns a `NoResult` marker instead of a printable value. |
| `(match text regex)` | Returns true when the regular expression matches the text (`RegExMatch`). |
| `(strip-prefix text prefix)` | Removes a matching prefix; otherwise returns the original string. |
| `(strip-suffix text suffix)` | Removes a matching suffix; otherwise returns the original string. |
| `(length value)` | String length, array length, or map or environment entry count. |
| `(substr text start [length])` | Returns a substring using AutoHotkey's 1-based `SubStr` indexing; negative positions count from the end. |
| `(upper text)` | Converts a string to uppercase. |
| `(lower text)` | Converts a string to lowercase. |
| `(trim text [omit-characters])` | Trims the specified characters from both ends. By default, trims spaces, tabs, carriage returns, and line feeds. |
| `(replace text search replacement)` | Replaces all case-sensitive occurrences of a non-empty search string. |
| `(starts-with text prefix)` | Performs a case-sensitive prefix check. An empty prefix matches. |
| `(ends-with text suffix)` | Performs a case-sensitive suffix check. An empty suffix matches. |
| `(index-of text search)` | Returns the 1-based position of the first case-sensitive match, or `0` when not found. |
| `(get value key-or-path)` | Retrieves an environment or map key, native object property, or 1-based array index. Dot-separated paths traverse nested values. Missing values raise an error. |
| `(contains array value)` | Tests array membership. Also supports environment keys, map keys, and substring checks. |
| `(in array value)` | Alias for `contains`. |

Use an `Environment` to add typed variables and merge another environment:

```autohotkey
env := Environment()
env.AddString("name", "Ada")
env.AddNumber("count", 0)
env.AddBoolean("enabled", false)

other := Environment()
other.AddString("name", "Grace")
env.AddEnvironment(other) ; incoming names replace existing names
```

`AddBoolean` accepts AHK `true` or `false` (integers `1` and `0`); `AddNumber` accepts integers and floats, and `AddString` accepts strings. Names must be non-empty strings without dots, whitespace, delimiters, or quotes. `AddEnvironment` copies bindings and returns the destination; later changes to the source do not replace values in the destination. `Get(name)` returns the stored value, including tagged booleans, and throws `EvaluationError` if the name is missing. The backing map is held in closures and is not exposed.

Environments also support AutoHotkey's `for name, value in env` iteration protocol, which is used for merging and evaluation. Iteration exposes bindings, not the backing map.

`Environment()` starts empty. Both typed setters and `make-env` restrict values to booleans, numbers, and strings; `make-env` raises an `EvaluationError` for other values. `make-env` requires an `Environment` as its input context, even though other expressions can use native maps or objects.

A native environment can also be used to pass collections:

```autohotkey
env := Map("user", Map("name", "Ada"), "items", ["tea", "coffee"])
lisp.Eval('(get $user "name")', env)
lisp.Eval('(get $items 2)', env)
lisp.Eval('(or $user.name "guest")', env)
lisp.Eval('(contains $items "tea")', env)
```

Use `make-env` to compute an environment once and pass it to later calls or merge it into an existing environment:

```autohotkey
context := lisp.Eval('(make-env (name "Ada") (greeting (concat "Hello, " $name)))')
lisp.Eval('(concat $greeting "!")', context) ; "Hello, Ada!"
env := Environment()
env.AddEnvironment(context)
```

Bindings are evaluated sequentially, so each value can reference earlier names. When an input environment is supplied, its values are visible while computing the bindings, but are not copied into the returned environment or changed by `make-env`.

Use `or` to look up an environment variable or nested path and optionally supply a fallback. The fallback is one expression:

```lisp
(or $name "guest")
(or $user.name "guest")
(or $count 0)
```

Without a fallback, a missing variable raises an error. In a larger expression, use `or` as an expression, for example `(concat "Hello, " (or $user.name "guest"))`.

## Implementation

`Eval` is the only evaluation method exposed by an `Interpreter` instance. Its parser, evaluator, cache, and builtin registry are held in closures rather than a separately constructible engine class. Special forms (`if`, `and`, `or`, and `not`) control evaluation directly; other operators are dispatched through the builtin registry. Interpreter failures use `EvaluationError`, with the failed expression available in its `expr` property when evaluation has begun.

<font color="red">**Important:** `copy-to-clipboard` returns an instance of `NoResult`, not a printable value. Check with `result is NoResult` before displaying an evaluation result; this distinguishes the side-effect-only result from ordinary values such as `false` (the interpreter's `nil`).</font>

## Benchmarking

Run `.\measure-expressions.ps1 -Expression '(> 1 1)'` to measure repeated evaluations of the supplied Lisp expression. Use `-Iterations` and `-Rounds` to adjust the workload. AutoHotkey v2 must be installed or provided with `-AutoHotkeyPath`.
