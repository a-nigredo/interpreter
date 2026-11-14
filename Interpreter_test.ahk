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
        initialEnv := Environment()
        initialEnv.AddString("prefix", "Hello, ")
        variables := mainInterpreter.Eval(
            '(make-env (name "Ada") (greeting (concat $prefix $name)) (ready (> 2 1)))',
            initialEnv)
        if !(variables is Environment) || mainInterpreter.Eval("(length $env)", Map("env", variables)) != 3
            throw Error("expected an environment containing three declared variables")
        if (mainInterpreter.Eval("$name", variables) != "Ada"
            || mainInterpreter.Eval("$greeting", variables) != "Hello, Ada"
            || !mainInterpreter.Eval("$ready", variables))
            throw Error("expected declared values and earlier bindings to be available")
        if (mainInterpreter.Eval('(concat $greeting "!")', variables) != "Hello, Ada!")
            throw Error("expected returned variables to be usable in a later Eval call")
        if (mainInterpreter.Eval('(contains $env "name")', Map("env", initialEnv)))
            throw Error("expected the original environment to remain unchanged")
        if (mainInterpreter.Eval('(contains $env "prefix")', Map("env", variables)))
            throw Error("expected input bindings not to be copied into the returned environment")

        nested := mainInterpreter.Eval('(make-env (name (get (make-env (value "nested")) "value")))')
        if (nested.Get("name") != "nested")
            throw Error("expected nested make-env to use an Environment scope")

        arrayVariables := mainInterpreter.Eval(
            ["make-env", ["name", "Ada"], ["greeting", ['(concat "Hi, " $name)']]])
        if (mainInterpreter.Eval("$greeting", arrayVariables) != "Hi, Ada")
            throw Error("expected expression arrays to support sequential bindings")
        RecordResult("PASS", caseName)
    } catch as err {
        RecordResult("FAIL", caseName, err.Message)
    }
}

