; A small Lisp-like interpreter for AutoHotkey v2.
; See README.md for syntax and examples.

class EvaluationError extends Error {
    __New(message, expr := unset, cause := unset, location := unset) {
        if IsSet(location) {
            coordinates := EvaluationError._GetCoordinates(location.source, location.position)
            this.position := location.position
            this.sourceLine := coordinates.line
            this.sourceColumn := coordinates.column
            message .= " (line " coordinates.line ", column " coordinates.column ", position " location.position ")"
        }
        super.__New(message)
        if IsSet(expr)
            this.expr := expr
        if IsSet(cause)
            this.cause := cause
    }

    static _GetCoordinates(source, position) {
        line := 1
        column := 1
        index := 1
        while (index < position) {
            char := SubStr(source, index, 1)
            if (char = "`r") {
                line += 1
                column := 1
                if (SubStr(source, index + 1, 1) = "`n")
                    index += 1
            } else if (char = "`n") {
                line += 1
                column := 1
            } else
                column += 1
            index += 1
        }
        return {line: line, column: column}
    }
}

class SyntaxForm {
    __New(items, position := unset, source := unset) {
        this.items := items
        if IsSet(position)
            this.position := position
        if IsSet(source)
            this.source := source
    }
}

class NoResult {
}

class _LispBoolean {
    __New(value) => this.value := value
}

class Environment {
    __New() {
        variables := Map()

        Store(env, name, value) {
            if !(name is String) || name = "" || InStr(name, ".")
                throw ValueError("Variable name must be a non-empty string without dots")
            if RegExMatch(name, '[ \t\r\n()[\]{}"]')
                throw ValueError("Invalid variable name: " name)
            if !(value is _LispBoolean) && !(value is Integer)
                && !(value is Float) && !(value is String)
                throw TypeError("Environment values must be booleans, numbers, or strings")
            variables[name] := value
        }

        AddBoolean(env, name, value) {
            if !(value is Integer) || (value != 0 && value != 1)
                throw TypeError("AddBoolean expects true or false")
            Store(env, name, _LispBoolean(value))
        }

        AddNumber(env, name, value) {
            if !(value is Integer) && !(value is Float)
                throw TypeError("AddNumber expects a number")
            Store(env, name, value)
        }

        AddString(env, name, value) {
            if !(value is String)
                throw TypeError("AddString expects a string")
            Store(env, name, value)
        }

        Get(env, name) {
            if !variables.Has(name)
                throw EvaluationError("Variable is not present: " name)
            return variables[name]
        }

        AddEnvironment(env, other) {
            if !(other is Environment)
                throw TypeError("AddEnvironment expects an Environment")
            if (env == other)
                return env
            for name, value in other
                Store(env, name, value)
            return env
        }

        Enumerate(env, count) => variables.__Enum(count)

        this.DefineProp("AddBoolean", {Call: AddBoolean})
        this.DefineProp("AddNumber", {Call: AddNumber})
        this.DefineProp("AddString", {Call: AddString})
        this.DefineProp("AddEnvironment", {Call: AddEnvironment})
        this.DefineProp("Get", {Call: Get})
        this.DefineProp("__Enum", {Call: Enumerate})
    }
}

class Interpreter {
    static True := _LispBoolean(true)
    static False := _LispBoolean(false)
    static Boolean(value) {
        if !(value is Integer) || (value != 0 && value != 1)
            throw TypeError("Boolean expects true or false")
        return value ? Interpreter.True : Interpreter.False
    }

