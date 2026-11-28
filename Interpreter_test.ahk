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

AssertSet(caseName) {
    global mainInterpreter
    try {
        env := Map("prefix", "Hello, ", "name", "old")
        result := mainInterpreter.Eval(
            '(set (name "Ada") (greeting (concat $prefix $name)) (ready (> 2 1)))', env)
        if (result != false || env["name"] != "Ada" || env["greeting"] != "Hello, Ada"
            || !env["ready"] || env["prefix"] != "Hello, ")
            throw Error("expected sequential assignments to update the original Map")
        if (mainInterpreter.Eval('(concat $greeting "!")', env) != "Hello, Ada!")
            throw Error("expected assignments to be usable in a later Eval call")

        arrayEnv := Map()
        mainInterpreter.Eval(
            ["set", ["name", "Ada"], ["greeting", ['(concat "Hi, " $name)']]], arrayEnv)
        if (mainInterpreter.Eval("$greeting", arrayEnv) != "Hi, Ada")
            throw Error("expected expression arrays to support sequential bindings")
        data := Map("enabled", false, "items", [1, 2], "record", Map("name", "Ada"))
        mainInterpreter.Eval(["set", ["data", data]], arrayEnv)
        if (arrayEnv["data"] != data || arrayEnv["data"]["record"]["name"] != "Ada")
            throw Error("expected set to preserve nested Map and collection values")
        objectEnv := {prefix: "Hi, ", name: "old"}
        mainInterpreter.Eval('(set (name "Ada") (greeting (concat $prefix $name)))', objectEnv)
        if (objectEnv.name != "Ada" || objectEnv.greeting != "Hi, Ada")
            throw Error("expected assignments to update native object properties")
        localEnv := Map("name", "outer")
        if (mainInterpreter.Eval('(let (name "local") (set (name "updated")) $name)', localEnv) != "updated"
            || localEnv["name"] != "outer")
            throw Error("expected let assignments to remain in the local scope")
        if (mainInterpreter.Eval('(do (set (f (func () (set (name "inner")) $name))) ($f))', localEnv) != "inner"
            || localEnv["name"] != "outer")
            throw Error("expected function assignments to remain in the function scope")
        if (mainInterpreter.Eval('(do (set (first (set (nested 3)))) (+ $first $nested))') != 3)
            throw Error("expected nested set expressions to share the current scope")
        partialEnv := Map()
        failed := false
        try mainInterpreter.Eval("(set (first 1) (second $missing))", partialEnv)
        catch EvaluationError as err {
            failed := true
            if !partialEnv.Has("first") || partialEnv.Has("second")
                throw Error("expected earlier assignments to survive a later error")
        }
        if !failed
            throw Error("expected a later failing assignment to raise an error")
        RecordResult("PASS", caseName)
    } catch as err {
        RecordResult("FAIL", caseName, err.Message)
    }
}

AssertEnvironment(caseName) {
    global mainInterpreter
    try {
        data := Map("enabled", false, "count", 0, "name", "Ada",
            "record", Map("profile", Map("name", "Grace")), "items", ["tea", "coffee"])
        if (mainInterpreter.Eval('(if $enabled "yes" $name)', data) != "Ada"
            || mainInterpreter.Eval("(+ $count 1)", data) != 1
            || mainInterpreter.Eval("$record.profile.name", data) != "Grace"
            || mainInterpreter.Eval('(get $items 2)', data) != "coffee")
            throw Error("expected Map data and nested collections to be available to Eval")
        if (mainInterpreter.Eval("(if 0 1 2)") != 2
            || mainInterpreter.Eval("(if nil 1 2)") != 2
            || mainInterpreter.Eval("(if 1 1 2)") != 1
            || mainInterpreter.Eval("(if t 1 2)") != 1
            || mainInterpreter.Eval('(if "" 1 2)') != 2)
            throw Error("expected conditionals to use native AutoHotkey truthiness")
        if (mainInterpreter.Eval("(= nil 0)") != true
            || mainInterpreter.Eval("(= t 1)") != true)
            throw Error("expected booleans and numeric 0/1 to share AutoHotkey semantics")
        for expression in ["(= 2 2)", "(not 0)", '(starts-with "abc" "a")', '(match "x" "x")'] {
            if (Type(mainInterpreter.Eval(expression)) != "Integer")
                throw Error("expected boolean operators to return native AutoHotkey booleans")
        }
        RecordResult("PASS", caseName)
    } catch as err {
        RecordResult("FAIL", caseName, err.Message)
    }
}

AssertInterpreterFacade(caseName) {
    try {
        instance := Interpreter()
        for name, value in ObjOwnProps(instance) {
            if (name != "Eval")
                throw Error("unexpected interpreter member: " name)
        }
        for name in ["_Evaluate", "_CopyEnvironment", "_CreateEnvironment",
            "builtins", "expressionCache", "expressionCacheLimit"] {
            if HasProp(instance, name)
                throw Error("internal interpreter member exposed: " name)
        }
        if (instance.Eval("(+ 2 3)") != 5)
            throw Error("expected public Eval to evaluate expressions")
        RecordResult("PASS", caseName)
    } catch as err {
        RecordResult("FAIL", caseName, err.Message)
    }
}

CaptureFailedForm(instance, source) {
    try instance.Eval(source)
    catch EvaluationError as err {
        if err.HasOwnProp("expr") && (err.expr is SyntaxForm)
            return err.expr
        throw err
    }
    throw Error("expected evaluation to fail")
}

