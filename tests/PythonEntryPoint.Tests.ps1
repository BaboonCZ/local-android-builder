Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Assert-Equal {
    param ($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) {
        throw "${Message}: expected '$Expected', got '$Actual'."
    }
}

function Assert-PathEqual {
    param ([string]$Actual, [string]$Expected, [string]$Message)
    if (-not [string]::Equals(
        [System.IO.Path]::GetFullPath($Actual),
        [System.IO.Path]::GetFullPath($Expected),
        [System.StringComparison]::OrdinalIgnoreCase
    )) {
        throw "${Message}: expected '$Expected', got '$Actual'."
    }
}

function Assert-OutputContains {
    param ([object[]]$Output, [string]$Expected, [string]$Message)
    $text = ($Output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($text -notlike "*$Expected*") { throw "${Message}: '$Expected' not found." }
}

function Assert-OutputNotContains {
    param ([object[]]$Output, [string]$Unexpected, [string]$Message)
    $text = ($Output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($text -like "*$Unexpected*") { throw "${Message}: unexpected '$Unexpected'." }
}

function Get-BooleanResult {
    param ([object[]]$Output)
    $values = @($Output | Where-Object { $_ -is [bool] })
    if ($values.Count -ne 1) { throw "Expected one pause decision; got $($values.Count)." }
    return $values[0]
}

function Write-FixtureFile {
    param ([string]$Path, [string]$Content)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding $false))
}

function Get-Text {
    param ([string]$Key, [string]$Lang)
    return $Key
}

function Show-Menu {
    param ([string]$Title, [array]$Options)
    $script:menuCalls++
    $script:menuOptions = @($Options)
    $script:menuTitle = $Title
    return $script:menuChoice
}

function Get-PythonRuntime {
    param ([string]$ProjectPath)
    if ($script:runtimeAvailable) { return $script:runtime }
    return $null
}

$python = Get-Command python -ErrorAction SilentlyContinue
if ($python) {
    $script:runtime = @{ Path = $python.Source; Prefix = @() }
} else {
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if (-not $launcher) { throw 'Python 3 is required to run these tests.' }
    $script:runtime = @{ Path = $launcher.Source; Prefix = @('-3') }
}
$script:runtimeAvailable = $true
$script:menuCalls = 0
$script:menuOptions = @()
$script:menuTitle = ''
$script:menuChoice = -1

$builderPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'builder.ps1'
$tokens = $null
$parseErrors = $null
$builderAst = [System.Management.Automation.Language.Parser]::ParseFile(
    $builderPath, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) { throw "Builder has PowerShell syntax errors: $parseErrors" }

foreach ($name in @(
    'Get-PythonBuildArguments',
    'Get-PythonSpecEntryPoints',
    'Select-PythonEntryPoint',
    'Invoke-PythonProjectRun',
    'Invoke-PythonProjectBuild'
)) {
    $functionAst = $builderAst.Find({
        param ($candidate)
        $candidate -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $candidate.Name -eq $name
    }, $true)
    if (-not $functionAst) { throw "Builder function not found: $name" }
    Invoke-Expression $functionAst.Extent.Text
}