AssertEnvironment(caseName) {
    global mainInterpreter
    try {
        env := Environment()
        env.AddBoolean("enabled", false)
        env.AddNumber("count", 0)
        env.AddNumber("fraction", 1.5)
        env.AddString("name", "Ada")
        for value in [0, -42, 0x7F, 9223372036854775807, 0.0, -1.5, 1e4, 1e-10] {
            env.AddNumber("numeric", value)
            if (Type(env.Get("numeric")) != Type(value) || env.Get("numeric") != value)
                throw Error("expected AddNumber to preserve integer and float values")
        }
        allowed := Map("AddBoolean", true, "AddNumber", true, "AddString", true,
            "AddEnvironment", true, "Get", true, "__Enum", true)
        for name, value in ObjOwnProps(env) {
            if !allowed.Has(name)
                throw Error("unexpected environment member: " name)
        }
        if (env.Get("name") != "Ada")
            throw Error("expected Get to return the value for a name")
        enumerated := Map()
        for name, value in env
            enumerated[name] := value
        if (enumerated.Count != 5 || enumerated["name"] != "Ada"
            || !(enumerated["enabled"] is _LispBoolean))
            throw Error("expected iteration to expose all bindings with their stored types")
        noNameRejected := false
        try env.Get()
        catch Error
            noNameRejected := true
        if !noNameRejected
            throw Error("expected Get to require a name")
        missingRejected := false
        try env.Get("missing")
        catch EvaluationError
            missingRejected := true
        if !missingRejected
            throw Error("expected Get to reject missing names")
        constructorRejected := false
        try Environment(Map("name", "initial"))
        catch Error
            constructorRejected := true
        if !constructorRejected
            throw Error("expected constructor to reject initial bindings")
        if !(env.Get("enabled") is _LispBoolean) || (env.Get("count") is _LispBoolean)
            throw Error("expected boolean false and numeric zero to remain distinct")
        if (mainInterpreter.Eval('(if $enabled "yes" $name)', env) != "Ada"
            || mainInterpreter.Eval("(+ $count $fraction)", env) != 1.5)
            throw Error("expected typed bindings to be visible to Eval")
        numeric := mainInterpreter.Eval('(make-env (integer -42) (float 1.5) (exponent 1e4) (text "42"))')
        if !(numeric.Get("integer") is Integer) || !(numeric.Get("float") is Float)
            || !(numeric.Get("exponent") is Float) || !(numeric.Get("text") is String)
            throw Error("expected make-env to preserve number and numeric string types")

        incoming := Environment()
        incoming.AddString("name", "Grace")
        incoming.AddBoolean("enabled", true)
        if (env.AddEnvironment(incoming) != env)
            throw Error("expected AddEnvironment to return the destination")
        incoming.AddString("name", "Lin")
        if (mainInterpreter.Eval("$name", env) != "Grace"
            || !mainInterpreter.Eval("$enabled", env))
            throw Error("expected independent bindings with incoming values replacing duplicates")
        env.AddEnvironment(env)
        if (mainInterpreter.Eval("$name", env) != "Grace")
            throw Error("expected self-merge to preserve values")
        extraArgRejected := false
        try env.AddEnvironment(incoming, (name, value) => 0)
        catch Error
            extraArgRejected := true
        if !extraArgRejected
            throw Error("expected AddEnvironment to accept only one environment")

        derived := mainInterpreter.Eval('(make-env (name (concat $name "!")) (ready nil) (count 0))', env)
        if !(derived is Environment) || !(derived.Get("ready") is _LispBoolean)
            || (derived.Get("count") is _LispBoolean)
            throw Error("expected make-env to preserve tagged booleans and numeric values")
        if (mainInterpreter.Eval("$name", env) != "Grace"
            || mainInterpreter.Eval("$name", derived) != "Grace!")
            throw Error("expected make-env to shadow without changing its input")
        env.AddEnvironment(derived)
        if (mainInterpreter.Eval("$name", env) != "Grace!"
            || mainInterpreter.Eval("(if $ready 1 2)", env) != 2)
            throw Error("expected make-env result to merge into the original")
        if (mainInterpreter.Eval('(contains (make-env (name "Ada")) "name")') != true
            || mainInterpreter.Eval('(contains (make-env) "name")') != false
            || mainInterpreter.Eval('(contains (make-env (name "Ada")) "Name")') != false
            || mainInterpreter.Eval('(if (get (make-env (ready nil)) "ready") 1 2)') != 2)
            throw Error("expected environment get, contains and boolean values to work")

        for unsupported in [Map("key", "value"), {name: "Ada"}, Environment(), NoResult()] {
            rejected := false
            try mainInterpreter.Eval(["make-env", ["item", unsupported]])
            catch EvaluationError as err {
                if InStr(err.Message, "binding value must be a boolean, number, or string")
                    rejected := true
            }
            if !rejected
                throw Error("expected make-env to reject unsupported value: " Type(unsupported))
        }

        for invalid in [() => env.AddBoolean("bad", 2), () => env.AddBoolean("bad", "0"),
            () => env.AddNumber("bad", "1"), () => env.AddString("bad", 1),
            () => env.AddString("", "x"), () => env.AddString("bad.name", "x"),
            () => env.AddString("bad name", "x"), () => env.AddString("bad[", "x"),
            () => env.AddString("bad]", "x"), () => env.AddString('bad"', "x"),
            () => env.AddEnvironment(Map())] {
            rejected := false
            try invalid.Call()
            catch TypeError
                rejected := true
            catch ValueError
                rejected := true
            if !rejected
                throw Error("expected invalid environment input to be rejected")
        }
        RecordResult("PASS", caseName)
    } catch as err {
        RecordResult("FAIL", caseName, err.Message)
    }
}

