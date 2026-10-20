@echo off
setlocal DisableDelayedExpansion
if not defined NBIOT_START_MODE set "NBIOT_START_MODE=demo"
if /i "%NBIOT_START_MODE%"=="demo" goto mode_ok
if /i "%NBIOT_START_MODE%"=="saved100" goto mode_ok
if /i "%NBIOT_START_MODE%"=="check" goto mode_ok
echo ERROR: Unknown startup mode. Use START.cmd, SAVED-100.cmd or CHECK.cmd.
exit /b 2
:mode_ok
if defined NBIOT_MATLAB_EXE goto matlab_selected
if exist "%ProgramFiles%\MATLAB\R2025b\bin\matlab.exe" set "NBIOT_MATLAB_EXE=%ProgramFiles%\MATLAB\R2025b\bin\matlab.exe"
if defined NBIOT_MATLAB_EXE goto matlab_selected
for /f "delims=" %%M in ('where matlab.exe 2^>nul') do if not defined NBIOT_MATLAB_EXE set "NBIOT_MATLAB_EXE=%%M"
:matlab_selected
if not defined NBIOT_MATLAB_EXE goto missing_matlab
if not exist "%NBIOT_MATLAB_EXE%" goto missing_matlab
if /i "%~1"=="--check" goto discovery_check
cd /d "%~dp0"
if errorlevel 1 goto unwritable
if not exist "logs" mkdir "logs"
if not exist "logs" goto unwritable
set "NBIOT_START_LOG=%CD%\logs\startup-%RANDOM%-%RANDOM%.log"
echo Starting NB-IoT v4.0.0. MATLAB may take a minute to open.
echo Startup log: "%NBIOT_START_LOG%"
if /i "%NBIOT_START_MODE%"=="check" goto check_environment
start "" "%NBIOT_MATLAB_EXE%" -sd "%CD%" -logfile "%NBIOT_START_LOG%" -r "startNBIoT('%NBIOT_START_MODE%');"
exit /b %errorlevel%
:check_environment
"%NBIOT_MATLAB_EXE%" -wait -batch "startNBIoT('check');" -logfile "%NBIOT_START_LOG%"
set "NBIOT_CHECK_EXIT=%errorlevel%"
echo.
if "%NBIOT_CHECK_EXIT%"=="0" echo CHECK PASSED. You can open START.cmd.
if not "%NBIOT_CHECK_EXIT%"=="0" echo CHECK FAILED. See the message above and docs\v4-install.md.
pause
exit /b %NBIOT_CHECK_EXIT%
:discovery_check
echo STARTUP_CHECK_OK mode=%NBIOT_START_MODE%
echo MATLAB: "%NBIOT_MATLAB_EXE%"
exit /b 0
:missing_matlab
echo ERROR: MATLAB R2025b was not found. Install MATLAB R2025b and LTE Toolbox.
echo If already installed elsewhere, open MATLAB and run startNBIoT from this folder.
echo Instructions: docs\v4-install.md
if /i not "%~1"=="--check" pause
exit /b 2
:unwritable
echo ERROR: Extract the complete ZIP into a writable folder, for example Documents\NB-IOT.
echo Do not start files inside the ZIP or in Program Files.
if /i not "%~1"=="--check" pause
exit /b 2
