@echo off
setlocal EnableExtensions
title NetScan - Build
color 0B

set "REPO_URL=https://github.com/razvannicu15/NetScan.git"
set "GH_URL=https://github.com/razvannicu15/NetScan"

rem Daca .bat-ul sta in folderul proiectului il folosim pe acela,
rem altfel lucram in %USERPROFILE%\NetScan (ex. cand e pus pe Desktop).
set "SCRIPT_DIR=%~dp0"
if exist "%SCRIPT_DIR%pubspec.yaml" (
  set "APP_DIR=%SCRIPT_DIR:~0,-1%"
) else (
  set "APP_DIR=%USERPROFILE%\NetScan"
)
set "OUT_DIR=%APP_DIR%\dist"

:menu
cls
echo.
echo   ==============================================
echo                N E T S C A N   B U I L D
echo   ==============================================
echo    Proiect: %APP_DIR%
echo.
echo    [1] Descarca / actualizeaza codul din GitHub
echo    [2] Build EXE Windows        - local
echo    [3] Build APK Android        - local
echo    [4] Build EXE + APK          - local
echo    [5] Build in cloud + Release - GitHub Actions
echo    [6] Deschide folderul cu rezultate (dist)
echo    [7] Ruleaza aplicatia pe Windows - debug
echo    [8] Verifica mediul - flutter doctor
echo    [9] Deschide GitHub - Actions / Releases
echo    [0] Iesire
echo.
set "CH="
set /p "CH=   Alege optiunea: "
if "%CH%"=="1" goto update
if "%CH%"=="2" goto exe
if "%CH%"=="3" goto apk
if "%CH%"=="4" goto both
if "%CH%"=="5" goto release
if "%CH%"=="6" goto open
if "%CH%"=="7" goto run
if "%CH%"=="8" goto doctor
if "%CH%"=="9" goto web
if "%CH%"=="0" exit /b 0
goto menu

rem ------------------------------------------------------------- 1. git
:update
call :need_git || goto pause_menu
if exist "%APP_DIR%\.git" goto do_pull
echo.
echo   Clonez %REPO_URL% in %APP_DIR% ...
git clone "%REPO_URL%" "%APP_DIR%"
if errorlevel 1 goto fail
goto ok
:do_pull
echo.
echo   Actualizez codul ...
git -C "%APP_DIR%" pull --ff-only
if errorlevel 1 goto fail
goto ok

rem ------------------------------------------------------------- 2. exe
:exe
call :build_exe
if errorlevel 1 goto fail
goto ok

rem ------------------------------------------------------------- 3. apk
:apk
call :build_apk
if errorlevel 1 goto fail
goto ok

rem ------------------------------------------------------------- 4. both
:both
call :build_exe
if errorlevel 1 goto fail
call :build_apk
if errorlevel 1 goto fail
goto ok

rem ---------------------------------------------------------- 5. release
:release
call :need_git || goto pause_menu
if not exist "%APP_DIR%\.git" (
  echo   Proiectul nu e descarcat. Ruleaza intai optiunea 1.
  goto pause_menu
)
cd /d "%APP_DIR%"
echo.
echo   Tag-uri existente:
git tag --list "v*"
echo.
set "VER="
set /p "VER=   Versiune noua, ex. 1.0.1: "
if "%VER%"=="" goto menu
git push origin HEAD
git tag "v%VER%"
if errorlevel 1 goto fail
git push origin "v%VER%"
if errorlevel 1 goto fail
echo.
echo   GitHub Actions construieste acum APK + EXE (aprox. 10 min).
echo   Fisierele apar la: %GH_URL%/releases
start "" "%GH_URL%/actions"
goto ok

rem ------------------------------------------------------------- 6..9
:open
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
start "" explorer "%OUT_DIR%"
goto menu

:run
call :prepare windows || goto fail
call flutter run -d windows
goto pause_menu

:doctor
call :need_flutter || goto pause_menu
call flutter doctor -v
goto pause_menu

:web
start "" "%GH_URL%/actions"
start "" "%GH_URL%/releases"
goto menu

rem ============================================================ helpers
:build_exe
call :prepare windows || exit /b 1
echo.
echo   === Build Windows (release) ===
call flutter build windows --release
if errorlevel 1 exit /b 1
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
if exist "%OUT_DIR%\NetScan-windows" rmdir /s /q "%OUT_DIR%\NetScan-windows"
xcopy /e /i /q /y "build\windows\x64\runner\Release" "%OUT_DIR%\NetScan-windows" >nul
if errorlevel 1 exit /b 1
if exist "%OUT_DIR%\NetScan-windows.zip" del /q "%OUT_DIR%\NetScan-windows.zip"
powershell -NoProfile -Command "Compress-Archive -Path '%OUT_DIR%\NetScan-windows\*' -DestinationPath '%OUT_DIR%\NetScan-windows.zip'"
echo   EXE: %OUT_DIR%\NetScan-windows\NetScan.exe
exit /b 0

:build_apk
call :prepare android || exit /b 1
echo.
echo   === Build Android APK (release) ===
call flutter build apk --release
if errorlevel 1 exit /b 1
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
copy /y "build\app\outputs\flutter-apk\app-release.apk" "%OUT_DIR%\NetScan-android.apk" >nul
if errorlevel 1 exit /b 1
echo   APK: %OUT_DIR%\NetScan-android.apk
exit /b 0

rem Genereaza folderul de platforma (android / windows) daca lipseste.
:prepare
call :need_flutter || exit /b 1
if not exist "%APP_DIR%\pubspec.yaml" (
  echo   Proiectul nu e descarcat. Ruleaza intai optiunea 1.
  exit /b 1
)
cd /d "%APP_DIR%"
if not exist "%APP_DIR%\%1\" (
  echo.
  echo   Generez fisierele pentru %1 ...
  call flutter create --platforms=%1 --org ro.netscan --project-name netscan .
  if errorlevel 1 exit /b 1
)
call flutter pub get
if errorlevel 1 exit /b 1
call dart run tool/patch_platforms.dart
if errorlevel 1 exit /b 1
call dart run flutter_launcher_icons
exit /b 0

:need_git
where git >nul 2>&1
if errorlevel 1 (
  echo.
  echo   Git nu este instalat. Descarca-l de la https://git-scm.com/download/win
  exit /b 1
)
exit /b 0

:need_flutter
where flutter >nul 2>&1
if errorlevel 1 (
  echo.
  echo   Flutter nu este instalat sau nu e in PATH.
  echo   Instaleaza-l de la https://docs.flutter.dev/get-started/install/windows
  echo   sau foloseste optiunea 5 - build in cloud, fara nimic instalat.
  exit /b 1
)
exit /b 0

rem ============================================================= final
:ok
echo.
echo   ======  GATA  ======
goto pause_menu

:fail
echo.
echo   ======  EROARE - vezi mesajele de mai sus  ======

:pause_menu
echo.
pause
goto menu
