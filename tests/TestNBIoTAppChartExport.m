classdef TestNBIoTAppChartExport < matlab.unittest.TestCase
    methods (Test)
        function completedRunExportsStaticChartsFromWindow(t)
            parent=tempname; mkdir(parent);
            t.addTeardown(@() removeFolder(parent));
            dialogs=struct('chooseChartOutputDirectory',@() parent);
            app=openNBIoTApp(dialogs);
            t.addTeardown(@() closeApp(app));
            button=findall(app.Figure,'Tag','exportChartsButton');
            t.assertEqual(numel(button),1);
            t.verifyEqual(string(button.Enable),"off");

            setField(app.Figure,'numUE',1);
            setField(app.Figure,'durationTicks',10);
            setField(app.Figure,'trafficKind','none');
            trigger(app.Figure,'Запуск');
            started=tic;
            while strcmp(app.Session.Status,'running') && toc(started)<60
                drawnow; pause(.02);
            end
            t.assertEqual(app.Session.Status,'completed',app.Session.LastError);
            t.verifyEmpty(findall(app.Figure,'Text','Выполняется…'));
            t.assertEqual(string(button.Enable),"on");

            feval(button.ButtonPushedFcn,button,[]);

            outputs=dir(fullfile(parent,'nbiot-charts-*'));
            t.assertEqual(numel(outputs),1);
            output=fullfile(outputs(1).folder,outputs(1).name);
            files=dir(fullfile(output,'*.png'));
            t.verifyEqual(numel(files),8);
            info=findall(app.Figure,'Tag','savedKpiInfo');
            t.assertEqual(numel(info),1);
            t.verifyTrue(contains(info.Text,'8 графиков PNG сохранено'));
        end
    end
end

function setField(fig,tag,value)
control=findall(fig,'Tag',tag);
assert(isscalar(control),['Expected one UI field tagged ' tag]);
control.Value=value;
end

function trigger(fig,label)
button=findall(fig,'Text',label);
assert(isscalar(button),['Expected one button: ' label]);
feval(button.ButtonPushedFcn,button,[]);
end

function closeApp(app)
try
    if isvalid(app.Figure), close(app.Figure); end
catch
end
end

function removeFolder(folder)
if isfolder(folder), rmdir(folder,'s'); end
end
