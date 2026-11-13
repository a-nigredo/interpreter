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

class Interpreter {
    static True := _LispBoolean(true)
    static False := _LispBoolean(false)
    static TOKEN_PUNCT := "punct"
    static TOKEN_STRING := "string"
    static TOKEN_ATOM := "atom"
    static OP_ADD := "+"
    static OP_SUBTRACT := "-"
    static OP_MULTIPLY := "*"
    static OP_DIVIDE := "/"
    static OP_MODULO := "%"
    static OP_EQUAL := "="
    static OP_EQUAL_ALIAS := "=="
    static OP_NOT_EQUAL := "!="
    static OP_NOT_EQUAL_ALIAS := "<>"
    static OP_LESS_THAN := "<"
    static OP_LESS_THAN_OR_EQUAL := "<="
    static OP_GREATER_THAN := ">"
    static OP_GREATER_THAN_OR_EQUAL := ">="
    static OP_CONCAT := "concat"
    static OP_JOIN := "join"
    static OP_COPY_TO_CLIPBOARD := "copy-to-clipboard"
    static OP_LENGTH := "length"
    static OP_MATCH := "match"
    static OP_SUBSTR := "substr"
    static OP_UPPER := "upper"
    static OP_LOWER := "lower"
    static OP_TRIM := "trim"
    static OP_REPLACE := "replace"
    static OP_STARTS_WITH := "starts-with"
    static OP_ENDS_WITH := "ends-with"
    static OP_INDEX_OF := "index-of"
    static OP_STRIP_PREFIX := "strip-prefix"
    static OP_STRIP_SUFFIX := "strip-suffix"
    static OP_CONTAINS := "contains"
    static OP_IN := "in"
    static FORM_IF := "if"
    static FORM_AND := "and"
    static FORM_OR := "or"
    static FORM_NOT := "not"
    static FORM_GET := "get"
    static FORM_MAKE_ENV := "make-env"

