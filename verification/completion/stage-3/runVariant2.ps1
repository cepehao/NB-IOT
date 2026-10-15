[CmdletBinding()]
param(
    [switch]$DesignOnly,
    [switch]$Execute,
    [switch]$Resume,
    [string]$RunFolder = '',
    [string]$MatlabCommand = 'matlab',
    [string]$Stage2AcceptanceFile = ''
)
$ErrorActionPreference = 'Stop'

function Write-JsonAtomic([string]$Path,[object]$Value) {
    $temporary="$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $json=$Value | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($temporary,$json,[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Read-Json([string]$Path) {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Test-ProcessIdentity([int]$ProcessId,[string]$StartTimeUtc,[string]$ExpectedCommand) {
    if ($ProcessId -le 0) { return $false }
    $process=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $process) { return $false }
    try {
        $actualStart=$process.StartTime.ToUniversalTime()
        $expectedStart=[DateTime]::Parse($StartTimeUtc).ToUniversalTime()
        if ([Math]::Abs(($actualStart-$expectedStart).TotalSeconds) -gt 0.05) { return $false }
    } catch { return $false }
    $wmi=Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
    if ($null -eq $wmi -or [string]::IsNullOrWhiteSpace([string]$wmi.CommandLine)) { return $false }
    if ([string]::IsNullOrWhiteSpace($ExpectedCommand)) { return $false }
    return [string]::Equals([string]$wmi.CommandLine,$ExpectedCommand,[StringComparison]::OrdinalIgnoreCase)
}