$actionSwitch = $builderAst.Find({
    param ($candidate)
    $candidate -is [System.Management.Automation.Language.SwitchStatementAst] -and
        $candidate.Condition.Extent.Text -eq '$selectedAction'
}, $true)
if (-not $actionSwitch) { throw 'Project action switch not found.' }
$runClause = @($actionSwitch.Clauses | Where-Object { $_.Item1.Extent.Text -like "*'PythonRun'*" })
$buildClause = @($actionSwitch.Clauses | Where-Object { $_.Item1.Extent.Text -like "*'PythonBuild'*" })
if ($runClause.Count -ne 1 -or $buildClause.Count -ne 1) { throw 'Python menu actions not found.' }
$runBody = $runClause[0].Item2.Extent.Text
$buildBody = $buildClause[0].Item2.Extent.Text
$runAction = [scriptblock]::Create($runBody.Substring(1, $runBody.Length - 2))
$buildAction = [scriptblock]::Create($buildBody.Substring(1, $buildBody.Length - 2))

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("builder python tests " + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    $specProject = Join-Path $testRoot 'Domaindiag'
    $mainFile = Join-Path $specProject 'DomainAdminMonitor.py'
    $specSentinel = Join-Path $specProject 'spec-executed.txt'
    $escapedSentinel = $specSentinel.Replace('\', '\\').Replace("'", "\'")
    Write-FixtureFile $mainFile "from pathlib import Path`nPath('ran.txt').write_text('ok')`nprint('expected application output')`n"
    Write-FixtureFile (Join-Path $specProject 'main.py') "raise RuntimeError('wrong entry')`n"
    Write-FixtureFile (Join-Path $specProject 'test_monitor.py') ''
    Write-FixtureFile (Join-Path $specProject 'DomainAdminMonitor.spec') (
        "open('$escapedSentinel', 'w').write('unexpected')`n" +
        "a = Analysis(['DomainAdminMonitor.py'], pathex=[])`n"
    )

    $script:menuCalls = 0
    $entry = Select-PythonEntryPoint -ProjectPath $specProject -ProjectName 'Domaindiag' -Lang 'EN' -Runtime $script:runtime
    Assert-Equal $entry.Status 'Selected' 'Spec entry must be selected'
    Assert-PathEqual $entry.Path $mainFile 'Spec entry must take precedence over main.py'
    Assert-Equal $script:menuCalls 0 'An unambiguous spec must not open a file menu'
    Assert-Equal (Test-Path -LiteralPath $specSentinel) $false 'Spec code must never execute'

    $runOutput = @(Invoke-PythonProjectRun -ProjectPath $specProject -ProjectName 'Domaindiag' -Lang 'EN' 6>&1)
    Assert-Equal (Get-BooleanResult $runOutput) $true 'A successful application must return directly to the menu'
    Assert-Equal (Test-Path -LiteralPath (Join-Path $specProject 'ran.txt')) $true 'The spec entry must run in the project directory'
    Assert-Equal (Test-Path -LiteralPath $specSentinel) $false 'Running the entry must not execute the spec'
    $projectPath = $specProject
    $selectedProject = 'Domaindiag'
    $L = 'EN'
    $skipPause = $false
    . $runAction
    Assert-Equal $skipPause $true 'The actual run menu action must skip the pause after success'

    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if ($launcher) {
        $launcherRuntime = @{ Path = $launcher.Source; Prefix = @('-3') }
        $entry = Select-PythonEntryPoint -ProjectPath $specProject -ProjectName 'Domaindiag' -Lang 'EN' -Runtime $launcherRuntime
        Assert-PathEqual $entry.Path $mainFile 'Spec inspection must support the Python launcher prefix'
    }

    $pathSpecProject = Join-Path $testRoot 'pathlib spec'
    $pathSpecEntry = Join-Path $pathSpecProject 'Converter.py'
    $pathSpec = Join-Path $pathSpecProject 'Converter.spec'
    Write-FixtureFile $pathSpecEntry ''
    Write-FixtureFile (Join-Path $pathSpecProject 'main.py') ''
    Write-FixtureFile $pathSpec (
        "from pathlib import Path`nproject_directory = Path(SPECPATH)`n" +
        "a = Analysis([str(project_directory / 'Converter.py')])`n"
    )
    $script:menuCalls = 0
    $entry = Select-PythonEntryPoint -ProjectPath $pathSpecProject -ProjectName 'pathlib' -Lang 'EN' -Runtime $script:runtime
    Assert-PathEqual $entry.Path $pathSpecEntry 'Static pathlib spec entries must be selected'
    Assert-Equal $script:menuCalls 0 'A static pathlib entry must not open a file menu'
    Write-FixtureFile $pathSpec (
        "from pathlib import Path`nproject_directory = Path(SPECPATH)`n" +
        "project_directory = Path('other')`na = Analysis([str(project_directory / 'Converter.py')])`n"
    )
    $script:menuChoice = 1
    $fallbackOutput = @(Select-PythonEntryPoint -ProjectPath $pathSpecProject -ProjectName 'pathlib' -Lang 'EN' -Runtime $script:runtime 6>&1)
    Assert-OutputContains $fallbackOutput 'PythonSpecFallback' 'A reassigned pathlib root must not be resolved as static'
    Assert-Equal ($script:menuTitle -like '*PythonSpecFallback*') $true 'The fallback warning must remain visible in the menu'
    $entry = @($fallbackOutput | Where-Object { $_.PSObject.Properties['Status'] })[0]
    Assert-PathEqual $entry.Path (Join-Path $pathSpecProject 'main.py') 'An unresolved spec must use the manually selected entry'
    Write-FixtureFile $pathSpec (
        "from pathlib import Path`nproject_directory = Path(SPECPATH)`n" +
        "def str(value):`n    raise RuntimeError('spec code must not run')`n" +
        "a = Analysis([str(project_directory / 'Converter.py')])`n"
    )
    $fallbackOutput = @(Select-PythonEntryPoint -ProjectPath $pathSpecProject -ProjectName 'pathlib' -Lang 'EN' -Runtime $script:runtime 6>&1)
    Assert-OutputContains $fallbackOutput 'PythonSpecFallback' 'A shadowed str function must not be resolved as static'

    $windowedProject = Join-Path $testRoot 'windowed'
    $windowedEntry = Join-Path $windowedProject 'windowed.pyw'
    Write-FixtureFile $windowedEntry ''
    Write-FixtureFile (Join-Path $windowedProject 'windowed.spec') "a = Analysis(['windowed.pyw'])`n"
    $entry = Select-PythonEntryPoint -ProjectPath $windowedProject -ProjectName 'windowed' -Lang 'EN' -Runtime $script:runtime
    Assert-PathEqual $entry.Path $windowedEntry 'A spec entry may also be a .pyw file'

    $multiProject = Join-Path $testRoot ("multiple " + [char]0x010D + " [entries]")
    $firstFile = Join-Path $multiProject 'src\first.py'
    $secondFile = Join-Path $multiProject 'second.py'
    Write-FixtureFile $firstFile ''
    Write-FixtureFile $secondFile ''
    Write-FixtureFile (Join-Path $multiProject 'test_unrelated.py') ''
    Write-FixtureFile (Join-Path $multiProject 'first.spec') "a = Analysis(scripts=['src\\first.py'])`n"
    Write-FixtureFile (Join-Path $multiProject 'second.spec') "a = Analysis(['second.py'])`n"

    $script:menuChoice = 1
    $script:menuCalls = 0
    $entry = Select-PythonEntryPoint -ProjectPath $multiProject -ProjectName 'multiple' -Lang 'EN' -Runtime $script:runtime
    Assert-Equal $script:menuCalls 1 'Multiple spec entries must open a menu'
    Assert-Equal $script:menuOptions.Count 3 'The menu must contain only spec entries and Back'
    Assert-Equal ($script:menuOptions -contains 'test_unrelated.py') $false 'Unrelated test files must not be offered'
    Assert-PathEqual $entry.Path $secondFile 'The selected spec entry must be returned'

    $script:menuChoice = 2
    $entry = Select-PythonEntryPoint -ProjectPath $multiProject -ProjectName 'multiple' -Lang 'EN' -Runtime $script:runtime
    Assert-Equal $entry.Status 'Cancelled' 'Back from the spec entry menu must cancel'
    $script:menuChoice = -1
    $entry = Select-PythonEntryPoint -ProjectPath $multiProject -ProjectName 'multiple' -Lang 'EN' -Runtime $script:runtime
    Assert-Equal $entry.Status 'Cancelled' 'Escape from the spec entry menu must cancel'
    $output = @(Invoke-PythonProjectBuild -ProjectPath $multiProject -ProjectName 'multiple' -Lang 'EN' 6>&1)
    Assert-Equal (Get-BooleanResult $output) $true 'Cancelling the spec build menu must return directly'
    Assert-OutputNotContains $output 'PythonEntryMissing' 'Cancelling a spec build must not report a missing file'

    $fallbackProject = Join-Path $testRoot 'dynamic spec'
    $fallbackFile = Join-Path $fallbackProject 'main.py'
    Write-FixtureFile $fallbackFile ''
    Write-FixtureFile (Join-Path $fallbackProject 'dynamic.spec') "a = Analysis(get_scripts())`n"
    $script:menuChoice = 0
    $script:menuCalls = 0
    $fallbackOutput = @(Select-PythonEntryPoint -ProjectPath $fallbackProject -ProjectName 'dynamic' -Lang 'EN' -Runtime $script:runtime 6>&1)
    Assert-OutputContains $fallbackOutput 'PythonSpecFallback' 'Dynamic spec inspection must report the fallback'
    Assert-Equal $script:menuCalls 1 'Even a single fallback file must require manual confirmation'
    Assert-Equal ($script:menuTitle -like '*PythonSpecFallback*') $true 'The fallback warning must remain visible after the menu is drawn'
    $entry = @($fallbackOutput | Where-Object { $_.PSObject.Properties['Status'] })[0]
    Assert-PathEqual $entry.Path $fallbackFile 'A dynamic spec must use the manually selected entry'

    $script:menuChoice = -1
    $output = @(Invoke-PythonProjectRun -ProjectPath $fallbackProject -ProjectName 'dynamic' -Lang 'EN' 6>&1)
    Assert-Equal (Get-BooleanResult $output) $true 'Cancelling an unresolved spec must return directly to the menu'
    Assert-OutputNotContains $output 'PythonEntryMissing' 'Cancelling an unresolved spec must not report a missing file'
    $script:menuChoice = 0

    Write-FixtureFile (Join-Path $fallbackProject 'dynamic.spec') "a = Analysis(['missing.py'])`n"
    $fallbackOutput = @(Select-PythonEntryPoint -ProjectPath $fallbackProject -ProjectName 'dynamic' -Lang 'EN' -Runtime $script:runtime 6>&1)
    Assert-OutputContains $fallbackOutput 'missing.py' 'A missing spec entry must be reported'

    Write-FixtureFile (Join-Path $fallbackProject 'dynamic.spec') "a = Analysis([`n"
    $fallbackOutput = @(Select-PythonEntryPoint -ProjectPath $fallbackProject -ProjectName 'dynamic' -Lang 'EN' -Runtime $script:runtime 6>&1)
    Assert-OutputContains $fallbackOutput 'PythonSpecFallback' 'A malformed spec must report the fallback'

    $cancelProject = Join-Path $testRoot 'cancel'
    Write-FixtureFile (Join-Path $cancelProject 'one.py') ''
    Write-FixtureFile (Join-Path $cancelProject 'two.py') ''
    $script:menuChoice = 0
    $entry = Select-PythonEntryPoint -ProjectPath $cancelProject -ProjectName 'cancel' -Lang 'EN' -Runtime $script:runtime
    Assert-PathEqual $entry.Path (Join-Path $cancelProject 'one.py') 'Projects without a spec must preserve manual selection'
    foreach ($choice in @(-1, 2)) {
        $script:menuChoice = $choice
        $output = @(Invoke-PythonProjectRun -ProjectPath $cancelProject -ProjectName 'cancel' -Lang 'EN' 6>&1)
        Assert-Equal (Get-BooleanResult $output) $true 'Cancelling a run must return directly to the menu'
        Assert-OutputNotContains $output 'PythonEntryMissing' 'Cancelling a run must not report a missing file'
        $output = @(Invoke-PythonProjectBuild -ProjectPath $cancelProject -ProjectName 'cancel' -Lang 'EN' 6>&1)
        Assert-Equal (Get-BooleanResult $output) $true 'Cancelling a build must return directly to the menu'
        Assert-OutputNotContains $output 'PythonEntryMissing' 'Cancelling a build must not report a missing file'
    }
    $projectPath = $cancelProject
    $selectedProject = 'cancel'
    $script:menuChoice = -1
    $skipPause = $false
    $output = @(. $runAction 6>&1)
    Assert-Equal $skipPause $true 'The actual run menu action must skip the pause after cancellation'
    Assert-OutputNotContains $output 'PythonEntryMissing' 'The actual run menu must not report a missing file after cancellation'
    $skipPause = $false
    $output = @(. $buildAction 6>&1)
    Assert-Equal $skipPause $true 'The actual build menu action must skip the pause after cancellation'
    Assert-OutputNotContains $output 'PythonEntryMissing' 'The actual build menu must not report a missing file after cancellation'

    $emptyProject = Join-Path $testRoot 'empty'
    New-Item -ItemType Directory -Path $emptyProject | Out-Null
    $output = @(Invoke-PythonProjectRun -ProjectPath $emptyProject -ProjectName 'empty' -Lang 'EN' 6>&1)
    Assert-Equal (Get-BooleanResult $output) $false 'A missing entry must keep the error visible'
    Assert-OutputContains $output 'PythonEntryMissing' 'A missing run entry must be reported'
    $output = @(Invoke-PythonProjectBuild -ProjectPath $emptyProject -ProjectName 'empty' -Lang 'EN' 6>&1)
    Assert-Equal (Get-BooleanResult $output) $false 'A missing build entry must keep the error visible'
    Assert-OutputContains $output 'PythonEntryMissing' 'A missing build entry must be reported'
    $projectPath = $emptyProject
    $selectedProject = 'empty'
    $skipPause = $true
    $output = @(. $buildAction 6>&1)
    Assert-Equal $skipPause $false 'The actual build menu must pause for a missing entry'
    Assert-OutputContains $output 'PythonEntryMissing' 'The actual build menu must report a missing entry'

    $failedProject = Join-Path $testRoot 'failed run'
    Write-FixtureFile (Join-Path $failedProject 'main.py') "import sys`nsys.stderr.write('expected error\n')`nsys.exit(7)`n"
    $output = @(Invoke-PythonProjectRun -ProjectPath $failedProject -ProjectName 'failed' -Lang 'EN' 6>&1)
    Assert-Equal (Get-BooleanResult $output) $false 'A failed application must keep its error visible'
    Assert-OutputContains $output 'PythonRunFailed 7' 'The application exit code must be reported'
    $projectPath = $failedProject
    $selectedProject = 'failed'
    $skipPause = $true
    $output = @(. $runAction 6>&1)
    Assert-Equal $skipPause $false 'The actual run menu must pause after a failed application'
    Assert-OutputContains $output 'PythonRunFailed 7' 'The actual run menu must report the exit code'

    $script:runtimeAvailable = $false
    $output = @(Invoke-PythonProjectRun -ProjectPath $failedProject -ProjectName 'failed' -Lang 'EN' 6>&1)
    Assert-Equal (Get-BooleanResult $output) $false 'A missing runtime must keep the error visible'
    Assert-OutputContains $output 'PythonRuntimeMissing' 'A missing runtime must be reported'
    $script:runtimeAvailable = $true
    $originalRuntime = $script:runtime
    $script:runtime = @{ Path = (Join-Path $testRoot 'nonexistent-python.exe'); Prefix = @() }
    $output = @(Invoke-PythonProjectRun -ProjectPath $failedProject -ProjectName 'failed' -Lang 'EN' 6>&1)
    Assert-Equal (Get-BooleanResult $output) $false 'A Python launch failure must keep the error visible'
    Assert-OutputContains $output 'PythonProcessLaunchFailed' 'A Python launch failure must be reported'
    $script:runtime = $originalRuntime

    $buildProject = Join-Path $testRoot 'build'
    $buildSpec = Join-Path $buildProject 'project.spec'
    Write-FixtureFile $buildSpec "a = Analysis(['entry.py'])`n"
    Write-FixtureFile (Join-Path $buildProject 'entry.py') ''
    Write-FixtureFile (Join-Path $buildProject 'PyInstaller\__init__.py') ''
    Write-FixtureFile (Join-Path $buildProject 'PyInstaller\__main__.py') (
        "import json`nimport sys`nfrom pathlib import Path`n" +
        "Path('build-arguments.json').write_text(json.dumps(sys.argv[1:]), encoding='utf-8')`n"
    )
    $output = @(Invoke-PythonProjectBuild -ProjectPath $buildProject -ProjectName 'build' -Lang 'EN' 6>&1)
    Assert-Equal (Get-BooleanResult $output) $false 'A completed build must preserve the existing pause'
    $buildArgs = Get-Content -LiteralPath (Join-Path $buildProject 'build-arguments.json') -Raw | ConvertFrom-Json
    $buildArgs = @($buildArgs)
    Assert-Equal $buildArgs.Count 1 'A spec build must pass exactly the spec path'
    Assert-PathEqual $buildArgs[0] $buildSpec 'The existing PyInstaller spec build must be preserved'

    Remove-Item -LiteralPath $buildSpec
    Write-FixtureFile (Join-Path $buildProject 'main.py') ''
    $output = @(Invoke-PythonProjectBuild -ProjectPath $buildProject -ProjectName 'build' -Lang 'EN' 6>&1)
    Assert-Equal (Get-BooleanResult $output) $false 'A completed one-file build must preserve the existing pause'
    $buildArgs = Get-Content -LiteralPath (Join-Path $buildProject 'build-arguments.json') -Raw | ConvertFrom-Json
    $buildArgs = @($buildArgs)
    Assert-Equal $buildArgs.Count 2 'A build without a spec must pass --onefile and an entry path'
    Assert-Equal $buildArgs[0] '--onefile' 'A build without a spec must preserve --onefile'
    Assert-PathEqual $buildArgs[1] (Join-Path $buildProject 'main.py') 'A build without a spec must use the selected entry'

    Write-FixtureFile (Join-Path $buildProject 'PyInstaller\__main__.py') "import sys`nsys.exit(9)`n"
    $output = @(Invoke-PythonProjectBuild -ProjectPath $buildProject -ProjectName 'build' -Lang 'EN' 6>&1)
    Assert-Equal (Get-BooleanResult $output) $false 'A failed build must preserve the existing pause'
    Assert-OutputContains $output 'PythonBuildFailed' 'A failed build must report its exit code'
    Assert-OutputContains $output '9' 'The build exit code must be visible'

    Write-Host 'Python entry-point regression tests passed.'
} finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