    _Tokenize(source) {
        tokens := []
        i := 1
        n := StrLen(source)
        while (i <= n) {
            ch := SubStr(source, i, 1)
            if this._IsWhitespace(ch) {
                i += 1
                continue
            }
            if this._IsPunctuation(ch) {
                tokens.Push({kind: Interpreter.TOKEN_PUNCT, value: ch, start: i})
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
                tokens.Push({kind: Interpreter.TOKEN_STRING, value: value, start: stringStart})
                continue
            }
            start := i
            while (i <= n) {
                ch := SubStr(source, i, 1)
                if (this._IsWhitespace(ch) || this._IsPunctuation(ch))
                    break
                i += 1
            }
            if (i = start)
                throw EvaluationError("Unexpected character", SubStr(source, i, 1), unset, {position: i, source: source})
            tokens.Push({kind: Interpreter.TOKEN_ATOM, value: SubStr(source, start, i - start), start: start})
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
        if (token.kind = Interpreter.TOKEN_STRING)
            return token.value
        if (token.kind = Interpreter.TOKEN_ATOM)
            return this._ParseAtom(token.value, token.start, state.source)
        if !this._IsPunctuationToken(token)
            throw EvaluationError("Invalid token", token)
        return this._ReadPunctuation(state, token)
    }

    _ReadSequence(state, closing, openingToken) {
        items := []
        while (state.index <= state.tokens.Length) {
            token := state.tokens[state.index]
            if this._IsPunctuationToken(token, closing) {
                state.index += 1
                return SyntaxForm(items, openingToken.start, state.source)
            }
            items.Push(this._ReadExpression(state))
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

    _IsPunctuationToken(token, value := "") => token.kind = Interpreter.TOKEN_PUNCT && (value = "" || token.value = value)

    _IsOpeningParenthesis(token) => this._IsPunctuationToken(token, "(")

    _IsWhitespace(ch) => ch = " " || ch = "`t" || ch = "`r" || ch = "`n"

    _IsSymbol(value) => IsObject(value) && value.HasOwnProp("symbol")

    _ReadPunctuation(state, token) {
        if this._IsOpeningParenthesis(token)
            return this._ReadSequence(state, ")", token)
        throw EvaluationError("Unexpected delimiter: " token.value, token.value, unset,
            {position: token.start, source: state.source})
    }

    __New(cacheSize := 256) {
        ; Keep the language operators in one registry. Aliases point to the same
        ; implementation, and adding a builtin does not require extending Apply's
        ; dispatch logic.
        this.builtins := Map(
            Interpreter.OP_ADD, ObjBindMethod(this, "_BuiltinAdd"),
            Interpreter.OP_SUBTRACT, ObjBindMethod(this, "_BuiltinSubtract"),
            Interpreter.OP_MULTIPLY, ObjBindMethod(this, "_BuiltinMultiply"),
            Interpreter.OP_DIVIDE, ObjBindMethod(this, "_BuiltinDivide"),
            Interpreter.OP_MODULO, ObjBindMethod(this, "_BuiltinModulo"),
            Interpreter.OP_EQUAL, ObjBindMethod(this, "_BuiltinEqual"),
            Interpreter.OP_EQUAL_ALIAS, ObjBindMethod(this, "_BuiltinEqual"),
            Interpreter.OP_NOT_EQUAL, ObjBindMethod(this, "_BuiltinNotEqual"),
            Interpreter.OP_NOT_EQUAL_ALIAS, ObjBindMethod(this, "_BuiltinNotEqual"),
            Interpreter.OP_LESS_THAN, ObjBindMethod(this, "_BuiltinLessThan"),
            Interpreter.OP_LESS_THAN_OR_EQUAL, ObjBindMethod(this, "_BuiltinLessThanOrEqual"),
            Interpreter.OP_GREATER_THAN, ObjBindMethod(this, "_BuiltinGreaterThan"),
            Interpreter.OP_GREATER_THAN_OR_EQUAL, ObjBindMethod(this, "_BuiltinGreaterThanOrEqual"),
            Interpreter.OP_CONCAT, ObjBindMethod(this, "_BuiltinConcat"),
            Interpreter.OP_JOIN, ObjBindMethod(this, "_BuiltinJoin"),
            Interpreter.OP_COPY_TO_CLIPBOARD, ObjBindMethod(this, "_BuiltinCopyToClipboard"),
            Interpreter.OP_LENGTH, ObjBindMethod(this, "_BuiltinLength"),
            Interpreter.OP_MATCH, ObjBindMethod(this, "_BuiltinMatch"),
            Interpreter.OP_SUBSTR, ObjBindMethod(this, "_BuiltinSubstr"),
            Interpreter.OP_UPPER, ObjBindMethod(this, "_BuiltinUpper"),
            Interpreter.OP_LOWER, ObjBindMethod(this, "_BuiltinLower"),
            Interpreter.OP_TRIM, ObjBindMethod(this, "_BuiltinTrim"),
            Interpreter.OP_REPLACE, ObjBindMethod(this, "_BuiltinReplace"),
            Interpreter.OP_STARTS_WITH, ObjBindMethod(this, "_BuiltinStartsWith"),
            Interpreter.OP_ENDS_WITH, ObjBindMethod(this, "_BuiltinEndsWith"),
            Interpreter.OP_INDEX_OF, ObjBindMethod(this, "_BuiltinIndexOf"),
            Interpreter.OP_STRIP_PREFIX, ObjBindMethod(this, "_BuiltinStripPrefix"),
            Interpreter.OP_STRIP_SUFFIX, ObjBindMethod(this, "_BuiltinStripSuffix"),
            Interpreter.OP_CONTAINS, ObjBindMethod(this, "_BuiltinContains"),
            Interpreter.OP_IN, ObjBindMethod(this, "_BuiltinContains")
        )

        if !IsNumber(cacheSize) || cacheSize < 0 || cacheSize != Floor(cacheSize)
            throw EvaluationError("Cache size must be a non-negative integer.")
        this.expressionCache := Map()
        this.expressionCacheOrder := []
        this.expressionCacheLimit := cacheSize + 0
    }

    Eval(source, env := 0) {
        if !IsObject(env)
            env := this._CreateEnvironment()
        if (source is Array) {
            if (source.Length = 1 && source[1] is String)
                source := source[1]
            else
                value := this._BuildArrayExpression(source)
        }
        if (source is String) {
            value := this._GetOrParseExpression(source)
        } else if !(source is Array) {
            throw EvaluationError("Eval expects a source string or expression array.")
        }
        return this._UnwrapBoolean(this._Evaluate(value, env))
    }

    _BuildArrayExpression(items) {
        if (items.Length = 1 && items[1] is String)
            return this._GetOrParseExpression(items[1])
        formItems := []
        if (items.Length = 0)
            return SyntaxForm(formItems)
        if !(items[1] is String)
            throw EvaluationError("An expression array must start with an operator string.")
        this._ValidateOperatorName(items[1])
        formItems.Push({symbol: items[1]})
        index := 2
        while (index <= items.Length) {
            item := items[index]
            if (item is Array)
                item := this._BuildArrayExpression(item)
            formItems.Push(item)
            index += 1
        }
        return SyntaxForm(formItems)
    }

    _ValidateOperatorName(value) {
        if (value = "")
            throw EvaluationError("An operator or symbol cannot be empty.")
        for index, char in StrSplit(value) {
            if (this._IsWhitespace(char) || this._IsPunctuation(char) || char = Chr(34))
                throw EvaluationError("Invalid operator or symbol: " value)
        }
        if (value = "t" || value = "nil" || RegExMatch(value, "^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"))
            throw EvaluationError("An operator array element must be a symbol, not a number.")
    }

    _Parse(source) {
        tokens := this._Tokenize(source)
        state := {tokens: tokens, index: 1, source: source}
        isScalar := tokens.Length > 0 && (tokens[1].kind = Interpreter.TOKEN_STRING
            || (tokens[1].kind = Interpreter.TOKEN_ATOM && (tokens[1].value = "t" || tokens[1].value = "nil"
                || RegExMatch(tokens[1].value, "^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"))))
        if (tokens.Length > 1 && !isScalar && !this._IsOpeningParenthesis(tokens[1])) {
            items := []
            while (state.index <= state.tokens.Length)
                items.Push(this._ReadExpression(state))
            value := SyntaxForm(items, tokens[1].start, source)
        } else {
            value := this._ReadExpression(state)
        }
        if (state.index <= state.tokens.Length)
            throw EvaluationError("Unexpected input after expression", source, unset,
                {position: tokens[state.index].start, source: source})
        return value
    }

    _CacheExpression(source, expression) {
        if (this.expressionCacheLimit = 0)
            return
        this.expressionCache[source] := expression
        this.expressionCacheOrder.Push(source)
        if (this.expressionCacheOrder.Length > this.expressionCacheLimit) {
            expiredSource := this.expressionCacheOrder.RemoveAt(1)
            this.expressionCache.Delete(expiredSource)
        }
    }

    _GetOrParseExpression(source) {
        if this.expressionCache.Has(source)
            return this.expressionCache[source]
        expression := this._Parse(source)
        this._CacheExpression(source, expression)
        return expression
    }

    _CreateEnvironment() {
        return Map()
    }

    _Evaluate(expr, env) {
        try {
            return this._EvaluateExpression(expr, env)
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
            return this._EvaluateForm(expr.items, env)
        return this._EvaluateAtom(expr, env)
    }

    _EvaluateAtom(expr, env) {
        if (expr is _LispBoolean)
            return expr
        if this._IsSymbol(expr) {
            if InStr(expr.symbol, ".") {
                value := this._LookupPathRoot(env, expr.symbol)
                tail := this._PathTail(expr.symbol)
                return (tail = "") ? value : this._GetPath(value, tail)
            }
            return this._Lookup(env, expr.symbol)
        }
        return expr
    }

    _EvaluateForm(items, env) {
        if (items.Length = 0)
            return ""
        head := items[1]
        if this._IsSymbol(head)
            op := head.symbol
        else
            op := this._Evaluate(head, env)
        if (op = Interpreter.FORM_IF) {
            this._RequireCount(items, 4, Interpreter.FORM_IF)
            condition := this._CoerceBoolean(this._Evaluate(items[2], env))
            return this._Truthy(condition) ? this._Evaluate(items[3], env) : this._Evaluate(items[4], env)
        }
        if (op = Interpreter.FORM_AND) {
            result := _LispBoolean(true)
            for index, item in items {
                if (index = 1)
                    continue
                result := this._Evaluate(item, env)
                if !this._Truthy(this._CoerceBoolean(result))
                    return result
            }
            return result
        }
        if (op = Interpreter.FORM_OR) {
            result := _LispBoolean(false)
            for index, item in items {
                if (index = 1)
                    continue
                if this._IsSymbol(item) {
                    path := item.symbol
                    try {
                        value := this._LookupPathRoot(env, path)
                        tail := this._PathTail(path)
                        if (tail != "")
                            value := this._GetPath(value, tail)
                    } catch {
                        if (index = items.Length)
                            throw
                        continue
                    }
                } else
                    value := this._Evaluate(item, env)
                result := value
                if this._Truthy(this._CoerceBoolean(value))
                    return value
            }
            return result
        }
        if (op = Interpreter.FORM_NOT) {
            this._RequireCount(items, 2, Interpreter.FORM_NOT)
            condition := this._CoerceBoolean(this._Evaluate(items[2], env))
            return _LispBoolean(!this._Truthy(condition))
        }
        if (op = Interpreter.FORM_GET) {
            if (items.Length != 3)
                throw EvaluationError(op " expects a value, a key/path")
            target := this._Evaluate(items[2], env)
            path := this._Evaluate(items[3], env)
            return this._GetPath(target, path)
        }
        if (op = Interpreter.FORM_MAKE_ENV)
            return this._EvaluateMakeEnv(items, env)
        args := []
        index := 2
        while (index <= items.Length) {
            args.Push(this._Evaluate(items[index], env))
            index += 1
        }
        return this._Apply(op, args)
    }

    _EvaluateMakeEnv(items, env) {
        variables := Map()
        scope := this._CopyEnvironment(env)
        index := 2
        while (index <= items.Length) {
            binding := items[index]
            if !(binding is SyntaxForm) || binding.items.Length != 2
                throw EvaluationError(Interpreter.FORM_MAKE_ENV " expects each binding to contain a name and one value expression")

            nameExpr := binding.items[1]
            if this._IsSymbol(nameExpr)
                name := nameExpr.symbol
            else if (nameExpr is String)
                name := nameExpr
            else
                throw EvaluationError(Interpreter.FORM_MAKE_ENV " binding name must be a string or symbol")

            if (name = "" || InStr(name, "."))
                throw EvaluationError(Interpreter.FORM_MAKE_ENV " binding name must be non-empty and cannot contain a dot")
            for char in StrSplit(name) {
                if (this._IsWhitespace(char) || this._IsPunctuation(char) || char = Chr(34))
                    throw EvaluationError(Interpreter.FORM_MAKE_ENV " binding name is invalid: " name)
            }

            value := this._UnwrapBoolean(this._Evaluate(binding.items[2], scope))
            variables[name] := value
            scope[name] := value
            index += 1
        }
        return variables
    }

    _CopyEnvironment(env) {
        scope := Map()
        if (env is Map) {
            for name, value in env
                scope[name] := value
        } else if IsObject(env) {
            for name, value in ObjOwnProps(env)
                scope[name] := value
        }
        return scope
    }

    _Apply(op, args) {
        if !(op is String)
            throw EvaluationError("Operator must be a string, got " Type(op))
        if !this.builtins.Has(op)
            throw EvaluationError("Unknown operator: " op)
        return this.builtins[op](args)
    }

    _BuiltinAdd(args) {
        this._RequireAtLeast(args, 1, Interpreter.OP_ADD)
        value := 0
        for item in args
            value += this._Number(item)
        return value
    }

    _BuiltinSubtract(args) {
        this._RequireAtLeast(args, 1, Interpreter.OP_SUBTRACT)
        value := this._Number(args[1])
        if (args.Length = 1)
            return -value
        index := 2
        while (index <= args.Length) {
            value -= this._Number(args[index])
            index += 1
        }
        return value
    }

    _BuiltinMultiply(args) {
        this._RequireAtLeast(args, 1, Interpreter.OP_MULTIPLY)
        value := 1
        for item in args
            value *= this._Number(item)
        return value
    }

    _BuiltinDivide(args) {
        this._RequireAtLeast(args, 2, Interpreter.OP_DIVIDE)
        value := this._Number(args[1])
        index := 2
        while (index <= args.Length) {
            divisor := this._Number(args[index])
            if (divisor = 0)
                throw EvaluationError("Division by zero")
            value /= divisor
            index += 1
        }
        return value
    }

    _BuiltinModulo(args) {
        this._RequireCount(args, 2, Interpreter.OP_MODULO)
        return Mod(this._Number(args[1]), this._Number(args[2]))
    }

    _BuiltinEqual(args) {
        this._RequireCount(args, 2, Interpreter.OP_EQUAL)
        return _LispBoolean(this._UnwrapBoolean(args[1]) = this._UnwrapBoolean(args[2]))
    }

    _BuiltinNotEqual(args) {
        this._RequireCount(args, 2, Interpreter.OP_NOT_EQUAL)
        return _LispBoolean(this._UnwrapBoolean(args[1]) != this._UnwrapBoolean(args[2]))
    }

    _BuiltinLessThan(args) {
        this._RequireCount(args, 2, Interpreter.OP_LESS_THAN)
        return _LispBoolean(args[1] < args[2])
    }

    _BuiltinLessThanOrEqual(args) {
        this._RequireCount(args, 2, Interpreter.OP_LESS_THAN_OR_EQUAL)
        return _LispBoolean(args[1] <= args[2])
    }

    _BuiltinGreaterThan(args) {
        this._RequireCount(args, 2, Interpreter.OP_GREATER_THAN)
        return _LispBoolean(args[1] > args[2])
    }

    _BuiltinGreaterThanOrEqual(args) {
        this._RequireCount(args, 2, Interpreter.OP_GREATER_THAN_OR_EQUAL)
        return _LispBoolean(args[1] >= args[2])
    }

    _BuiltinConcat(args) {
        value := ""
        for item in args
            value .= item
        return value
    }

    _BuiltinJoin(args) {
        this._RequireAtLeast(args, 1, Interpreter.OP_JOIN)
        separator := args[1]
        if !(separator is String)
            throw EvaluationError(Interpreter.OP_JOIN " expects a string separator")
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
        this._RequireCount(args, 1, Interpreter.OP_COPY_TO_CLIPBOARD)
        value := args[1]
        A_Clipboard := value
        return NoResult()
    }

    _BuiltinLength(args) {
        this._RequireCount(args, 1, Interpreter.OP_LENGTH)
        if (args[1] is Array)
            return args[1].Length
        if (args[1] is Map)
            return args[1].Count
        return StrLen(args[1])
    }

    _BuiltinMatch(args) {
        this._RequireCount(args, 2, Interpreter.OP_MATCH)
        return _LispBoolean(RegExMatch(args[1], args[2]) != 0)
    }

    _BuiltinSubstr(args) {
        if (args.Length < 2 || args.Length > 3)
            throw EvaluationError(Interpreter.OP_SUBSTR " expects 2 or 3 arguments")
        text := this._RequireString(args[1], Interpreter.OP_SUBSTR, "text")
        start := this._RequireInteger(args[2], Interpreter.OP_SUBSTR, "start")
        if (args.Length = 2)
            return SubStr(text, start)
        length := this._RequireInteger(args[3], Interpreter.OP_SUBSTR, "length")
        return SubStr(text, start, length)
    }

    _BuiltinUpper(args) {
        this._RequireCount(args, 1, Interpreter.OP_UPPER)
        return StrUpper(this._RequireString(args[1], Interpreter.OP_UPPER, "text"))
    }

    _BuiltinLower(args) {
        this._RequireCount(args, 1, Interpreter.OP_LOWER)
        return StrLower(this._RequireString(args[1], Interpreter.OP_LOWER, "text"))
    }

    _BuiltinTrim(args) {
        if (args.Length < 1 || args.Length > 2)
            throw EvaluationError(Interpreter.OP_TRIM " expects 1 or 2 arguments")
        text := this._RequireString(args[1], Interpreter.OP_TRIM, "text")
        omitChars := args.Length = 2 ? this._RequireString(args[2], Interpreter.OP_TRIM, "omit characters") : " `t`r`n"
        return Trim(text, omitChars)
    }

    _BuiltinReplace(args) {
        this._RequireCount(args, 3, Interpreter.OP_REPLACE)
        text := this._RequireString(args[1], Interpreter.OP_REPLACE, "text")
        search := this._RequireString(args[2], Interpreter.OP_REPLACE, "search text")
        replacement := this._RequireString(args[3], Interpreter.OP_REPLACE, "replacement")
        if (search = "")
            throw EvaluationError(Interpreter.OP_REPLACE " expects non-empty search text")
        return StrReplace(text, search, replacement, true)
    }

    _BuiltinStartsWith(args) {
        this._RequireCount(args, 2, Interpreter.OP_STARTS_WITH)
        text := this._RequireString(args[1], Interpreter.OP_STARTS_WITH, "text")
        prefix := this._RequireString(args[2], Interpreter.OP_STARTS_WITH, "prefix")
        return _LispBoolean(SubStr(text, 1, StrLen(prefix)) == prefix)
    }

    _BuiltinEndsWith(args) {
        this._RequireCount(args, 2, Interpreter.OP_ENDS_WITH)
        text := this._RequireString(args[1], Interpreter.OP_ENDS_WITH, "text")
        suffix := this._RequireString(args[2], Interpreter.OP_ENDS_WITH, "suffix")
        return _LispBoolean(suffix == "" || SubStr(text, -StrLen(suffix)) == suffix)
    }

    _BuiltinIndexOf(args) {
        this._RequireCount(args, 2, Interpreter.OP_INDEX_OF)
        text := this._RequireString(args[1], Interpreter.OP_INDEX_OF, "text")
        search := this._RequireString(args[2], Interpreter.OP_INDEX_OF, "search text")
        return InStr(text, search, true)
    }

    _BuiltinStripPrefix(args) {
        this._RequireCount(args, 2, Interpreter.OP_STRIP_PREFIX)
        text := args[1], prefix := args[2]
        return (SubStr(text, 1, StrLen(prefix)) = prefix) ? SubStr(text, StrLen(prefix) + 1) : text
    }

    _BuiltinStripSuffix(args) {
        this._RequireCount(args, 2, Interpreter.OP_STRIP_SUFFIX)
        text := args[1], suffix := args[2]
        return (suffix != "" && SubStr(text, -StrLen(suffix)) = suffix) ? SubStr(text, 1, StrLen(text) - StrLen(suffix)) : text
    }

    _BuiltinContains(args) {
        this._RequireCount(args, 2, Interpreter.OP_CONTAINS)
        return _LispBoolean(this._Contains(args[1], args[2]))
    }

    _GetPath(target, path) {
        parts := StrSplit(path, ".")
        for part in parts
            target := this._GetOne(target, part)
        return target
    }

    _GetOne(target, key) {
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
        return this._Lookup(env, parts[1])
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
        if (env is Map) {
            if env.Has(name)
                return env[name]
        } else if IsObject(env) && env.HasOwnProp(name)
            return env.%name%
        throw EvaluationError("Variable is not present: " name)
    }

    _Contains(collection, value) {
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
        throw EvaluationError("contains expects an array, map, or string")
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
}
