@echo off
REM One-time setup: installs everything lyricsync needs and downloads the model.
echo Installing lyricsync dependencies...
python -m pip install -r "%~dp0requirements.txt"
python -m lyricsync setup %*
pause
