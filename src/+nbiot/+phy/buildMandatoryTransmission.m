function tx=buildMandatoryTransmission(cfg,tick)
% Stateless public wrapper, derives SIB1 bundle phase from absolute frame.
% Пояснение (рус.): обязательные служебные сигналы станции в этом тике
% (синхросигналы NPSS/NSSS, NPBCH, системная информация SIB1). Они всегда
% присутствуют в DL и занимают свои подкадры; их не может занять планировщик.
[~,kinds]=nbiot.scheduler.mandatoryDlMask(tick+1,cfg.phy.cellId);
state=[];
if kinds.sib1(end)
    startFrame=16*mod(cfg.phy.cellId,4);
    relative=mod(floor(tick/10)-startFrame,256);
    index=8*floor(relative/64)+floor(mod(relative,64)/2);
    state=struct('sibEncoder',struct('SubframeIdx',index));
end
tx=nbiot.phy.mandatoryDL(cfg,tick,state);
end
