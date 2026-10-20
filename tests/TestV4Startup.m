classdef TestV4Startup < matlab.unittest.TestCase
    methods (Test)
        function environmentIsCheckedWithoutStartingSimulation(t)
            t.assertEqual(exist('startNBIoT','file'),2,'The v4 entry point is missing.');
            [app,report]=startNBIoT('check');
            t.verifyEmpty(app);
            t.verifyEqual(report.release,'2025b');
            t.verifyTrue(report.lteAvailable);
            t.verifyTrue(report.calibrationAccepted);
            t.verifyTrue(report.writableResults);
        end
        function invalidModeIsRejected(t)
            t.verifyError(@() startNBIoT('unknown'),'nbiot:startup:Mode');
        end
        function demoOpensReadyWithOneDevice(t)
            app=startNBIoT();
            t.addTeardown(@() close(app.Figure));
            t.verifyEqual(app.Session.Status,'idle');
            t.verifyEqual(findall(app.Figure,'Tag','numUE').Value,1);
            t.verifyEqual(findall(app.Figure,'Tag','durationTicks').Value,5000);
            t.verifyEqual(findall(app.Figure,'Tag','trafficKind').Value,'burst');
        end
        function savedReportOpensWithoutCalculation(t)
            app=startNBIoT('saved100');
            t.addTeardown(@() close(app.Figure));
            t.verifyEqual(app.Session.Status,'idle');
            table=findall(app.Figure,'Tag','savedKpiTable');
            t.verifyEqual(size(table.Data,1),10);
            card=findall(app.Figure,'Tag','savedReportCard');
            t.verifyTrue(contains(strjoin(string(card.Value),newline),'100'));
            axes=findall(app.Figure,'Tag','savedKpiAxes');
            t.verifyEqual(numel(axes),1);
            t.verifyNotEmpty(axes.Children);
        end
        function completeSavedCasesStillVerify(t)
            root=fileparts(fileparts(mfilename('fullpath')));
            for name={'single-ue','100-ue'}
                report=nbiot.results.verifyCase(fullfile(root,'reports',name{1}));
                t.verifyTrue(report.passed,strjoin(string(report.errors),newline));
                t.verifyEqual(report.status,'completed');
            end
        end
    end
end
