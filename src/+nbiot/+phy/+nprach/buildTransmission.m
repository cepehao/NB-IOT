function tx=buildTransmission(cfg,occasion,nInit)
% Пояснение (рус.): передатчик NPRACH (Msg1). Берёт шаблон выбранной
% преамбулы nInit и оформляет передачу, начинающуюся в окне доступа.
% Мощность 23 дБм выставит RadioChannel.add.
validateattributes(nInit,{'numeric'},{'scalar','integer','>=',0,'<=',11});
bank=nbiot.phy.nprach.templates(cfg); t=bank{nInit+1};
g=struct('grantId',occasion.occasionId,'startTick',occasion.startTick,'kind','nprach');
if isfield(occasion,'grantId'), g.grantId=occasion.grantId; end
tx=nbiot.phy.transmission(cfg,g,t.waveform,0,t.activeRanges);
end
