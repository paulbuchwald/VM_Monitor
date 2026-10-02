@echo off
setlocal EnableDelayedExpansion

title VM Status Monitor
color 09

:: ====================================================================
:: Einstellungen
:: ====================================================================
set "LOCKFILE=%SystemRoot%\Temp\vm_monitor.lock"
set "JSON_FILE=vm_status.json"
set "VM_LIST=PVM01 PVM02 PVM03 PVM04 PVM05 PVM06 PVM07 PVM08 PVM09 PVM10"
:: Max. Wartezeit pro Zyklus (Sekunden). Wer bis dahin nicht antwortet, gilt als offline.
set /a QUERY_TIMEOUT=8
:: Pause zwischen zwei Zyklen (Sekunden)
set /a CYCLE_PAUSE=60

set /a VM_TOTAL=0
for %%V in (%VM_LIST%) do set /a VM_TOTAL+=1

:: ====================================================================
:: Lock: Handle 9 bleibt offen, solange :Main laeuft.
:: Eine zweite Instanz kann die Datei nicht oeffnen und landet im ||-Zweig.
:: ====================================================================
2>nul (
  9>>"%LOCKFILE%" (
    call :Main
  )
) || (
  color 0C
  echo.
  echo  FEHLER: Es laeuft bereits eine andere Instanz.
  echo  ^(Lock-Datei: %LOCKFILE%^)
  echo.
  echo  Dieses Fenster schliesst sich in 10 Sekunden...
  timeout /t 10 >nul
)
exit /b


:Main
echo Lock aktiv. Skript laeuft dauerhaft.
echo Beenden: Fenster schliessen oder Strg+C.
echo.

:MainLoop
echo ======================================================================
echo [%time%] Starte Abfrage von %VM_TOTAL% VMs (parallel)...
echo.

:: Alte Arbeitsordner aufraeumen (evtl. noch haengende Abfragen ignorieren)
for /d %%D in ("%TEMP%\vmmon_*") do rd /s /q "%%D" >nul 2>&1

set "WORK=%TEMP%\vmmon_%RANDOM%%RANDOM%"
md "%WORK%" >nul 2>&1

:: --- Alle Abfragen gleichzeitig im Hintergrund starten ---
:: Jede Abfrage schreibt ihr Ergebnis in <VM>.txt und danach eine <VM>.done
for %%V in (%VM_LIST%) do (
  start "" /b cmd /c query user /server:%%V ^>"%WORK%\%%V.txt" 2^>^&1 ^& type nul ^>"%WORK%\%%V.done"
)

:: --- Warten, bis alle fertig sind oder das Timeout erreicht ist ---
set /a waited=0
:WaitLoop
set /a done=0
for %%V in (%VM_LIST%) do if exist "%WORK%\%%V.done" set /a done+=1
if !done! lss %VM_TOTAL% if !waited! lss %QUERY_TIMEOUT% (
  timeout /t 1 /nobreak >nul
  set /a waited+=1
  goto WaitLoop
)

:: --- Ergebnisse auswerten ---
for %%V in (%VM_LIST%) do call :Eval %%V

:: --- JSON in Temp-Datei schreiben und dann ersetzen (nie halb geschrieben) ---
set /a i=0
>"%JSON_FILE%.tmp" (
  echo {
  echo   "vms": [
  for %%V in (%VM_LIST%) do (
    set /a i+=1
    if !i! lss %VM_TOTAL% (set "SEP=,") else (set "SEP=")
    echo     {"name": "%%V", "online": !R_%%V_ON!, "users": !R_%%V_US!}!SEP!
  )
  echo   ]
  echo }
)
move /y "%JSON_FILE%.tmp" "%JSON_FILE%" >nul 2>&1 || copy /y "%JSON_FILE%.tmp" "%JSON_FILE%" >nul

echo.
echo [%time%] Abfrage fertig (%done%/%VM_TOTAL% haben geantwortet). Warte %CYCLE_PAUSE% Sekunden...
echo ======================================================================
echo.

timeout /t %CYCLE_PAUSE% /nobreak >nul
goto MainLoop


:: ====================================================================
:: Auswertung einer VM  ->  setzt R_<VM>_ON und R_<VM>_US
:: ====================================================================
:Eval
set "VM=%~1"
set "F=%WORK%\%VM%.txt"
set "ON=false"
set "US=0"

if not exist "%WORK%\%VM%.done" (
  set "STATE=keine Antwort (Timeout)"
  goto EvalEnd
)
findstr /i /c:"Fehler" "%F%" >nul 2>&1 && (
  set "STATE=offline (Fehler)"
  goto EvalEnd
)
set "ON=true"
set "STATE=online"
findstr /i /c:"BENUTZERNAME" "%F%" >nul 2>&1 || goto EvalEnd
for /f %%i in ('type "%F%" ^| find /c /v ""') do set /a US=%%i-1
if !US! lss 0 set "US=0"

:EvalEnd
set "R_%VM%_ON=%ON%"
set "R_%VM%_US=%US%"
echo   ^> %VM%: %STATE%, Benutzer: %US%
exit /b
