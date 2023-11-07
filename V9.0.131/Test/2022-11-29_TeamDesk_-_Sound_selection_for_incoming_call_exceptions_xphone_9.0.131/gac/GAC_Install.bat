FOR %%I in (AtlasCltExport.dll) DO "%~dp0gacutil.exe" /if "%~dp0%%I"
pause
