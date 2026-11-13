; External regression tests for Interpreter.ahk (AutoHotkey v2).
; Results are written to the path passed by run-tests.ps1 as:
; STATUS|CASE NAME|DETAILS
#Include Interpreter.ahk

mainInterpreter := Interpreter()
cachedInterpreter := Interpreter()
boundedCachedInterpreter := Interpreter(1)
uncachedInterpreter := Interpreter(0)
resultsPath := A_Args.Length ? A_Args[1] : EnvGet("INTERPRETER_TEST_RESULTS")
failedTests := 0

RecordResult(status, caseName, details := "") {
    global resultsPath
    global failedTests
    if (resultsPath = "")
        throw Error("Missing test-results path argument. Run this script through run-tests.ps1.")

    if (status = "FAIL")
        failedTests += 1

    ; Keep each result on one line and preserve the pipe-delimited format.
    caseName := StrReplace(caseName, "|", "-")
    details := StrReplace(details, "|", "-")
    details := StrReplace(details, "`r", " ")
    details := StrReplace(details, "`n", " ")
    FileAppend(status "|" caseName "|" details "`n", resultsPath, "UTF-8")
}

AssertEvaluationCause(caseName, source) {
    global mainInterpreter
    try {
        mainInterpreter.Eval(source)
        RecordResult("FAIL", caseName, "Expected an EvaluationError")
    } catch as err {
        if !(err is EvaluationError) || !err.HasOwnProp("cause")
            RecordResult("FAIL", caseName, "Expected EvaluationError to preserve the original cause")
        else
            RecordResult("PASS", caseName)
    }
}

AssertEval(caseName, source, expected, env := 0, evaluator := 0) {
    global mainInterpreter
    if !IsObject(evaluator)
        evaluator := mainInterpreter
    try {
        actual := evaluator.Eval(source, env)
        if (actual != expected)
            throw Error("expected " expected " but got " actual)
        RecordResult("PASS", caseName)
    } catch as err {
        RecordResult("FAIL", caseName, err.Message)
    }
}

AssertMakeEnv(caseName) {
    global mainInterpreter
    try {
        initialEnv := Map("prefix", "Hello, ")
        variables := mainInterpreter.Eval(
            '(make-env (name "Ada") (greeting (concat $prefix $name)) (ready (> 2 1)))',
            initialEnv)
        if !(variables is Map) || variables.Count != 3
            throw Error("expected a map containing three declared variables")
        if (variables["name"] != "Ada" || variables["greeting"] != "Hello, Ada" || variables["ready"] != true)
            throw Error("expected declared values and earlier bindings to be available")
        if (mainInterpreter.Eval('(concat $greeting "!")', variables) != "Hello, Ada!")
            throw Error("expected returned variables to be usable in a later Eval call")
        if initialEnv.Has("name") || initialEnv.Has("greeting")
            throw Error("expected the original environment to remain unchanged")

        objectEnv := {prefix: "Hi, "}
        objectVariables := mainInterpreter.Eval('(make-env (greeting (concat $prefix "Ada")))', objectEnv)
        if (objectVariables["greeting"] != "Hi, Ada")
            throw Error("expected object environment properties to be visible")

        arrayVariables := mainInterpreter.Eval(
            ["make-env", ["name", "Ada"], ["greeting", ['(concat "Hi, " $name)']]])
        if (arrayVariables["greeting"] != "Hi, Ada")
            throw Error("expected expression arrays to support sequential bindings")
        RecordResult("PASS", caseName)
    } catch as err {
        RecordResult("FAIL", caseName, err.Message)
    }
}

