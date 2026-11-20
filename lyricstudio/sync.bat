@echo off
REM Drag an .mp3 onto this file, or run:  sync.bat song.mp3 6910191685
setlocal
if "%~1"=="" (
  echo Usage: sync.bat "song.mp3" [roblox_audio_id]
  pause & exit /b 1
)
set "AUDIO=%~1"
set "ID=%~2"
if "%ID%"=="" set /p ID=Roblox audio id: 
python -m lyricsync "%AUDIO%" --id "%ID%" %3 %4 %5 %6 %7 %8 %9
pause
