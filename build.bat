SET target=D:\gitrepos\OCEmu\extras\cmd\a\e05fbfd8-f5ba-48d6-bf27-dd698803215d\
SET CP=C:\Windows\System32\xcopy.exe

%CP% /s /v /y payo-bash %target%
%CP% /s /v /y payo-lib %target%
REM %CP% /s /v /y payo-persistent-links %target%
%CP% /s /v /y payo-tests %target%
%CP% /s /v /y popm %target%
%CP% /s /v /y psh %target%