AssertEvalCache(caseName) {
    global cachedInterpreter
    try {
        first := cachedInterpreter.Eval('(concat $value "!")', Map("value", "Ada"))
        second := cachedInterpreter.Eval('(concat $value "!")', Map("value", "Grace"))
        if (first != "Ada!" || second != "Grace!")
            throw Error("expected environment-specific results Ada! and Grace!")
        if (cachedInterpreter.expressionCache.Count != 1)
            throw Error("expected parsed expression to be cached once")

        nestedInterpreter := Interpreter()
        nested := ["concat", ['(concat $value "!")']]
        first := nestedInterpreter.Eval(nested, Map("value", "Ada"))
        second := nestedInterpreter.Eval(nested, Map("value", "Grace"))
        direct := nestedInterpreter.Eval('(concat $value "!")', Map("value", "Lin"))
        if (first != "Ada!" || second != "Grace!" || direct != "Lin!")
            throw Error("expected nested and direct source forms to reevaluate with their environments")
        if (nestedInterpreter.expressionCache.Count != 1)
            throw Error("expected nested and direct source forms to share one cached parse")
        RecordResult("PASS", caseName)
    } catch as err {
        RecordResult("FAIL", caseName, err.Message)
    }
}

AssertCacheConfiguration(caseName) {
    global mainInterpreter
    global boundedCachedInterpreter
    try {
        if (mainInterpreter.expressionCacheLimit != 256)
            throw Error("expected default cache size 256, got " mainInterpreter.expressionCacheLimit)
        boundedCachedInterpreter.Eval("(+ 1 2)")
        boundedCachedInterpreter.Eval("(* 2 3)")
        boundedCachedInterpreter.Eval("(+ 1 2)")
        if (boundedCachedInterpreter.expressionCache.Count != 1 || boundedCachedInterpreter.expressionCache.Has("(* 2 3)"))
            throw Error("expected size-one cache to evict the older expression")
        uncachedInterpreter.Eval("(+ 1 2)")
        uncachedInterpreter.Eval(["concat", "(+ 1 2)"])
        if (uncachedInterpreter.expressionCache.Count != 0)
            throw Error("expected zero-size cache to remain empty")
        try {
            Interpreter(-1)
            throw Error("expected negative cache size to be rejected")
        } catch as err {
            if !InStr(err.Message, "non-negative integer")
                throw err
        }
        try {
            Interpreter("invalid")
            throw Error("expected non-numeric cache size to be rejected")
        } catch as err {
            if !InStr(err.Message, "non-negative integer")
                throw err
        }
        try {
            Interpreter(1.5)
            throw Error("expected fractional cache size to be rejected")
        } catch as err {
            if !InStr(err.Message, "non-negative integer")
                throw err
        }
        RecordResult("PASS", caseName)
    } catch as err {
        RecordResult("FAIL", caseName, err.Message)
    }
}

AssertThrows(caseName, source, expectedMessage, env := 0) {
    global mainInterpreter
    threw := false
    try {
        mainInterpreter.Eval(source, env)
    } catch as err {
        threw := true
        if !(err is EvaluationError)
            RecordResult("FAIL", caseName, "Expected EvaluationError, got " Type(err))
        else if InStr(err.Message, expectedMessage)
            RecordResult("PASS", caseName)
        else
            RecordResult("FAIL", caseName, "Expected EvaluationError containing '" expectedMessage "' but got '" err.Message "'")
    }
    if !threw
        RecordResult("FAIL", caseName, "Expected an error containing: " expectedMessage)
}

AssertReaderThrows(caseName, state, expectedMessage) {
    global mainInterpreter
    try {
        mainInterpreter._ReadExpression(state)
        RecordResult("FAIL", caseName, "Expected an error containing: " expectedMessage)
    } catch as err {
        if InStr(err.Message, expectedMessage)
            RecordResult("PASS", caseName)
        else
            RecordResult("FAIL", caseName, "Expected error containing '" expectedMessage "' but got '" err.Message "'")
    }
}

AssertGetOneThrows(caseName, target, key, expectedMessage) {
    global mainInterpreter
    try {
        mainInterpreter._GetOne(target, key)
        RecordResult("FAIL", caseName, "Expected an error containing: " expectedMessage)
    } catch as err {
        if InStr(err.Message, expectedMessage)
            RecordResult("PASS", caseName)
        else
            RecordResult("FAIL", caseName, "Expected error containing '" expectedMessage "' but got '" err.Message "'")
    }
}

