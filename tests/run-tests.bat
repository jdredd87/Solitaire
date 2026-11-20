@echo off
rem Builds and runs both test layers:
rem   1. console tests for the rules engine / auto-player / statistics
rem   2. the in-app FMX self-test (plays a whole game through the real UI)
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /d "%~dp0"

if not exist out mkdir out
dcc64 -B -Q -NSSystem -E.\out -NU.\out SolitaireTests.dpr
if errorlevel 1 exit /b 1
out\SolitaireTests.exe
if errorlevel 1 exit /b 1

cd ..
msbuild Solitaire.dproj /t:Build /p:Config=Debug /p:Platform=Win64 /nologo /v:quiet
if errorlevel 1 exit /b 1
start /wait "" Win64\Debug\Solitaire.exe -selftest
set RESULT=%errorlevel%
type Win64\Debug\selftest-out\selftest.log
exit /b %RESULT%
