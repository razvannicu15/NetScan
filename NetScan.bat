@echo off
setlocal EnableExtensions
title NetScan
color 0B

set "REPO_URL=https://github.com/razvannicu15/NetScan.git"
set "DL_URL=https://github.com/razvannicu15/NetScan/releases/download/latest"

rem Daca .bat-ul sta in folderul proiectului il folosim pe acela,
rem altfel lucram in D:\Apps\NetScan (ex. cand e pus pe Desktop).
set "SCRIPT_DIR=%~dp0"
if exist "%SCRIPT_DIR%pubspec.yaml" (
  set "APP_DIR=%SCRIPT_DIR:~0,-1%"
) else (
  set "APP_DIR=D:\Apps\NetScan"
)
set "OUT_DIR=%APP_DIR%\dist"

:menu
cls
echo.
echo   ==============================================
echo                    N E T S C A N
echo   ==============================================
echo    Proiect: %APP_DIR%
echo.
echo    [1] DESCARCA ultima versiune APK + EXE - fara Flutter, fara login
echo    [2] Deschide folderul cu APK si EXE
echo    [3] Porneste NetScan.exe
echo    [4] Actualizeaza codul din GitHub
echo    [5] Build local      - doar daca ai Flutter instalat
echo    [0] Iesire
echo.
set "CH="
set /p "CH=   Alege optiunea: "
if "%CH%"=="1" goto cloud
if "%CH%"=="2" goto open
if "%CH%"=="3" goto runexe
if "%CH%"=="4" goto update
if "%CH%"=="5" goto local
if "%CH%"=="0" exit /b 0
goto menu

rem ------------------------------------------------------------ 1. cloud
:cloud
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
echo.
echo   Descarc NetScan-android.apk ...
curl -L -f --progress-bar -o "%OUT_DIR%\NetScan-android.apk.part" "%DL_URL%/NetScan-android.apk"
if errorlevel 1 goto dl_fail
move /y "%OUT_DIR%\NetScan-android.apk.part" "%OUT_DIR%\NetScan-android.apk" >nul
echo   Descarc NetScan-windows.zip ...
curl -L -f --progress-bar -o "%OUT_DIR%\NetScan-windows.zip.part" "%DL_URL%/NetScan-windows.zip"
if errorlevel 1 goto dl_fail
move /y "%OUT_DIR%\NetScan-windows.zip.part" "%OUT_DIR%\NetScan-windows.zip" >nul
if exist "%OUT_DIR%\NetScan-windows" rmdir /s /q "%OUT_DIR%\NetScan-windows"
mkdir "%OUT_DIR%\NetScan-windows"
tar -xf "%OUT_DIR%\NetScan-windows.zip" -C "%OUT_DIR%\NetScan-windows"
if errorlevel 1 goto dl_fail
echo.
echo   ======  GATA  ======
echo   APK: %OUT_DIR%\NetScan-android.apk
echo   EXE: %OUT_DIR%\NetScan-windows\NetScan.exe
start "" explorer "%OUT_DIR%"
goto pause_menu
:dl_fail
del /q "%OUT_DIR%\*.part" >nul 2>&1
echo.
echo   Descarcarea a esuat. Verifica:
echo    - repo-ul este public pe GitHub
echo    - build-ul s-a terminat: https://github.com/razvannicu15/NetScan/actions
goto pause_menu

rem ------------------------------------------------------------- 2. open
:open
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
start "" explorer "%OUT_DIR%"
goto menu

rem -------------------------------------------------------------- 3. run
:runexe
if not exist "%OUT_DIR%\NetScan-windows\NetScan.exe" (
  echo.
  echo   Nu exista inca NetScan.exe. Ruleaza intai optiunea 1.
  goto pause_menu
)
start "" "%OUT_DIR%\NetScan-windows\NetScan.exe"
goto menu

rem ----------------------------------------------------------- 4. update
:update
call :ensure_repo || goto pause_menu
echo.
git -C "%APP_DIR%" pull --ff-only
goto pause_menu

rem ------------------------------------------------------------ 5. local
:local
call :need_flutter || goto pause_menu
call :ensure_repo || goto pause_menu
echo.
echo    [1] EXE Windows   [2] APK Android   [3] Ambele
set "LB="
set /p "LB=   Alege: "
if "%LB%"=="1" call :build_exe
if "%LB%"=="2" call :build_apk
if "%LB%"=="3" call :build_exe
if "%LB%"=="3" call :build_apk
goto pause_menu

rem ============================================================ helpers
:ensure_repo
where git >nul 2>&1
if not errorlevel 1 goto have_git
echo.
echo   Instalez Git - doar prima data ...
winget install --id Git.Git -e --silent --accept-source-agreements --accept-package-agreements
set "PATH=%PATH%;C:\Program Files\Git\cmd"
where git >nul 2>&1
if not errorlevel 1 goto have_git
echo   Git nu s-a putut instala. Instaleaza-l de la https://git-scm.com/download/win
exit /b 1
:have_git
if exist "%APP_DIR%\.git" exit /b 0
echo.
echo   Descarc proiectul in %APP_DIR% ...
if not exist "D:\Apps" mkdir "D:\Apps"
git clone "%REPO_URL%" "%APP_DIR%"
if errorlevel 1 exit /b 1
exit /b 0

:need_flutter
where flutter >nul 2>&1
if not errorlevel 1 exit /b 0
echo.
echo   Flutter nu este instalat. Foloseste optiunea 1 - build in cloud.
exit /b 1

:build_exe
call :prepare windows || exit /b 1
call flutter build windows --release
if errorlevel 1 exit /b 1
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
if exist "%OUT_DIR%\NetScan-windows" rmdir /s /q "%OUT_DIR%\NetScan-windows"
xcopy /e /i /q /y "build\windows\x64\runner\Release" "%OUT_DIR%\NetScan-windows" >nul
echo   EXE: %OUT_DIR%\NetScan-windows\NetScan.exe
exit /b 0

:build_apk
call :prepare android || exit /b 1
call flutter build apk --release
if errorlevel 1 exit /b 1
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
copy /y "build\app\outputs\flutter-apk\app-release.apk" "%OUT_DIR%\NetScan-android.apk" >nul
echo   APK: %OUT_DIR%\NetScan-android.apk
exit /b 0

:prepare
cd /d "%APP_DIR%"
if exist "%APP_DIR%\%1\" goto prepared
call flutter create --platforms=%1 --org ro.netscan --project-name netscan .
if errorlevel 1 exit /b 1
:prepared
call flutter pub get
if errorlevel 1 exit /b 1
call dart run tool/patch_platforms.dart
call dart run flutter_launcher_icons
exit /b 0

:pause_menu
echo.
pause
goto menu
