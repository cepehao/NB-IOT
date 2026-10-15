function app=NBIoTApp(dialogs)
%NBIOTAPP Open the bounded local simulation interface.
if nargin<1 || isempty(dialogs), dialogs=struct(); end
if ~isstruct(dialogs) || ~isscalar(dialogs)
    error('nbiot:ui:DialogAdapter','Dialog adapters must be a scalar structure.');
end
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root); setupProject(); addpath(fullfile(root,'apps'));
chooseOutputDirectory=@() uigetdir(fullfile(root,'results'),'Выберите папку для результата');
chooseDatasetOutputDirectory=@() uigetdir(fullfile(root,'results'),'Выберите папку для development-набора');
chooseChartOutputDirectory=@() uigetdir(fullfile(root,'results'), ...
    'Выберите папку для PNG-графиков');
chooseComparisonFolder=@() uigetdir(fullfile(root,'results'), ...
    'Выберите папку со сводкой сравнения');
chooseKpiFile=@() uigetfile('*.csv', ...
    'Выберите одну или несколько таблиц KPI','MultiSelect','on');
chooseModelFile=@() uigetfile('*.mat','Выберите пакет модели нагрузки');
if isfield(dialogs,'chooseOutputDirectory')
    if ~isa(dialogs.chooseOutputDirectory,'function_handle')
        error('nbiot:ui:DialogAdapter','chooseOutputDirectory must be a function handle.');
    end
    chooseOutputDirectory=dialogs.chooseOutputDirectory;
end
if isfield(dialogs,'chooseKpiFile')
    if ~isa(dialogs.chooseKpiFile,'function_handle')
        error('nbiot:ui:DialogAdapter','chooseKpiFile must be a function handle.');
    end
    chooseKpiFile=dialogs.chooseKpiFile;
end
if isfield(dialogs,'chooseDatasetOutputDirectory')
    if ~isa(dialogs.chooseDatasetOutputDirectory,'function_handle')
        error('nbiot:ui:DialogAdapter','chooseDatasetOutputDirectory must be a function handle.');
    end
    chooseDatasetOutputDirectory=dialogs.chooseDatasetOutputDirectory;
end
if isfield(dialogs,'chooseChartOutputDirectory')
    if ~isa(dialogs.chooseChartOutputDirectory,'function_handle')
        error('nbiot:ui:DialogAdapter','chooseChartOutputDirectory must be a function handle.');
    end
    chooseChartOutputDirectory=dialogs.chooseChartOutputDirectory;
end
if isfield(dialogs,'chooseModelFile')
    if ~isa(dialogs.chooseModelFile,'function_handle')
        error('nbiot:ui:DialogAdapter','chooseModelFile must be a function handle.');
    end
    chooseModelFile=dialogs.chooseModelFile;
end
if isfield(dialogs,'chooseComparisonFolder')
    if ~isa(dialogs.chooseComparisonFolder,'function_handle')
        error('nbiot:ui:DialogAdapter','chooseComparisonFolder must be a function handle.');
    end
    chooseComparisonFolder=dialogs.chooseComparisonFolder;
end
if isfield(dialogs,'showAlert') && ~isa(dialogs.showAlert,'function_handle')
    error('nbiot:ui:DialogAdapter','showAlert must be a function handle.');
end
session=nbiot.ui.SimulationSession();
selectedModelFile='';
modelSelectionError=false;
cfg=nbiot.config.defaultConfig();
cfg.simulation.numUE=10;
calibrationFile=fullfile(root,'results','nprach-calibration.mat');
calibrationStatus='Калибровка не загружена';
try
    cfg=nbiot.experiments.loadCalibration(cfg,calibrationFile);
    calibrationStatus='Калибровка загружена';
catch exception
    calibrationStatus=['Нужна калибровка: ' exception.message];
end

fig=uifigure('Name','NB-IoT — локальный запуск','Position',[80 70 1320 850]);
fig.CloseRequestFcn=@closeApp;
showAlert=@(message,title) uialert(fig,message,title);
if isfield(dialogs,'showAlert'), showAlert=dialogs.showAlert; end
main=uigridlayout(fig,[2 2]);
main.RowHeight={48,'1x'}; main.ColumnWidth={'1.05x','1x'};
main.Padding=[12 12 12 12]; main.RowSpacing=10; main.ColumnSpacing=12;
titleLabel=uilabel(main,'Text','NB-IoT · обычный режим','FontSize',20,'FontWeight','bold');
titleLabel.Layout.Row=1; titleLabel.Layout.Column=[1 2];

left=uigridlayout(main,[2 1]); left.Layout.Row=2; left.Layout.Column=1;
left.RowHeight={52,'1x'}; left.Padding=[0 0 0 0]; left.RowSpacing=8;
buttons=uigridlayout(left,[2 3]); buttons.RowHeight={24,24};
buttons.ColumnWidth={'1x','1x','1x'}; buttons.Padding=[0 0 0 0];
startButton=uibutton(buttons,'Text','Запуск','ButtonPushedFcn',@startRun);
pauseButton=uibutton(buttons,'Text','Пауза','ButtonPushedFcn',@pauseRun);
resumeButton=uibutton(buttons,'Text','Продолжить','ButtonPushedFcn',@resumeRun);
stopButton=uibutton(buttons,'Text','Остановить','ButtonPushedFcn',@stopRun);
resetButton=uibutton(buttons,'Text','Сброс','ButtonPushedFcn',@resetRun);
saveButton=uibutton(buttons,'Text','Сохранить','ButtonPushedFcn',@saveRun);

tabs=uitabgroup(left); tabs.Layout.Row=2; tabs.Layout.Column=1;
networkTab=uitab(tabs,'Title','Сеть');
channelTab=uitab(tabs,'Title','Канал');
trafficTab=uitab(tabs,'Title','Трафик');
controllerTab=uitab(tabs,'Title','Контроллер');
networkForm=formGrid(networkTab,30);
channelForm=formGrid(channelTab,30);
trafficForm=formGrid(trafficTab,30);
controllerForm=formGrid(controllerTab,12);
controls=struct(); paths=struct(); kinds=struct();
addDropdown(networkForm,'Режим запуска','simulationMode','policy.name', ...
    cfg.policy.name,{'Static','Adaptive-P','Adaptive-RA/DT'});
addNumber(networkForm,'Устройства (местный предел 10)','numUE','simulation.numUE',cfg.simulation.numUE,[1 10],'integer');
addNumber(networkForm,'Длительность, мс (макс. 5000)','durationTicks','simulation.durationTicks',cfg.simulation.durationTicks,[1 5000],'integer');
addNumber(networkForm,'Seed','seed','simulation.seed',cfg.simulation.seed,[0 4294967295],'integer');
addNumber(networkForm,'Номер реализации','realizationId','simulation.realizationId',cfg.simulation.realizationId,[0 4095],'integer');
addNumber(networkForm,'Радиус соты, м','radiusM','cell.radiusM',cfg.cell.radiusM,[10 100000],'number');
addNumber(networkForm,'Минимальное расстояние, м','minDistanceM','cell.minDistanceM',cfg.cell.minDistanceM,[0 99999],'number');
addNumber(networkForm,'Доля устройств внутри зданий','indoorFraction','cell.indoorFraction',cfg.cell.indoorFraction,[0 1],'number');
addNumber(networkForm,'Высота базовой станции, м','bsHeightM','cell.bsHeightM',cfg.cell.bsHeightM,[0 1000],'number');
addNumber(networkForm,'Высота устройства, м','ueHeightM','cell.ueHeightM',cfg.cell.ueHeightM,[0 1000],'number');
addNumber(networkForm,'ID соты','cellId','cell.cellId',cfg.cell.cellId,[0 503],'integer');
row=nextRow(networkForm); note=uilabel(networkForm, ...
    'Text','Полоса: 180 кГц (фиксирована) · шаг 1 мс · канал static-v1 · начальные P и RA/DT для Static задаются во вкладке «Трафик»', ...
    'FontColor',[0.25 0.35 0.5],'Tag','fixedBandwidthInfo','WordWrap','on');
note.Layout.Row=row; note.Layout.Column=[1 2];
row=nextRow(networkForm);
selectModelButton=uibutton(networkForm,'Text','Выбрать модель', ...
    'Tag','selectModelButton','ButtonPushedFcn',@selectModel);
selectModelButton.Layout.Row=row; selectModelButton.Layout.Column=[1 2];
allowDevelopmentModel= uicheckbox(networkForm, ...
    'Text','Разрешить development-модель (только отладка)', ...
    'Value',false,'Tag','allowDevelopmentModel');
row=nextRow(networkForm); allowDevelopmentModel.Layout.Row=row;
allowDevelopmentModel.Layout.Column=[1 2];
modelStatus=uilabel(networkForm,'Text','Модель не выбрана. Для Static она не нужна.', ...
    'Tag','modelStatus','WordWrap','on');
