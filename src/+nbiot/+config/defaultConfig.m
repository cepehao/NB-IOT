function cfg = defaultConfig()
%DEFAULTCONFIG Research profile static-v1, with no toolbox execution.
%
% Пояснение (рус.): все настройки опыта по умолчанию (профиль static-v1).
% Значения из ТЗ: 5000 тиков по 1 мс, 1000 UE, seed 42, сота 1000/10 м,
% высоты 30/1,5 м, indoor 0,30, 900 МГц, 23 дБм, NF BS 5 дБ, 290 К,
% shadowing 8/10 дБ, стены 20 дБ, CFO sigma 50 Гц до 200 Гц, 200 байт,
% очередь 10, 8 попыток RA, Static RA/DT 10/90, окно 500 мс.
% Остальное - проектные решения, обоснованные в docs/model-profile.md.
% Перед запуском настройки проверяет validateConfig.
cfg.profileVersion = 'static-v1';
% simulation: длительность в тиках, длина тика (с), частота дискретизации
% (1,92 МГц = 1920 отсчётов на тик), число UE, seed, номер реализации.
cfg.simulation = struct('durationTicks',5000,'tickSeconds',1e-3,'sampleRateHz',1920000,'numUE',1000,'seed',42,'realizationId',0);
% cell: геометрия соты (§10 ТЗ).
cfg.cell = struct('radiusM',1000,'minDistanceM',10,'bsHeightM',30,'ueHeightM',1.5,'indoorFraction',.30,'cellId',1);
% channel: радиоканал и бюджет линии (§13 ТЗ): потери log-distance,
% shadowing, стены, мощности, шум-факторы, CFO, ошибка синхронизации и
% три луча fading (задержки и средние мощности).
cfg.channel = struct('carrierHz',900e6,'referenceDistanceM',10,'pathLossExponent',3.5,'shadowOutdoorDb',8,'shadowIndoorDb',10,'penetrationIndoorDb',20,'uePowerDbm',23,'bsPowerDbm',23,'bsNoiseFigureDb',5,'ueNoiseFigureDb',7,'temperatureK',290,'cfoSigmaHz',50,'cfoLimitHz',200,'syncLimitSeconds',2e-6,'tapDelaysSeconds',[0 .3 .9]*1e-6,'tapPowersDb',[0 -3 -6],'fractionalFilterLength',65);
% traffic: вид трафика (burst/periodic/poisson), размер сообщения, лимит
% очереди, параметры всплеска, срок жизни сообщения (10 с), активные UE.
cfg.traffic = struct('kind','burst','packetBytes',200,'queueLimit',10,'periodTicks',1000,'poissonRatePerSecond',.2,'burstStartTick',1000,'burstDurationTicks',100,'lifetimeTicks',10000,'activityMode','all','activeUeIds',[]);
% ra: случайный доступ - максимум попыток, BACKOFF до 256 мс, окна NPRACH
% каждые 80 мс со сдвигом 8 мс, 12 преамбул, формат 0, окна ожидания
% RAR и Msg4 (в периодах прослушивания NPDCCH).
cfg.ra = struct('maxAttempts',8,'backoffTicks',256,'periodTicks',80,'startOffsetTicks',8,'numSubcarriers',12,'format',0,'repetitions',1,'rarPp',10,'contentionPp',16);
% phy: физический уровень - время обработки, HARQ (до 4 передач, RV 0-2-0-2),
% таймауты, порог детектора NPRACH (NaN, пока не загружена калибровка),
% сетка поиска CFO. Ниже профили NPUSCH для Msg3, данных и ACK, профиль
% нисходящих данных и NPDCCH.
cfg.phy = struct('processingTicks',1,'cellId',1,'sampleRateHz',1920000,'maxHarqTransmissions',4,'rvSequence',[0 2 0 2],'decoderIterations',5,'progressTimeoutTicks',1024,'receiptTimeoutTicks',512,'maxReceiptTransmissions',4,'nprachThreshold',NaN,'nprachCfoGridHz',-200:25:200);
cfg.phy.msg3 = struct('format','Data','spacingHz',15000,'numSubcarriers',3,'nru',1,'nulSlots',8,'repetitions',2,'tbs',88,'rarIndex',2,'durationTicks',8);
cfg.phy.data = struct('format','Data','spacingHz',15000,'numSubcarriers',3,'nru',4,'nulSlots',8,'repetitions',2,'tbs',256,'mcs',4,'iru',3,'durationTicks',32);
cfg.phy.ack = struct('format','Control','spacingHz',15000,'numSubcarriers',1,'nru',1,'nulSlots',4,'repetitions',2,'tbs',1,'durationTicks',4);
cfg.phy.downlink = struct('modulation','QPSK','mcs',6,'isf',0,'nsf',1,'tbs',88,'repetitions',2,'nbRefP',1);
cfg.phy.npdcch = struct('rmax',4,'g',8,'offset',0,'repetitions',2,'aggregationLevel',2);
% policy: начальная политика управления. Static: P = 1, доля RA = 0,1 (10/90).
% dataset: длина окна датасета. logging: сохранение сигналов и папка вывода.
cfg.policy = struct('name','Static','accessProbability',1,'raShare',.1,'windowTicks',500);
cfg.dataset = struct('windowTicks',500);
cfg.logging = struct('saveWaveforms',false,'outputFolder','results');
cfg.parameterSources = struct('simulation','requirement','geometry','requirement','channel','static-v1 research decision','phy','Release 13 and static-v1 research decision','traffic','static-v1 research decision');
end