AssertObjectPassthrough(caseName) {
    global mainInterpreter
    value := {name: "Ada"}
    actual := mainInterpreter._Evaluate(value, Map())
    if IsObject(actual) && actual.HasOwnProp("name") && actual.name = "Ada"
        RecordResult("PASS", caseName)
    else
        RecordResult("FAIL", caseName, "Expected evaluation to return the same plain object")
}

AssertClipboard(caseName, expected) {
    if (A_Clipboard = expected)
        RecordResult("PASS", caseName)
    else
        RecordResult("FAIL", caseName, "Expected clipboard to contain '" expected "'")
}

AssertNoResult(caseName, source) {
    global mainInterpreter
    try {
        actual := mainInterpreter.Eval(source)
        if (actual is NoResult)
            RecordResult("PASS", caseName)
        else
            RecordResult("FAIL", caseName, "Expected NoResult, got " (IsObject(actual) ? Type(actual) : "a value"))
    } catch as err {
        RecordResult("FAIL", caseName, err.Message)
    }
}

AssertEvaluationError(caseName, source, expectedOperator) {
    global mainInterpreter
    try {
        mainInterpreter.Eval(source)
        RecordResult("FAIL", caseName, "Expected EvaluationError")
    } catch as err {
        if !(err is EvaluationError) {
            RecordResult("FAIL", caseName, "Expected EvaluationError, got " Type(err))
            return
        }
        if !err.HasOwnProp("expr") || !(err.expr is SyntaxForm) {
            RecordResult("FAIL", caseName, "Expected EvaluationError.expr to contain the failed form")
            return
        }
        head := err.expr.items.Length ? err.expr.items[1] : ""
        if (err.expr.items.Length = 0) || ((head is String) ? (head != expectedOperator) : (!(head is Object) || !head.HasOwnProp("symbol") || head.symbol != expectedOperator)) {
            RecordResult("FAIL", caseName, "Expected failed expression headed by " expectedOperator)
            return
        }
        RecordResult("PASS", caseName)
    }
}

AssertEvaluationPosition(caseName, source, expectedPosition, expectedLine, expectedColumn) {
    global mainInterpreter
    try {
        mainInterpreter.Eval(source)
        RecordResult("FAIL", caseName, "Expected EvaluationError with source position")
    } catch as err {
        if !(err is EvaluationError) {
            RecordResult("FAIL", caseName, "Expected EvaluationError, got " Type(err))
            return
        }
        if !err.HasOwnProp("position") || err.position != expectedPosition
            || err.sourceLine != expectedLine || err.sourceColumn != expectedColumn {
            RecordResult("FAIL", caseName, "Expected position " expectedPosition " at line " expectedLine
                ", column " expectedColumn ", got " (err.HasOwnProp("position") ? err.position : "none")
                " at line " (err.HasOwnProp("sourceLine") ? err.sourceLine : "none")
                ", column " (err.HasOwnProp("sourceColumn") ? err.sourceColumn : "none"))
            return
        }
        RecordResult("PASS", caseName)
    }
}

