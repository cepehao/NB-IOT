function [app,report]=startNBIoT(mode)
%STARTNBIOT Open the v4 demo, saved report, or installation check.
% startNBIoT; startNBIoT('saved100'); startNBIoT('check');
if nargin<1, mode='demo'; end
if ~(ischar(mode)||(isstring(mode)&&isscalar(mode))) || ...
        ~ismember(string(mode),["demo","saved100","check"])
    error('nbiot:startup:Mode','Use demo, saved100 or check.');
end
root=fileparts(mfilename('fullpath'));
addpath(root); cd(root); setupProject();
app=[];
try
    if ~strcmp(version('-release'),'2025b')
        error('nbiot:startup:MatlabVersion', ...
            'Нужен MATLAB R2025b. Сейчас открыт R%s. Инструкция: docs/v4-install.md.',version('-release'));
    end
    lteAvailable=~isempty(ver('lte')) && exist('lteNPRACH','file')==2 ...
        && license('test','LTE_Toolbox');
    if ~lteAvailable
        error('nbiot:startup:LTE', ...
            'Установите и активируйте LTE Toolbox для MATLAB R2025b. Инструкция: docs/v4-install.md.');
    end
    cfg=nbiot.config.defaultConfig();
    nbiot.experiments.loadCalibration(cfg,fullfile(root,'results','nprach-calibration.mat'));
    probe=[tempname(fullfile(root,'results')) '.tmp'];
    [fid,message]=fopen(probe,'w');
    if fid<0
        error('nbiot:startup:WritableFolder', ...
            'Не удаётся сохранить результат: %s. Распакуйте ZIP в папку Документы.',message);
    end
    fclose(fid); delete(probe);
    report=struct('release',version('-release'),'lteAvailable',logical(lteAvailable), ...
        'calibrationAccepted',true,'writableResults',true,'root',root);
    switch char(mode)
        case 'demo'
            run(fullfile(root,'startDemo.m'));
            app=meetingApp;
        case 'saved100'
            run(fullfile(root,'viewSaved100.m'));
            app=meetingSavedApp;
        case 'check'
            fprintf('NB-IoT v4.0.0: MATLAB R2025b, LTE Toolbox, calibration and results folder OK.\n');
    end
catch exception
    fprintf(2,'\nNB-IoT не удалось открыть.\n%s\nИнструкция: %s\n', ...
        exception.message,fullfile(root,'docs','v4-install.md'));
    rethrow(exception);
end
end
