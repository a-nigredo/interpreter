param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Expression,
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Iterations = 10000,
    [ValidateRange(1, 100)]
    [int]$Rounds = 3,
    [string]$AutoHotkeyPath
)

$ErrorActionPreference = 'Stop'

if (-not $AutoHotkeyPath) {
    $command = Get-Command 'AutoHotkey64.exe', 'AutoHotkey.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) { $AutoHotkeyPath = $command.Source }
}

if (-not $AutoHotkeyPath) {
    $installRoots = @(
        (Join-Path $env:ProgramFiles 'AutoHotkey'),
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }

    foreach ($root in $installRoots) {
        $candidates = @(
            (Join-Path $root 'v2\AutoHotkey64.exe'),
            (Join-Path $root 'v2\AutoHotkey.exe'),
            (Join-Path $root 'AutoHotkey64.exe'),
            (Join-Path $root 'AutoHotkey.exe')
        )
        $AutoHotkeyPath = $candidates |
            Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
            Select-Object -First 1
        if ($AutoHotkeyPath) { break }
    }
}

if (-not $AutoHotkeyPath) {
    throw 'AutoHotkey v2 was not found. Pass -AutoHotkeyPath with the full path to AutoHotkey.exe.'
}
if (-not (Test-Path -LiteralPath $AutoHotkeyPath -PathType Leaf)) {
    throw "AutoHotkey executable not found: $AutoHotkeyPath"
}

$runId = [guid]::NewGuid().ToString('N')
$tempRoot = [System.IO.Path]::GetTempPath()
$benchmarkScript = Join-Path $tempRoot "interpreter-benchmark-$runId.ahk"
$expressionPath = Join-Path $tempRoot "interpreter-expression-$runId.txt"
$resultsPath = Join-Path $tempRoot "interpreter-benchmark-$runId.txt"
$stdoutPath = Join-Path $tempRoot "interpreter-benchmark-$runId.stdout.txt"
$stderrPath = Join-Path $tempRoot "interpreter-benchmark-$runId.stderr.txt"

$scriptContent = @'
#Requires AutoHotkey v2.0
#Include "__INTERPRETER_PATH__"

resultsPath := A_Args[2]
try {
    expression := Trim(FileRead(A_Args[1]), " `t`r`n")
    if (expression = "")
        throw Error("The expression must not be empty.")

    iterations := __ITERATIONS__
    rounds := __ROUNDS__
    lisp := Interpreter()
    environment := lisp._CreateEnvironment()

    Loop rounds
        _Measure(expression, A_Index, iterations, lisp, environment, resultsPath)
} catch as err {
    FileAppend("ERROR|" err.Message "`n", resultsPath, "UTF-8")
    ExitApp(1)
}
ExitApp

_Measure(expression, roundNumber, iterations, lisp, environment, resultsPath) {
    lisp.Eval(expression, environment)
    started := A_TickCount
    Loop iterations
        lisp.Eval(expression, environment)
    elapsed := A_TickCount - started
    FileAppend(roundNumber "|" elapsed "`n", resultsPath, "UTF-8")
}
'@

$scriptContent = $scriptContent.Replace('__INTERPRETER_PATH__', (Join-Path $PSScriptRoot 'Interpreter.ahk'))
$scriptContent = $scriptContent.Replace('__ITERATIONS__', $Iterations.ToString())
$scriptContent = $scriptContent.Replace('__ROUNDS__', $Rounds.ToString())

try {
    [System.IO.File]::WriteAllText($expressionPath, $Expression, [System.Text.UTF8Encoding]::new($false))
    Set-Content -LiteralPath $benchmarkScript -Value $scriptContent -Encoding UTF8
    $argumentLine = '/ErrorStdOut "' + $benchmarkScript + '" "' + $expressionPath + '" "' + $resultsPath + '"'
    $process = Start-Process -FilePath $AutoHotkeyPath -ArgumentList $argumentLine `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

    if ($process.ExitCode -ne 0) {
        $diagnostics = @()
        if (Test-Path -LiteralPath $resultsPath) {
            $diagnostics += @(Get-Content -LiteralPath $resultsPath | Where-Object { $_ })
        }
        foreach ($logPath in @($stdoutPath, $stderrPath)) {
            if (Test-Path -LiteralPath $logPath) {
                $diagnostics += @(Get-Content -LiteralPath $logPath | Where-Object { $_ })
            }
        }
        $detail = if ($diagnostics.Count) { "`n" + ($diagnostics -join "`n") } else { '' }
        throw "AutoHotkey benchmark exited with code $($process.ExitCode).$detail"
    }
    if (-not (Test-Path -LiteralPath $resultsPath)) {
        throw 'The benchmark completed without producing results.'
    }

    $measurements = @()
    foreach ($line in Get-Content -LiteralPath $resultsPath) {
        if ($line -match '^(\d+)\|(\d+)$') {
            $measurements += [PSCustomObject]@{
                Round = [int]$Matches[1]
                Milliseconds = [double]$Matches[2]
            }
        } elseif (-not [string]::IsNullOrWhiteSpace($line)) {
            throw "Malformed benchmark result: $line"
        }
    }

    if ($measurements.Count -ne $Rounds) {
        throw "Expected $Rounds measurements, got $($measurements.Count)."
    }
    $sorted = @($measurements.Milliseconds | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    $median = if ($sorted.Count % 2) {
        $sorted[$middle]
    } else {
        ($sorted[$middle - 1] + $sorted[$middle]) / 2
    }

    Write-Host "AutoHotkey: $AutoHotkeyPath"
    Write-Host "Expression: $Expression"
    Write-Host "Rounds: $Rounds; iterations per round: $Iterations"
    [PSCustomObject]@{
        Iterations = $Iterations
        MedianMs = [Math]::Round($median, 1)
        MicrosecondsPerEval = [Math]::Round(($median * 1000 / $Iterations), 2)
        EvaluationsPerSecond = if ($median -gt 0) {
            [Math]::Round(($Iterations * 1000 / $median), 0)
        } else {
            'below timer resolution'
        }
    } | Format-List | Out-String | Write-Host
}
finally {
    foreach ($path in @($benchmarkScript, $expressionPath, $resultsPath, $stdoutPath, $stderrPath)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}
