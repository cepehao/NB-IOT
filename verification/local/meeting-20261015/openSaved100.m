% Show copied, hash-verified CSV from an existing completed 100-device run.
% No simulation and no large MAT loading.
meetingFolder=fileparts(mfilename('fullpath'));
meetingRoot=fileparts(fileparts(fileparts(meetingFolder)));
cd(meetingRoot); setupProject();
meetingSavedFolder=fullfile(meetingRoot,'reports','100-ue');
meetingKpiName='static-v1_n100_r1088_kpi.csv';
assert(isfile(fullfile(meetingSavedFolder,meetingKpiName)), ...
    'Prepared saved result is missing.');
meetingSavedApp=openNBIoTApp(struct('chooseKpiFile', ...
    @() deal(meetingKpiName,meetingSavedFolder)));
meetingOpenButton=findall(meetingSavedApp.Figure,'Tag','savedKpiButton');
feval(meetingOpenButton.ButtonPushedFcn,meetingOpenButton,[]);
meetingTabs=findall(meetingSavedApp.Figure,'Type','uitab');
for meetingIndex=1:numel(meetingTabs)
    if strcmp(meetingTabs(meetingIndex).Title,'Сохранённые результаты')
        meetingTabs(meetingIndex).Parent.SelectedTab=meetingTabs(meetingIndex);
    end
end
meetingScores=readtable(fullfile(meetingSavedFolder, ...
    'static-v1_n100_r1088_summary.csv'));
disp(meetingScores(:,{'numUE','durationTicks','kpi_created', ...
    'kpi_delivered','kpi_dropped','kpi_unfinished'}));
disp('SAVED run, not a new simulation: 100 devices, 5 model seconds.');
disp('6 delivered, 86 dropped, 8 unfinished. One scenario, not general statistics.');
drawnow;
