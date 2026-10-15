$ErrorActionPreference = 'Stop'
function Test-IsAlive([int]$ProcessId) {
    $candidate = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $candidate) { return $false }
    try { return -not $candidate.HasExited } catch { return $false }
}
. (Join-Path $PSScriptRoot 'InvokeBoundedProcess.ps1')
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('nbiot-budget-test-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testRoot | Out-Null
$shellExe = (Get-Process -Id $PID).Path
$other = $null
$ownedOrphanId = $null
try {
    $successScript = Join-Path $testRoot 'success.ps1'
    Set-Content -LiteralPath $successScript -Value "Write-Output 'child-output'; exit 0" -Encoding UTF8
    $ok = Invoke-BoundedProcess -Executable $shellExe -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$successScript`"" -WorkingDirectory $testRoot -OutputFolder (Join-Path $testRoot 'success') -TimeoutSeconds 10
    if ($ok.status -ne 'completed' -or $ok.exitCode -ne 0) { throw ('Successful process was not recorded: ' + ($ok | ConvertTo-Json -Compress) + ' stderr=' + (Get-Content -LiteralPath $ok.stderr -Raw)) }
    if ((Get-Content -LiteralPath $ok.stdout -Raw) -notmatch 'child-output') { throw 'stdout missing.' }
    $failScript = Join-Path $testRoot 'fail.ps1'
    Set-Content -LiteralPath $failScript -Value "[Console]::Error.WriteLine('child-error'); exit 7" -Encoding UTF8
    $failed = Invoke-BoundedProcess -Executable $shellExe -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$failScript`"" -WorkingDirectory $testRoot -OutputFolder (Join-Path $testRoot 'failed') -TimeoutSeconds 10
    if ($failed.status -ne 'failed' -or $failed.exitCode -ne 7) { throw 'Nonzero exit was hidden.' }
    $sleepScript = Join-Path $testRoot 'sleep.ps1'
    Set-Content -LiteralPath $sleepScript -Value 'Start-Sleep -Seconds 30' -Encoding UTF8
    $other = Start-Process -FilePath $shellExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$sleepScript`"" -WindowStyle Hidden -PassThru
    $childPidFile = Join-Path $testRoot 'child.pid'
    $treeScript = Join-Path $testRoot 'tree.ps1'
    $treeText = @'
param($ShellExe,$SleepScript,$PidFile)
$child = Start-Process -FilePath $ShellExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$SleepScript`"" -WindowStyle Hidden -PassThru
$child.Id | Set-Content -LiteralPath $PidFile
Start-Sleep -Seconds 30
'@
    Set-Content -LiteralPath $treeScript -Value $treeText -Encoding UTF8
    $timed = Invoke-BoundedProcess -Executable $shellExe -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$treeScript`" -ShellExe `"$shellExe`" -SleepScript `"$sleepScript`" -PidFile `"$childPidFile`"" -WorkingDirectory $testRoot -OutputFolder (Join-Path $testRoot 'timed') -TimeoutSeconds 3
    if ($timed.status -ne 'timed-out' -or $timed.exitCode -ne 124) { throw 'Timeout was not reported.' }
    $ownedChildId = [int](Get-Content -LiteralPath $childPidFile)
    if (Test-IsAlive $ownedChildId) { throw 'Owned descendant survived timeout.' }
    $other.Refresh()
    if ($other.HasExited) { throw 'Unrelated process was stopped.' }
    $orphanPidFile = Join-Path $testRoot 'orphan.pid'
    $orphanScript = Join-Path $testRoot 'orphan.ps1'
    Set-Content -LiteralPath $orphanScript -Value ($treeText.Replace('Start-Sleep -Seconds 30','exit 0')) -Encoding UTF8
    $orphan = Invoke-BoundedProcess -Executable $shellExe -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$orphanScript`" -ShellExe `"$shellExe`" -SleepScript `"$sleepScript`" -PidFile `"$orphanPidFile`"" -WorkingDirectory $testRoot -OutputFolder (Join-Path $testRoot 'orphan') -TimeoutSeconds 3
    $ownedOrphanId = [int](Get-Content -LiteralPath $orphanPidFile)
    if ($orphan.status -ne 'timed-out' -or (Test-IsAlive $ownedOrphanId)) { throw 'A child escaped after its parent exited.' }
    $pilotScript = Join-Path $PSScriptRoot '..\completion\stage-3\runLoadPilot.ps1'
    $blocked = $false
    try { & $pilotScript -MatlabCommand 'deliberately-missing' } catch { $blocked = $_.Exception.Message -like 'ExecutionBudget:*' }
    if (-not $blocked) { throw 'Pilot default was not blocked before MATLAB startup.' }
    Write-Output 'BOUNDED_PROCESS_TESTS passed=5 failed=0'
}
finally {
    if ($null -ne $ownedOrphanId -and (Test-IsAlive $ownedOrphanId)) { Stop-Process -Id $ownedOrphanId -Force }
    if ($null -ne $other) { $other.Refresh(); if (-not $other.HasExited) { Stop-Process -Id $other.Id -Force } }
    $resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).Path
    if ($resolvedTestRoot.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force }
}