function Assert-LocalResources([string]$Path) {
    $driveName=[IO.Path]::GetPathRoot($Path).TrimEnd('\').TrimEnd(':')
    $drive=Get-PSDrive -Name $driveName -ErrorAction Stop
    $requiredDisk=[int64](20GB)
    if ([int64]$drive.Free -lt $requiredDisk) {
        throw "Вариант 2 не запущен: свободно на диске $([Math]::Round($drive.Free/1GB,1)) GiB, требуется не меньше 20 GiB."
    }
    $os=Get-CimInstance Win32_OperatingSystem
    $freeMemory=[int64]$os.FreePhysicalMemory*1KB
    $requiredMemory=[int64](16GB)
    if ($freeMemory -lt $requiredMemory) {
        throw "Вариант 2 не запущен: свободно в RAM $([Math]::Round($freeMemory/1GB,1)) GiB, требуется не меньше 16 GiB."
    }
}

if (($DesignOnly -and ($Execute -or $Resume)) -or ($Execute -and $Resume) -or ($RunFolder -ne '' -and -not $Resume)) {
    throw 'Выберите один режим: -DesignOnly, -Execute или -Resume -RunFolder <absolute path>.'
}

$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$planned=[pscustomobject]@{
    scope='variant2-preliminary-load-probe'
    counts=@(100,500,1000,2500)
    policy='Static'
    durationTicks=5000
    burstDurationTicks=100
    sharedBudgetSeconds=57600
    realization='one fresh Stage 3 ID shared across four sizes; ID 1064 is forbidden'
    fullPilotCompleted=$false
    missingFullPilotCounts=5000
}
if (-not $Execute -and -not $Resume) {
    if ($DesignOnly) { $planned | Add-Member -NotePropertyName mode -NotePropertyValue 'design-only' }
    else { $planned | Add-Member -NotePropertyName mode -NotePropertyValue 'plan-only' }
    $planned
    return
}

$stage2Directory=Join-Path $projectRoot 'verification\completion\stage-2'
if ([string]::IsNullOrWhiteSpace($Stage2AcceptanceFile)) {
    $Stage2AcceptanceFile=Join-Path $stage2Directory 'acceptance.json'
}
$sharedLedger=Join-Path $stage2Directory 'budget-ledger.json'
$probeFolder=''
$runRoot=''
$history=@()
$oldWorker=$null

if ($Execute) {
    if (-not (Test-Path -LiteralPath $Stage2AcceptanceFile -PathType Leaf)) {
        throw "Вариант 2 не запущен: нет допуска Stage 2 $Stage2AcceptanceFile"
    }
    if (-not (Test-Path -LiteralPath $sharedLedger -PathType Leaf)) {
        throw "Вариант 2 не запущен: нет общего бюджета Stage 2/3 $sharedLedger"
    }
    $base=Join-Path $projectRoot 'verification\completion\stage-3'
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    $runRoot=Join-Path $base ('variant2-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    New-Item -ItemType Directory -Path $runRoot | Out-Null
    $probeFolder=Join-Path $runRoot 'probe'
    Assert-LocalResources $runRoot
    $runManifest=[ordered]@{
        scope='variant2-preliminary-load-probe'
        status='preparing'
        createdAtUtc=[DateTime]::UtcNow.ToString('o')
        projectRoot=$projectRoot
        runFolder=$runRoot
        probeFolder=$probeFolder
        sharedBudgetLedger=$sharedLedger
        stage2AcceptanceFile=$Stage2AcceptanceFile
        counts=@(100,500,1000,2500)
        durationTicks=5000
        burstDurationTicks=100
        policy='Static'
        fullPilotCompleted=$false
    }
    Write-JsonAtomic (Join-Path $runRoot 'run-manifest.json') $runManifest
    $options=[ordered]@{
        designOnly=$false
        counts=@(100,500,1000,2500)
        outputFolder=$probeFolder
        stage2AcceptanceFile=$Stage2AcceptanceFile
        calibrationFile=(Join-Path $projectRoot 'results\nprach-calibration.mat')
        registryFile=(Join-Path $projectRoot 'experiments\realizationRegistry.json')
        realizationId=$null
        execution=@{profile='scheduled-local';role='stage-3-load-pilot';maxUE=2500;maxCaseSeconds=57600;maxSuiteSeconds=57600;timePolicy='finish-current'}
        resume=$false
        budgetLedgerFile=$sharedLedger
        memoryRootFolder=$runRoot
    }
    Write-JsonAtomic (Join-Path $runRoot 'worker-options.json') $options
} else {
    if (-not [IO.Path]::IsPathFullyQualified($RunFolder)) { throw '-RunFolder должен содержать абсолютный путь.' }
    $runRoot=(Resolve-Path -LiteralPath $RunFolder).Path
    $probeFolder=Join-Path $runRoot 'probe'
    $optionsPath=Join-Path $runRoot 'worker-options.json'
    $manifestPath=Join-Path $runRoot 'worker.json'
    $runManifestPath=Join-Path $runRoot 'run-manifest.json'
    $progressPath=Join-Path $probeFolder 'progress.json'
    foreach ($required in @($optionsPath,$manifestPath,$runManifestPath,$progressPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Нет файла для безопасного resume: $required" }
    }
    $oldWorker=Read-Json $manifestPath
    $workerAlive=Test-ProcessIdentity ([int]$oldWorker.workerProcessId) `
        ([string]$oldWorker.workerProcessStartTimeUtc) ([string]$oldWorker.workerCommandLine)
    $matlabAlive=Test-ProcessIdentity ([int]$oldWorker.matlabProcessId) `
        ([string]$oldWorker.matlabProcessStartTimeUtc) ([string]$oldWorker.matlabCommandLine)
    if ($workerAlive -or $matlabAlive) {
        throw "Resume не запущен: MATLAB worker ещё работает (worker PID=$($oldWorker.workerProcessId), MATLAB PID=$($oldWorker.matlabProcessId))."
    }
    $progress=Read-Json $progressPath
    $previousReport=$null
    if (Test-Path -LiteralPath ([string]$oldWorker.processReport) -PathType Leaf) {
        $previousReport=Read-Json ([string]$oldWorker.processReport)
        $oldWorker.status=[string]$previousReport.status
        $oldWorker.exitCode=[int]$previousReport.exitCode
        $oldWorker.processReportRecordedAtUtc=[DateTime]::UtcNow.ToString('o')
        Write-JsonAtomic $manifestPath $oldWorker
    }
    if ($progress.status -eq 'preliminary-completed') {
        $runManifest=Read-Json $runManifestPath
        $runManifest.status='preliminary-completed'
        $runManifest.updatedAtUtc=[DateTime]::UtcNow.ToString('o')
        Write-JsonAtomic $runManifestPath $runManifest
        [pscustomobject]@{status='preliminary-completed';runFolder=$runRoot;report=(Join-Path $probeFolder 'load-probe.json');workerStarted=$false}
        return
    }
    if ($Stage2AcceptanceFile -ne (Join-Path $stage2Directory 'acceptance.json')) {
        $options=Read-Json $optionsPath
        $Stage2AcceptanceFile=[string]$options.stage2AcceptanceFile
    }
    $options=Read-Json $optionsPath
    $options.resume=$true
    $options.memoryRootFolder=$runRoot
    $sharedLedger=[string]$options.budgetLedgerFile
    if ($progress.status -eq 'budget-paused' -and (Test-Path -LiteralPath $sharedLedger -PathType Leaf)) {
        $ledger=Read-Json $sharedLedger
        if ([double]$ledger.elapsedSeconds -ge [double]$ledger.budgetSeconds) {
            $runManifest=Read-Json $runManifestPath
            $runManifest.status='budget-paused'
            $runManifest.updatedAtUtc=[DateTime]::UtcNow.ToString('o')
            Write-JsonAtomic $runManifestPath $runManifest
            [pscustomobject]@{
                status='budget-paused'
                runFolder=$runRoot
                report=(Join-Path $probeFolder 'load-probe.json')
                pendingCounts=@($progress.pendingCounts)
                workerStarted=$false
            }
            return
        }
    }
    $optionsPath=Join-Path $runRoot 'worker-options.json'
    Write-JsonAtomic $optionsPath $options
    $history=@($oldWorker.history)
    if ($null -eq $history) { $history=@() }
    $history+=,[pscustomobject]@{
        runId=$oldWorker.runId
        workerProcessId=$oldWorker.workerProcessId
        matlabProcessId=$oldWorker.matlabProcessId
        workerStatus='exited'
        workerFolder=$oldWorker.workerFolder
        previousRecordedAtUtc=$oldWorker.recordedAtUtc
    }
}

Assert-LocalResources $runRoot
$matlab=(Get-Command $MatlabCommand -ErrorAction Stop).Source
$workerRoot=Join-Path $runRoot 'workers'
New-Item -ItemType Directory -Path $workerRoot -Force | Out-Null
$runId=[guid]::NewGuid().ToString('N')
$workerFolder=Join-Path $workerRoot ('worker-'+$runId)
$memoryCsv=Join-Path $workerFolder 'memory.csv'
$optionsPath=Join-Path $runRoot 'worker-options.json'
$matlabRoot=$projectRoot.Replace('\','/').Replace("'","''")
$optionsM=(Resolve-Path -LiteralPath $optionsPath).Path.Replace('\','/').Replace("'","''")
$batch="cd('$matlabRoot'); addpath('$matlabRoot'); setupProject(); options=jsondecode(fileread('$optionsM')); report=runLoadProbe(options); assert(any(strcmp(report.status,{'preliminary-completed','budget-paused'})),'Load probe requires attention; inspect progress.json and case evidence.');"
$arguments='-batch "'+$batch+'"'
$scheduledWrapper=Join-Path $PSScriptRoot '..\..\local\InvokeScheduledProcess.ps1'
$scheduledWrapper=(Resolve-Path -LiteralPath $scheduledWrapper).Path
$progressFile=Join-Path $probeFolder 'worker-progress.json'
$launch=& $scheduledWrapper -Executable $matlab -Arguments $arguments `
    -WorkingDirectory $projectRoot -OutputFolder $workerFolder `
    -ProgressFile $progressFile -MemoryCsvPath $memoryCsv `
    -SampleIntervalSeconds 1 -HeartbeatSeconds 30 `
    -NoProgressWarningSeconds 900 -StartupWaitSeconds 60

$workerProcess=Get-Process -Id ([int]$launch.workerProcessId) -ErrorAction Stop
$workerCim=Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$launch.workerProcessId)"
$matlabCim=Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$launch.rootProcessId)"
if ($null -eq $workerCim -or $null -eq $matlabCim -or
    [string]::IsNullOrWhiteSpace([string]$workerCim.CommandLine) -or
    [string]::IsNullOrWhiteSpace([string]$matlabCim.CommandLine)) {
    throw 'Worker identities were not available after the scheduled process started; the child was left running and its launch folder was preserved.'
}
$currentWorker=[ordered]@{
    status='running'
    runId=$runId
    runFolder=$runRoot
    workerFolder=$workerFolder
    workerProcessId=[int]$launch.workerProcessId
    workerProcessStartTimeUtc=$workerProcess.StartTime.ToUniversalTime().ToString('o')
    workerCommandLine=[string]$workerCim.CommandLine
    matlabProcessId=[int]$launch.rootProcessId
    matlabProcessStartTimeUtc=[string]$launch.processStartTimeUtc
    matlabCommandLine=[string]$matlabCim.CommandLine
    executable=$matlab
    arguments=$arguments
    stdout=[string]$launch.stdout
    stderr=[string]$launch.stderr
    memoryCsv=$memoryCsv
    progressFile=$progressFile
    processReport=[string]$launch.processReport
    heartbeat=[string]$launch.heartbeat
    recordedAtUtc=[DateTime]::UtcNow.ToString('o')
    history=$history
}
Write-JsonAtomic (Join-Path $runRoot 'worker.json') $currentWorker
$manifest=Read-Json (Join-Path $runRoot 'run-manifest.json')
$manifest.status='running'
$manifest.updatedAtUtc=[DateTime]::UtcNow.ToString('o')
Write-JsonAtomic (Join-Path $runRoot 'run-manifest.json') $manifest
[pscustomobject]@{
    status='running'
    runFolder=$runRoot
    probeFolder=$probeFolder
    workerFolder=$workerFolder
    workerProcessId=$launch.workerProcessId
    matlabProcessId=$launch.rootProcessId
    heartbeat=$launch.heartbeat
    processReport=$launch.processReport
    fullPilotCompleted=$false
}