row=nextRow(networkForm); modelStatus.Layout.Row=row; modelStatus.Layout.Column=[1 2];
modelDetails=uitextarea(networkForm,'Editable','off', ...
    'Value',{'После выбора модели здесь появятся тип, цель, версия и признаки.'}, ...
    'Tag','modelDetails');
row=nextRow(networkForm); modelDetails.Layout.Row=[row row+3];
modelDetails.Layout.Column=[1 2];

addNumber(channelForm,'Несущая частота, Гц','carrierHz','channel.carrierHz',cfg.channel.carrierHz,[1 1e12],'number');
addNumber(channelForm,'Опорное расстояние, м','referenceDistanceM','channel.referenceDistanceM',cfg.channel.referenceDistanceM,[1e-6 1e9],'number');
addNumber(channelForm,'Показатель потерь пути','pathLossExponent','channel.pathLossExponent',cfg.channel.pathLossExponent,[0.01 10],'number');
addNumber(channelForm,'Теневая вариация снаружи, дБ','shadowOutdoorDb','channel.shadowOutdoorDb',cfg.channel.shadowOutdoorDb,[0 100],'number');
addNumber(channelForm,'Теневая вариация внутри, дБ','shadowIndoorDb','channel.shadowIndoorDb',cfg.channel.shadowIndoorDb,[0 100],'number');
addNumber(channelForm,'Потери стен, дБ','penetrationIndoorDb','channel.penetrationIndoorDb',cfg.channel.penetrationIndoorDb,[0 200],'number');
addNumber(channelForm,'Мощность устройства, дБм','uePowerDbm','channel.uePowerDbm',cfg.channel.uePowerDbm,[-100 100],'number');
addNumber(channelForm,'Мощность станции, дБм','bsPowerDbm','channel.bsPowerDbm',cfg.channel.bsPowerDbm,[-100 100],'number');
addNumber(channelForm,'Шум приёмника станции, дБ','bsNoiseFigureDb','channel.bsNoiseFigureDb',cfg.channel.bsNoiseFigureDb,[0 100],'number');
addNumber(channelForm,'Шум приёмника устройства, дБ','ueNoiseFigureDb','channel.ueNoiseFigureDb',cfg.channel.ueNoiseFigureDb,[0 100],'number');
addNumber(channelForm,'Температура шума, К','temperatureK','channel.temperatureK',cfg.channel.temperatureK,[1e-6 1e6],'number');
addNumber(channelForm,'Разброс CFO, Гц','cfoSigmaHz','channel.cfoSigmaHz',cfg.channel.cfoSigmaHz,[0 10000],'number');
addNumber(channelForm,'Предел CFO, Гц','cfoLimitHz','channel.cfoLimitHz',cfg.channel.cfoLimitHz,[0 10000],'number');
addNumber(channelForm,'Предел ошибки синхронизации, с','syncLimitSeconds','channel.syncLimitSeconds',cfg.channel.syncLimitSeconds,[0 0.01],'number');
addText(channelForm,'Задержки лучей, с','tapDelaysSeconds','channel.tapDelaysSeconds',cfg.channel.tapDelaysSeconds);
addText(channelForm,'Мощности лучей, дБ','tapPowersDb','channel.tapPowersDb',cfg.channel.tapPowersDb);
addNumber(channelForm,'Длина фильтра дробной задержки','fractionalFilterLength', ...
    'channel.fractionalFilterLength',cfg.channel.fractionalFilterLength,[3 4095],'integer');
row=nextRow(channelForm); channelProfileInfo=uilabel(channelForm, ...
    'Text','Модель радиоканала: static-v1 (единственный поддерживаемый профиль)', ...
    'Tag','channelModelInfo','WordWrap','on');
channelProfileInfo.Layout.Row=row; channelProfileInfo.Layout.Column=[1 2];

addDropdown(trafficForm,'Тип трафика','trafficKind','traffic.kind',cfg.traffic.kind,{'burst','periodic','poisson','none'});
addNumber(trafficForm,'Размер пакета, байт','packetBytes','traffic.packetBytes',cfg.traffic.packetBytes,[1 6630],'integer');
addNumber(trafficForm,'Предел очереди, пакетов','queueLimit','traffic.queueLimit',cfg.traffic.queueLimit,[1 65535],'integer');
addNumber(trafficForm,'Период, мс','periodTicks','traffic.periodTicks',cfg.traffic.periodTicks,[1 16777215],'integer');
addNumber(trafficForm,'Частота пуассоновского трафика, 1/с','poissonRatePerSecond','traffic.poissonRatePerSecond',cfg.traffic.poissonRatePerSecond,[0 100000],'number');
addNumber(trafficForm,'Начало всплеска, мс','burstStartTick','traffic.burstStartTick',cfg.traffic.burstStartTick,[0 16777215],'integer');
addNumber(trafficForm,'Длина всплеска, мс','burstDurationTicks','traffic.burstDurationTicks',cfg.traffic.burstDurationTicks,[1 16777215],'integer');
addNumber(trafficForm,'Срок жизни пакета, мс','lifetimeTicks','traffic.lifetimeTicks',cfg.traffic.lifetimeTicks,[1 16777215],'integer');
addNumber(trafficForm,'Максимум попыток доступа','maxAttempts','ra.maxAttempts',cfg.ra.maxAttempts,[1 65535],'integer');
addNumber(trafficForm,'Ожидание после неудачи, мс','backoffTicks','ra.backoffTicks',cfg.ra.backoffTicks,[0 16777215],'integer');
addNumber(trafficForm,'Период доступа, мс','raPeriodTicks','ra.periodTicks',cfg.ra.periodTicks,[1 16777215],'integer');
addNumber(trafficForm,'Смещение доступа, мс','raStartOffsetTicks','ra.startOffsetTicks',cfg.ra.startOffsetTicks,[0 16777214],'integer');
addNumber(trafficForm,'Окно ответа станции, слоты','rarPp','ra.rarPp',cfg.ra.rarPp,[1 65535],'integer');
addNumber(trafficForm,'Окно разрешения конфликта, слоты','contentionPp', ...
    'ra.contentionPp',cfg.ra.contentionPp,[1 65535],'integer');
addNumber(trafficForm,'Вероятность попытки P','accessProbability','policy.accessProbability',cfg.policy.accessProbability,[0 1],'number');
addNumericDropdown(trafficForm,'Доля ресурсов RA','raShare','policy.raShare', ...
    cfg.policy.raShare,{'10/90','20/80','30/70'},[0.1 0.2 0.3]);
row=nextRow(controllerForm);
labelHandle=uilabel(controllerForm,'Text','Начальное P для Adaptive-P');
labelHandle.Layout.Row=row; labelHandle.Layout.Column=1;
adaptiveStartProbability=uidropdown(controllerForm, ...
    'Items',{'1.00','0.75','0.50','0.25','0.10'}, ...
    'ItemsData',[1 0.75 0.5 0.25 0.1],'Value',1, ...
    'Tag','adaptiveStartProbability');
adaptiveStartProbability.Layout.Row=row; adaptiveStartProbability.Layout.Column=2;
probabilityChoices=[0.1 0.25 0.5 0.75 1];
probabilityLabels={'0.10','0.25','0.50','0.75','1.00'};
row=nextRow(controllerForm);
labelHandle=uilabel(controllerForm,'Text','Минимальное допустимое P');
labelHandle.Layout.Row=row; labelHandle.Layout.Column=1;
allowedPMin=uidropdown(controllerForm,'Items',probabilityLabels, ...
    'ItemsData',probabilityChoices,'Value',0.1,'Tag','allowedPMin');
allowedPMin.Layout.Row=row; allowedPMin.Layout.Column=2;
row=nextRow(controllerForm);
labelHandle=uilabel(controllerForm,'Text','Максимальное допустимое P');
labelHandle.Layout.Row=row; labelHandle.Layout.Column=1;
allowedPMax=uidropdown(controllerForm,'Items',probabilityLabels, ...
    'ItemsData',probabilityChoices,'Value',1,'Tag','allowedPMax');
allowedPMax.Layout.Row=row; allowedPMax.Layout.Column=2;
row=nextRow(controllerForm);
labelHandle=uilabel(controllerForm,'Text','Начальная доля RA/DT для Adaptive-RA/DT');
labelHandle.Layout.Row=row; labelHandle.Layout.Column=1;
adaptiveStartRaShare=uidropdown(controllerForm, ...
    'Items',{'10/90','20/80','30/70'},'ItemsData',[0.1 0.2 0.3], ...
    'Value',0.1,'Tag','adaptiveStartRaShare');
