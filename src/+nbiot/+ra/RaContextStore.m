classdef RaContextStore < handle
    %RACONTEXTSTORE BS observations only: no true UE identity or contenders.
    %
    % Пояснение (рус.): контексты процедуры доступа на стороне станции.
    % Контекст создаётся на каждую обнаруженную преамбулу - станция не знает,
    % сколько UE за ней стоит. Временный номер RNTI = 255 + номер контекста.
    % Состояния: RAR_PENDING -> MSG3_RX -> MSG4_PENDING -> MSG4_ACK ->
    % DATA_PENDING <-> DATA_RX -> RECEIPT_PENDING -> RECEIPT_ACK -> DONE,
    % а также FAILED, EXPIRED и *_RETRY (повтор Msg4/квитанции).
    % Поля: token/sequence - прочитаны из Msg3; nextFragment/ndi/harqTry/
    % softBuffer - приём блоков данных и HARQ; pending - ждёт планирования;
    % deadlineTick - срок; delaySeconds - оценённая задержка для поправки TA.
    properties (SetAccess=private)
        entries = struct('id',{},'rnti',{},'nInit',{},'occasionId',{},'state',{}, ...
            'deadlineTick',{},'token',{},'sequence',{},'nextFragment',{},'ndi',{}, ...
            'harqTry',{},'softBuffer',{},'pending',{},'schedule',{}, ...
            'receiptAttempts',{},'lastProgressTick',{},'dataComplete',{},'delaySeconds',{})
    end
    methods
        function id=create(obj,nInit,occasionId,deadlineTick,delaySeconds)
            id=numel(obj.entries)+1;
            if id>65000, error('nbiot:ra:RntiExhausted','Temporary RNTI pool exhausted.'); end
            e=struct('id',id,'rnti',255+id,'nInit',nInit,'occasionId',occasionId, ...
                'state','RAR_PENDING','deadlineTick',deadlineTick,'token',uint64(0), ...
                'sequence',0,'nextFragment',1,'ndi',0,'harqTry',1,'softBuffer',[], ...
                'pending',true,'schedule',[],'receiptAttempts',0,'lastProgressTick',0, ...
                'dataComplete',false,'delaySeconds',delaySeconds);
            obj.entries(end+1)=e;
        end
        function e=get(obj,id), e=obj.entries(id); end
        function set(obj,id,e), obj.entries(id)=e; end
        function id=findRnti(obj,rnti)
            id=find([obj.entries.rnti]==rnti,1); if isempty(id), id=0; end
        end
    end
end
