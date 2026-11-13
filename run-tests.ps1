param(
    [string]$AutoHotkeyPath
)

$ErrorActionPreference = 'Stop'
$testScript = Join-Path $PSScriptRoot 'Interpreter_test.ahk'
$tempRoot = [System.IO.Path]::GetTempPath()
$runId = [guid]::NewGuid().ToString('N')
$resultsPath = Join-Path $tempRoot "interpreter-tests-$runId.txt"
$stdoutPath = Join-Path $tempRoot "interpreter-tests-$runId.stdout.txt"
$stderrPath = Join-Path $tempRoot "interpreter-tests-$runId.stderr.txt"

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

$caseNames = @(
    [regex]::Matches((Get-Content -LiteralPath $testScript -Raw), '(?m)^\s*Assert(?:CacheConfiguration|EvalCache|MakeEnv|Eval|Throws|EvaluationError|EvaluationPosition|EvaluationCause|ReaderThrows|GetOneThrows|ObjectPassthrough|Clipboard|NoResult)\("([^"]+)"') |
        ForEach-Object { $_.Groups[1].Value }
)

try {
    Write-Host "Running interpreter tests with $AutoHotkeyPath..."
    # Start-Process -Wait ensures the AHK process has exited and closed the
    # results file before PowerShell reads it. Avoid stdout for test records:
    # GUI-subsystem AutoHotkey builds do not reliably expose redirected stdout.
    $argumentLine = '/ErrorStdOut "' + $testScript + '" "' + $resultsPath + '"'
    $process = Start-Process -FilePath $AutoHotkeyPath -ArgumentList $argumentLine `
        -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $testExitCode = $process.ExitCode

    $caseResults = @{}
    $diagnostics = @()
    if (Test-Path -LiteralPath $resultsPath) {
        foreach ($line in Get-Content -LiteralPath $resultsPath) {
            if ($line -match '^(PASS|FAIL)\|([^|]*)\|(.*)$') {
                $caseResults[$Matches[2]] = [PSCustomObject]@{ Status = $Matches[1]; Details = $Matches[3] }
            } elseif (-not [string]::IsNullOrWhiteSpace($line)) {
                $diagnostics += "Malformed result: $line"
            }
        }
    }
    foreach ($logPath in @($stdoutPath, $stderrPath)) {
        if (Test-Path -LiteralPath $logPath) {
            $diagnostics += @(Get-Content -LiteralPath $logPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }

    $rows = @()
    $passed = 0
    $failed = 0
    $notRun = 0
    foreach ($caseName in $caseNames) {
        if ($caseResults.ContainsKey($caseName)) {
            $result = $caseResults[$caseName]
            $rows += [PSCustomObject]@{ Status = $result.Status; Case = $caseName; Details = $result.Details }
            if ($result.Status -eq 'PASS') { $passed++ } else { $failed++ }
        } else {
            $notRun++
            $reason = if ($testExitCode -ne 0) {
                "No result recorded; AutoHotkey exited with code $testExitCode."
            } else {
                "No result recorded in $resultsPath."
            }
            $rows += [PSCustomObject]@{ Status = 'NOT RUN'; Case = $caseName; Details = $reason }
        }
    }
    foreach ($name in $caseResults.Keys) {
        if ($caseNames -notcontains $name) {
            $failed++
            $rows += [PSCustomObject]@{ Status = 'FAIL'; Case = $name; Details = 'Result is not a declared test case.' }
        }
    }
    if ($testExitCode -ne 0) {
        $failed++
        $rows += [PSCustomObject]@{ Status = 'FAIL'; Case = 'AutoHotkey process'; Details = "Exited with code $testExitCode." }
    }
    if ($caseNames.Count -eq 0) {
        $failed++
        $rows += [PSCustomObject]@{ Status = 'FAIL'; Case = 'Test case discovery'; Details = 'No AssertEval/AssertThrows cases found.' }
    }

    $caseWidth = [Math]::Max(9, ($rows | ForEach-Object { $_.Case.Length } | Measure-Object -Maximum).Maximum)
    $detailsWidth = [Math]::Max(12, [Math]::Min(54, ($rows | ForEach-Object { $_.Details.Length } | Measure-Object -Maximum).Maximum))
    $header = '| {0,-7} | {1,-' + $caseWidth + '} | {2,-' + $detailsWidth + '} |'
    $caseFormat = '{0,-' + $caseWidth + '}'
    $detailsFormat = ' | {0,-' + $detailsWidth + '} |'
    $border = '+' + ('-' * 9) + '+' + ('-' * ($caseWidth + 2)) + '+' + ('-' * ($detailsWidth + 2)) + '+'
    $useColor = -not [Console]::IsOutputRedirected
    [Console]::WriteLine($border)
    [Console]::WriteLine(($header -f 'Status', 'Test case', 'Details'))
    [Console]::WriteLine($border)
    foreach ($row in $rows) {
        $case = $row.Case
        $details = $row.Details
        if ($details.Length -gt $detailsWidth) { $details = $details.Substring(0, $detailsWidth - 3) + '...' }
        $color = if ($row.Status -eq 'PASS') { 'Green' } elseif ($row.Status -eq 'FAIL') { 'Red' } else { 'Yellow' }
        [Console]::Write('| ')
        if ($useColor) {
            $previousColor = [Console]::ForegroundColor
            [Console]::ForegroundColor = [Enum]::Parse([ConsoleColor], $color)
        }
        [Console]::Write(('{0,-7}' -f $row.Status))
        if ($useColor) {
            [Console]::ForegroundColor = $previousColor
        }
        [Console]::Write(' | ')
        if ($useColor) {
            [Console]::ForegroundColor = [Enum]::Parse([ConsoleColor], $color)
        }
        [Console]::Write(($caseFormat -f $case))
        if ($useColor) {
            [Console]::ForegroundColor = $previousColor
        }
        [Console]::WriteLine(($detailsFormat -f $details))
        [Console]::WriteLine($border)
    }

    if ($diagnostics.Count -gt 0) {
        Write-Host "`nAutoHotkey diagnostics:"
        foreach ($line in $diagnostics) { Write-Host $line }
    }

    $total = $passed + $failed + $notRun
    Write-Host "`nTest summary: $passed passed, $failed failed, $notRun not run, $total total."
    if ($testExitCode -ne 0 -or $failed -gt 0 -or $notRun -gt 0) { exit 1 }
    exit 0
}
finally {
    foreach ($path in @($resultsPath, $stdoutPath, $stderrPath)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}
