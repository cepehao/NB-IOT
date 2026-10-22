function scenario=buildScenario(cfg,sources)
%BUILDSCENARIO Immutable geometry, slow fading and pre-generated traffic.
%
% Пояснение (рус.): сценарий развёртывания (§10 ТЗ). Строится один раз на
% опыт и дальше не меняется. Для каждого UE: координаты, indoor/outdoor,
% расстояние, потери (path loss, shadowing, стены), CFO, ошибка
% синхронизации, коэффициенты трёх лучей fading отдельно для UL и DL.
% Также здесь заранее генерируется расписание всех сообщений.
% Каждая величина берётся из своего потока случайных чисел, поэтому
% одинаковые seed и номер реализации дают одинаковый сценарий.
cfg=nbiot.config.validateConfig(cfg);
if nargin<2, sources=nbiot.randomness.RandomSources(cfg.simulation.seed,cfg.simulation.realizationId); end
n=cfg.simulation.numUE; c=cfg.cell; h=cfg.channel;
% Ровно round(0.30*N) устройств «в зданиях», выбранных случайно.
s=sources.stream('layout',0,0,0); indoor=false(n,1); [~,order]=sort(rand(s,n,1)); indoor(order(1:round(c.indoorFraction*n)))=true;
ue=repmat(struct('ueId',uint32(0),'xM',0,'yM',0,'indoor',false,'distanceM',0,'horizontalDistanceM',0,'pathLossDb',0,'medianPathLossDb',0,'shadowingDb',0,'penetrationDb',0,'cfoHz',0,'syncOffsetSeconds',0,'tapsUl',[],'tapsDl',[],'coverageClass','CE0'),n,1);
% Средние мощности лучей fading (0, -3, -6 дБ), нормированные к сумме 1.
p=10.^(h.tapPowersDb(:)/10); p=p/sum(p);
% Потери в свободном пространстве на опорном расстоянии 10 м (~51,5 дБ при 900 МГц).
ref=20*log10(4*pi*h.carrierHz*h.referenceDistanceM/299792458);
for id=1:n
 % Радиус через sqrt даёт равномерное распределение по площади кольца
 % 10..1000 м (иначе устройства скапливались бы у центра). Угол - любой.
 s=sources.stream('layout',0,id,0); radius=sqrt(c.minDistanceM^2+(c.radiusM^2-c.minDistanceM^2)*rand(s)); angle=2*pi*rand(s);
 u=ue(id); u.ueId=uint32(id); u.xM=radius*cos(angle); u.yM=radius*sin(angle); u.horizontalDistanceM=radius; u.indoor=indoor(id); u.distanceM=hypot(radius,c.bsHeightM-c.ueHeightM);
 % distanceM - трёхмерное расстояние с учётом высот BS 30 м и UE 1,5 м.
 % Path loss: модель log-distance с показателем 3,5 (~121,5 дБ на 1 км).
 u.medianPathLossDb=ref+10*h.pathLossExponent*log10(max(u.distanceM,h.referenceDistanceM)/h.referenceDistanceM);
 % Shadowing: нормальная добавка с sigma 8 дБ (улица) или 10 дБ (здание);
 % в здании ещё +20 дБ на стены. Итог pathLossDb - полное ослабление.
 sigma=h.shadowOutdoorDb; if u.indoor, sigma=h.shadowIndoorDb; u.penetrationDb=h.penetrationIndoorDb; end
 s=sources.stream('shadowing',0,id,0); u.shadowingDb=sigma*randn(s); u.pathLossDb=max(0,u.medianPathLossDb+u.shadowingDb+u.penetrationDb);
 % CFO - сдвиг частоты генератора UE: нормальный с sigma 50 Гц,
 % обрезанный до +-200 Гц (§13, §17 ТЗ).
 s=sources.stream('CFO',0,id,0); u.cfoHz=0;
 if h.cfoLimitHz>0&&h.cfoSigmaHz>0
  % Inverse-CDF sampling avoids unbounded rejection for narrow limits.
  a=.5*(1+erf(-h.cfoLimitHz/(h.cfoSigmaHz*sqrt(2)))); b=1-a;
  u.cfoHz=h.cfoSigmaHz*sqrt(2)*erfinv(2*(a+(b-a)*rand(s))-1);
 end
 % Остаточная ошибка синхронизации UE: равномерно в +-2 мкс.
 s=sources.stream('timing',0,id,0); u.syncOffsetSeconds=(2*rand(s)-1)*h.syncLimitSeconds;
 % Fading Рэлея: комплексные гауссовы коэффициенты трёх лучей, отдельно
 % для UL и DL. Постоянны в течение опыта (устройства неподвижны).
 s=sources.stream('channel',0,id,0); u.tapsUl=sqrt(p/2).*(randn(s,numel(p),1)+1i*randn(s,numel(p),1));
 s=sources.stream('channel',1,id,0); u.tapsDl=sqrt(p/2).*(randn(s,numel(p),1)+1i*randn(s,numel(p),1)); ue(id)=u;
end
% Итог: UE, опорный бюджет линии, расписание сообщений и описание
% использованных генераторов случайных чисел (для воспроизводимости).
scenario=struct('ue',ue,'linkBudget',nbiot.channel.evaluateLinks(cfg,ue), ...
 'arrivals',nbiot.traffic.generateArrivals(cfg,sources), ...
 'randomManifest',sources.manifest(),'externalRealizationId',sources.realizationId);
end
