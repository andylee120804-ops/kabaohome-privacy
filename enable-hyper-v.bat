@echo off
setlocal enabledelayedexpansion
title Install Hyper-V on Windows 10 Home
echo ============================================
echo   Hyper-V Installer for Win10 Home
echo ============================================
echo.

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [ERROR] Admin required!
    echo Right-click this file - Run as Administrator
    pause
    exit /b 1
)

echo [OK] Admin confirmed
echo.

echo [Step 1] Finding Hyper-V packages...
echo.

pushd "%~dp0"

dir /b %SystemRoot%\servicing\Packages\*Hyper-V*.mum > hv-list.txt 2>nul

if %errorLevel% neq 0 (
    echo [WARN] No Hyper-V packages found. Trying method 2...
    goto :method2
)

echo Found packages:
echo ----------------------------------------
type hv-list.txt
echo ----------------------------------------
echo.

echo Installing packages, please wait...
for /f %%i in ('findstr /i . hv-list.txt 2^>nul') do (
    echo   Installing: %%i
    dism /online /norestart /add-package:"%SystemRoot%\servicing\Packages\%%i"
)

del hv-list.txt 2>nul

echo.
echo [Step 2] Enabling Hyper-V feature...
Dism /online /enable-feature /featurename:Microsoft-Hyper-V -All /LimitAccess /NoRestart

echo [Step 3] Enabling Virtual Machine Platform...
Dism /online /enable-feature /featurename:VirtualMachinePlatform -All /NoRestart

echo [Step 4] Enabling Hypervisor Platform...
Dism /online /enable-feature /featurename:HypervisorPlatform -All /NoRestart

popd

goto :ask_restart

:method2
echo.
echo [Method 2] Trying direct DISM enable...
echo.

Dism /online /enable-feature /featurename:Microsoft-Hyper-V -All /LimitAccess /NoRestart
Dism /online /enable-feature /featurename:VirtualMachinePlatform -All /NoRestart
Dism /online /enable-feature /featurename:HypervisorPlatform -All /NoRestart

popd

:ask_restart
echo.
echo ============================================
echo   Done! You MUST restart to apply changes.
echo ============================================
echo.
echo  Type YES and press Enter to restart now
echo  Press Enter or type anything else = do NOT restart
echo.
set "confirm="
set /p confirm="Restart? (type YES / press Enter to skip): "
if /i "%confirm%"=="YES" (
    echo.
    echo Are you sure? Type YES again to confirm restart.
    set "confirm2="
    set /p confirm2="Final confirm (YES / Enter to cancel): "
    if /i "!confirm2!"=="YES" (
        echo Restarting in 10 seconds... Run "shutdown /a" to cancel.
        shutdown /r /t 10 /c "Restarting to complete Hyper-V setup"
    ) else (
        echo Cancelled. Please restart manually later.
    )
) else (
    echo Not restarting. Please restart your PC manually later.
)
pause
exit /b 0
