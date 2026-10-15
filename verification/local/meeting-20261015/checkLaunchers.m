% Read-only meeting launcher rehearsal. No simulator is started here.
meetingCheckFolder=fileparts(mfilename('fullpath'));
run(fullfile(meetingCheckFolder,'openDemo.m'));
assert(strcmp(meetingApp.Session.Status,'idle'));
assert(findall(meetingApp.Figure,'Tag','numUE').Value==1);
assert(findall(meetingApp.Figure,'Tag','durationTicks').Value==5000);
assert(findall(meetingApp.Figure,'Tag','radiusM').Value==20);
exportapp(meetingApp.Figure,fullfile(meetingCheckFolder,'live-ready.png'));
close(meetingApp.Figure);
run(fullfile(meetingCheckFolder,'openSaved100.m'));
assert(strcmp(meetingSavedApp.Session.Status,'idle'));
meetingCheckTable=findall(meetingSavedApp.Figure,'Tag','savedKpiTable');
assert(size(meetingCheckTable.Data,1)==10);
meetingCheckAxes=findall(meetingSavedApp.Figure,'Tag','savedKpiAxes');
assert(~isempty(findobj(meetingCheckAxes,'Type','line')));
assert(meetingScores.kpi_created==100 && meetingScores.kpi_delivered==6);
exportapp(meetingSavedApp.Figure,fullfile(meetingCheckFolder,'saved-100-view.png'));
close(meetingSavedApp.Figure);
fprintf('MEETING_LAUNCHERS passed=2 failed=0 simulationsStarted=0 release=%s\n',version('-release'));