    __New(cacheSize := 256) {
        this.DefineProp("Eval", {Call: Evaluate})

        ; Keep the language operators in one registry. Aliases point to the same
        ; implementation, and adding a builtin does not require extending Apply's
        ; dispatch logic.
        builtins := Map(
            "+", _BuiltinAdd,
            "-", _BuiltinSubtract,
            "*", _BuiltinMultiply,
            "/", _BuiltinDivide,
            "%", _BuiltinModulo,
            "=", _BuiltinEqual,
            "==", _BuiltinEqual,
            "!=", _BuiltinNotEqual,
            "<>", _BuiltinNotEqual,
            "<", _BuiltinLessThan,
            "<=", _BuiltinLessThanOrEqual,
            ">", _BuiltinGreaterThan,
            ">=", _BuiltinGreaterThanOrEqual,
            "concat", _BuiltinConcat,
            "join", _BuiltinJoin,
            "copy-to-clipboard", _BuiltinCopyToClipboard,
            "length", _BuiltinLength,
            "match", _BuiltinMatch,
            "substr", _BuiltinSubstr,
            "upper", _BuiltinUpper,
            "lower", _BuiltinLower,
            "trim", _BuiltinTrim,
            "replace", _BuiltinReplace,
            "starts-with", _BuiltinStartsWith,
            "ends-with", _BuiltinEndsWith,
            "index-of", _BuiltinIndexOf,
            "strip-prefix", _BuiltinStripPrefix,
            "strip-suffix", _BuiltinStripSuffix,
            "contains", _BuiltinContains,
            "in", _BuiltinContains
        )

        if !IsNumber(cacheSize) || cacheSize < 0 || cacheSize != Floor(cacheSize)
            throw EvaluationError("Cache size must be a non-negative integer.")
        expressionCache := Map()
        expressionCacheOrder := []
        expressionCacheLimit := cacheSize + 0

        _Tokenize(source) {
            tokens := []
            i := 1
            n := StrLen(source)
            while (i <= n) {
                ch := SubStr(source, i, 1)
                if _IsWhitespace(ch) {
                    i += 1
                    continue
                }
                if _IsPunctuation(ch) {
                    tokens.Push({kind: "punct", value: ch, start: i})
                    i += 1
                    continue
                }
                if (ch = '"' || ch = "``") {
                    stringStart := i
                    quote := ch
                    i += 1
                    value := ""
                    closed := false
                    while (i <= n) {
                        ch := SubStr(source, i, 1)
                        if (ch = quote) {
                            if (SubStr(source, i + 1, 1) = quote) {
                                value .= quote
                                i += 2
                                continue
                            }
                            i += 1
                            closed := true
                            break
                        }
                        if (quote != "``" && ch = "``" && i < n) {
                            next := SubStr(source, i + 1, 1)
                            if (next = "n")
                                value .= "`n"
                            else if (next = "r")
                                value .= "`r"
                            else if (next = "t")
                                value .= "`t"
                            else
                                value .= next
                            i += 2
                            continue
                        }
                        value .= ch
                        i += 1
                    }
                    if !closed
                        throw EvaluationError("Unterminated string literal", SubStr(source, stringStart), unset,
                            {position: stringStart, source: source})
                    tokens.Push({kind: "string", value: value, start: stringStart})
                    continue
                }
                start := i
                while (i <= n) {
                    ch := SubStr(source, i, 1)
                    if (_IsWhitespace(ch) || _IsPunctuation(ch))
                        break
                    i += 1
                }
                if (i = start)
                    throw EvaluationError("Unexpected character", SubStr(source, i, 1), unset, {position: i, source: source})
                tokens.Push({kind: "atom", value: SubStr(source, start, i - start), start: start})
            }
            return tokens
        }

        _ReadExpression(state) {
            if (state.index > state.tokens.Length) {
                source := state.HasOwnProp("source") ? state.source : ""
                throw EvaluationError("Unexpected end of input", unset, unset,
                    {position: StrLen(source) + 1, source: source})
            }
            token := state.tokens[state.index]
            state.index += 1
            if (token.kind = "string")
                return token.value
            if (token.kind = "atom")
                return _ParseAtom(token.value, token.start, state.source)
            if !_IsPunctuationToken(token)
                throw EvaluationError("Invalid token", token)
            return _ReadPunctuation(state, token)
        }

        _ReadSequence(state, closing, openingToken) {
            items := []
            while (state.index <= state.tokens.Length) {
                token := state.tokens[state.index]
                if _IsPunctuationToken(token, closing) {
                    state.index += 1
                    return SyntaxForm(items, openingToken.start, state.source)
                }
                items.Push(_ReadExpression(state))
            }
            throw EvaluationError("Missing closing delimiter " closing,
                SyntaxForm(items, openingToken.start, state.source),
                unset, {position: StrLen(state.source) + 1, source: state.source})
        }

        _ParseAtom(text, position := unset, source := unset) {
            if (SubStr(text, 1, 1) = "$") {
                symbol := {symbol: SubStr(text, 2)}
                if IsSet(position) {
                    symbol.position := position
                    symbol.source := source
                }
                return symbol
            }
            if (text = "t")
                return _LispBoolean(true)
            if (text = "nil")
                return _LispBoolean(false)
            if RegExMatch(text, "^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")
                return text + 0
            return text
        }

        _IsPunctuation(ch) => InStr("()[]{}", ch) != 0

        _IsPunctuationToken(token, value := "") => token.kind = "punct" && (value = "" || token.value = value)

        _IsOpeningParenthesis(token) => _IsPunctuationToken(token, "(")

        _IsWhitespace(ch) => ch = " " || ch = "`t" || ch = "`r" || ch = "`n"

        _IsSymbol(value) => IsObject(value) && value.HasOwnProp("symbol")

        _ReadPunctuation(state, token) {
            if _IsOpeningParenthesis(token)
                return _ReadSequence(state, ")", token)
            throw EvaluationError("Unexpected delimiter: " token.value, token.value, unset,
                {position: token.start, source: state.source})
        }

        EvalInternal(source, env := 0) {
            if !IsObject(env)
                env := _CreateEnvironment()
            if (source is Array) {
                if (source.Length = 1 && source[1] is String)
                    source := source[1]
                else
                    value := _BuildArrayExpression(source)
            }
            if (source is String) {
                value := _GetOrParseExpression(source)
            } else if !(source is Array) {
                throw EvaluationError("Eval expects a source string or expression array.")
            }
            return _UnwrapBoolean(_Evaluate(value, env))
        }

        _BuildArrayExpression(items) {
            if (items.Length = 1 && items[1] is String)
                return _GetOrParseExpression(items[1])
            formItems := []
            if (items.Length = 0)
                return SyntaxForm(formItems)
            if !(items[1] is String)
                throw EvaluationError("An expression array must start with an operator string.")
            _ValidateOperatorName(items[1])
            formItems.Push({symbol: items[1]})
            index := 2
            while (index <= items.Length) {
                item := items[index]
                if (item is Array)
                    item := _BuildArrayExpression(item)
                formItems.Push(item)
                index += 1
            }
            return SyntaxForm(formItems)
        }

        _ValidateOperatorName(value) {
            if (value = "")
                throw EvaluationError("An operator or symbol cannot be empty.")
            for index, char in StrSplit(value) {
                if (_IsWhitespace(char) || _IsPunctuation(char) || char = Chr(34))
                    throw EvaluationError("Invalid operator or symbol: " value)
            }
            if (value = "t" || value = "nil" || RegExMatch(value, "^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"))
                throw EvaluationError("An operator array element must be a symbol, not a number.")
        }

        _Parse(source) {
            tokens := _Tokenize(source)
            state := {tokens: tokens, index: 1, source: source}
            isScalar := tokens.Length > 0 && (tokens[1].kind = "string"
                || (tokens[1].kind = "atom" && (tokens[1].value = "t" || tokens[1].value = "nil"
                    || RegExMatch(tokens[1].value, "^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"))))
            if (tokens.Length > 1 && !isScalar && !_IsOpeningParenthesis(tokens[1])) {
                items := []
                while (state.index <= state.tokens.Length)
                    items.Push(_ReadExpression(state))
                value := SyntaxForm(items, tokens[1].start, source)
            } else {
                value := _ReadExpression(state)
            }
            if (state.index <= state.tokens.Length)
                throw EvaluationError("Unexpected input after expression", source, unset,
                    {position: tokens[state.index].start, source: source})
            return value
        }

        _CacheExpression(source, expression) {
            if (expressionCacheLimit = 0)
                return
            expressionCache[source] := expression
            expressionCacheOrder.Push(source)
            if (expressionCacheOrder.Length > expressionCacheLimit) {
                expiredSource := expressionCacheOrder.RemoveAt(1)
                expressionCache.Delete(expiredSource)
            }
        }

        _GetOrParseExpression(source) {
            if expressionCache.Has(source)
                return expressionCache[source]
            expression := _Parse(source)
            _CacheExpression(source, expression)
            return expression
        }

        _CreateEnvironment() {
            return Environment()
        }

        _Evaluate(expr, env) {
            try {
                return _EvaluateExpression(expr, env)
            } catch as err {
                if (err is EvaluationError) {
                    if !err.HasOwnProp("expr")
                        err.expr := expr
                    if !err.HasOwnProp("position") && IsObject(expr) {
                        if expr.HasOwnProp("position") && expr.HasOwnProp("source")
                            throw EvaluationError(err.Message, err.expr, err, {position: expr.position, source: expr.source})
                    }
                    throw err
                }
                if IsObject(expr) && expr.HasOwnProp("position") && expr.HasOwnProp("source")
                    throw EvaluationError(err.Message, expr, err, {position: expr.position, source: expr.source})
                throw EvaluationError(err.Message, expr, err)
            }
        }

        _EvaluateExpression(expr, env) {
            if (expr is SyntaxForm)
                return _EvaluateForm(expr.items, env)
            return _EvaluateAtom(expr, env)
        }

        _EvaluateAtom(expr, env) {
            if (expr is _LispBoolean)
                return expr
            if _IsSymbol(expr) {
                if InStr(expr.symbol, ".") {
                    value := _LookupPathRoot(env, expr.symbol)
                    tail := _PathTail(expr.symbol)
                    return (tail = "") ? value : _GetPath(value, tail)
                }
                return _Lookup(env, expr.symbol)
            }
            return expr
        }

        _EvaluateForm(items, env) {
            if (items.Length = 0)
                return ""
            head := items[1]
            if _IsSymbol(head)
                op := head.symbol
            else
                op := _Evaluate(head, env)
            if (op = "if") {
                _RequireCount(items, 4, "if")
                condition := _CoerceBoolean(_Evaluate(items[2], env))
                return _Truthy(condition) ? _Evaluate(items[3], env) : _Evaluate(items[4], env)
            }
            if (op = "and") {
                result := _LispBoolean(true)
                for index, item in items {
                    if (index = 1)
                        continue
                    result := _Evaluate(item, env)
                    if !_Truthy(_CoerceBoolean(result))
                        return result
                }
                return result
            }
            if (op = "or") {
                result := _LispBoolean(false)
                for index, item in items {
                    if (index = 1)
                        continue
                    if _IsSymbol(item) {
                        path := item.symbol
                        try {
                            value := _LookupPathRoot(env, path)
                            tail := _PathTail(path)
                            if (tail != "")
                                value := _GetPath(value, tail)
                        } catch {
                            if (index = items.Length)
                                throw
                            continue
                        }
                    } else
                        value := _Evaluate(item, env)
                    result := value
                    if _Truthy(_CoerceBoolean(value))
                        return value
                }
                return result
            }
            if (op = "not") {
                _RequireCount(items, 2, "not")
                condition := _CoerceBoolean(_Evaluate(items[2], env))
                return _LispBoolean(!_Truthy(condition))
            }
            if (op = "get") {
                if (items.Length != 3)
                    throw EvaluationError(op " expects a value, a key/path")
                target := _Evaluate(items[2], env)
                path := _Evaluate(items[3], env)
                return _GetPath(target, path)
            }
            if (op = "make-env")
                return _EvaluateMakeEnv(items, env)
            args := []
            index := 2
            while (index <= items.Length) {
                args.Push(_Evaluate(items[index], env))
                index += 1
            }
            return _Apply(op, args)
        }

        _EvaluateMakeEnv(items, env) {
            variables := Environment()
            scope := _CopyEnvironment(env)
            index := 2
            while (index <= items.Length) {
                binding := items[index]
                if !(binding is SyntaxForm) || binding.items.Length != 2
                    throw EvaluationError("make-env" " expects each binding to contain a name and one value expression")

                nameExpr := binding.items[1]
                if _IsSymbol(nameExpr)
                    name := nameExpr.symbol
                else if (nameExpr is String)
                    name := nameExpr
                else
                    throw EvaluationError("make-env" " binding name must be a string or symbol")

                if (name = "" || InStr(name, "."))
                    throw EvaluationError("make-env" " binding name must be non-empty and cannot contain a dot")
                for char in StrSplit(name) {
                    if (_IsWhitespace(char) || _IsPunctuation(char) || char = Chr(34))
                        throw EvaluationError("make-env" " binding name is invalid: " name)
                }

                value := _Evaluate(binding.items[2], scope)
                _AddEnvironmentValue(variables, name, value)
                _AddEnvironmentValue(scope, name, value)
                index += 1
            }
            return variables
        }

        _CopyEnvironment(env) {
            if !(env is Environment)
                throw EvaluationError("make-env requires an Environment")
            return Environment().AddEnvironment(env)
        }

        _AddEnvironmentValue(env, name, value) {
            if (value is _LispBoolean)
                env.AddBoolean(name, value.value)
            else if (value is Integer) || (value is Float)
                env.AddNumber(name, value)
            else if (value is String)
                env.AddString(name, value)
            else
                throw EvaluationError("make-env" " binding value must be a boolean, number, or string")
        }

        _Apply(op, args) {
            if !(op is String)
                throw EvaluationError("Operator must be a string, got " Type(op))
            if !builtins.Has(op)
                throw EvaluationError("Unknown operator: " op)
            return builtins[op](args)
        }

        _BuiltinAdd(args) {
            _RequireAtLeast(args, 1, "+")
            value := 0
            for item in args
                value += _Number(item)
            return value
        }

        _BuiltinSubtract(args) {
            _RequireAtLeast(args, 1, "-")
            value := _Number(args[1])
            if (args.Length = 1)
                return -value
            index := 2
            while (index <= args.Length) {
                value -= _Number(args[index])
                index += 1
            }
            return value
        }

        _BuiltinMultiply(args) {
            _RequireAtLeast(args, 1, "*")
            value := 1
            for item in args
                value *= _Number(item)
            return value
        }

        _BuiltinDivide(args) {
            _RequireAtLeast(args, 2, "/")
            value := _Number(args[1])
            index := 2
            while (index <= args.Length) {
                divisor := _Number(args[index])
                if (divisor = 0)
                    throw EvaluationError("Division by zero")
                value /= divisor
                index += 1
            }
            return value
        }

        _BuiltinModulo(args) {
            _RequireCount(args, 2, "%")
            return Mod(_Number(args[1]), _Number(args[2]))
        }

        _BuiltinEqual(args) {
            _RequireCount(args, 2, "=")
            return _LispBoolean(_UnwrapBoolean(args[1]) = _UnwrapBoolean(args[2]))
        }

        _BuiltinNotEqual(args) {
            _RequireCount(args, 2, "!=")
            return _LispBoolean(_UnwrapBoolean(args[1]) != _UnwrapBoolean(args[2]))
        }

        _BuiltinLessThan(args) {
            _RequireCount(args, 2, "<")
            return _LispBoolean(args[1] < args[2])
        }

        _BuiltinLessThanOrEqual(args) {
            _RequireCount(args, 2, "<=")
            return _LispBoolean(args[1] <= args[2])
        }

        _BuiltinGreaterThan(args) {
            _RequireCount(args, 2, ">")
            return _LispBoolean(args[1] > args[2])
        }

        _BuiltinGreaterThanOrEqual(args) {
            _RequireCount(args, 2, ">=")
            return _LispBoolean(args[1] >= args[2])
        }

        _BuiltinConcat(args) {
            value := ""
            for item in args
                value .= item
            return value
        }

        _BuiltinJoin(args) {
            _RequireAtLeast(args, 1, "join")
            separator := args[1]
            if !(separator is String)
                throw EvaluationError("join" " expects a string separator")
            value := ""
            index := 2
            while (index <= args.Length) {
                if (index > 2)
                    value .= separator
                value .= args[index]
                index += 1
            }
            return value
        }

        _BuiltinCopyToClipboard(args) {
            _RequireCount(args, 1, "copy-to-clipboard")
            value := args[1]
            A_Clipboard := value
            return NoResult()
        }

        _BuiltinLength(args) {
            _RequireCount(args, 1, "length")
            if (args[1] is Environment) {
                count := 0
                for name in args[1]
                    count += 1
                return count
            }
            if (args[1] is Array)
                return args[1].Length
            if (args[1] is Map)
                return args[1].Count
            return StrLen(args[1])
        }

        _BuiltinMatch(args) {
            _RequireCount(args, 2, "match")
            return _LispBoolean(RegExMatch(args[1], args[2]) != 0)
        }

        _BuiltinSubstr(args) {
            if (args.Length < 2 || args.Length > 3)
                throw EvaluationError("substr" " expects 2 or 3 arguments")
            text := _RequireString(args[1], "substr", "text")
            start := _RequireInteger(args[2], "substr", "start")
            if (args.Length = 2)
                return SubStr(text, start)
            length := _RequireInteger(args[3], "substr", "length")
            return SubStr(text, start, length)
        }

        _BuiltinUpper(args) {
            _RequireCount(args, 1, "upper")
            return StrUpper(_RequireString(args[1], "upper", "text"))
        }

        _BuiltinLower(args) {
            _RequireCount(args, 1, "lower")
            return StrLower(_RequireString(args[1], "lower", "text"))
        }

        _BuiltinTrim(args) {
            if (args.Length < 1 || args.Length > 2)
                throw EvaluationError("trim" " expects 1 or 2 arguments")
            text := _RequireString(args[1], "trim", "text")
            omitChars := args.Length = 2 ? _RequireString(args[2], "trim", "omit characters") : " `t`r`n"
            return Trim(text, omitChars)
        }

        _BuiltinReplace(args) {
            _RequireCount(args, 3, "replace")
            text := _RequireString(args[1], "replace", "text")
            search := _RequireString(args[2], "replace", "search text")
            replacement := _RequireString(args[3], "replace", "replacement")
            if (search = "")
                throw EvaluationError("replace" " expects non-empty search text")
            return StrReplace(text, search, replacement, true)
        }

        _BuiltinStartsWith(args) {
            _RequireCount(args, 2, "starts-with")
            text := _RequireString(args[1], "starts-with", "text")
            prefix := _RequireString(args[2], "starts-with", "prefix")
            return _LispBoolean(SubStr(text, 1, StrLen(prefix)) == prefix)
        }

        _BuiltinEndsWith(args) {
            _RequireCount(args, 2, "ends-with")
            text := _RequireString(args[1], "ends-with", "text")
            suffix := _RequireString(args[2], "ends-with", "suffix")
            return _LispBoolean(suffix == "" || SubStr(text, -StrLen(suffix)) == suffix)
        }

        _BuiltinIndexOf(args) {
            _RequireCount(args, 2, "index-of")
            text := _RequireString(args[1], "index-of", "text")
            search := _RequireString(args[2], "index-of", "search text")
            return InStr(text, search, true)
        }

        _BuiltinStripPrefix(args) {
            _RequireCount(args, 2, "strip-prefix")
            text := args[1], prefix := args[2]
            return (SubStr(text, 1, StrLen(prefix)) = prefix) ? SubStr(text, StrLen(prefix) + 1) : text
        }

        _BuiltinStripSuffix(args) {
            _RequireCount(args, 2, "strip-suffix")
            text := args[1], suffix := args[2]
            return (suffix != "" && SubStr(text, -StrLen(suffix)) = suffix) ? SubStr(text, 1, StrLen(text) - StrLen(suffix)) : text
        }

        _BuiltinContains(args) {
            _RequireCount(args, 2, "contains")
            return _LispBoolean(_Contains(args[1], args[2]))
        }

        _GetPath(target, path) {
            parts := StrSplit(path, ".")
            for part in parts
                target := _GetOne(target, part)
            return target
        }

        _GetOne(target, key) {
            if (target is Environment)
                return target.Get(key)
            if (target is Map) {
                if !target.Has(key)
                    throw EvaluationError("Missing map key: " key)
                return target[key]
            }
            if (target is Array) {
                index := key + 0
                if (index < 1 || index > target.Length || index != Floor(index))
                    throw EvaluationError("Array index out of range: " key)
                return target[index]
            }
            if IsObject(target) {
                if target.HasOwnProp(key)
                    return target.%key%
                throw EvaluationError("Missing object property: " key)
            }
            throw EvaluationError("Cannot get key from a non-object value")
        }

        _LookupPathRoot(env, path) {
            parts := StrSplit(path, ".")
            return _Lookup(env, parts[1])
        }

        _PathTail(path) {
            parts := StrSplit(path, ".")
            if (parts.Length = 1)
                return ""
            tail := parts[2]
            index := 3
            while (index <= parts.Length) {
                tail .= "." parts[index]
                index += 1
            }
            return tail
        }

        _Lookup(env, name) {
            if (env is Environment)
                return env.Get(name)
            if (env is Map) {
                if env.Has(name)
                    return env[name]
            } else if IsObject(env) && env.HasOwnProp(name)
                return env.%name%
            throw EvaluationError("Variable is not present: " name)
        }

        _Contains(collection, value) {
            if (collection is Environment) {
                if !(value is String)
                    return false
                for name in collection
                    if (name == value)
                        return true
                return false
            }
            if (collection is Array) {
                for item in collection
                    if (item = value)
                        return true
                return false
            }
            if (collection is Map)
                return collection.Has(value)
            if (collection is String)
                return InStr(collection, value) != 0
            throw EvaluationError("contains expects an array, map, environment, or string")
        }

        _CoerceBoolean(value) {
            if (value is _LispBoolean)
                return value

            if value is String
                return Interpreter.True

            return value ? Interpreter.True : Interpreter.False
        }

        _Number(value) {
            if !IsNumber(value)
                throw EvaluationError("Expected a number")
            return value + 0
        }

        _RequireString(value, op, argumentName) {
            if !(value is String)
                throw EvaluationError(op " expects " argumentName " to be a string")
            return value
        }

        _RequireInteger(value, op, argumentName) {
            if !IsNumber(value) || value != Floor(value)
                throw EvaluationError(op " expects " argumentName " to be an integer")
            return value + 0
        }

        _Truthy(value) => !(value is _LispBoolean) || value.value

        _UnwrapBoolean(value) => value is _LispBoolean ? value.value : value

        _RequireCount(args, count, op) {
            if (args.Length != count)
                throw EvaluationError(op " expects " count " argument(s)")
        }

        _RequireAtLeast(args, count, op) {
            if (args.Length < count)
                throw EvaluationError(op " expects at least " count " argument(s)")
        }

        Evaluate(interpreter, source, env := 0) => EvalInternal(source, env)
    }
}
