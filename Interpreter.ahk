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
            this.sourceExpression := location.source
            message .= "`nExpression: " location.source
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

class LambdaFunction {
    __New(parameters, body, environment) {
        this.parameters := parameters
        this.body := body
        this.environment := environment
    }
}

class NoResult {
}

class Interpreter {
    static _TrueLiteral := "t"
    static _NilLiteral := "nil"
    static _OperatorAdd := "+"
    static _OperatorSubtract := "-"
    static _OperatorMultiply := "*"
    static _OperatorDivide := "/"
    static _OperatorModulo := "%"
    static _OperatorEqual := "="
    static _OperatorEqualAlias := "=="
    static _OperatorNotEqual := "!="
    static _OperatorNotEqualAlias := "<>"
    static _OperatorLessThan := "<"
    static _OperatorLessThanOrEqual := "<="
    static _OperatorGreaterThan := ">"
    static _OperatorGreaterThanOrEqual := ">="
    static _OperatorConcat := "concat"
    static _OperatorJoin := "join"
    static _OperatorArray := "array"
    static _OperatorCopyToClipboard := "copy-to-clipboard"
    static _OperatorLength := "length"
    static _OperatorMatch := "match"
    static _OperatorSubstr := "substr"
    static _OperatorUpper := "upper"
    static _OperatorLower := "lower"
    static _OperatorTrim := "trim"
    static _OperatorReplace := "replace"
    static _OperatorStartsWith := "starts-with"
    static _OperatorEndsWith := "ends-with"
    static _OperatorIndexOf := "index-of"
    static _OperatorStripPrefix := "strip-prefix"
    static _OperatorStripSuffix := "strip-suffix"
    static _OperatorContains := "contains"
    static _OperatorIn := "in"
    static _OperatorNumberType := "number?"
    static _OperatorIntegerType := "integer?"
    static _OperatorFloatType := "float?"
    static _OperatorStringType := "string?"
    static _FormIf := "if"
    static _FormCond := "cond"
    static _FormWhen := "when"
    static _FormDo := "do"
    static _FormLet := "let"
    static _FormFunc := "func"
    static _FormAnd := "and"
    static _FormOr := "or"
    static _FormNot := "not"
    static _OpeningParenthesis := "("
    static _ClosingParenthesis := ")"
    static _OperatorGet := "get"
    static _OperatorMakeEnv := "make-env"