adaptiveStartRaShare.Layout.Row=row; adaptiveStartRaShare.Layout.Column=2;
row=nextRow(controllerForm);
labelHandle=uilabel(controllerForm,'Text','Допустимые доли ресурсов RA/DT');
labelHandle.Layout.Row=row; labelHandle.Layout.Column=1;
allowedRaShares=uilistbox(controllerForm,'Items',{'10/90','20/80','30/70'}, ...
    'ItemsData',[0.1 0.2 0.3],'Value',[0.1 0.2 0.3], ...
    'Multiselect','on','Tag','allowedRaShares');
allowedRaShares.Layout.Row=[row row+2]; allowedRaShares.Layout.Column=2;
controllerForm.UserData=row+2;
row=nextRow(controllerForm);
controllerHint=uilabel(controllerForm, ...
    'Text','В режиме Static эти поля не используются. Выберите Adaptive-P или Adaptive-RA/DT во вкладке «Сеть». Начальное значение должно входить в разрешённый набор.', ...
    'Tag','controllerSettingsInfo','WordWrap','on');
controllerHint.Layout.Row=row; controllerHint.Layout.Column=[1 2];
controls.simulationMode.ValueChangedFcn=@updateModeControls;
updateModeControls();

right=uigridlayout(main,[3 1]); right.Layout.Row=2; right.Layout.Column=2;
right.RowHeight={34,24,'1x'}; right.Padding=[0 0 0 0]; right.RowSpacing=8;
statusLabel=uilabel(right,'Text',calibrationStatus,'FontSize',14,'FontWeight','bold');
progress= uigauge(right,'linear','Limits',[0 100]); progress.Layout.Row=2;
displayTabs=uitabgroup(right); displayTabs.Layout.Row=3;
liveTab=uitab(displayTabs,'Title','Текущий запуск');
savedTab=uitab(displayTabs,'Title','Сохранённые результаты');
liveGrid=uigridlayout(liveTab,[13 1]);
liveGrid.Padding=[6 6 6 6]; liveGrid.RowSpacing=4;
liveGrid.RowHeight={145,64,22,70,22,65,22,44,96,22,56,22,'1x'};
map=uiaxes(liveGrid); title(map,'Расположение устройств'); xlabel(map,'X, м'); ylabel(map,'Y, м');
axis(map,'equal'); grid(map,'on');
deviceTable=uitable(liveGrid,'Data',cell(0,4), ...
    'ColumnName',{'UE','Состояние','Пакетов в очереди','В здании'}, ...
    'Tag','deviceTable','CellSelectionCallback',@selectUe);
uilabel(liveGrid,'Text','Сведения о выбранном устройстве','FontWeight','bold');
selectedUeDetails=uitextarea(liveGrid,'Editable','off', ...
    'Value',{'Выберите UE в таблице, чтобы посмотреть подробности.'}, ...
    'Tag','selectedUeDetails');
uilabel(liveGrid,'Text','Сводка запуска','FontWeight','bold');
summary=uitextarea(liveGrid,'Editable','off', ...
    'Value',{'Static · 1 мс · не более 10 устройств';calibrationStatus});
summary.Tag='runSummary';
uilabel(liveGrid,'Text','Прогноз и решения контроллера','FontWeight','bold');
controllerSummary=uilabel(liveGrid,'Text','Static · P = 1.00 · RA/DT = 10/90 · прогноз не используется', ...
    'WordWrap','on','Tag','controllerSummary');
controllerHistory=uitable(liveGrid,'Data',cell(0,8), ...
    'ColumnName',{'Время, с','Прогноз','Факт','Ошибка','P','RA/DT','Применено','Причина'}, ...
    'ColumnWidth',{65,75,50,65,32,62,90,75}, ...
    'Tag','controllerHistory');
uilabel(liveGrid,'Text','Действия и ошибки','FontWeight','bold');
eventLog=uitextarea(liveGrid,'Editable','off','Value',{'Окно готово'});
eventLog.Tag='eventLog';
uilabel(liveGrid,'Text','Радиособытия, наблюдаемые базовой станцией','FontWeight','bold');
radioEventLog=uitextarea(liveGrid,'Editable','off','Value',{'Радиособытий пока нет'});
radioEventLog.Tag='radioEventLog';
initialControllerView=nbiot.ui.buildControllerDisplayData(session.snapshot());
controllerSummary.Text=initialControllerView.summary;
controllerHistory.Data=initialControllerView.historyDisplay;
savedGrid=uigridlayout(savedTab,[7 1]); savedGrid.RowHeight={38,30,'1x','1x',28,38,38};
uibutton(savedGrid,'Text','Открыть/сравнить KPI CSV','Tag','savedKpiButton', ...
    'ButtonPushedFcn',@loadSavedKpi);
savedMetric=uidropdown(savedGrid,'Items',{'Скорость доставки, бит/с'}, ...
    'ItemsData',{'throughputBitsPerSecond'},'Value','throughputBitsPerSecond', ...
    'Tag','savedKpiMetric','ValueChangedFcn',@plotSavedKpi);
savedTable=uitable(savedGrid,'Data',cell(0,0),'ColumnName',{},'Tag','savedKpiTable');
savedAxes=uiaxes(savedGrid); title(savedAxes,'Сравнение сохранённых результатов');
savedAxes.Tag='savedKpiAxes';
xlabel(savedAxes,'Время модели, с'); ylabel(savedAxes,'бит/с'); grid(savedAxes,'on');
savedInfo=uilabel(savedGrid,'Text','Выберите один или несколько *_kpi.csv. Таблица показывает первый файл; график сравнивает выбранные запуски.');
savedInfo.Tag='savedKpiInfo';
savedDatasetButton=uibutton(savedGrid,'Text','Экспортировать development-набор', ...
    'Tag','savedDatasetButton','Enable','off','ButtonPushedFcn',@exportDataset);
exportChartsButton=uibutton(savedGrid,'Text','Экспортировать графики PNG', ...
    'Tag','exportChartsButton','Enable','off','ButtonPushedFcn',@exportCharts);
comparisonTab=uitab(displayTabs,'Title','Сравнение режимов','Tag','methodSummaryTab');
comparisonGrid=uigridlayout(comparisonTab,[7 2]);
comparisonGrid.RowHeight={34,28,22,'1x',22,'1x','1.1x'};
comparisonGrid.ColumnWidth={'1x','1x'};
comparisonGrid.Padding=[6 6 6 6]; comparisonGrid.RowSpacing=5;
loadMethodSummaryButton=uibutton(comparisonGrid,'Text','Открыть сводку сравнения', ...
    'Tag','loadMethodSummaryButton','ButtonPushedFcn',@loadSavedMethodComparison);
loadMethodSummaryButton.Layout.Row=1; loadMethodSummaryButton.Layout.Column=1;
methodSummaryMetric=uidropdown(comparisonGrid, ...
    'Items',{'Вероятность доставки'},'ItemsData',{'deliveryProbability'}, ...
    'Value','deliveryProbability','Tag','methodSummaryMetric', ...
    'ValueChangedFcn',@refreshSavedMethodComparison);
methodSummaryMetric.Layout.Row=1; methodSummaryMetric.Layout.Column=2;
methodSummaryBurst=uidropdown(comparisonGrid,'Items',{'Сначала загрузите сводку'}, ...
    'ItemsData',0,'Value',0,'Tag','methodSummaryBurst', ...
    'ValueChangedFcn',@refreshSavedMethodComparison);
methodSummaryBurst.Layout.Row=2; methodSummaryBurst.Layout.Column=1;
methodSummaryInfo=uilabel(comparisonGrid, ...
    'Text','Таблицы читают готовые сводки; пересчёт симуляции не запускается.', ...
    'Tag','methodSummaryInfo','WordWrap','on');
methodSummaryInfo.Layout.Row=2; methodSummaryInfo.Layout.Column=2;
methodSummaryHeading=uilabel(comparisonGrid, ...
    'Text','Среднее по режимам и 95% интервал');
methodSummaryHeading.Layout.Row=3; methodSummaryHeading.Layout.Column=[1 2];
methodSummaryTable=uitable(comparisonGrid,'Data',cell(0,8), ...
    'ColumnName',{'Устройства','Всплеск, мс','Режим','Полных','Неполных', ...
    'Среднее','Нижняя граница','Верхняя граница'},'Tag','methodSummaryTable');
methodSummaryTable.Layout.Row=4; methodSummaryTable.Layout.Column=[1 2];
pairedSummaryHeading=uilabel(comparisonGrid, ...
    'Text','Парное различие: второй режим минус первый');
pairedSummaryHeading.Layout.Row=5; pairedSummaryHeading.Layout.Column=[1 2];
pairedSummaryTable=uitable(comparisonGrid,'Data',cell(0,9), ...
    'ColumnName',{'Устройства','Всплеск, мс','Режим 1','Режим 2','Пар', ...
    'Неполных пар','Разница средних','Нижняя граница','Верхняя граница'}, ...
    'Tag','pairedSummaryTable');
