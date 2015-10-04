SET target_prefix=D:\gitrepos\OCEmu\extras\cmd
SET CP=C:\Windows\System32\xcopy.exe

FOR /F "tokens=*" %%a in (%target_prefix%\instances.txt) do (
  SET target=%target_prefix%\%%a
  REM %CP% /s /v /y /EXCLUDE:xcopy-excludes.txt OpenOS %target%
  REM %CP% /s /v /y payo-bash %target%
  REM %CP% /s /v /y payo-lib %target%
  REM %CP% /s /v /y payo-persistent-links %target%
  REM %CP% /s /v /y payo-tests %target%
  REM %CP% /s /v /y popm %target%
  REM %CP% /s /v /y psh %target%
)