AssertEvalCache(caseName) {
    global cachedInterpreter
    try {
        first := cachedInterpreter.Eval('(concat $value "!")', Map("value", "Ada"))
        second := cachedInterpreter.Eval('(concat $value "!")', Map("value", "Grace"))
        if (first != "Ada!" || second != "Grace!")
            throw Error("expected environment-specific results Ada! and Grace!")
        if (CaptureFailedForm(cachedInterpreter, "(unknown-cache 1)")
            != CaptureFailedForm(cachedInterpreter, "(unknown-cache 1)"))
            throw Error("expected repeated source to reuse its parsed form")
        nestedInterpreter := Interpreter()
        nested := ["concat", ['(concat $value "!")']]
        first := nestedInterpreter.Eval(nested, Map("value", "Ada"))
        second := nestedInterpreter.Eval(nested, Map("value", "Grace"))
        direct := nestedInterpreter.Eval('(concat $value "!")', Map("value", "Lin"))
        if (first != "Ada!" || second != "Grace!" || direct != "Lin!")
            throw Error("expected nested and direct source forms to reevaluate with their environments")
        if (CaptureFailedForm(nestedInterpreter, ["concat", ["(unknown-cache 2)"]])
            != CaptureFailedForm(nestedInterpreter, "(unknown-cache 2)"))
            throw Error("expected nested and direct source forms to share a cached parse")
        RecordResult("PASS", caseName)
    } catch as err {
        RecordResult("FAIL", caseName, err.Message)
    }
}