pairedSummaryTable.Layout.Row=6; pairedSummaryTable.Layout.Column=[1 2];
methodSummaryAxes=uiaxes(comparisonGrid,'Tag','methodSummaryAxes');
methodSummaryAxes.Layout.Row=7; methodSummaryAxes.Layout.Column=[1 2];
title(methodSummaryAxes,'Средний показатель по трём режимам');
xlabel(methodSummaryAxes,'Число устройств'); ylabel(methodSummaryAxes,'Вероятность доставки');
grid(methodSummaryAxes,'on');
chartTab=uitab(displayTabs,'Title','Графики запуска','Tag','resultChartsTab');
chartGrid=uigridlayout(chartTab,[5 2]);
chartGrid.RowHeight={34,'1x','1x','1x','1x'};
chartGrid.ColumnWidth={'1x','1x'};
chartGrid.Padding=[6 6 6 6]; chartGrid.RowSpacing=6; chartGrid.ColumnSpacing=8;
chartInfo=uilabel(chartGrid,'Text', ...
    'Итоговые Static-графики. Фактическая нагрузка и столкновения — диагностические данные; Adaptive-прогноз пока недоступен.', ...
    'WordWrap','on','Tag','staticChartInfo');
chartInfo.Layout.Row=1; chartInfo.Layout.Column=[1 2];
chartSpecs={ ...
    'activeUe','staticChartActiveUe','Средняя активность UE','Устройств'; ...
    'actualLoad','staticChartActualLoad','Фактическая нагрузка (диагностика)','UE в RA'; ...
    'collisions','staticChartCollisions','Столкновения попыток RA','%'; ...
    'successfulRa','staticChartSuccessfulRa','Успешные попытки RA','Попыток'; ...
    'throughput','staticChartThroughput','Скорость доставки','бит/с'; ...
    'delay','staticChartDelay','Задержка доставленных пакетов','мс'; ...
    'dataBler','staticChartDataBler','Data BLER','%'; ...
    'occupancy','staticChartOccupancy','Занятость ресурсов','%'};
chartAxes=struct();
for chartIndex=1:size(chartSpecs,1)
    key=chartSpecs{chartIndex,1};
    ax=uiaxes(chartGrid,'Tag',chartSpecs{chartIndex,2});
    ax.Layout.Row=ceil(chartIndex/2)+1; ax.Layout.Column=mod(chartIndex-1,2)+1;
    title(ax,chartSpecs{chartIndex,3}); xlabel(ax,'Время модели, с');
    ylabel(ax,chartSpecs{chartIndex,4}); grid(ax,'on');
    chartAxes.(key)=ax;
end
controllerChartTab=uitab(displayTabs,'Title','Прогноз и управление','Tag','controllerChartsTab');
controllerChartGrid=uigridlayout(controllerChartTab,[3 2]);
controllerChartGrid.RowHeight={30,'1x','1x'};
controllerChartGrid.ColumnWidth={'1x','1x'};
controllerChartGrid.Padding=[6 6 6 6];
controllerChartInfo=uilabel(controllerChartGrid, ...
    'Text','Static · прогноз и адаптивные графики не используются.', ...
    'WordWrap','on','Tag','controllerChartInfo');
controllerChartInfo.Layout.Row=1; controllerChartInfo.Layout.Column=[1 2];
controllerChartAxes=struct();
controllerChartAxes.forecast=uiaxes(controllerChartGrid,'Tag','controllerChartForecast');
controllerChartAxes.forecast.Layout.Row=2; controllerChartAxes.forecast.Layout.Column=1;
title(controllerChartAxes.forecast,'Фактическая нагрузка и прогноз');
xlabel(controllerChartAxes.forecast,'Время модели, с');
ylabel(controllerChartAxes.forecast,'UE в RA'); grid(controllerChartAxes.forecast,'on');
controllerChartAxes.access=uiaxes(controllerChartGrid,'Tag','controllerChartAccess');
controllerChartAxes.access.Layout.Row=2; controllerChartAxes.access.Layout.Column=2;
title(controllerChartAxes.access,'Вероятность доступа P');
xlabel(controllerChartAxes.access,'Время модели, с');
ylabel(controllerChartAxes.access,'P'); ylim(controllerChartAxes.access,[0 1]);
grid(controllerChartAxes.access,'on');
controllerChartAxes.raDt=uiaxes(controllerChartGrid,'Tag','controllerChartRaDt');
controllerChartAxes.raDt.Layout.Row=3; controllerChartAxes.raDt.Layout.Column=1;
title(controllerChartAxes.raDt,'Доля ресурсов RA/DT');
xlabel(controllerChartAxes.raDt,'Время модели, с');
ylabel(controllerChartAxes.raDt,'RA, %'); ylim(controllerChartAxes.raDt,[0 100]);
grid(controllerChartAxes.raDt,'on');
controllerChartAxes.error=uiaxes(controllerChartGrid,'Tag','controllerChartError');
controllerChartAxes.error.Layout.Row=3; controllerChartAxes.error.Layout.Column=2;
title(controllerChartAxes.error,'Ошибка прогноза');
xlabel(controllerChartAxes.error,'Время модели, с');
ylabel(controllerChartAxes.error,'Прогноз − факт, UE'); grid(controllerChartAxes.error,'on');
clearControllerCharts();
staticChartsReady=false;
timerHandle=timer('ExecutionMode','fixedSpacing','Period',0.05,'BusyMode','drop', ...
    'TimerFcn',@advanceRun,'ErrorFcn',@timerFailed);