; Arithmetic.
AssertThrows("Empty source reports end of input", "", "Unexpected end of input")
AssertThrows("Whitespace-only source reports end of input", " `t`r`n", "Unexpected end of input")
AssertEvaluationPosition("Runtime error reports exact source coordinates", "(`r`n  concat $missing `"x`")", 13, 2, 10)
AssertEvaluationPosition("Trailing input reports its exact source position", "(+ 1 2) 3", 9, 1, 9)
AssertEvaluationPosition("Missing delimiter reports end-of-input position", "(+ 1`n  2", 9, 2, 4)
AssertEval("Empty form evaluates to an empty string", "()", "")
AssertObjectPassthrough("Evaluation passes through plain objects")
AssertEval("Integer atom", "42", 42)
AssertEval("Decimal atom", "-.5", -0.5)
AssertEval("Exponent atom", "1.25e2", 125)
AssertEval("Self-evaluating string atom", '"hello"', "hello")
AssertEval("Self-evaluating number atom inside a form", "(+ 1 2)", 3)
AssertEval("Unprefixed atom is a string", "answer", "answer", Map("answer", 42))
AssertEval("Dollar-prefixed symbol resolves to clean environment key", "$answer", 42, Map("answer", 42))
AssertEval("Dollar-prefixed numeric af[tom is a symbol", "$42", "symbol value", Map("42", "symbol value"))
AssertEval("Unprefixed dotted atom is a string", "user.name", "user.name", Map("user", Map("name", "Grace")))
AssertEval("Path symbol traverses one nested map level", "$user.name", "Grace", Map("user", Map("name", "Grace")))
AssertEval("Path symbol traverses multiple nested map levels", "$user.profile.name", "Ada", Map("user", Map("profile", Map("name", "Ada"))))
AssertEval("Single quotes are ordinary atom characters", "'hello'", "'hello'")
AssertEval("Empty string literal", '""', "")
AssertEval("Backtick-delimited string literal", Chr(96) . "hello world" . Chr(96), "hello world")
AssertEval("Empty backtick-delimited string", Chr(96) . Chr(96), "")
AssertEval("Backtick-delimited string includes double quotes", Chr(96) . "say " . Chr(34) . "hello" . Chr(34) . Chr(96), 'say "hello"')
AssertEval("Doubled backtick in backtick-delimited string", Chr(96) . "a" . Chr(96) . Chr(96) . "b" . Chr(96), "a" . Chr(96) . "b")
AssertEval("Backtick escapes in strings", '"a`nb`rc`t"', "a`nb`rc`t")
AssertEval("Unknown backtick escape drops the escape marker", '"a`xb"', "axb")
AssertEval("Doubled quote in string", '"say ""hello"""', 'say "hello"')
AssertThrows("Unterminated string reports an error", '"unterminated', "Unterminated string literal")
AssertThrows("Unterminated trailing backtick reports an error", '"trailing' Chr(96), "Unterminated string literal")
AssertThrows("Unterminated backtick-delimited string reports an error", Chr(96) . "unterminated", "Unterminated string literal")
AssertThrows("Missing closing parenthesis reports an error", "(+ 1 2", "Missing closing delimiter")
AssertThrows("Trailing expression reports an error", "1 2", "Unexpected input after expression")
AssertThrows("Closing parenthesis outside a form reports delimiter error", ")", "Unexpected delimiter")
AssertThrows("Closing bracket outside a form reports delimiter error", "]", "Unexpected delimiter")
AssertThrows("Opening bracket reports delimiter error", "[", "Unexpected delimiter")
AssertThrows("Opening brace reports delimiter error", "{", "Unexpected delimiter")
AssertThrows("Closing brace reports delimiter error", "}", "Unexpected delimiter")
AssertReaderThrows("Reader rejects unexpected token kinds", {tokens: [{kind: "invalid"}], index: 1}, "Invalid token")
AssertReaderThrows("Reader rejects exhausted input", {tokens: [], index: 1}, "Unexpected end of input")
AssertThrows("Unknown operator reports its name", "(unknown 1)", "Unknown operator: unknown")
AssertThrows("Numeric list head is not callable", "(+ 1 (2))", "Operator must be a string")
AssertEval("Addition with multiple arguments", "(+ 1 2 3)", 6)
AssertEval("Subtraction with multiple arguments", "(- 5 2)", 3)
AssertEval("Unary subtraction", "(- 5)", -5)
AssertEval("Multiplication", "(* 2 3 4)", 24)
AssertEval("Division", "(/ 8 2)", 4)
AssertEval("Modulo", "(% 7 4)", 3)
AssertEval("Common Lisp t literal is true", "t", true)
AssertEval("Common Lisp nil literal is false", "nil", false)
AssertEval("Common Lisp nil is false in conditions", "(if nil 1 0)", 0)
AssertEval("True spelling is a string value", '(= true "true")', true, Map("true", "provided"))
AssertThrows("Division by zero reports an error", "(/ 1 0)", "Division by zero")
AssertThrows("Addition requires at least one argument", "(+)", "expects at least 1")
AssertThrows("Subtraction requires an argument", "(-)", "expects at least 1")
AssertThrows("Multiplication requires an argument", "(*)", "expects at least 1")
AssertThrows("Division requires two arguments", "(/ 1)", "expects at least 2")
AssertThrows("Numeric operator rejects non-numbers", '(+ "one")', "Expected a number")
AssertEval("False spelling is a string value", '(= false "false")', true, Map("false", "provided"))
AssertThrows("Eval rejects non-string expression array head", [2, 1], "operator string")
AssertThrows("Eval rejects numeric expression array head", ["2", 1], "symbol, not a number")
AssertEval("Eval tokenizes a single-string expression array", ["(+ 1 2)"], 3)
AssertEval("Eval accepts an unparenthesized single-string expression array", ["+ 1 2"], 3)
AssertEval("Nested single-string expression array parses Lisp source", ["if", ["> 1 1"], "foo", "bar"], "bar")
AssertEval("Nested single-string expression array parses atom source", ["concat", ["hello"]], "hello")
AssertEvaluationCause("EvaluationError preserves a native exception cause", '(match "x" "[")')

; Comparisons and aliases.
AssertEval("Equality operator", "(= 2 2)", true)
AssertEval("Equality operator unequal values", "(= 2 3)", false)
AssertEval("Equality alias", "(== 2 2)", true)
AssertEval("Inequality operator", "(!= 2 3)", true)
AssertEval("Inequality operator equal values", "(!= 2 2)", false)
AssertEval("Inequality alias", "(<> 2 3)", true)
AssertEval("Less-than comparison", "(< 1 2)", true)
AssertEval("Less-than false result", "(< 2 1)", false)
AssertEval("Less-than-or-equal comparison", "(<= 2 2)", true)
AssertEval("Less-than-or-equal below", "(<= 1 2)", true)
AssertEval("Less-than-or-equal false result", "(<= 3 2)", false)
AssertEval("Greater-than comparison", "(> 3 2)", true)
AssertEval("Greater-than false result", "(> 2 3)", false)
AssertEval("Greater-than-or-equal comparison", "(>= 3 3)", true)
AssertEval("Greater-than-or-equal above", "(>= 3 2)", true)
AssertEval("Greater-than-or-equal false result", "(>= 1 2)", false)
AssertThrows("Comparison validates argument count", "(= 1)", "expects 2 argument")
AssertThrows("Not-equal validates argument count", "(!= 1)", "expects 2 argument")
AssertThrows("Less-than validates argument count", "(< 1)", "expects 2 argument")
AssertThrows("Less-than-or-equal validates argument count", "(<= 1)", "expects 2 argument")
AssertThrows("Greater-than validates argument count", "(> 1)", "expects 2 argument")
AssertThrows("Greater-than-or-equal validates argument count", "(>= 1)", "expects 2 argument")
AssertThrows("Computed operator head is evaluated", '((if t "unknown" "unknown") 1)', "Unknown operator: unknown")

; String and collection builtins.
collectionEnv := Map("items", [10, 20], "numbers", [1, 2, 3], "lookup", Map("a", 1, "b", 2))
AssertEval("Concatenate strings", '(concat "hello" " " "world")', "hello world")
AssertEval("Concatenate with no arguments", "(concat)", "")
AssertEval("Join strings with a separator", '(join ", " "red" "green" "blue")', "red, green, blue")
AssertEval("Join evaluates nested forms as values", '(join "-" "a" (concat "b" "c") "d")', "a-bc-d")
AssertEval("Join with no values returns an empty string", '(join ", ")', "")
AssertEval("Join accepts an empty separator", '(join "" "a" "b")', "ab")
AssertThrows("Join requires a separator", "(join)", "expects at least 1")
AssertThrows("Join requires a string separator", '(join 1 "a")', "string separator")
AssertEval("String length", '(length "abc")', 3)
AssertEval("Number length uses string conversion", "(length 123)", 3)
AssertEval("Array length from environment", "(length $items)", 2, collectionEnv)
AssertEval("Map length from environment", "(length $lookup)", 2, collectionEnv)
AssertEval("Substring from one-based position", '(substr "hello" 2)', "ello")
AssertEval("Substring with length", '(substr "hello" 2 3)', "ell")
AssertEval("Substring with negative position", '(substr "hello" -2)', "lo")
AssertEval("Substring with negative length", '(substr "hello" 2 -1)', "ell")
AssertThrows("Substring rejects fractional position", '(substr "hello" 1.5)', "start to be an integer")
AssertEval("Uppercase string", '(upper "Hello")', "HELLO")
AssertEval("Lowercase string", '(lower "Hello")', "hello")
AssertEval("Trim whitespace from both sides", '(trim "  hello `t")', "hello")
AssertEval("Trim selected characters", '(trim "xxhellox" "x")', "hello")
AssertEval("Replace all exact matches", '(replace "one ONE one" "one" "two")', "two ONE two")
AssertThrows("Replace rejects an empty search string", '(replace "hello" "" "x")', "non-empty search")
AssertEval("Starts-with exact prefix", '(starts-with "hello" "he")', true)
AssertEval("Starts-with is case-sensitive", '(starts-with "hello" "He")', false)
AssertEval("Ends-with exact suffix", '(ends-with "hello" "lo")', true)
AssertEval("Empty suffix matches", '(ends-with "hello" "")', true)
AssertEval("Index-of returns one-based position", '(index-of "hello" "ll")', 3)
AssertEval("Index-of is case-sensitive", '(index-of "hello" "LL")', 0)
; Backslashes are literal in this AHK string; use one to pass the regex digit class \d.
AssertEval("Regular-expression match", '(match "abc123" "^abc\d+$")', true)
AssertEval("Strip matching prefix", '(strip-prefix "prefix-value" "prefix-")', "value")
AssertEval("Strip matching suffix", '(strip-suffix "value-suffix" "-suffix")', "value")
AssertEval("Array contains value from environment", "(contains $numbers 2)", true, collectionEnv)
AssertEval("Map contains key from environment", '(contains $lookup "a")', true, collectionEnv)
AssertEval("String contains substring", '(contains "hello" "ell")', true)
AssertEval("Membership alias on environment value", "(in $numbers 3)", true, collectionEnv)
AssertThrows("Contains rejects unsupported values", "(contains 42 1)", "contains expects")
AssertEval("Array does not contain value", "(contains $numbers 99)", false, collectionEnv)
AssertEval("Map does not contain key", '(contains $lookup "missing")', false, collectionEnv)
AssertEval("String does not contain substring", '(contains "hello" "xyz")', false)
AssertThrows("Lisp dialect rejects array literals", "[1 2]", "Unexpected delimiter")
AssertThrows("Lisp dialect rejects map literals", '{"a" 1}', "Unexpected delimiter")
AssertEval("Strip-prefix leaves unmatched text unchanged", '(strip-prefix "value" "prefix")', "value")
AssertEval("Strip-suffix leaves unmatched text unchanged", '(strip-suffix "value" "-suffix")', "value")
AssertEval("Strip-suffix with empty suffix is unchanged", '(strip-suffix "value" "")', "value")
AssertEval("Regex mismatch returns false", '(match "abc" "^z")', false)
AssertThrows("Modulo validates argument count", "(% 1)", "expects 2 argument")
AssertThrows("Match validates argument count", '(match "x")', "expects 2 argument")
AssertThrows("Strip-prefix validates argument count", '(strip-prefix "x")', "expects 2 argument")
AssertThrows("Strip-suffix validates argument count", '(strip-suffix "x")', "expects 2 argument")
AssertThrows("Length validates argument count", "(length)", "expects 1 argument")
AssertEval("Get map key", '(get $lookup "a")', 1, collectionEnv)
AssertEval("Get nested map path", '(get $lookup "b")', 2, collectionEnv)
AssertEval("Get array index", '(get $items 2)', 20, collectionEnv)
AssertEval("Get nested map path", '(get $record "user.profile.name")', "Ada", Map("record", Map("user", Map("profile", Map("name", "Ada")))))
AssertEval("Get native object property", '(get $profile "name")', "Ada", Map("profile", {name: "Ada"}))
AssertEval("Get nested object property", '(get $profile "user.name")', "Grace", Map("profile", {user: {name: "Grace"}}))
AssertThrows("Get validates argument count", '(get lookup)', "expects a value")
AssertThrows("Get rejects missing map key", '(get $lookup "missing")', "Missing map key", collectionEnv)
AssertThrows("Get rejects out-of-range array index", '(get $items 3)', "Array index out of range", collectionEnv)
AssertThrows("Get rejects array index below one", '(get $items 0)', "Array index out of range", collectionEnv)
AssertGetOneThrows("Get rejects fractional array index", [10, 20], "1.5", "Array index out of range")
AssertThrows("Get rejects missing object property", '(get $profile "missing")', "Missing object property", Map("profile", {name: "Ada"}))
AssertThrows("Get rejects scalar target", '(get 1 "key")', "non-object value")
AssertNoResult("Copy-to-clipboard returns NoResult", '(copy-to-clipboard "clipboard test")')
AssertClipboard("Copy-to-clipboard updates clipboard", "clipboard test")
AssertThrows("Copy-to-clipboard requires one argument", "(copy-to-clipboard)", "expects 1 argument")
AssertEval("Eval preserves single-quote characters in array strings", ["concat", "'foo'"], "'foo'")
AssertEval("Eval executes nested expression arrays", ["+", 1, ["*", 2, 3]], 7)
AssertEval("Eval treats expression array strings as values", ["concat", "foo", "bar"], "foobar")
AssertEval("Eval executes boolean operations in arrays", ["and", Interpreter.True, ["not", Interpreter.False]], true)
AssertEval("Eval executes conditional expression arrays", ["if", ["=", 2, 2], "yes", "no"], "yes")
AssertEvaluationError("EvaluationError contains the failed form", "(length)", "length")
AssertEvaluationError("Nested EvaluationError contains the failing subexpression", '(concat "prefix" (length))', "length")

; Variable lookups and fallbacks.
AssertEval("If selects true branch", "(if t 1 2)", 1)
AssertEval("If selects false branch", "(if nil 1 2)", 2)
AssertEval("If accepts a true comparison condition", "(if (= 2 2) 1 2)", 1)
AssertEval("If accepts a false comparison condition", "(if (= 2 3) 1 2)", 2)
AssertEval("If accepts an and condition", "(if (and t (> 3 2)) 1 2)", 1)
AssertEval("If accepts an or condition", "(if (or nil (= 2 2)) 1 2)", 1)
AssertEval("If accepts a not condition", "(if (not nil) 1 2)", 1)
AssertEval("If accepts a symbol condition", "(if $enabled 1 2)", 1, Map("enabled", true))
AssertEval("If accepts nil condition in expression array", ["if", Interpreter.False, 1, 2], 2)
AssertEval("If accepts true condition in expression array", ["if", Interpreter.True, 1, 2], 1)
AssertEval("False boolean is false in conditions", "(if (= 2 3) 1 2)", 2)
AssertEval("If coerces zero to false", "(if 0 1 2)", 2)
AssertEval("If coerces one to true", "(if 1 1 2)", 1)
AssertEval("If accepts empty string literal condition", '(if "" 1 2)', 1)
AssertEval("If accepts non-empty string literal condition", '(if "yes" 1 2)', 1)
AssertEval("If coerces zero from environment to false", "(if $value 1 2)", 2, Map("value", 0))
AssertEval("If coerces one from environment to true", "(if $value 1 2)", 1, Map("value", 1))
AssertEval("If treats explicit nil from environment as false", "(if $value 1 2)", 2, Map("value", Interpreter.False))
AssertEval("If treats explicit true from environment as true", "(if $value 1 2)", 1, Map("value", Interpreter.True))
AssertEval("If coerces zero returned by a form to false", "(if (- 1 1) 1 2)", 2)
AssertEval("If treats empty string returned by a form as true", '(if (concat "") 1 2)', 1)
AssertThrows("If requires three arguments", "(if t 1)", "expects 4 argument")
AssertEval("And with no operands is true", "(and)", true)
AssertEval("And returns the original last operand", "(and t 1)", 1)
AssertEval("And returns the original false operand", "(and t 0)", 0)
AssertEval("And preserves numeric operand values", "(+ (and t 1) 2)", 3)
AssertEval("And short-circuits on false", "(and nil missing)", false)
AssertEval("Or with no operands is false", "(or)", false)
AssertEval("Or returns false when all operands are nil", "(or nil nil)", false)
AssertEval("Or returns the original last false operand", "(or nil 0)", 0)
AssertEval("Or preserves numeric operand values", "(+ (or nil 0) 1)", 1)
AssertEval("Or returns its first truthy operand", '(or nil "value")', "value")
AssertEval("Not returns true for false", "(not nil)", true)
AssertEval("Not returns false for truthy value", "(not 1)", false)
AssertThrows("Not requires one argument", "(not t nil)", "expects 2 argument")
AssertThrows("coerceBoolean is not exposed as an operator", "(coerceBoolean 1)", "Unknown operator: coerceBoolean")
AssertMakeEnv("make-env returns sequential bindings for reuse")
AssertEval("make-env reads variables from the supplied context",
    '(get (make-env (greeting (concat $prefix "Ada"))) "greeting")',
    "Hello, Ada", Map("prefix", "Hello, "))
AssertEval("make-env without bindings returns an empty map", "(length (make-env))", 0)
AssertThrows("make-env rejects malformed bindings", '(make-env (name))', "each binding to contain")
AssertThrows("make-env rejects dotted variable names", '(make-env ("user.name" 1))', "cannot contain a dot")
lookupEnv := Map("name", "Ada", "user", Map("name", "Grace"), "count", 7)
AssertEval("or returns an existing variable value", "(or $name)", "Ada", lookupEnv)
AssertEval("or skips fallback for an existing variable", '(or $name "guest")', "Ada", lookupEnv)
AssertEval("or uses fallback for a missing variable", '(or $missing "guest")', "guest", lookupEnv)
AssertThrows("or reports a missing variable without fallback", "(or $missing)", "Variable is not present: missing")
AssertEval("or reads a nested map path", "(or $user.name)", "Grace", lookupEnv)
AssertEval("or reads deeper nested path", "(or $user.profile.name)", "Ada", Map("user", Map("profile", Map("name", "Ada"))))
AssertEval("or falls through for nil", '(or nil "guest")', "guest", lookupEnv)
AssertEval("or treats zero as false and uses fallback", '(or nil 0 "guest")', "guest", lookupEnv)
AssertEval("or evaluates non-symbol expressions", '(or (concat "guest"))', "guest")
AssertEval("or works inside a larger expression", '(concat "Hello, " (or $missing "guest"))', "Hello, guest", lookupEnv)
AssertThrows("or reports missing nested path without fallback", "(or $user.missing)", "Missing map key", lookupEnv)

; Native AutoHotkey object environments.
objectLookupEnv := {name: "Ada", user: {name: "Grace"}}
AssertEval("Path symbol traverses a nested object property", "$user.name", "Grace", objectLookupEnv)
AssertEval("or reads a variable from an AHK object", "(or $name)", "Ada", objectLookupEnv)
AssertEval("or reads a nested property from an AHK object", "(or $user.name)", "Grace", objectLookupEnv)
AssertEval("or uses fallback for a missing AHK object property", '(or $missing "guest")', "guest", objectLookupEnv)
AssertEvalCache("Parsed expression cache reuses syntax but reevaluates environment")
AssertCacheConfiguration("Cache size defaults to 256 and is configurable")

ExitApp(failedTests > 0 ? 1 : 0)
