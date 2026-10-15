param(
    [switch]$Controller,
    [string]$ConfigPath = ''
)
$ErrorActionPreference = 'Stop'

function Write-JsonFile([string]$Path,[object]$Value) {
    [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 8),
        [Text.UTF8Encoding]::new($false))
}

function Wait-File([string]$Path,[int]$TimeoutSeconds=15) {
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if ([DateTime]::UtcNow -ge $deadline) { throw "Timed out waiting for $Path" }
        Start-Sleep -Milliseconds 100
    }
}

function Test-IsAlive([int]$ProcessId) {
    $candidate=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $candidate) { return $false }
    try { return -not $candidate.HasExited } catch { return $false }
}

if ($Controller) {
    $controllerConfig=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $launch=& ([string]$controllerConfig.wrapper) `
        -Executable ([string]$controllerConfig.executable) `
        -Arguments ([string]$controllerConfig.arguments) `
        -WorkingDirectory ([string]$controllerConfig.workingDirectory) `
        -OutputFolder ([string]$controllerConfig.outputFolder) `
        -SampleIntervalSeconds 0.1 -HeartbeatSeconds 0.2 `
        -NoProgressWarningSeconds 10
    Write-JsonFile ([string]$controllerConfig.launchResult) $launch
    Start-Sleep -Seconds 30
    exit 0
}

$projectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$wrapper=Join-Path $PSScriptRoot 'InvokeScheduledProcess.ps1'
$legacyTest=Join-Path $PSScriptRoot 'testBoundedProcess.ps1'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('nbiot-scheduled-test-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
$shellExe=(Get-Process -Id $PID).Path
$controllerProcess=$null
$otherProcess=$null
$testPassed=$false
$ownedChildIds=[System.Collections.Generic.HashSet[int]]::new()
try {
    $sleepScript=Join-Path $testRoot 'sleep.ps1'
    Set-Content -LiteralPath $sleepScript -Value @'
Start-Sleep -Seconds 4
Write-Output 'scheduled-child-done'
exit 0
'@ -Encoding UTF8
    $childArguments="-NoProfile -ExecutionPolicy Bypass -File `"$sleepScript`""
    $progressFile=Join-Path $testRoot 'stale-progress.json'
    Write-JsonFile $progressFile ([ordered]@{
        phase='test-long-step';currentTick=7;lastCheckpoint='';
        updatedAtUtc=[DateTime]::UtcNow.ToString('o')
    })

    $warningFolder=Join-Path $testRoot 'warning-run'
    $warningLaunch=& $wrapper -Executable $shellExe -Arguments $childArguments `
        -WorkingDirectory $testRoot -OutputFolder $warningFolder `
        -ProgressFile $progressFile -SampleIntervalSeconds 0.1 `
        -HeartbeatSeconds 0.2 -NoProgressWarningSeconds 1
    [void]$ownedChildIds.Add([int]$warningLaunch.rootProcessId)
    if (-not (Test-Path -LiteralPath $warningLaunch.stdout -PathType Leaf) -or
        -not (Test-Path -LiteralPath $warningLaunch.stderr -PathType Leaf) -or
        -not (Test-Path -LiteralPath $warningLaunch.processStarted -PathType Leaf) -or
        [string]::IsNullOrWhiteSpace([string]$warningLaunch.runId) -or
        [string]::IsNullOrWhiteSpace([string]$warningLaunch.processStartTimeUtc)) {
        throw 'Scheduled launch did not record the run identity, PID, creation time and child logs before returning.'
    }
    Wait-File $warningLaunch.processReport 15
    $warningReport=Get-Content -LiteralPath $warningLaunch.processReport -Raw | ConvertFrom-Json
    $heartbeat=Get-Content -LiteralPath $warningLaunch.heartbeat -Raw | ConvertFrom-Json
    if ($warningReport.status -ne 'completed' -or $warningReport.exitCode -ne 0 -or
        -not $warningReport.progressWarningIssued -or
        -not (Test-Path -LiteralPath $warningLaunch.memoryCsv -PathType Leaf) -or
        -not (Test-Path -LiteralPath $warningLaunch.progressFile -PathType Leaf) -or
        $heartbeat.progressPhase -ne 'test-long-step' -or
        -not ($warningReport.maximumDescription -like '*sampled*')) {
        throw ('Warning-threshold run failed or was terminated: '+($warningReport|ConvertTo-Json -Compress))
    }
    $childOutput=Get-Content -LiteralPath $warningLaunch.stdout -Raw
    if ($childOutput -notmatch 'scheduled-child-done') { throw 'Child stdout was not retained.' }

    $controllerChild=Join-Path $testRoot 'controller-child.ps1'
    Set-Content -LiteralPath $controllerChild -Value @'
Start-Sleep -Seconds 4
Write-Output 'controller-child-done'
exit 0
'@ -Encoding UTF8
    $controllerChildArguments="-NoProfile -ExecutionPolicy Bypass -File `"$controllerChild`""
    $controllerFolder=Join-Path $testRoot 'controller-run'
    $controllerResult=Join-Path $testRoot 'controller-launch.json'
    $controllerConfig=Join-Path $testRoot 'controller-config.json'
    Write-JsonFile $controllerConfig ([ordered]@{
        wrapper=$wrapper
        executable=$shellExe
        arguments=$controllerChildArguments
        workingDirectory=$testRoot
        outputFolder=$controllerFolder
        launchResult=$controllerResult
    })
    $controllerArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $PSCommandPath),
        '-Controller','-ConfigPath',('"{0}"' -f $controllerConfig))
    $controllerProcess=Start-Process -FilePath $shellExe -ArgumentList $controllerArgs `
        -WorkingDirectory $testRoot -WindowStyle Hidden -PassThru
    Wait-File $controllerResult 15
    $controllerLaunch=Get-Content -LiteralPath $controllerResult -Raw | ConvertFrom-Json
    [void]$ownedChildIds.Add([int]$controllerLaunch.rootProcessId)
    $otherScript=Join-Path $testRoot 'unrelated.ps1'
    Set-Content -LiteralPath $otherScript -Value 'Start-Sleep -Seconds 20' -Encoding UTF8
    $otherArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $otherScript))
    $otherProcess=Start-Process -FilePath $shellExe -ArgumentList $otherArgs `
        -WorkingDirectory $testRoot -WindowStyle Hidden -PassThru
    Stop-Process -Id $controllerProcess.Id -Force
    $controllerProcess.Refresh()
    if (-not $controllerProcess.HasExited -or -not (Test-IsAlive ([int]$controllerLaunch.rootProcessId))) {
        throw 'The test controller did not exit cleanly or its scheduled child did not survive.'
    }
    $otherProcess.Refresh()
    if ($otherProcess.HasExited) { throw 'The unrelated process was stopped.' }
    Wait-File $controllerLaunch.processReport 15
    $controllerReport=Get-Content -LiteralPath $controllerLaunch.processReport -Raw | ConvertFrom-Json
    if ($controllerReport.status -ne 'completed' -or $controllerReport.exitCode -ne 0) {
        throw ('The process did not finish after controller exit: '+($controllerReport|ConvertTo-Json -Compress))
    }
    if ((Get-Content -LiteralPath $controllerLaunch.stdout -Raw) -notmatch 'controller-child-done') {
        throw 'Detached child stdout was not retained.'
    }

    $blockedSampler=Join-Path $testRoot 'sampler-blocked'
    New-Item -ItemType Directory -Path $blockedSampler | Out-Null
    $samplerFolder=Join-Path $testRoot 'sampler-error-run'
    $samplerLaunch=& $wrapper -Executable $shellExe -Arguments $childArguments `
        -WorkingDirectory $testRoot -OutputFolder $samplerFolder `
        -MemoryCsvPath $blockedSampler -SampleIntervalSeconds 0.1 `
        -HeartbeatSeconds 0.2 -NoProgressWarningSeconds 10
    [void]$ownedChildIds.Add([int]$samplerLaunch.rootProcessId)
    Wait-File $samplerLaunch.processReport 15
    $samplerReport=Get-Content -LiteralPath $samplerLaunch.processReport -Raw | ConvertFrom-Json
    $workerLog=Get-Content -LiteralPath (Join-Path $samplerFolder 'worker.log') -Raw
    if ($samplerReport.status -ne 'completed' -or $samplerReport.exitCode -ne 0 -or
        [string]::IsNullOrWhiteSpace([string]$samplerReport.samplerError) -or
        $workerLog -notmatch 'SAMPLER_ERROR' -or
        (Get-Content -LiteralPath $samplerLaunch.stdout -Raw) -notmatch 'scheduled-child-done') {
        throw ('Sampler failure terminated or lost the scheduled process: '+($samplerReport|ConvertTo-Json -Compress))
    }

    & $legacyTest
    $testPassed=$true
    Write-Output 'SCHEDULED_PROCESS_TESTS passed=4 detached-lifecycle=1 sampler-failure=1 legacy-bounded=5'
} catch {
    Write-Output ("SCHEDULED_PROCESS_FAILURE="+$_.Exception.ToString())
    throw
} finally {
    if ($null -ne $controllerProcess) {
        $controllerProcess.Refresh()
        if (-not $controllerProcess.HasExited) { Stop-Process -Id $controllerProcess.Id -Force }
    }
    foreach ($id in $ownedChildIds) {
        if (Test-IsAlive $id) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    }
    if ($null -ne $otherProcess) {
        $otherProcess.Refresh()
        if (-not $otherProcess.HasExited) { Stop-Process -Id $otherProcess.Id -Force }
    }
    $resolvedTestRoot=(Resolve-Path -LiteralPath $testRoot).Path
    $tempRoot=[IO.Path]::GetTempPath()
    if ($resolvedTestRoot.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and $testPassed) {
        try { Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force }
        catch { Write-Warning "Test temp cleanup deferred: $($_.Exception.Message)" }
    } elseif ($resolvedTestRoot.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase)) {
        Write-Warning "Test artifacts preserved for diagnosis: $resolvedTestRoot"
    }
}