AssertBooleanFactory(caseName) {
    try {
        for value in [2, -1, 0.0, "0", "true", Map()] {
            rejected := false
            try Interpreter.Boolean(value)
            catch TypeError
                rejected := true
            if !rejected
                throw Error("expected invalid factory input to be rejected")
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
            || uncachedInterpreter.Eval(["concat", "(+ 1 2)"]) != "(+ 1 2)")
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
AssertEval("Membership alias supports Environment keys", '(in (make-env (name "Ada")) "name")', true)
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
AssertEval("Get traverses mixed map object and array paths", '(get $data "user.items.2")', "coffee",
    Map("data", Map("user", {items: ["tea", "coffee"]})))
AssertThrows("Get rejects missing Environment key", '(get (make-env) "missing")', "Variable is not present: missing")
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
AssertEval("Eval executes boolean operations in arrays", ["and", Interpreter.True, ["not", Interpreter.False]], true)
AssertEval("Boolean factory creates true in expression arrays", ["if", Interpreter.Boolean(true), 1, 2], 1)
AssertEval("Boolean factory creates false in expression arrays", ["if", Interpreter.Boolean(false), 1, 2], 2)
AssertEval("Boolean factory creates false in environments", "(if $value 1 2)", 2, Map("value", Interpreter.Boolean(false)))
AssertBooleanFactory("Boolean factory rejects non-boolean inputs")
AssertEval("Eval executes conditional expression arrays", ["if", ["=", 2, 2], "yes", "no"], "yes")
AssertEvaluationError("EvaluationError contains the failed form", "(length)", "length")
AssertEvaluationError("Nested EvaluationError contains the failing subexpression", '(concat "prefix" (length))', "length")

; Variable lookups and fallbacks.
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
AssertMakeEnv("make-env returns sequential bindings for reuse")
AssertEnvironment("Typed environment supports evaluation and merging")
AssertInterpreterFacade("Interpreter exposes Eval without engine internals")
mergeInput := Environment()
mergeInput.AddString("name", "merged")
AssertThrows("make-env rejects direct environment entries", ["make-env", mergeInput], "each binding to contain")
AssertThrows("make-env rejects environment-producing forms",
    '(make-env (if t (make-env (name "Ada")) (make-env)))', "each binding to contain")
AssertThrows("make-env rejects scalar entries", "(make-env 42)", "each binding to contain")
AssertEval("make-env treats two-item forms as bindings",
    '(get (make-env (make-env "value")) "make-env")', "value")
makeEnvContext := Environment()
makeEnvContext.AddString("prefix", "Hello, ")
AssertEval("make-env reads variables from the supplied context",
    '(get (make-env (greeting (concat $prefix "Ada"))) "greeting")',
    "Hello, Ada", makeEnvContext)
AssertThrows("make-env rejects map input", "(make-env)", "requires an Environment", Map())
AssertThrows("make-env rejects object input", "(make-env)", "requires an Environment", {prefix: "Hi"})
AssertEval("make-env without bindings returns an empty environment", "(length (make-env))", 0)
AssertThrows("make-env rejects malformed bindings", '(make-env (name))', "each binding to contain")
AssertThrows("make-env rejects dotted variable names", '(make-env ("user.name" 1))', "cannot contain a dot")
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

; Native AutoHotkey object environments.
objectLookupEnv := {name: "Ada", user: {name: "Grace"}}
AssertEval("Path symbol traverses a nested object property", "$user.name", "Grace", objectLookupEnv)
AssertEval("or reads a variable from an AHK object", "(or $name)", "Ada", objectLookupEnv)
AssertEval("or reads a nested property from an AHK object", "(or $user.name)", "Grace", objectLookupEnv)
AssertEval("or uses fallback for a missing AHK object property", '(or $missing "guest")', "guest", objectLookupEnv)
AssertEval("or uses fallback for a missing nested object property", '(or $user.missing "guest")', "guest", objectLookupEnv)
AssertEvalCache("Parsed expression cache reuses syntax but reevaluates environment")
AssertCacheConfiguration("Cache size defaults to 256 and is configurable")

ExitApp(failedTests > 0 ? 1 : 0)
