classdef TestV3Package < matlab.unittest.TestCase
    % Publication checks: saved cases, source identity and public launchers.
    methods (Test)
        function savedCompleteCasesAreIntact(t)
            releaseRoot=fileparts(fileparts(mfilename('fullpath')));
            addpath(releaseRoot); setupProject();
            for name={'single-ue','100-ue'}
                report=nbiot.results.verifyCase(fullfile(releaseRoot,'reports',name{1}));
                t.verifyTrue(report.passed,strjoin(string(report.errors),newline));
                t.verifyEqual(report.status,'completed');
            end
        end
        function computationalSourcesMatchFrozenManifest(t)
            releaseRoot=fileparts(fileparts(mfilename('fullpath')));
            addpath(releaseRoot); setupProject();
            frozen=jsondecode(fileread(fullfile(releaseRoot,'verification', ...
                'v3','source-manifest.json')));
            actual=optimizationSourceManifest(releaseRoot);
            t.verifyEqual(actual.sha256,frozen.computationalSourceSha256);
            t.verifyEqual(numel(actual.files),119);
        end
        function publicCommandsOpenWithoutOriginalCheckout(t)
            releaseRoot=fileparts(fileparts(mfilename('fullpath')));
            addpath(releaseRoot); setupProject();
            run(fullfile(releaseRoot,'startDemo.m'));
            t.addTeardown(@() close(meetingApp.Figure));
            t.verifyEqual(meetingApp.Session.Status,'idle');
            count=findall(meetingApp.Figure,'Tag','numUE');
            t.verifyEqual(count.Value,1);
            run(fullfile(releaseRoot,'showRadioLog.m'));
            t.addTeardown(@() close(meetingLogFigure));
            t.verifyTrue(isvalid(meetingLogFigure));
            run(fullfile(releaseRoot,'viewSaved100.m'));
            t.addTeardown(@() close(meetingSavedApp.Figure));
            t.verifyEqual(meetingSavedApp.Session.Status,'idle');
            savedTable=findall(meetingSavedApp.Figure,'Tag','savedKpiTable');
            t.verifyEqual(size(savedTable.Data,1),10);
            run(fullfile(releaseRoot,'viewDevices100.m'));
            t.addTeardown(@() close(meetingDeviceFigure));
            t.verifyEqual(height(meetingDevices),100);
            t.verifyEqual(sum(meetingDevices.delivered),6);
        end
    end
end