lastDisplayTick=0;
lastStaticChartWindow=0;
radioEventCursor=0; radioLogLines=cell(0,1);
latestUeDetails=struct([]); selectedUeId=NaN;
savedComparison=[]; savedLabels={}; savedMethodComparison=[];
app=struct('Figure',fig,'Session',session,'Timer',timerHandle);
refreshButtons();
appendLog('Окно готово к запуску');

    function addNumber(parent,label,key,path,value,limits,kind)
        row=nextRow(parent); labelHandle=uilabel(parent,'Text',label,'Interpreter','none');
        labelHandle.Layout.Row=row; labelHandle.Layout.Column=1;
        field=uieditfield(parent,'numeric','Value',value,'Limits',limits);
        field.Layout.Row=row; field.Layout.Column=2; field.Tag=key;
        controls.(key)=field; paths.(key)=path; kinds.(key)=kind;
    end
    function addText(parent,label,key,path,value)
        row=nextRow(parent); labelHandle=uilabel(parent,'Text',label,'Interpreter','none');
        labelHandle.Layout.Row=row; labelHandle.Layout.Column=1;
        field=uieditfield(parent,'text','Value',strjoin(compose('%.12g',value),' '));
        field.Layout.Row=row; field.Layout.Column=2; field.Tag=key;
        controls.(key)=field; paths.(key)=path; kinds.(key)='vector';
    end
    function addDropdown(parent,label,key,path,value,items)
        row=nextRow(parent); labelHandle=uilabel(parent,'Text',label);
        labelHandle.Layout.Row=row; labelHandle.Layout.Column=1;
        field=uidropdown(parent,'Items',items,'Value',value);
        field.Layout.Row=row; field.Layout.Column=2; field.Tag=key;
        controls.(key)=field; paths.(key)=path; kinds.(key)='text';
    end
    function addNumericDropdown(parent,label,key,path,value,items,itemsData)
        row=nextRow(parent); labelHandle=uilabel(parent,'Text',label);
        labelHandle.Layout.Row=row; labelHandle.Layout.Column=1;
        field=uidropdown(parent,'Items',items,'ItemsData',itemsData,'Value',value);
        field.Layout.Row=row; field.Layout.Column=2; field.Tag=key;
        controls.(key)=field; paths.(key)=path; kinds.(key)='number';
    end
    function row=nextRow(parent)
        if isempty(parent.UserData), parent.UserData=0; end
        row=parent.UserData+1; parent.UserData=row;
    end
    function cfgOut=readConfiguration()
        cfgOut=nbiot.config.defaultConfig();
        names=fieldnames(controls);
        for ix=1:numel(names)
            key=names{ix}; control=controls.(key); kind=kinds.(key);
            value=control.Value;
            if strcmp(kind,'vector')
                value=parseVector(value);
            elseif strcmp(kind,'integer')
                if value~=fix(value), error('nbiot:ui:InvalidInput','Поле «%s» должно быть целым числом.',key); end
            end
            cfgOut=setNested(cfgOut,paths.(key),value);
        end
        if strcmp(cfgOut.policy.name,'Adaptive-P')
            cfgOut.policy.accessProbability=adaptiveStartProbability.Value;
            cfgOut.policy.raShare=0.1;
        elseif strcmp(cfgOut.policy.name,'Adaptive-RA/DT')
            cfgOut.policy.accessProbability=1;
            cfgOut.policy.raShare=adaptiveStartRaShare.Value;
        end
        cfgOut.logging.outputFolder=fullfile(root,'results','ui-local');
        cfgOut=nbiot.config.validateConfig(cfgOut);
        cfgOut=nbiot.experiments.loadCalibration(cfgOut,calibrationFile);
    end
    function startRun(~,~)
        if ~strcmp(session.Status,'idle'), return; end
        try
            cfgToRun=readConfiguration();
            controllerOptions=controllerOptionsFor(cfgToRun);
            session.start(cfgToRun,controllerOptions);
            clearStaticCharts(); clearControllerCharts();
            lastStaticChartWindow=0;
            radioEventCursor=0; radioLogLines=cell(0,1);
            radioEventLog.Value={'Радиособытий пока нет'};
            updateView(session.snapshot());
            lastDisplayTick=0;
            setConfigurationEnabled(false); statusLabel.Text='Выполняется…';
            appendLog(sprintf('Запуск %s. Лимит: 10 устройств, 5 секунд, до 5 минут на случай.', ...
                cfgToRun.policy.name));
            refreshButtons();
            start(timerHandle);
        catch exception
            statusLabel.Text='Запуск не выполнен';
            appendLog(['Запуск не выполнен: ' exception.message]);
            setConfigurationEnabled(true); refreshButtons();
            showAlert(exception.message,'Не удалось запустить');
        end
    end
    function selectModel(~,~)
        [file,folder]=chooseModelFile();
        if isequal(file,0)||isempty(file), return; end
        selectedModelFile=''; allowDevelopmentModel.Value=false;
        try
            candidate=fullfile(char(string(folder)),char(string(file)));
            bundle=nbiot.ml.validateModelBundle(candidate);
            if ~strcmp(bundle.status,'development')
                error('nbiot:ui:ModelStatus', ...
                    'Окно сейчас принимает только явно помеченные development-модели.');
            end
            selectedModelFile=candidate;
            modelSelectionError=false;
            modelStatus.Text=sprintf('Пакет проверен: %s · development',bundle.modelName);
            modelForDisplay=bundle;
            modelForDisplay.evaluationMetrics= ...
                nbiot.ui.loadModelEvaluationMetrics(candidate,bundle);
            modelDetails.Value=nbiot.ui.formatModelInfo(modelForDisplay);
            appendLog(['Выбрана development-модель: ' bundle.modelName]);
        catch exception
            modelSelectionError=true;
            modelStatus.Text=['Модель не подходит: ' exception.message];
            modelDetails.Value={'Сведения о модели не показаны, так как пакет не прошёл проверку.'};
            appendLog(['Модель не подходит: ' exception.message]);
            showAlert(exception.message,'Модель не подходит');
        end
        updateModeControls();
    end
    function options=controllerOptionsFor(cfgToRun)
        options=struct();
        if strcmp(cfgToRun.policy.name,'Static'), return; end
        if isempty(selectedModelFile)
            error('nbiot:ui:ModelRequired', ...
                'Для адаптивного режима сначала выберите совместимую модель.');
        end
        bundle=nbiot.ml.validateModelBundle(selectedModelFile);
        if ~strcmp(bundle.status,'development')
            error('nbiot:ui:ModelStatus', ...
                'Эта модель не прошла независимую проверку для обычного запуска.');
        end
        if ~allowDevelopmentModel.Value
            error('nbiot:ui:DevelopmentModelOptIn', ...
                'Для учебной модели явно включите разрешение только для отладки.');
        end
        method=cfgToRun.policy.name;
        accessRange=[]; allowedShares=[];
        if strcmp(method,'Adaptive-P')
            accessRange=[allowedPMin.Value allowedPMax.Value];
        else
            allowedShares=allowedRaShares.Value;
        end
        policy=nbiot.controller.buildAdaptivePolicy(method,accessRange,allowedShares);
        options=struct('model',selectedModelFile,'allowDevelopmentModel',true, ...
            'policy',policy);
    end
    function updateModeControls(~,~)
        method=controls.simulationMode.Value;
        accessControl=controls.accessProbability;
        shareControl=controls.raShare;
        adaptive=~strcmp(method,'Static');
        if strcmp(method,'Adaptive-P')
            shareControl.Value=0.1;
        elseif strcmp(method,'Adaptive-RA/DT')
            accessControl.Value=1;
        end
        accessControl.Enable=onOff(strcmp(method,'Static') && strcmp(session.Status,'idle'));
        shareControl.Enable=onOff(strcmp(method,'Static') && strcmp(session.Status,'idle'));
        adaptiveStartRaShare.Enable=onOff(strcmp(method,'Adaptive-RA/DT') && ...
            strcmp(session.Status,'idle'));
        adaptiveStartProbability.Enable=onOff(strcmp(method,'Adaptive-P') && ...
            strcmp(session.Status,'idle'));
        allowedPMin.Enable=onOff(strcmp(method,'Adaptive-P') && ...
            strcmp(session.Status,'idle'));
        allowedPMax.Enable=onOff(strcmp(method,'Adaptive-P') && ...
            strcmp(session.Status,'idle'));
        allowedRaShares.Enable=onOff(strcmp(method,'Adaptive-RA/DT') && ...
            strcmp(session.Status,'idle'));
        selectModelButton.Enable=onOff(adaptive && strcmp(session.Status,'idle'));
        allowDevelopmentModel.Enable=onOff(adaptive && strcmp(session.Status,'idle'));
        if modelSelectionError
            return;
        elseif adaptive && isempty(selectedModelFile)
            modelStatus.Text='Выберите совместимый пакет. Development-модель разрешена только для отладки.';
        elseif ~adaptive && isempty(selectedModelFile)
            modelStatus.Text='Модель не выбрана. Для Static она не нужна.';
        end
    end
    function advanceRun(~,~)
        if ~strcmp(session.Status,'running'), return; end
        try
            session.advance(20); state=session.snapshot();
            if nbiot.ui.shouldRefreshDisplay(state.tick,lastDisplayTick, ...
                    ~strcmp(session.Status,'running'))
                updateView(state); lastDisplayTick=state.tick;
            else
                drawnow limitrate;
            end
            if ~strcmp(session.Status,'running')
                stop(timerHandle); setConfigurationEnabled(true);
                statusLabel.Text=statusText(session.Status,state.tick,state.durationTicks);
                if ~isempty(state.error), appendLog(state.error); end
                appendLog(['Сценарий завершён: ' statusText(session.Status,state.tick,state.durationTicks)]);
                if any(strcmp(session.Status,{'completed','stopped','failed'}))
                    try
                        output=session.getResult(); appendSummary(nbiot.ui.formatResultSummary(output));
                        if strcmp(session.Status,'completed'), drawStaticCharts(output); end
                    catch exception
                        appendSummary(exception.message);
                    end
                end
                refreshButtons();
            end
        catch exception
            try
                session.stop();
            catch
            end
            stop(timerHandle); setConfigurationEnabled(true); statusLabel.Text='Ошибка';
            appendLog(['Ошибка обновления: ' exception.message]); refreshButtons();
        end
    end
    function pauseRun(~,~)
        if strcmp(session.Status,'running'), stop(timerHandle); session.pause(); statusLabel.Text='Пауза'; appendLog('Расчёт приостановлен'); refreshButtons(); end
    end
    function resumeRun(~,~)
        if strcmp(session.Status,'paused'), session.resume(); start(timerHandle); statusLabel.Text='Выполняется…'; appendLog('Расчёт продолжен'); refreshButtons(); end
    end
    function stopRun(~,~)
        session.stop(); if isvalid(timerHandle), stop(timerHandle); end
        setConfigurationEnabled(true); state=session.snapshot(); updateView(state);
        statusLabel.Text='Остановлено'; appendLog('Расчёт остановлен пользователем');
        try
            appendSummary(nbiot.ui.formatResultSummary(session.getResult()));
        catch exception
            appendSummary(exception.message);
        end
        refreshButtons();
    end
    function resetRun(~,~)
        if isvalid(timerHandle), stop(timerHandle); end
        session.reset(); setConfigurationEnabled(true); cla(map); deviceTable.Data=cell(0,4);
        clearStaticCharts(); clearControllerCharts();
        progress.Value=0; statusLabel.Text=calibrationStatus; lastDisplayTick=0;
        lastStaticChartWindow=0;
        latestUeDetails=struct([]); selectedUeId=NaN;
        selectedUeDetails.Value={'Выберите UE в таблице, чтобы посмотреть подробности.'};
        summary.Value={'Static · 1 мс · не более 10 устройств';calibrationStatus};
        eventLog.Value={'Окно готово к запуску'};
        radioEventCursor=0; radioLogLines=cell(0,1);
        radioEventLog.Value={'Радиособытий пока нет'};
        appendLog('Сессия сброшена'); refreshButtons();
    end
    function saveRun(~,~)
        if strcmp(session.Status,'idle'), return; end
        folder=chooseOutputDirectory();
        if isequal(folder,0), return; end
        stamp=char(datetime('now','Format','yyyyMMdd-HHmmss'));
        target=fullfile(folder,['nbiot-' stamp]);
        try
            destination=session.save(target);
            appendLog(['Результат сохранён: ' destination]); statusLabel.Text='Результат сохранён';
            refreshButtons();
        catch exception
            appendLog(['Не удалось сохранить: ' exception.message]);
            showAlert(exception.message,'Не удалось сохранить');
        end
    end
    function exportDataset(~,~)
        if ~strcmp(session.Status,'completed') || isempty(session.SavedPath) || ~isfile(session.SavedPath)
            showAlert('Сначала завершите расчёт и сохраните его результат.','Экспорт датасета');
            return;
        end
        parent=chooseDatasetOutputDirectory();
        if isequal(parent,0), return; end
        stamp=char(datetime('now','Format','yyyyMMdd-HHmmss'));
        target=fullfile(char(parent),['nbiot-dataset-development-' stamp]);
        try
            exported=nbiot.ui.exportDevelopmentDataset(session.SavedPath,target);
            savedInfo.Text=sprintf('Development-набор: %d окон · ID %d · тестовые данные', ...
                exported.rows,exported.realizationId);
            appendLog(sprintf('Development-набор сохранён: %s',exported.outputFolder));
        catch exception
            appendLog(['Не удалось экспортировать набор: ' exception.message]);
            showAlert(exception.message,'Не удалось экспортировать набор');
        end
    end
    function exportCharts(~,~)
        if ~staticChartsReady||~any(strcmp(session.Status,{'completed','stopped'}))
            showAlert('Сначала завершите или остановите запуск, чтобы сохранить графики.', ...
                'Экспорт графиков');
            return;
        end
        parent=chooseChartOutputDirectory();
        if isequal(parent,0)||isempty(parent), return; end
        stamp=char(datetime('now','Format','yyyyMMdd-HHmmss'));
        target=fullfile(char(string(parent)),['nbiot-charts-' stamp]);
        try
            files=nbiot.ui.exportStaticCharts(chartAxes,target);
            savedInfo.Text=sprintf('%d графиков PNG сохранено: %s',numel(files),target);
            appendLog(['Графики сохранены: ' target]);
        catch exception
            appendLog(['Не удалось экспортировать графики: ' exception.message]);
            showAlert(exception.message,'Не удалось экспортировать графики');
        end
    end
    function loadSavedKpi(~,~)
        [files,folder]=chooseKpiFile();
        if isequal(files,0), return; end
        try
            if ischar(files) || isstring(files), files=cellstr(files); end
            if ~iscell(files) || isempty(files)
                error('nbiot:ui:KpiFiles','Выберите один или несколько KPI CSV.');
            end
            selectedPaths=cellfun(@(file) fullfile(folder,char(string(file))), ...
                files,'UniformOutput',false);
            comparison=nbiot.ui.loadKpiCsvFiles(selectedPaths);
            first=comparison.tables{1};
            savedTable.Data=table2cell(first);
            savedTable.ColumnName=first.Properties.VariableNames;
            labels=cell(size(comparison.files));
            for index=1:numel(comparison.files)
                [~,base,extension]=fileparts(comparison.files{index});
                labels{index}=[base extension];
            end
            savedComparison=comparison;
            savedLabels=labels;
            [metricFields,metricLabels]=availableKpiMetrics(comparison.tables);
            savedMetric.ItemsData=[];
            savedMetric.Items=metricLabels;
            savedMetric.ItemsData=metricFields;
            savedMetric.Value='throughputBitsPerSecond';
            plotSavedKpi();
            savedInfo.Text=sprintf('%d запуск(а/ов) на графике · таблица: %s · без пересчёта', ...
                numel(labels),labels{1});
            appendLog(sprintf('Загружено KPI-файлов: %d',numel(labels)));
        catch exception
            appendLog(['Не удалось прочитать KPI: ' exception.message]);
            showAlert(exception.message,'Не удалось прочитать KPI');
        end
    end
    function loadSavedMethodComparison(~,~)
        folder=chooseComparisonFolder();
        if isequal(folder,0)||isempty(folder), return; end
        try
            savedMethodComparison=nbiot.ui.loadComparisonSummary(folder);
            metrics=savedMethodComparison.metrics;
            metricLabels=cell(numel(metrics),1);
            for index=1:numel(metrics)
                metricLabels{index}=metricLabel(char(metrics(index)));
            end
            methodSummaryMetric.Items=metricLabels;
            methodSummaryMetric.ItemsData=cellstr(metrics(:));
            if any(metrics=="deliveryProbability")
                methodSummaryMetric.Value='deliveryProbability';
            else
                methodSummaryMetric.Value=char(metrics(1));
            end
            durations=savedMethodComparison.burstDurations(:);
            durationLabels=cellstr(compose('%d мс',durations));
            methodSummaryBurst.Items=[{'Все варианты'};durationLabels];
            methodSummaryBurst.ItemsData=[0;durations];
            if isempty(durations), methodSummaryBurst.Value=0;
            else, methodSummaryBurst.Value=durations(1); end
            refreshSavedMethodComparison();
            methodSummaryInfo.Text=sprintf( ...
                'Загружено из %s · показаны полные и неполные случаи.',folder);
            appendLog('Загружена сводка трёх режимов');
        catch exception
            appendLog(['Не удалось открыть сравнение: ' exception.message]);
            showAlert(exception.message,'Не удалось открыть сравнение');
        end
    end
    function refreshSavedMethodComparison(~,~)
        if isempty(savedMethodComparison), return; end
        methods=savedMethodComparison.methodSummary;
        pairs=savedMethodComparison.pairedDifferences;
        selectedMetric=string(methodSummaryMetric.Value);
        selectedBurst=methodSummaryBurst.Value;
        methodMask=string(methods.metric)==selectedMetric;
        pairMask=string(pairs.metric)==selectedMetric;
        if selectedBurst~=0
            methodMask=methodMask&methods.burstDurationTicks==selectedBurst;
            pairMask=pairMask&pairs.burstDurationTicks==selectedBurst;
        end
        methodColumns={'numUE','burstDurationTicks','method','runCount', ...
            'incompleteCount','mean','ci95Low','ci95High'};
        pairColumns={'numUE','burstDurationTicks','methodA','methodB','pairCount', ...
            'incompletePairCount','meanDifference','ci95Low','ci95High'};
        methodView=methods(methodMask,methodColumns);
        pairView=pairs(pairMask,pairColumns);
        methodSummaryTable.Data=table2cell(methodView);
        pairedSummaryTable.Data=table2cell(pairView);
        cla(methodSummaryAxes); hold(methodSummaryAxes,'on');
        methodOrder=["Static";"Adaptive-P";"Adaptive-RA/DT"];
        bursts=unique(methodView.burstDurationTicks,'stable');
        for methodIndex=1:numel(methodOrder)
            for burstIndex=1:numel(bursts)
                rows=methodView(string(methodView.method)==methodOrder(methodIndex)& ...
                    methodView.burstDurationTicks==bursts(burstIndex),:);
                if isempty(rows), continue; end
                rows=sortrows(rows,'numUE');
                displayName=char(methodOrder(methodIndex));
                if selectedBurst==0
                    displayName=sprintf('%s · %d мс',displayName,bursts(burstIndex));
                end
                plot(methodSummaryAxes,rows.numUE,rows.mean,'-o', ...
                    'DisplayName',displayName,'Tag','methodSummaryLine');
                intervalRows=isfinite(rows.ci95Low)&isfinite(rows.ci95High);
                if any(intervalRows)
                    errorbar(methodSummaryAxes,rows.numUE(intervalRows), ...
                        rows.mean(intervalRows), ...
                        rows.mean(intervalRows)-rows.ci95Low(intervalRows), ...
                        rows.ci95High(intervalRows)-rows.mean(intervalRows), ...
                        'LineStyle','none','HandleVisibility','off');
                end
            end
        end
        hold(methodSummaryAxes,'off');
        if ~isempty(findobj(methodSummaryAxes,'Type','line','Tag','methodSummaryLine'))
            legend(methodSummaryAxes,'show','Location','best');
        end
        title(methodSummaryAxes,['Сравнение: ' metricLabel(char(selectedMetric))]);
        xlabel(methodSummaryAxes,'Число устройств');
        ylabel(methodSummaryAxes,metricLabel(char(selectedMetric)));
        grid(methodSummaryAxes,'on');
    end
    function plotSavedKpi(~,~)
        if isempty(savedComparison), return; end
        metric=savedMetric.Value;
        cla(savedAxes);
        hold(savedAxes,'on');
        for index=1:numel(savedComparison.tables)
            series=savedComparison.tables{index};
            plot(savedAxes,double(series.endTick)*.001,double(series.(metric)), ...
                '-o','DisplayName',savedLabels{index});
        end
        hold(savedAxes,'off');
        if numel(savedLabels)>1
            legend(savedAxes,'show','Interpreter','none','Location','best');
        else
            legend(savedAxes,'off');
        end
        title(savedAxes,['Сравнение: ' metricLabel(metric)]);
        xlabel(savedAxes,'Время модели, с');
        ylabel(savedAxes,metricLabel(metric));
        grid(savedAxes,'on');
    end
    function drawStaticCharts(result)
        values=nbiot.ui.buildStaticChartData(result);
        drawStaticChartValues(values);
        staticChartsReady=~isempty(values);
        chartInfo.Text=sprintf(['Итоговые Static-графики · %d окон KPI по 500 мс. ' ...
            'Фактическая нагрузка и столкновения показаны отдельно как диагностика; ' ...
            'прогноз и Adaptive-графики пока недоступны.'],height(values));
    end
    function drawStaticChartValues(values)
        time=values.endTimeSeconds;
        plotChart(chartAxes.activeUe,time,values.meanActiveUe,'Средняя активность UE','Устройств');
        plotChart(chartAxes.actualLoad,time,values.actualLoadMeanRaUe, ...
            'Фактическая нагрузка (диагностика)','UE в RA');
        plotChart(chartAxes.collisions,time,100*values.collisionProbability, ...
            'Столкновения попыток RA','%');
        plotChart(chartAxes.successfulRa,time,values.successfulRa,'Успешные попытки RA','Попыток');
        plotChart(chartAxes.throughput,time,values.throughputBitsPerSecond,'Скорость доставки','бит/с');
        plotChart(chartAxes.delay,time,1000*values.meanDeliveryDelaySeconds, ...
            'Задержка доставленных пакетов','мс');
        plotChart(chartAxes.dataBler,time,100*values.dataBler,'Data BLER','%');
        cla(chartAxes.occupancy); hold(chartAxes.occupancy,'on');
        plot(chartAxes.occupancy,time,100*values.ulOccupancy,'-o','DisplayName','UL');
        plot(chartAxes.occupancy,time,100*values.dlOccupancy,'-o','DisplayName','DL');
        hold(chartAxes.occupancy,'off');
        title(chartAxes.occupancy,'Занятость ресурсов');
        xlabel(chartAxes.occupancy,'Время модели, с'); ylabel(chartAxes.occupancy,'%');
        grid(chartAxes.occupancy,'on'); legend(chartAxes.occupancy,'show','Location','best');
    end
    function updateStaticChartsDuringRun(state)
        if ~strcmp(state.controllerMethod,'Static')||~session.hasResult()|| ...
                strcmp(session.Status,'completed')
            return;
        end
        windowTicks=session.Config.dataset.windowTicks;
        closedWindowCount=floor(min(state.tick,state.durationTicks)/windowTicks);
        if closedWindowCount<=lastStaticChartWindow, return; end
        values=session.liveStaticChartData();
        if isempty(values), return; end
        drawStaticChartValues(values);
        staticChartsReady=true;
        lastStaticChartWindow=height(values);
        chartInfo.Text=sprintf(['Промежуточные Static-графики · окно KPI — 500 мс; ' ...
            'показаны закрытые окна до %.3f с. Графики обновляются после каждого окна; ' ...
            'фактическая нагрузка и столкновения — диагностика.'], ...
            values.endTimeSeconds(end));
    end
    function clearStaticCharts()
        staticChartsReady=false;
        keys=fieldnames(chartAxes);
        for clearIndex=1:numel(keys)
            key=keys{clearIndex}; ax=chartAxes.(key);
            cla(ax);
            specIndex=find(strcmp(chartSpecs(:,1),key),1);
            title(ax,chartSpecs{specIndex,3});
            xlabel(ax,'Время модели, с'); ylabel(ax,chartSpecs{specIndex,4});
            grid(ax,'on');
        end
        legend(chartAxes.occupancy,'off');
        chartInfo.Text=['Графики появятся после завершения локального запуска. ' ...
            'Фактическая нагрузка и столкновения — диагностика; прогноз и Adaptive-графики пока недоступны.'];
    end
    function clearControllerCharts()
        keys=fieldnames(controllerChartAxes);
        for clearIndex=1:numel(keys)
            key=keys{clearIndex}; cla(controllerChartAxes.(key));
        end
        controllerChartInfo.Text='Для Static прогноз и адаптивные графики не используются.';
    end
    function drawControllerCharts(history,method)
        clearControllerCharts();
        if strcmp(method,'Static')||isempty(history), return; end
        time=history.decisionTimeSeconds;
        actual=history.actualLoadMeanRaUe;
        forecast=history.forecastMeanRaUe;
        hold(controllerChartAxes.forecast,'on');
        if any(isfinite(actual))
            plot(controllerChartAxes.forecast,time,actual,'-o', ...
                'DisplayName','Фактическая нагрузка (диагностика)');
        end
        if any(isfinite(forecast))
            plot(controllerChartAxes.forecast,time,forecast,'--s','DisplayName','Прогноз');
        end
        hold(controllerChartAxes.forecast,'off');
        legend(controllerChartAxes.forecast,'show','Location','best');
        access=history.accessProbability;
        if any(isfinite(access))
            plot(controllerChartAxes.access,time,access,'-o');
        end
        raShare=history.raShare;
        if any(isfinite(raShare))
            plot(controllerChartAxes.raDt,time,100*raShare,'-o');
        end
        errorValues=history.forecastErrorMeanRaUe;
        if any(isfinite(errorValues))
            plot(controllerChartAxes.error,time,errorValues,'-o');
            yline(controllerChartAxes.error,0,'k:');
        end
        controllerChartInfo.Text=sprintf(['%s · DEVELOPMENT-модель, только отладка. ' ...
            'Фактическая нагрузка и ошибка показаны только для диагностики.'],method);
    end
    function plotChart(ax,time,series,caption,units)
        cla(ax); plot(ax,time,series,'-o'); title(ax,caption);
        xlabel(ax,'Время модели, с'); ylabel(ax,units); grid(ax,'on');
    end
    function [fields,labels]=availableKpiMetrics(tables)
        fields={}; labels={};
        candidates=tables{1}.Properties.VariableNames;
        excluded={'windowId','startTick','endTick'};
        for candidateIndex=1:numel(candidates)
            field=candidates{candidateIndex};
            if any(strcmp(field,excluded)), continue; end
            presentNumeric=true;
            for tableIndex=1:numel(tables)
                current=tables{tableIndex};
                if ~ismember(field,current.Properties.VariableNames) || ...
                        ~isnumeric(current.(field))
                    presentNumeric=false;
                    break;
                end
            end
            if presentNumeric
                fields{end+1}=field; %#ok<AGROW>
                labels{end+1}=metricLabel(field); %#ok<AGROW>
            end
        end
    end
    function label=metricLabel(field)
        switch field
            case 'throughputBitsPerSecond', label='Скорость доставки, бит/с';
            case 'cohortDeliveryProbability', label='Вероятность доставки';
            case 'created', label='Создано пакетов';
            case 'delivered', label='Доставлено пакетов';
            case 'dropped', label='Потеряно пакетов';
            case 'unfinished', label='Незавершённые пакеты';
            case 'raSuccess', label='Успешный доступ';
            case 'raFailed', label='Неудачные попытки доступа';
            case 'raUnfinished', label='Незавершённые попытки доступа';
            case 'collidingAttempts', label='Попытки с коллизией';
            case 'raSuccessProbability', label='Вероятность успеха доступа';
            case 'raSuccessCompletedProbability', label='Успех среди завершённых попыток';
            case 'meanRaAttempts', label='Среднее число попыток доступа';
            case 'deliveryProbability', label='Вероятность доставки';
            case 'deliveryCompletedProbability', label='Доставка среди завершённых пакетов';
            case 'dropProbability', label='Вероятность потери';
            case 'collisionAttemptProbability', label='Доля попыток с коллизией';
            case 'meanDelayTicks', label='Средняя задержка, мс';
            case 'p95DelayTicks', label='95-й процентиль задержки, мс';
            case 'msg3Bler', label='Доля ошибок Msg3';
            case 'msg3Decoded', label='Принятые блоки Msg3';
            case 'msg3CrcFailures', label='Ошибки CRC Msg3';
            case 'dataBler', label='Доля ошибок данных';
            case 'dataDecoded', label='Принятые блоки данных';
            case 'dataCrcFailures', label='Ошибки CRC данных';
            case 'ulOccupancy', label='Доля занятости UL';
            case 'dlOccupancy', label='Доля занятости DL';
            case 'nprachOccupancy', label='Доля занятости NPRACH';
            case 'deliveredInWindow', label='Доставлено пакетов';
            case 'droppedInWindow', label='Отброшено пакетов';
            case 'raStarted', label='Попытки доступа';
            case 'raSucceededInWindow', label='Успешные попытки доступа';
            case 'raFailedInWindow', label='Неудачные попытки доступа';
            case 'ulTbDecoded', label='Принятые блоки данных';
            case 'ulCrcFailures', label='Ошибки CRC';
            case 'meanBsQueueLength', label='Средняя очередь станции';
            case 'maxBsQueueLength', label='Максимальная очередь станции';
            case 'meanUeQueueLength', label='Средняя очередь устройств';
            case 'maxUeQueueLength', label='Максимальная очередь устройств';
            case 'harqBlocksStarted', label='Начатые блоки HARQ';
            case 'harqBlocksFailed', label='Неуспешные блоки HARQ';
            case 'harqBlocksCensored', label='Блоки HARQ без завершения';
            case 'harqAttemptsStarted', label='Начатые попытки HARQ';
            case 'harqRetryAttempts', label='Повторные попытки HARQ';
            case 'harqRetryTransmissions', label='Повторные передачи HARQ';
            case 'harqFirstTransmissionBler', label='Ошибки HARQ при первой передаче';
            case 'harqAllAttemptBler', label='Ошибки HARQ по всем передачам';
            case 'controllerDecisionCount', label='Решения контроллера';
            case 'controllerSwitches', label='Переключения настроек';
            case 'controllerDecisions', label='Решения контроллера';
            case 'configurationSwitches', label='Переключения настроек';
            otherwise, label=field;
        end
    end
    function updateView(state)
        [newEvents,radioEventCursor]=session.observedEventsSince(radioEventCursor);
        newLines=nbiot.ui.formatObservedEvents(newEvents);
        if ~isempty(newLines)
            radioLogLines=[radioLogLines;newLines];
            radioEventLog.Value=radioLogLines;
        end
        tick=min(state.tick,state.durationTicks);
        progress.Value=100*tick/max(1,state.durationTicks);
        statusLabel.Text=statusText(session.Status,tick,state.durationTicks);
        if isfield(state,'ueDetails'), latestUeDetails=state.ueDetails; end
        deviceTable.Data=state.deviceTable;
        refreshSelectedUeDetails();
        if ~isempty(state.positions)
            cla(map); hold(map,'on');
            scatter(map,state.positions(:,1),state.positions(:,2),36,'filled');
            plot(map,0,0,'kp','MarkerSize',13,'MarkerFaceColor',[0.9 0.25 0.2]);
            plot(map,state.radiusM*cos(linspace(0,2*pi,100)), ...
                state.radiusM*sin(linspace(0,2*pi,100)),'k:');
            xlim(map,[-state.radiusM*1.05 state.radiusM*1.05]);
            ylim(map,[-state.radiusM*1.05 state.radiusM*1.05]);
            hold(map,'off');
        end
        crc=state.crcCounters;
        liveSummary=nbiot.ui.formatLiveStateSummary(state);
        summary.Value={sprintf('Время модели: %.3f / %.3f с; CRC Msg3: %d ошибок; CRC Data: %d ошибок', ...
            tick*.001,state.durationTicks*.001,crc.msg3Errors,crc.dataErrors), ...
            liveSummary{1},liveSummary{2},liveSummary{3}};
        controllerView=nbiot.ui.buildControllerDisplayData(state);
        controllerSummary.Text=controllerView.summary;
        controllerHistory.Data=controllerView.historyDisplay;
        drawControllerCharts(controllerView.history,state.controllerMethod);
        updateStaticChartsDuringRun(state);
        refreshButtons();
        drawnow limitrate;
    end
    function selectUe(~,eventData)
        if isempty(eventData.Indices)
            selectedUeId=NaN;
        else
            row=eventData.Indices(1,1);
            if row>=1&&row<=numel(latestUeDetails)
                selectedUeId=double(latestUeDetails(row).ueId);
            else
                selectedUeId=NaN;
            end
        end
        refreshSelectedUeDetails();
    end
    function refreshSelectedUeDetails()
        if ~isfinite(selectedUeId)||isempty(latestUeDetails)
            selectedUeDetails.Value={'Выберите UE в таблице, чтобы посмотреть подробности.'};
            return;
        end
        index=find(double([latestUeDetails.ueId])==selectedUeId,1);
        if isempty(index)
            selectedUeId=NaN;
            selectedUeDetails.Value={'Выберите UE в таблице, чтобы посмотреть подробности.'};
            return;
        end
        selectedUeDetails.Value=nbiot.ui.formatUeDetail(latestUeDetails(index));
    end
    function refreshButtons()
        active=any(strcmp(session.Status,{'running','paused'}));
        startButton.Enable=onOff(strcmp(session.Status,'idle'));
        pauseButton.Enable=onOff(strcmp(session.Status,'running'));
        resumeButton.Enable=onOff(strcmp(session.Status,'paused'));
        stopButton.Enable=onOff(active);
        resetButton.Enable=onOff(~strcmp(session.Status,'idle'));
        saveButton.Enable=onOff(session.hasResult());
        savedDatasetButton.Enable=onOff(strcmp(session.Status,'completed') && ...
            ~isempty(session.SavedPath) && isfile(session.SavedPath));
        exportChartsButton.Enable=onOff(staticChartsReady&& ...
            any(strcmp(session.Status,{'completed','stopped'})));
    end
    function setConfigurationEnabled(enabled)
        names=fieldnames(controls);
        for index=1:numel(names)
            controls.(names{index}).Enable=onOff(enabled);
        end
        method=controls.simulationMode.Value;
        adaptive=~strcmp(method,'Static');
        controls.accessProbability.Enable=onOff(enabled && ...
            strcmp(method,'Static'));
        controls.raShare.Enable=onOff(enabled && strcmp(method,'Static'));
        adaptiveStartRaShare.Enable=onOff(enabled && strcmp(method,'Adaptive-RA/DT'));
        adaptiveStartProbability.Enable=onOff(enabled && strcmp(method,'Adaptive-P'));
        allowedPMin.Enable=onOff(enabled && strcmp(method,'Adaptive-P'));
        allowedPMax.Enable=onOff(enabled && strcmp(method,'Adaptive-P'));
        allowedRaShares.Enable=onOff(enabled && strcmp(method,'Adaptive-RA/DT'));
        selectModelButton.Enable=onOff(enabled && adaptive);
        allowDevelopmentModel.Enable=onOff(enabled && adaptive);
    end
    function appendSummary(line)
        current=summary.Value; if ischar(current), current={current}; end
        current{end+1}=char(line);
        if numel(current)>100, current=current(end-99:end); end
        summary.Value=current;
    end
    function appendLog(line)
        current=eventLog.Value; if ischar(current), current={current}; end
        timestamp=char(datetime('now','Format','HH:mm:ss'));
        current{end+1}=[timestamp ' · ' char(line)];
        if numel(current)>200, current=current(end-199:end); end
        eventLog.Value=current;
    end
    function timerFailed(~,event)
        try
            session.stop();
        catch
        end
        try
            if isa(event.Data,'MException'), appendLog(event.Data.message); end
        catch
        end
        try
            stop(timerHandle);
        catch
        end
        setConfigurationEnabled(true);
        statusLabel.Text='Ошибка таймера'; refreshButtons();
    end
    function closeApp(~,~)
        try
            if isvalid(timerHandle), stop(timerHandle); delete(timerHandle); end
        catch
        end
        session.close(); fig.CloseRequestFcn=[]; delete(fig);
    end
end

function value=parseVector(textValue)
tokens=regexp(strtrim(char(textValue)),'[,;\s]+','split');
if isempty(tokens) || (isscalar(tokens) && isempty(tokens{1}))
    value=[]; return;
end
value=cellfun(@str2double,tokens);
if any(~isfinite(value)), error('nbiot:ui:InvalidInput','Введите список конечных чисел через пробел.'); end
end

function cfg=setNested(cfg,path,value)
parts=strsplit(path,'.');
if isscalar(parts)
    cfg.(parts{1})=value;
else
    cfg.(parts{1})=setNested(cfg.(parts{1}),strjoin(parts(2:end),'.'),value);
end
end

function state=onOff(condition)
if condition, state='on'; else, state='off'; end
end

function text=statusText(status,tick,duration)
text=sprintf('%s · %.3f / %.3f с модели',status,tick*.001,duration*.001);
end

function grid=formGrid(parent,rows)
grid=uigridlayout(parent,[rows 2]);
grid.ColumnWidth={'1x',150}; grid.RowHeight=repmat({26},1,rows);
grid.Padding=[8 8 8 8]; grid.RowSpacing=3; grid.UserData=0;
end