    __New(cacheSize := 256) {
        this.DefineProp("Eval", {Call: Evaluate})

        ; Keep the language operators in one registry. Aliases point to the same
        ; implementation, and adding a builtin does not require extending Apply's
        ; dispatch logic.
        builtins := Map(
            Interpreter._OperatorAdd, _BuiltinAdd,
            Interpreter._OperatorSubtract, _BuiltinSubtract,
            Interpreter._OperatorMultiply, _BuiltinMultiply,
            Interpreter._OperatorDivide, _BuiltinDivide,
            Interpreter._OperatorModulo, _BuiltinModulo,
            Interpreter._OperatorEqual, _BuiltinEqual,
            Interpreter._OperatorEqualAlias, _BuiltinEqual,
            Interpreter._OperatorNotEqual, _BuiltinNotEqual,
            Interpreter._OperatorNotEqualAlias, _BuiltinNotEqual,
            Interpreter._OperatorLessThan, _BuiltinLessThan,
            Interpreter._OperatorLessThanOrEqual, _BuiltinLessThanOrEqual,
            Interpreter._OperatorGreaterThan, _BuiltinGreaterThan,
            Interpreter._OperatorGreaterThanOrEqual, _BuiltinGreaterThanOrEqual,
            Interpreter._OperatorConcat, _BuiltinConcat,
            Interpreter._OperatorJoin, _BuiltinJoin,
            Interpreter._OperatorArray, _BuiltinArray,
            Interpreter._OperatorCopyToClipboard, _BuiltinCopyToClipboard,
            Interpreter._OperatorLength, _BuiltinLength,
            Interpreter._OperatorMatch, _BuiltinMatch,
            Interpreter._OperatorSubstr, _BuiltinSubstr,
            Interpreter._OperatorUpper, _BuiltinUpper,
            Interpreter._OperatorLower, _BuiltinLower,
            Interpreter._OperatorTrim, _BuiltinTrim,
            Interpreter._OperatorReplace, _BuiltinReplace,
            Interpreter._OperatorStartsWith, _BuiltinStartsWith,
            Interpreter._OperatorEndsWith, _BuiltinEndsWith,
            Interpreter._OperatorIndexOf, _BuiltinIndexOf,
            Interpreter._OperatorStripPrefix, _BuiltinStripPrefix,
            Interpreter._OperatorStripSuffix, _BuiltinStripSuffix,
            Interpreter._OperatorContains, _BuiltinContains,
            Interpreter._OperatorIn, _BuiltinContains,
            Interpreter._OperatorNumberType, _BuiltinNumberType,
            Interpreter._OperatorIntegerType, _BuiltinIntegerType,
            Interpreter._OperatorFloatType, _BuiltinFloatType,
            Interpreter._OperatorStringType, _BuiltinStringType
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
            if (text = Interpreter._TrueLiteral)
                return true
            if (text = Interpreter._NilLiteral)
                return false
            if RegExMatch(text, "^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$")
                return text + 0
            return text
        }

        _IsPunctuation(ch) => InStr(Interpreter._OpeningParenthesis Interpreter._ClosingParenthesis "[]{}", ch) != 0

        _IsPunctuationToken(token, value := "") => token.kind = "punct" && (value = "" || token.value = value)

        _IsOpeningParenthesis(token) => _IsPunctuationToken(token, Interpreter._OpeningParenthesis)

        _IsWhitespace(ch) => ch = " " || ch = "`t" || ch = "`r" || ch = "`n"

        _IsSymbol(value) => IsObject(value) && value.HasOwnProp("symbol")

        _ReadPunctuation(state, token) {
            if _IsOpeningParenthesis(token)
                return _ReadSequence(state, Interpreter._ClosingParenthesis, token)
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
            return _Evaluate(value, env)
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
            if (SubStr(items[1], 1, 1) = "$")
                formItems.Push({symbol: SubStr(items[1], 2)})
            else
                formItems.Push(items[1])
            index := 2
            while (index <= items.Length) {
                item := items[index]
                if (item is String && SubStr(item, 1, 1) = Interpreter._OpeningParenthesis) {
                    formItems.Push(_GetOrParseExpression(item))
                    index += 1
                    continue
                }
                if (items[1] = Interpreter._FormLet && index = 2 && item is Array) {
                    bindings := []
                    for bindingIndex, bindingItem in item {
                        if Mod(bindingIndex, 2) = 0 {
                            if (bindingItem is Array)
                                bindingItem := _BuildArrayExpression(bindingItem)
                            else if (bindingItem is String
                                && SubStr(bindingItem, 1, 1) = Interpreter._OpeningParenthesis)
                                bindingItem := _GetOrParseExpression(bindingItem)
                        }
                        bindings.Push(bindingItem)
                    }
                    formItems.Push(SyntaxForm(bindings))
                    index += 1
                    continue
                }
                if (items[1] = Interpreter._FormFunc && index = 2 && item is Array) {
                    formItems.Push(SyntaxForm(item))
                    index += 1
                    continue
                }
                if (items[1] = Interpreter._FormCond) {
                    if !(item is Array) || item.Length = 0
                        throw EvaluationError("cond expression arrays require non-empty clause arrays.")
                    clauseItems := []
                    for clauseItem in item {
                        if (clauseItem is Array)
                            clauseItem := _BuildArrayExpression(clauseItem)
                        clauseItems.Push(clauseItem)
                    }
                    formItems.Push(SyntaxForm(clauseItems))
                    index += 1
                    continue
                }
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
            if (value = Interpreter._TrueLiteral || value = Interpreter._NilLiteral
                || RegExMatch(value, "^-?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"))
                throw EvaluationError("An operator array element must be a symbol, not a number.")
        }

        _Parse(source) {
            tokens := _Tokenize(source)
            state := {tokens: tokens, index: 1, source: source}
            isScalar := tokens.Length > 0 && (tokens[1].kind = "string"
                || (tokens[1].kind = "atom" && (tokens[1].value = Interpreter._TrueLiteral
                    || tokens[1].value = Interpreter._NilLiteral
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
            return Map()
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
                op := _Lookup(env, head.symbol)
            else
                op := _Evaluate(head, env)
            isNamedOperator := op is String
            if (isNamedOperator && op = Interpreter._FormIf) {
                _RequireCount(items, 4, Interpreter._FormIf)
                condition := _Evaluate(items[2], env)
                return _Truthy(condition) ? _Evaluate(items[3], env) : _Evaluate(items[4], env)
            }
            if (isNamedOperator && op = Interpreter._FormCond)
                return _EvaluateCond(items, env)
            if (isNamedOperator && op = Interpreter._FormWhen) {
                _RequireAtLeast(items, 2, Interpreter._FormWhen)
                condition := _Evaluate(items[2], env)
                result := false
                if !_Truthy(condition)
                    return result
                index := 3
                while (index <= items.Length) {
                    result := _Evaluate(items[index], env)
                    index += 1
                }
                return result
            }
            if (isNamedOperator && op = Interpreter._FormDo)
                return _EvaluateBody(items, 2, env)
            if (isNamedOperator && op = Interpreter._FormLet)
                return _EvaluateLet(items, env)
            if (isNamedOperator && op = Interpreter._FormFunc)
                return _EvaluateFunc(items, env)
            if (isNamedOperator && op = Interpreter._FormAnd) {
                result := true
                for index, item in items {
                    if (index = 1)
                        continue
                    result := _Evaluate(item, env)
                    if !_Truthy(result)
                        return result
                }
                return result
            }
            if (isNamedOperator && op = Interpreter._FormOr) {
                result := false
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
                    if _Truthy(value)
                        return value
                }
                return result
            }
            if (isNamedOperator && op = Interpreter._FormNot) {
                _RequireCount(items, 2, Interpreter._FormNot)
                condition := _Evaluate(items[2], env)
                return !_Truthy(condition)
            }
            if (isNamedOperator && op = Interpreter._OperatorGet) {
                if (items.Length != 3)
                    throw EvaluationError(op " expects a value, a key/path")
                target := _Evaluate(items[2], env)
                path := _Evaluate(items[3], env)
                return _GetPath(target, path)
            }
            if (isNamedOperator && op = Interpreter._OperatorMakeEnv)
                return _EvaluateMakeEnv(items, env)
            args := []
            index := 2
            while (index <= items.Length) {
                args.Push(_Evaluate(items[index], env))
                index += 1
            }
            return _Apply(op, args)
        }

        _EvaluateBody(items, startIndex, env) {
            result := false
            index := startIndex
            while (index <= items.Length) {
                result := _Evaluate(items[index], env)
                index += 1
            }
            return result
        }

        _EvaluateLet(items, env) {
            _RequireAtLeast(items, 2, Interpreter._FormLet)
            bindings := items[2]
            if !(bindings is SyntaxForm)
                throw EvaluationError(Interpreter._FormLet " expects a binding list")

            names := []
            values := []
            bindingItems := bindings.items
            if (Mod(bindingItems.Length, 2) != 0)
                throw EvaluationError(Interpreter._FormLet " expects alternating names and values")

            index := 1
            while (index <= bindingItems.Length) {
                nameExpr := bindingItems[index]
                valueExpr := bindingItems[index + 1]
                if (nameExpr is SyntaxForm)
                    throw EvaluationError(Interpreter._FormLet " expects alternating names and values")
                name := _GetBindingName(nameExpr, Interpreter._FormLet)
                for existingName in names {
                    if (existingName = name)
                        throw EvaluationError(Interpreter._FormLet " binding names must be unique: " name)
                }
                names.Push(name)
                values.Push(_Evaluate(valueExpr, env))
                index += 2
            }

            scope := _CopyEnvironment(env)
            for index, name in names
                _AddEnvironmentValue(scope, name, values[index])
            return _EvaluateBody(items, 3, scope)
        }

        _EvaluateFunc(items, env) {
            _RequireAtLeast(items, 3, Interpreter._FormFunc)
            parameterForm := items[2]
            if !(parameterForm is SyntaxForm)
                throw EvaluationError(Interpreter._FormFunc " expects a parameter list")

            parameters := []
            for parameter in parameterForm.items {
                name := _GetBindingName(parameter, Interpreter._FormFunc)
                for existingName in parameters {
                    if (existingName = name)
                        throw EvaluationError(Interpreter._FormFunc " parameter names must be unique: " name)
                }
                parameters.Push(name)
            }
            body := []
            index := 3
            while (index <= items.Length) {
                body.Push(items[index])
                index += 1
            }
            return LambdaFunction(parameters, body, _CopyEnvironment(env))
        }

        _GetBindingName(nameExpr, op) {
            if _IsSymbol(nameExpr)
                name := nameExpr.symbol
            else if (nameExpr is String)
                name := nameExpr
            else
                throw EvaluationError(op " binding name must be a string or symbol")

            if (name = "" || InStr(name, "."))
                throw EvaluationError(op " binding name must be non-empty and cannot contain a dot")
            for char in StrSplit(name) {
                if (_IsWhitespace(char) || _IsPunctuation(char) || char = Chr(34))
                    throw EvaluationError(op " binding name is invalid: " name)
            }
            return name
        }

        _EvaluateCond(items, env) {
            index := 2
            while (index <= items.Length) {
                clause := items[index]
                if !(clause is SyntaxForm) || clause.items.Length = 0
                    throw EvaluationError(Interpreter._FormCond " expects each clause to contain a test")

                test := _Evaluate(clause.items[1], env)
                if _Truthy(test) {
                    if (clause.items.Length = 1)
                        return test
                    result := false
                    bodyIndex := 2
                    while (bodyIndex <= clause.items.Length) {
                        result := _Evaluate(clause.items[bodyIndex], env)
                        bodyIndex += 1
                    }
                    return result
                }
                index += 1
            }
            return false
        }

        _EvaluateMakeEnv(items, env) {
            variables := Map()
            scope := _CopyEnvironment(env)
            index := 2
            while (index <= items.Length) {
                binding := items[index]
                if !(binding is SyntaxForm) || binding.items.Length != 2
                    throw EvaluationError(Interpreter._OperatorMakeEnv " expects each binding to contain a name and one value expression")

                name := _GetBindingName(binding.items[1], Interpreter._OperatorMakeEnv)

                value := _Evaluate(binding.items[2], scope)
                _AddEnvironmentValue(variables, name, value)
                _AddEnvironmentValue(scope, name, value)
                index += 1
            }
            return variables
        }

        _CopyEnvironment(env) {
            if !(env is Map) && !(IsObject(env) && Type(env) = "Object")
                throw EvaluationError(Interpreter._OperatorMakeEnv " requires a Map or object context")
            copy := Map()
            if (env is Map) {
                for name, value in env
                    copy[name] := value
            } else {
                for name in ObjOwnProps(env)
                    copy[name] := env.%name%
            }
            return copy
        }

        _AddEnvironmentValue(env, name, value) {
            env[name] := value
        }

        _Apply(op, args) {
            if (op is LambdaFunction)
                return _InvokeLambda(op, args)
            if !(op is String)
                throw EvaluationError("Operator must be a string, got " Type(op))
            if !builtins.Has(op)
                throw EvaluationError("Unknown operator: " op)
            return builtins[op](args)
        }

        _InvokeLambda(function, args) {
            if (args.Length != function.parameters.Length)
                throw EvaluationError("func expects " function.parameters.Length " argument(s)")
            scope := _CopyEnvironment(function.environment)
            for index, name in function.parameters
                _AddEnvironmentValue(scope, name, args[index])
            result := false
            for expression in function.body
                result := _Evaluate(expression, scope)
            return result
        }

        _BuiltinAdd(args) {
            _RequireAtLeast(args, 1, Interpreter._OperatorAdd)
            value := 0
            for item in args
                value += _Number(item)
            return value
        }

        _BuiltinSubtract(args) {
            _RequireAtLeast(args, 1, Interpreter._OperatorSubtract)
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
            _RequireAtLeast(args, 1, Interpreter._OperatorMultiply)
            value := 1
            for item in args
                value *= _Number(item)
            return value
        }

        _BuiltinDivide(args) {
            _RequireAtLeast(args, 2, Interpreter._OperatorDivide)
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
            _RequireCount(args, 2, Interpreter._OperatorModulo)
            return Mod(_Number(args[1]), _Number(args[2]))
        }

        _BuiltinEqual(args) {
            _RequireCount(args, 2, Interpreter._OperatorEqual)
            return args[1] = args[2]
        }

        _BuiltinNotEqual(args) {
            _RequireCount(args, 2, Interpreter._OperatorNotEqual)
            return args[1] != args[2]
        }

        _BuiltinLessThan(args) {
            _RequireCount(args, 2, Interpreter._OperatorLessThan)
            return args[1] < args[2]
        }

        _BuiltinLessThanOrEqual(args) {
            _RequireCount(args, 2, Interpreter._OperatorLessThanOrEqual)
            return args[1] <= args[2]
        }

        _BuiltinGreaterThan(args) {
            _RequireCount(args, 2, Interpreter._OperatorGreaterThan)
            return args[1] > args[2]
        }

        _BuiltinGreaterThanOrEqual(args) {
            _RequireCount(args, 2, Interpreter._OperatorGreaterThanOrEqual)
            return args[1] >= args[2]
        }

        _BuiltinNumberType(args) {
            _RequireCount(args, 1, Interpreter._OperatorNumberType)
            return args[1] is Integer || args[1] is Float
        }

        _BuiltinIntegerType(args) {
            _RequireCount(args, 1, Interpreter._OperatorIntegerType)
            return args[1] is Integer
        }

        _BuiltinFloatType(args) {
            _RequireCount(args, 1, Interpreter._OperatorFloatType)
            return args[1] is Float
        }

        _BuiltinStringType(args) {
            _RequireCount(args, 1, Interpreter._OperatorStringType)
            return args[1] is String
        }

        _BuiltinConcat(args) {
            value := ""
            for item in args
                value .= item
            return value
        }

        _BuiltinJoin(args) {
            _RequireAtLeast(args, 1, Interpreter._OperatorJoin)
            separator := args[1]
            if !(separator is String)
                throw EvaluationError(Interpreter._OperatorJoin " expects a string separator")
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

        _BuiltinArray(args) {
            return args
        }

        _BuiltinCopyToClipboard(args) {
            _RequireCount(args, 1, Interpreter._OperatorCopyToClipboard)
            value := args[1]
            A_Clipboard := value
            return NoResult()
        }

        _BuiltinLength(args) {
            _RequireCount(args, 1, Interpreter._OperatorLength)
            if (args[1] is Array)
                return args[1].Length
            if (args[1] is Map)
                return args[1].Count
            return StrLen(args[1])
        }

        _BuiltinMatch(args) {
            _RequireCount(args, 2, Interpreter._OperatorMatch)
            return RegExMatch(args[1], args[2]) != 0
        }

        _BuiltinSubstr(args) {
            if (args.Length < 2 || args.Length > 3)
                throw EvaluationError(Interpreter._OperatorSubstr " expects 2 or 3 arguments")
            text := _RequireString(args[1], Interpreter._OperatorSubstr, "text")
            start := _RequireInteger(args[2], Interpreter._OperatorSubstr, "start")
            if (args.Length = 2)
                return SubStr(text, start)
            length := _RequireInteger(args[3], Interpreter._OperatorSubstr, "length")
            return SubStr(text, start, length)
        }

        _BuiltinUpper(args) {
            _RequireCount(args, 1, Interpreter._OperatorUpper)
            return StrUpper(_RequireString(args[1], Interpreter._OperatorUpper, "text"))
        }

        _BuiltinLower(args) {
            _RequireCount(args, 1, Interpreter._OperatorLower)
            return StrLower(_RequireString(args[1], Interpreter._OperatorLower, "text"))
        }

        _BuiltinTrim(args) {
            if (args.Length < 1 || args.Length > 2)
                throw EvaluationError(Interpreter._OperatorTrim " expects 1 or 2 arguments")
            text := _RequireString(args[1], Interpreter._OperatorTrim, "text")
            omitChars := args.Length = 2 ? _RequireString(args[2], Interpreter._OperatorTrim, "omit characters") : " `t`r`n"
            return Trim(text, omitChars)
        }

        _BuiltinReplace(args) {
            _RequireCount(args, 3, Interpreter._OperatorReplace)
            text := _RequireString(args[1], Interpreter._OperatorReplace, "text")
            search := _RequireString(args[2], Interpreter._OperatorReplace, "search text")
            replacement := _RequireString(args[3], Interpreter._OperatorReplace, "replacement")
            if (search = "")
                throw EvaluationError(Interpreter._OperatorReplace " expects non-empty search text")
            return StrReplace(text, search, replacement, true)
        }

        _BuiltinStartsWith(args) {
            _RequireCount(args, 2, Interpreter._OperatorStartsWith)
            text := _RequireString(args[1], Interpreter._OperatorStartsWith, "text")
            prefix := _RequireString(args[2], Interpreter._OperatorStartsWith, "prefix")
            return SubStr(text, 1, StrLen(prefix)) == prefix
        }

        _BuiltinEndsWith(args) {
            _RequireCount(args, 2, Interpreter._OperatorEndsWith)
            text := _RequireString(args[1], Interpreter._OperatorEndsWith, "text")
            suffix := _RequireString(args[2], Interpreter._OperatorEndsWith, "suffix")
            return suffix == "" || SubStr(text, -StrLen(suffix)) == suffix
        }

        _BuiltinIndexOf(args) {
            _RequireCount(args, 2, Interpreter._OperatorIndexOf)
            text := _RequireString(args[1], Interpreter._OperatorIndexOf, "text")
            search := _RequireString(args[2], Interpreter._OperatorIndexOf, "search text")
            return InStr(text, search, true)
        }

        _BuiltinStripPrefix(args) {
            _RequireCount(args, 2, Interpreter._OperatorStripPrefix)
            text := args[1], prefix := args[2]
            return (SubStr(text, 1, StrLen(prefix)) = prefix) ? SubStr(text, StrLen(prefix) + 1) : text
        }

        _BuiltinStripSuffix(args) {
            _RequireCount(args, 2, Interpreter._OperatorStripSuffix)
            text := args[1], suffix := args[2]
            return (suffix != "" && SubStr(text, -StrLen(suffix)) = suffix) ? SubStr(text, 1, StrLen(text) - StrLen(suffix)) : text
        }

        _BuiltinContains(args) {
            _RequireCount(args, 2, Interpreter._OperatorContains)
            return _Contains(args[1], args[2])
        }

        _GetPath(target, path) {
            parts := StrSplit(path, ".")
            for part in parts
                target := _GetOne(target, part)
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

        _Truthy(value) => value ? true : false

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