AssertCacheConfiguration(caseName) {
    global boundedCachedInterpreter
    try {
        if (boundedCachedInterpreter.Eval("(+ 1 2)") != 3
            || boundedCachedInterpreter.Eval("(* 2 3)") != 6
            || boundedCachedInterpreter.Eval("(+ 1 2)") != 3
            || uncachedInterpreter.Eval("(+ 1 2)") != 3
            || uncachedInterpreter.Eval(["concat", "(+ 1 2)"]) != "3")
            throw Error("expected bounded and disabled caches to preserve evaluation")
        first := CaptureFailedForm(boundedCachedInterpreter, "(unknown-cache 1)")
        CaptureFailedForm(boundedCachedInterpreter, "(unknown-cache 2)")
        if (first == CaptureFailedForm(boundedCachedInterpreter, "(unknown-cache 1)"))
            throw Error("expected size-one cache to evict the earlier form")
        if (CaptureFailedForm(uncachedInterpreter, "(unknown-cache 1)")
            == CaptureFailedForm(uncachedInterpreter, "(unknown-cache 1)"))
            throw Error("expected zero-size cache to reparse the form")
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

AssertGetOneThrows(caseName, target, key, expectedMessage) {
    global mainInterpreter
    try {
        mainInterpreter.Eval('(get $target $key)', Map("target", target, "key", key))
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
    actual := mainInterpreter.Eval("$value", Map("value", value))
    if (actual == value)
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
        if !InStr(err.Message, "Expression: " source) {
            RecordResult("FAIL", caseName, "Expected error message to include the full source expression")
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
        if !InStr(err.Message, "line " expectedLine) || !InStr(err.Message, "column " expectedColumn) {
            RecordResult("FAIL", caseName, "Expected source line and column in error message")
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
AssertThrows("Reader rejects exhausted input", "", "Unexpected end of input")
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
AssertEval("Floor rounds negative numbers down", "(floor -1.2)", -2)
AssertEval("Ceil rounds negative numbers up", "(ceil -1.2)", -1)
AssertEval("Round defaults to integer", "(round 3.6)", 4)
AssertEval("Round supports decimal places and returns a number", '(number? (round 3.141 2))', true)
AssertEval("Round supports decimal places", "(round 3.141 2)", 3.14)
AssertEval("Round supports negative places", "(round 345 -1)", 350)
AssertEval("Absolute value", "(abs -2.5)", 2.5)
AssertEval("Square root", "(sqrt 16)", 4)
AssertEval("Power", "(pow 2 3)", 8)
AssertEval("Minimum accepts numeric strings", '(min 3 "1.5" -2)', -2)
AssertEval("Maximum", "(max -3 5 2)", 5)
AssertEval("Math operators work with expression arrays", ["floor", ["+", 1, 0.9]], 1)
AssertThrows("Floor requires one argument", "(floor)", "expects 1 argument")
AssertThrows("Ceil rejects non-numbers", '(ceil "x")', "Expected a number")
AssertThrows("Round requires integer precision", "(round 1 1.5)", "expects digits to be an integer")
AssertThrows("Round rejects excess arguments", "(round 1 2 3)", "expects 1 or 2")
AssertEvaluationCause("Square root rejects negative input", "(sqrt -1)")
AssertThrows("Power requires two arguments", "(pow 2)", "expects 2 argument")
AssertThrows("Minimum requires a number", "(min)", "expects at least 1")
AssertThrows("Maximum validates every number", '(max 2 "x")', "Expected a number")

; UTC date and time operators.
AssertEval("Now is an ISO UTC string", '(match (now) "^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")', true)
AssertEval("Now returns the current UTC time", '(<= (abs (- (unix-timestamp (now)) $epoch)) 5)', true,
    Map("epoch", DateDiff(A_NowUTC, "19700101000000", "Seconds")))
AssertEval("Unix epoch", '(unix-timestamp "1970-01-01T00:00:00Z")', 0)
AssertEval("Positive offset converts to UTC epoch", '(unix-timestamp "1970-01-01T02:30:00+02:30")', 0)
AssertEval("Negative offset converts to UTC epoch", '(unix-timestamp "1969-12-31T19:45:00-04:15")', 0)
AssertEval("Zero positive offset converts to UTC epoch", '(unix-timestamp "1970-01-01T00:00:00+00:00")', 0)
AssertEval("Zero negative offset converts to UTC epoch", '(unix-timestamp "1970-01-01T00:00:00-00:00")', 0)
AssertEval("Offset can cross UTC year boundary", '(date-add "2024-01-01T00:15:00+01:00" 0 seconds)', "2023-12-31T23:15:00Z")
AssertEval("Offset can cross UTC leap day", '(date-add "2024-02-28T23:30:00-01:00" 0 seconds)', "2024-02-29T00:30:00Z")
AssertEval("Fraction survives offset normalization", '(date-add "2024-01-01T00:15:00.001200+01:00" 0 seconds)', "2023-12-31T23:15:00.001200Z")
AssertEval("Fraction survives date addition across a second", '(date-add "2024-02-28T23:59:59.987654321Z" 1 seconds)', "2024-02-29T00:00:00.987654321Z")
AssertEval("Zero fraction retains its precision", '(date-add "1970-01-01T00:00:00.000Z" 0 seconds)', "1970-01-01T00:00:00.000Z")
AssertEval("Date difference compares normalized offsets", '(date-diff "2024-01-01T02:30:00+02:30" "2023-12-31T19:00:00-05:00" seconds)', 0)
AssertEval("Offset input supports expression arrays", ["unix-timestamp", "1970-01-01T05:45:00+05:45"], 0)
AssertEval("Date-only strings represent midnight UTC", '(unix-timestamp "1970-01-02")', 86400)
AssertEval("Unix timestamp before epoch", '(unix-timestamp "1969-12-31T23:59:59Z")', -1)
AssertEval("Unix timestamp floors fractions before epoch", '(unix-timestamp "1969-12-31T23:59:59.9Z")', -1)
AssertEval("Unix timestamp ignores fractional seconds", '(unix-timestamp "1970-01-01T00:00:00.5Z")', 0)
AssertEval("Unix timestamp leap day", '(unix-timestamp "2000-02-29T12:34:56Z")', 951827696)
AssertEval("Unix timestamp converts back to UTC", '(from-unix-timestamp 0)', "1970-01-01T00:00:00Z")
AssertEval("Negative Unix timestamp converts back to UTC", '(from-unix-timestamp -1)', "1969-12-31T23:59:59Z")
AssertEval("Unix timestamp lower boundary", '(from-unix-timestamp -11644473600)', "1601-01-01T00:00:00Z")
AssertEval("Unix timestamp upper boundary", '(from-unix-timestamp 253402300799)', "9999-12-31T23:59:59Z")
AssertEval("Unix timestamp lower boundary round trips", '(unix-timestamp (from-unix-timestamp -11644473600))', -11644473600)
AssertEval("Unix timestamp upper boundary round trips", '(unix-timestamp (from-unix-timestamp 253402300799))', 253402300799)
AssertEval("Date addition crosses leap day", '(date-add "2024-02-28T23:30:00Z" 1 hours)', "2024-02-29T00:30:00Z")
AssertEval("Date addition supports subtraction and singular unit", '(date-add "2024-03-01" -1 day)', "2024-02-29T00:00:00Z")
AssertEval("Date addition supports fractional units", '(date-add "1970-01-01" 0.5 minutes)', "1970-01-01T00:00:30Z")
AssertEval("Date difference is first minus second", '(date-diff "1970-01-02" "1970-01-01" days)', 1)
AssertEval("Date difference can be negative", '(date-diff "1970-01-01" "1970-01-02" seconds)', -86400)
AssertEval("Date difference returns whole units", '(date-diff "1970-01-01T01:59:00Z" "1970-01-01" hours)', 1)
AssertEval("Date difference accounts for fractions across seconds", '(date-diff "1970-01-01T00:00:01.1Z" "1970-01-01T00:00:00.2Z" seconds)', 0)
AssertEval("Negative date difference accounts for fractions", '(date-diff "1970-01-01T00:00:00.2Z" "1970-01-01T00:00:01.1Z" seconds)', 0)
AssertEval("Date difference accounts for fractions across units", '(date-diff "1970-01-01T01:00:00.1Z" "1970-01-01T00:00:00.2Z" hours)', 0)
AssertEval("Date difference compares arbitrary precision", '(date-diff "1970-01-01T00:00:01.10000000000000000001Z" "1970-01-01T00:00:00.10000000000000000002Z" seconds)', 0)
AssertEval("Date difference treats trailing fraction zeros equally", '(date-diff "1970-01-01T00:00:01.1Z" "1970-01-01T00:00:00.1000Z" seconds)', 1)
AssertEval("Date difference negative partial unit", '(date-diff "1970-01-01" "1970-01-01T01:59:00Z" hours)', DateDiff("19700101000000", "19700101015900", "hours"))
AssertEval("Format date uses AutoHotkey patterns", '(format-date "2024-02-29T13:04:05.123Z" "yyyy-MM-dd HH:mm:ss")', "2024-02-29 13:04:05")
AssertEval("Format date normalizes offsets", '(format-date "2024-01-01T00:15:00.5+01:00" "yyyy-MM-dd HH:mm:ss")', "2023-12-31 23:15:00")
AssertEval("Format date supports native standalone patterns", '(format-date "2024-02-29" "YDay0")', "060")
AssertEval("Format date supports native quoted literals", ["format-date", "2024-02-29T13:04:05Z", "yyyy-MM-dd 'at' HH:mm"], "2024-02-29 at 13:04")
AssertEval("Format date defaults to native format", '(format-date "2024-02-29")', FormatTime("20240229000000"))
AssertThrows("Format date requires a date", "(format-date)", "expects 1 or 2")
AssertThrows("Format date validates the date", '(format-date "2024-02-30" "yyyy")', "valid UTC date")
AssertThrows("Format date validates format type", '(format-date "2024-01-01" 42)', "expects format to be a string")
AssertThrows("Format date rejects oversized format", ["format-date", "2024-01-01", Format("{:2001}", "")], "exceeds 2000")
AssertEval("Date operators work with expression arrays", ["date-add", "1970-01-01", 1, "seconds"], "1970-01-01T00:00:01Z")
AssertThrows("Now takes no arguments", "(now 1)", "expects 0 argument")
AssertThrows("Date conversion rejects non-string", "(unix-timestamp 123)", "expects date to be a string")
AssertThrows("Date conversion rejects an empty date", '(unix-timestamp "")', "expects a UTC date")
AssertThrows("Date conversion rejects missing timezone", '(unix-timestamp "2024-01-01T00:00:00")', "expects a UTC date")
AssertThrows("Date conversion rejects an empty fraction", '(unix-timestamp "2024-01-01T00:00:00.Z")', "expects a UTC date")
AssertThrows("Date conversion rejects fraction without timezone", '(unix-timestamp "2024-01-01T00:00:00.5")', "expects a UTC date")
AssertThrows("Date conversion rejects malformed offset", '(unix-timestamp "2024-01-01T00:00:00+0200")', "expects a UTC date")
AssertThrows("Date conversion rejects invalid offset hours", '(unix-timestamp "2024-01-01T00:00:00+24:00")', "valid UTC offset")
AssertThrows("Date conversion rejects invalid offset minutes", '(unix-timestamp "2024-01-01T00:00:00-02:60")', "valid UTC offset")
AssertThrows("Offset normalization rejects UTC before supported range", '(unix-timestamp "1601-01-01T00:00:00+00:01")', "out of range")
AssertThrows("Offset normalization rejects UTC after supported range", '(unix-timestamp "9999-12-31T23:59:59-00:01")', "out of range")
AssertEval("Offset normalization reaches lower bound", '(unix-timestamp "1601-01-01T00:01:00+00:01")', -11644473600)
AssertEval("Offset normalization reaches upper bound", '(unix-timestamp "9999-12-31T23:58:59-00:01")', 253402300799)
AssertThrows("Date conversion rejects invalid leap day", '(unix-timestamp "2023-02-29")', "valid UTC date")
AssertThrows("Date conversion rejects invalid month", '(unix-timestamp "2024-13-01")', "valid UTC date")
AssertThrows("Date conversion rejects invalid clock time", '(unix-timestamp "2024-01-01T24:00:00Z")', "valid UTC date")
AssertThrows("Date conversion rejects unsupported early years", '(unix-timestamp "1600-12-31")', "valid UTC date")
AssertThrows("Unix timestamp rejects fractions", "(from-unix-timestamp 0.5)", "expects timestamp to be an integer")
AssertThrows("Unix timestamp rejects values below range", "(from-unix-timestamp -11644473601)", "out of range")
AssertThrows("Unix timestamp rejects values above range", "(from-unix-timestamp 253402300800)", "out of range")
AssertThrows("Date addition rejects invalid unit", '(date-add "2024-01-01" 1 months)', "expects seconds")
AssertThrows("Date addition rejects dates before supported range", '(date-add "1601-01-01" -1 seconds)', "out of range")
AssertThrows("Date addition rejects dates after supported range", '(date-add "9999-12-31T23:59:59Z" 1 seconds)', "out of range")
AssertThrows("Date difference validates both dates", '(date-diff "2024-01-01" "2024-02-30" days)', "valid UTC date")
AssertThrows("Date difference requires three arguments", '(date-diff "2024-01-01" "2024-01-02")', "expects 3 argument")
AssertEval("False spelling is a string value", '(= false "false")', true, Map("false", "provided"))
AssertThrows("Eval rejects non-string expression array head", [2, 1], "operator string")
AssertThrows("Eval rejects numeric expression array head", ["2", 1], "symbol, not a number")
AssertEval("Eval tokenizes a single-string expression array", ["(+ 1 2)"], 3)
AssertEval("Eval accepts an unparenthesized single-string expression array", ["+ 1 2"], 3)
AssertEval("Nested parenthesized strings parse for regular operators", ["+", "(+ 2 3)", 4], 9)
AssertEval("Nested single-string expression array parses Lisp source", ["if", ["> 1 1"], "foo", "bar"], "bar")
AssertEval("Nested parenthesized strings parse for special forms", ["if", "(= 2 2)", "yes", "no"], "yes")
AssertEval("Nested single-string expression array parses atom source", ["concat", ["hello"]], "hello")
AssertEvaluationCause("EvaluationError preserves a native exception cause", '(match "x" "[")')

; Comparisons and aliases.
AssertEval("Equality operator", "(= 2 2)", true)
AssertEval("Equality operator unequal values", "(= 2 3)", false)
AssertEval("Equality alias", "(== 2 2)", true)
AssertEval("Equality alias returns false for unequal values", "(== 2 3)", false)
AssertEval("Inequality operator", "(!= 2 3)", true)
AssertEval("Inequality operator equal values", "(!= 2 2)", false)
AssertEval("Inequality alias", "(<> 2 3)", true)
AssertEval("Inequality alias returns false for equal values", "(<> 2 2)", false)
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
AssertThrows("Equality alias validates argument count", "(== 1)", "expects 2 argument")
AssertThrows("Inequality alias validates argument count", "(<> 1)", "expects 2 argument")
AssertThrows("Less-than validates argument count", "(< 1)", "expects 2 argument")
AssertThrows("Less-than-or-equal validates argument count", "(<= 1)", "expects 2 argument")
AssertThrows("Greater-than validates argument count", "(> 1)", "expects 2 argument")
AssertThrows("Greater-than-or-equal validates argument count", "(>= 1)", "expects 2 argument")
AssertThrows("Computed operator head is evaluated", '((if t "unknown" "unknown") 1)', "Unknown operator: unknown")
AssertEval("Computed operator can select a registered operator", '((if t "+" "*") 2 3)', 5)

; String and collection builtins.
collectionEnv := Map("items", [10, 20], "numbers", [1, 2, 3], "lookup", Map("a", 1, "b", 2))
AssertEval("Concatenate strings", '(concat "hello" " " "world")', "hello world")
AssertEval("Concatenate with no arguments", "(concat)", "")
AssertEval("Join strings with a separator", '(join ", " "red" "green" "blue")', "red, green, blue")
AssertEval("Join evaluates nested forms as values", '(join "-" "a" (concat "b" "c") "d")', "a-bc-d")
AssertEval("Join with no values returns an empty string", '(join ", ")', "")
AssertEval("Join accepts an empty separator", '(join "" "a" "b")', "ab")
AssertEval("Array creates an empty array", "(length (array))", 0)
AssertEval("Array evaluates its values", '(get (array (+ 1 2) "second") 1)', 3)
AssertEval("Array values are available with get", '(get (array "first" "second") 2)', "second")
AssertEval("Array values are available with one-based symbol paths",
    '(let (arr (array "first" "second")) $arr.1)', "first")
AssertEval("Array symbol paths support arbitrary one-based indexes",
    '(let (arr (array "first" "second" "third" "fourth")) $arr.4)', "fourth")
AssertEval("Array symbol paths traverse nested values",
    '(let (arr (array $record)) $arr.1.name)', "Ada", Map("record", Map("name", "Ada")))
AssertThrows("Array symbol path rejects index zero",
    '(let (arr (array "first")) $arr.0)', "Array index out of range")
AssertThrows("Array symbol path rejects out-of-range index",
    '(let (arr (array "first")) $arr.2)', "Array index out of range")
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
AssertEval("Empty prefix matches", '(starts-with "hello" "")', true)
AssertEval("Ends-with exact suffix", '(ends-with "hello" "lo")', true)
AssertEval("Ends-with is case-sensitive", '(ends-with "hello" "LO")', false)
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
AssertEval("Membership alias supports map keys", '(in $lookup "a")', true, collectionEnv)
AssertEval("Membership alias supports substrings", '(in "hello" "xyz")', false)
AssertEval("Membership alias supports nested map keys", '(in $record "name")', true, Map("record", Map("name", "Ada")))
AssertThrows("Contains rejects unsupported values", "(contains 42 1)", "contains expects")
AssertEval("Array does not contain value", "(contains $numbers 99)", false, collectionEnv)
AssertEval("Map does not contain key", '(contains $lookup "missing")', false, collectionEnv)
AssertEval("String does not contain substring", '(contains "hello" "xyz")', false)
AssertEval("Map applies a single-parameter callback",
    '(get (map (array 1 2 3) (func (item) (* $item 10))) 3)', 30)
AssertEval("Map passes one-based index to two-parameter callbacks",
    '(get (map (array 10 20 30) (func (item index) (+ $item $index))) 3)', 33)
AssertEval("Map is read-only and preserves source values",
    '(let* (items (array 1 2 3) mapped (map $items (func (item) (+ $item 5))))'
    . ' (and (= (length $items) 3) (= (get $items 1) 1) (= (get $mapped 1) 6)))', true)
AssertEval("Filter keeps matching values",
    '(length (filter (array 1 2 3 4) (func (item) (= (% $item 2) 0))))', 2)
AssertEval("Filter supports index-aware predicate",
    '(get (filter (array 10 20 30) (func (item index) (= $index 2))) 1)', 20)
AssertEval("Filter is read-only and leaves source unchanged",
    '(let* (items (array 1 2 3) filtered (filter $items (func (item) (> $item 1))))'
    . ' (and (= (length $items) 3) (= (length $filtered) 2) (= (get $items 1) 1)))', true)
AssertEval("Reduce sums values with an explicit initial value",
    '(reduce (array 1 2 3) (func (acc item) (+ $acc $item)) 0)', 6)
AssertEval("Reduce sums values without an initial value",
    '(reduce (array 1 2 3) (func (acc item) (+ $acc $item)))', 6)
AssertEval("Reduce supports index-aware reducer",
    '(reduce (array 10 20 30) (func (acc item index) (+ $acc (* $item $index))) 0)', 140)
AssertEval("Distinct keeps first-seen values in order",
    '(let (items (distinct (array 3 1 3 2 1)))'
    . ' (and (= (length $items) 3) (= (get $items 1) 3) (= (get $items 2) 1) (= (get $items 3) 2)))', true)
AssertEval("Distinct is read-only and does not change source array",
    '(let* (items (array 1 1 2) unique (distinct $items))'
    . ' (and (= (length $items) 3) (= (length $unique) 2)))', true)
AssertThrows("Map validates source type", '(map "abc" (func (item) $item))', "expects array to be an array")
AssertThrows("Map validates callback arity", '(map (array 1) (func (a b c) $a))', "callback must accept 1 or 2")
AssertThrows("Filter validates source type", '(filter 42 (func (item) t))', "expects array to be an array")
AssertThrows("Filter validates callback arity", '(filter (array 1) (func (a b c) t))', "callback must accept 1 or 2")
AssertThrows("Reduce validates source type",
    '(reduce "abc" (func (acc item) (+ $acc $item)) 0)', "expects array to be an array")
AssertThrows("Reduce validates callback arity", '(reduce (array 1) (func (item) $item) 0)', "callback must accept 2 or 3")
AssertThrows("Reduce requires non-empty source without initial value",
    '(reduce (array) (func (acc item) (+ $acc $item)))', "non-empty array")
AssertThrows("Distinct validates source type", '(distinct 42)', "expects array to be an array")
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
AssertEval("Get traverses mixed map object and array paths", '(get $data "user.items.2")', "coffee",
    Map("data", Map("user", {items: ["tea", "coffee"]})))
AssertThrows("Get rejects missing empty map key", '(get $empty "missing")', "Missing map key", Map("empty", Map()))
AssertThrows("Get validates argument count", '(get lookup)', "expects a value")
AssertThrows("Get rejects missing map key", '(get $lookup "missing")', "Missing map key", collectionEnv)
AssertThrows("Get rejects out-of-range array index", '(get $items 3)', "Array index out of range", collectionEnv)
AssertThrows("Get rejects array index below one", '(get $items 0)', "Array index out of range", collectionEnv)
AssertGetOneThrows("Get rejects out-of-range array index", [10, 20], "3", "Array index out of range")
AssertThrows("Get rejects missing object property", '(get $profile "missing")', "Missing object property", Map("profile", {name: "Ada"}))
AssertThrows("Get rejects scalar target", '(get 1 "key")', "non-object value")
AssertNoResult("Copy-to-clipboard returns NoResult", '(copy-to-clipboard "clipboard test")')
AssertClipboard("Copy-to-clipboard updates clipboard", "clipboard test")
AssertThrows("Copy-to-clipboard requires one argument", "(copy-to-clipboard)", "expects 1 argument")
AssertEval("Eval preserves single-quote characters in array strings", ["concat", "'foo'"], "'foo'")
AssertEval("Eval executes nested expression arrays", ["+", 1, ["*", 2, 3]], 7)
AssertEval("Eval treats expression array strings as values", ["concat", "foo", "bar"], "foobar")
AssertEval("Eval executes boolean operations in arrays", ["and", true, ["not", false]], true)
AssertEval("Boolean values work directly in expression arrays", ["if", false, 1, 2], 2)
AssertEval("Boolean values work directly in maps", "(if $value 1 2)", 2, Map("value", false))
AssertEval("Eval executes conditional expression arrays", ["if", ["=", 2, 2], "yes", "no"], "yes")
AssertEvaluationError("EvaluationError contains the failed form", "(length)", "length")
AssertEvaluationError("Nested EvaluationError contains the failing subexpression", '(concat "prefix" (length))', "length")

; Variable lookups and fallbacks.
AssertEval("Cond selects the first matching clause", "(cond (nil 1) (t 2) (t 3))", 2)
AssertEval("Cond evaluates all forms in the selected clause", "(cond (t 1 2))", 2)
AssertEval("Cond returns a matching test without a body", "(cond (42))", 42)
AssertEval("Cond returns nil when no clause matches", "(cond (nil 1) (0 2))", false)
AssertEval("Cond skips later clauses after a match", "(cond (t 7) (t (/ 1 0)))", 7)
AssertEval("Cond evaluates nested expression arrays", ["cond", [false, "no"], [["=", 2, 2], ["concat", "yes"]]], "yes")
AssertEval("Cond parses source-string clauses in expression arrays", ["cond", "(t 1)"], 1)
AssertThrows("Cond rejects a clause without a test", "(cond ())", "expects each clause to contain a test")
AssertEval("Do evaluates every form and returns the last result", "(do 1 2 (+ 3 4))", 7)
AssertEval("Do without forms returns nil", "(do)", false)
AssertEval("Let evaluates bindings and runs its body in a local scope",
    "(let (x 2 y (+ 3 4)) (* $x $y))", 14)
AssertEval("Let evaluates bindings in expression arrays",
    ["let", ["x", 2, "y", ["+", 3, 4]], ["(* $x $y)"]], 14)
AssertEval("Expression-array let can bind and call a function",
    ["let", ["f", ["func", ["x"], ["(+ $x 1)"]]], ["$f", 4]], 5)
AssertEval("Let evaluates initializers in the outer scope",
    "(let (x 1 y $x) (+ $x $y))", 10, Map("x", 9))
AssertEval("Let bindings shadow outer values only in their body",
    "(do (let (x 2) $x) $x)", 1, Map("x", 1))
AssertEval("Let with no body returns nil", "(let ())", false)
AssertThrows("Let rejects parenthesized binding pairs", "(let ((x 2) (y 3)) (+ $x $y))",
    "alternating names and values")
AssertThrows("Let rejects malformed bindings", "(let (x))", "alternating names and values")
AssertThrows("Let rejects an unmatched flat binding",
    "(let (x 1 y) $x)", "alternating names and values")
AssertThrows("Let rejects duplicate names", "(let (x 1 x 2) $x)", "must be unique")
AssertEval("Let star evaluates dependent bindings", "(let* (price 10 tax (* $price 0.2) total (+ $price $tax)) $total)", 12)
AssertEval("Let star evaluates expression array bindings",
    ["let*", ["x", 2, "y", "(+ $x 3)"], ["(* $x $y)"]], 10)
AssertEval("Let star initializers see previous shadowing", "(let* (x (+ $x 1) y $x) $y)", 10, Map("x", 9))
AssertEval("Let star allows sequential rebinding", "(let* (x 1 x (+ $x 1)) $x)", 2)
AssertEval("Let star closures capture earlier bindings",
    "(let* (x 1 f (func () $x) x 2) ($f))", 1)
AssertEval("Let star bindings stay local", "(do (let* (x 2 y $x) $y) $x)", 1, Map("x", 1))
AssertEval("Let star with no body returns nil", "(let* ())", false)
AssertEval("Let star empty bindings create a local scope", "(do (let* () (set (x 2))) $x)", 1, Map("x", 1))
AssertEval("Let star first initializer uses outer scope",
    "(do (let* (x (do (set (outer 2)) 1)) $x) $outer)", 2, Map("outer", 1))
AssertEval("Let star later initializers use local scope",
    "(do (let* (x 1 y (do (set (outer 2)) $x)) $y) $outer)", 1, Map("outer", 1))
AssertThrows("Let star requires a binding list", "(let* 1 2)", "expects a binding list")
AssertThrows("Let star rejects odd bindings", "(let* (x 1 y) $x)", "alternating names and values")
AssertThrows("Let star rejects parenthesized binding pairs", "(let* ((x 2)) $x)", "alternating names and values")
AssertThrows("Let star rejects invalid binding names", "(let* (a.b 1) 2)", "binding name")
AssertThrows("Let star cannot see later bindings", "(let* (x $y y 2) $x)", "y")
AssertThrows("Let initializers cannot read sibling bindings",
    "(let (items (array 1 2 3) mapped (map $items (func (item) (+ $item 1)))) (length $mapped))", "items")
AssertEval("Let star supports dependent initializer bindings",
    "(let* (items (array 1 2 3) mapped (map $items (func (item) (+ $item 1)))) (get $mapped 3))", 4)
AssertEval("Function accepts arguments and evaluates multiple body forms",
    "((func (x y) (+ $x 1) (+ $x $y)) 2 3)", 5)
AssertEval("Function can be bound and called by variable",
    "(let (add-one (func (x) (+ $x 1))) ($add-one 4))", 5)
AssertEval("Function closes over its lexical environment",
    "(let (x 10) (let (f (func (y) (+ $x $y))) (let (x 100) ($f 1))))", 11)
AssertEval("Function supports zero arguments", "((func () 7))", 7)
AssertEval("Function supports higher-order calls",
    "((func (f) ($f 5)) (func (x) (* $x 2)))", 10)
AssertThrows("Function checks its argument count", "((func (x) $x))", "func expects 1 argument")
AssertThrows("Function rejects duplicate parameters", "(func (x x) $x)", "must be unique")
arrayFunction := mainInterpreter.Eval("(func (x) (+ $x 1))")
AssertEval("Expression arrays call a function from the environment", ["$f", 4], 5, Map("f", arrayFunction))
AssertEval("If selects true branch", "(if t 1 2)", 1)
AssertEval("If selects false branch", "(if nil 1 2)", 2)
AssertEval("If skips the unselected else branch", "(if t 7 (/ 1 0))", 7)
AssertEval("If skips the unselected then branch", "(if nil (/ 1 0) 8)", 8)
AssertEval("If accepts a true comparison condition", "(if (= 2 2) 1 2)", 1)
AssertEval("If accepts a false comparison condition", "(if (= 2 3) 1 2)", 2)
AssertEval("If accepts an and condition", "(if (and t (> 3 2)) 1 2)", 1)
AssertEval("If accepts an or condition", "(if (or nil (= 2 2)) 1 2)", 1)
AssertEval("If accepts a not condition", "(if (not nil) 1 2)", 1)
AssertEval("If accepts a symbol condition", "(if $enabled 1 2)", 1, Map("enabled", true))
AssertEval("If accepts nil condition in expression array", ["if", false, 1, 2], 2)
AssertEval("If accepts true condition in expression array", ["if", true, 1, 2], 1)
AssertEval("False boolean is false in conditions", "(if (= 2 3) 1 2)", 2)
AssertEval("If coerces zero to false", "(if 0 1 2)", 2)
AssertEval("If coerces one to true", "(if 1 1 2)", 1)
AssertEval("If treats empty string as false", '(if "" 1 2)', 2)
AssertEval("If treats empty map as true", "(if $value 1 2)", 1, Map("value", Map()))
AssertEval("If accepts non-empty string literal condition", '(if "yes" 1 2)', 1)
AssertEval("If coerces zero from environment to false", "(if $value 1 2)", 2, Map("value", 0))
AssertEval("If coerces one from environment to true", "(if $value 1 2)", 1, Map("value", 1))
AssertEval("If treats false from environment as false", "(if $value 1 2)", 2, Map("value", false))
AssertEval("If treats true from environment as true", "(if $value 1 2)", 1, Map("value", true))
AssertEval("If coerces zero returned by a form to false", "(if (- 1 1) 1 2)", 2)
AssertEval("If treats empty string returned by a form as false", '(if (concat "") 1 2)', 2)
AssertThrows("If requires three arguments", "(if t 1)", "expects 4 argument")
AssertEval("When evaluates its body when true", "(when t 42)", 42)
AssertEval("When returns the last body result", "(when t 1 2 3)", 3)
AssertEval("When skips its body when false", "(when nil missing)", false)
AssertEval("When skips failing body expressions when false", "(when nil (/ 1 0))", false)
AssertThrows("When evaluates earlier body expressions", "(when t (/ 1 0) 42)", "Division by zero")
AssertEval("When without a body returns nil", "(when t)", false)
AssertEval("When evaluates conditions in expression arrays", ["when", ["=", 2, 2], 1, 2], 2)
AssertThrows("When requires a condition", "(when)", "expects at least 2 argument")
AssertEval("And with no operands is true", "(and)", true)
AssertEval("And returns the original last operand", "(and t 1)", 1)
AssertEval("And returns the original false operand", "(and t 0)", 0)
AssertEval("And preserves numeric operand values", "(+ (and t 1) 2)", 3)
AssertEval("And short-circuits on false", "(and nil missing)", false)
AssertEval("And skips failing operands after false", "(and 0 (/ 1 0))", 0)
AssertThrows("And evaluates operands before a false value", "(and t (/ 1 0) nil)", "Division by zero")
AssertEval("Or with no operands is false", "(or)", false)
AssertEval("Or returns false when all operands are nil", "(or nil nil)", false)
AssertEval("Or returns the original last false operand", "(or nil 0)", 0)
AssertEval("Or preserves numeric operand values", "(+ (or nil 0) 1)", 1)
AssertEval("Or returns its first truthy operand", '(or nil "value")', "value")
AssertEval("Or skips failing operands after truthy value", '(or "value" (/ 1 0))', "value")
AssertThrows("Or evaluates operands before a truthy value", '(or nil (/ 1 0) "value")', "Division by zero")
AssertEval("Not returns true for false", "(not nil)", true)
AssertEval("Not returns false for truthy value", "(not 1)", false)
AssertThrows("Not requires one argument", "(not t nil)", "expects 2 argument")
AssertThrows("coerceBoolean is not exposed as an operator", "(coerceBoolean 1)", "Unknown operator: coerceBoolean")
AssertEval("number? accepts integers", "(number? 2)", true)
AssertEval("number? accepts floats", "(number? 2.5)", true)
AssertEval("number? rejects numeric strings", '(number? "2")', false)
AssertEval("integer? identifies integer values", "(integer? 2)", true)
AssertEval("integer? rejects floats", "(integer? 2.5)", false)
AssertEval("float? identifies float values", "(float? 2.5)", true)
AssertEval("float? rejects integers", "(float? 2)", false)
AssertEval("string? identifies strings", '(string? "2")', true)
AssertEval("string? rejects numbers", "(string? 2)", false)
AssertEval("number? accepts nil's native integer value", "(number? nil)", true)
AssertEval("integer? accepts t's native integer value", "(integer? t)", true)
AssertThrows("number? validates argument count", "(number?)", "expects 1 argument")
AssertSet("set updates environments with sequential bindings")
AssertEnvironment("Native Map supports evaluation and nested values")
AssertInterpreterFacade("Interpreter exposes Eval without engine internals")
AssertThrows("set rejects direct map entries as binding syntax", ["set", Map("name", "merged")], "each binding to contain")
AssertThrows("set rejects scalar entries", "(set 42)", "each binding to contain")
AssertEval("set treats two-item forms as bindings", '(do (set (set "value")) $set)', "value")
AssertEval("set returns nil after assignments", '(set (first 1) (second 2))', false)
AssertEval("set without bindings returns nil", "(set)", false)
AssertEval("set accepts symbol binding names", '(do (set ($name "Ada")) $name)', "Ada")
AssertEval("set supports a computed operator", '(do ((if t "set" "set") (name "Ada")) $name)', "Ada")
AssertEval("set updates repeated bindings in sequence", '(do (set (count 1) (count (+ $count 1))) $count)', 2)
AssertEval("set works in a function local scope",
    '(let (f (func (x) (set (x (+ $x 1))) $x)) ($f 2))', 3)
AssertThrows("set rejects malformed bindings", '(set (name))', "each binding to contain")
AssertThrows("set rejects dotted variable names", '(set ("user.name" 1))', "cannot contain a dot")
AssertThrows("make-env is no longer an operator", "(make-env)", "Unknown operator: make-env")
lookupEnv := Map("name", "Ada", "user", Map("name", "Grace"), "count", 7)
AssertEval("or returns an existing variable value", "(or $name)", "Ada", lookupEnv)
AssertEval("or skips fallback for an existing variable", '(or $name "guest")', "Ada", lookupEnv)
AssertEval("or uses fallback for a missing variable", '(or $missing "guest")', "guest", lookupEnv)
AssertThrows("or reports a missing variable without fallback", "(or $missing)", "Variable is not present: missing")
AssertEval("or reads a nested map path", "(or $user.name)", "Grace", lookupEnv)
AssertEval("or falls back for a missing nested map path", '(or $user.missing "guest")', "guest", lookupEnv)
AssertEval("or falls back after multiple missing variables", '(or $missing $user.missing "guest")', "guest", lookupEnv)
AssertThrows("or reports a final missing variable after a false value", "(or nil $missing)", "Variable is not present: missing")
AssertEval("or reads deeper nested path", "(or $user.profile.name)", "Ada", Map("user", Map("profile", Map("name", "Ada"))))
AssertEval("or falls through for nil", '(or nil "guest")', "guest", lookupEnv)
AssertEval("or treats zero as false and uses fallback", '(or nil 0 "guest")', "guest", lookupEnv)
AssertEval("or evaluates non-symbol expressions", '(or (concat "guest"))', "guest")
AssertEval("or works inside a larger expression", '(concat "Hello, " (or $missing "guest"))', "Hello, guest", lookupEnv)
AssertThrows("or reports missing nested path without fallback", "(or $user.missing)", "Missing map key", lookupEnv)
AssertEval("Optional lookup returns an existing variable", "$?name", "Ada", lookupEnv)
AssertEval("Optional lookup returns nil for a missing variable", "$?missing", false, lookupEnv)
AssertEval("Optional lookup returns an existing nested path", "$?user.name", "Grace", lookupEnv)
AssertEval("Optional lookup returns nil for a missing nested path", "$?user.missing", false, lookupEnv)
AssertEval("Optional lookup returns nil for a missing intermediate path", "$?user.missing.name", false, lookupEnv)
AssertEval("Optional lookup returns nil for a scalar intermediate value", "$?count.name", false, lookupEnv)
AssertEval("Optional lookup returns nil for zero", "$?count", false, Map("count", 0))
AssertEval("Optional lookup returns nil for an empty string", "$?name", false, Map("name", ""))
AssertEval("Optional lookup replaces an empty string with nil", "(string? $?name)", false, Map("name", ""))
AssertEval("Optional lookup traverses arrays", "$?items.1", "tea", Map("items", ["tea"]))
AssertEval("Optional lookup returns nil for an invalid array index", "$?items.2", false, Map("items", ["tea"]))
AssertEval("Optional lookup works within another expression", '(concat "Hello, " $?user.name)', "Hello, Grace", lookupEnv)
AssertEval("Optional lookup works with a fallback", '(or $?missing "guest")', "guest", lookupEnv)
AssertEval("Quoted optional lookup remains a literal", '"$?name"', "$?name", lookupEnv)
AssertEval("Optional lookup works as a computed operator", '($?op "a" "b")', "ab", Map("op", "concat"))
AssertEval("Optional lookup works in a single-element expression array", ["$?name"], "Ada", lookupEnv)
AssertEval("Optional lookup works in a nested expression array", ["concat", ["$?name"]], "Ada", lookupEnv)
AssertEval("Optional lookup works as an expression array operator", ["$?op", "a", "b"], "ab", Map("op", "concat"))
AssertEval("Expression array argument strings remain literal", ["concat", "$?name"], "$?name", lookupEnv)

; Native AutoHotkey object environments.
objectLookupEnv := {name: "Ada", user: {name: "Grace"}}
AssertEval("Optional lookup traverses object properties", "$?user.name", "Grace", objectLookupEnv)
AssertEval("Optional lookup returns nil for a missing object property", "$?user.missing", false, objectLookupEnv)
AssertEval("Path symbol traverses a nested object property", "$user.name", "Grace", objectLookupEnv)
AssertEval("or reads a variable from an AHK object", "(or $name)", "Ada", objectLookupEnv)
AssertEval("or reads a nested property from an AHK object", "(or $user.name)", "Grace", objectLookupEnv)
AssertEval("or uses fallback for a missing AHK object property", '(or $missing "guest")', "guest", objectLookupEnv)
AssertEval("or uses fallback for a missing nested object property", '(or $user.missing "guest")', "guest", objectLookupEnv)
AssertEvalCache("Parsed expression cache reuses syntax but reevaluates environment")
AssertCacheConfiguration("Cache size defaults to 256 and is configurable")

ExitApp(failedTests > 0 ? 1 : 0)
