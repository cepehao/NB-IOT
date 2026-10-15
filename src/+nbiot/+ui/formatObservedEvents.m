function lines=formatObservedEvents(events)
%FORMATOBSERVEDEVENTS Format only base-station-observed radio events for UI.
lines=cell(0,1);
if isempty(events), return; end
required={'tick','kind','fields'};
if ~isstruct(events)||~all(isfield(events,required)), return; end
for k=1:numel(events)
    event=events(k); fields=event.fields;
    if ~isstruct(fields)||~isscalar(fields), continue; end
    switch char(event.kind)
        case 'nprach_detection'
            if ~all(isfield(fields,{'count','maxMetric'})), continue; end
            line=sprintf('t=%.0f мс · Обнаружение доступа: кандидатов %d, показатель %.3g', ...
                event.tick,fields.count,fields.maxMetric);
        case 'grant'
            if ~all(isfield(fields,{'phase','rnti','format','startTick','endTick'})), continue; end
            line=sprintf('t=%.0f мс · Выдано разрешение: %s, формат %s, RNTI %g, %.0f–%.0f мс', ...
                event.tick,char(fields.phase),char(fields.format),fields.rnti, ...
                fields.startTick,fields.endTick);
        case 'rar_sent'
            if ~isfield(fields,'rnti'), continue; end
            line=sprintf('t=%.0f мс · Отправлен ответ RAR для RNTI %g',event.tick,fields.rnti);
        case 'phy_decode'
            if ~all(isfield(fields,{'channel','phase','rnti','hasCrc','crcError','receiverId'}))|| ...
                    fields.receiverId~=0
                continue;
            end
            if ~fields.hasCrc
                outcome='без CRC';
            elseif fields.crcError==0
                outcome='CRC OK';
            else
                outcome='ошибка CRC';
            end
            line=sprintf('t=%.0f мс · Приём %s/%s, RNTI %g: %s',event.tick, ...
                char(fields.channel),char(fields.phase),fields.rnti,outcome);
        otherwise
            continue;
    end
    lines{end+1,1}=line; %#ok<AGROW>
end
end
