classdef DeviceStore < handle
    %DEVICESTORE Plain records; no object per UE and no BS CRC field.
    %
    % Пояснение (рус.): таблица состояний всех UE (модель состояний §12 ТЗ).
    % Одна запись на устройство - так быстрее, чем объект на каждое UE.
    % Состояния (поле state):
    %   IDLE      - нет сообщения;
    %   WAIT_RA   - есть сообщение, ждёт окна случайного доступа;
    %   WAIT_RAR  - отправило преамбулу, ждёт ответа станции (RAR);
    %   WAIT_MSG4 - отправило Msg3, ждёт разрешения конкуренции (Msg4);
    %   DATA      - доступ получен, передаёт блоки данных и ждёт квитанции;
    %   BACKOFF   - попытка не удалась, случайная пауза до новой попытки.
    % Итог сообщения (DONE/DROPPED из ТЗ) хранится в PacketStore.
    % Важные поля: attemptNumber - попытки RA для текущего сообщения;
    % nInit - выбранная преамбула; token - идентификатор для Msg3/Msg4;
    % rnti - временный номер от станции; deadlineTick - срок ожидания ответа;
    % nextAllowedTick - когда кончится BACKOFF; ndi/fragmentIndex - HARQ и
    % номер передаваемого блока; ulBusy* - интервал, когда UE уже передаёт
    % (UE не может одновременно передавать и принимать).
    properties (SetAccess=private)
        entries
    end
    methods
        function obj=DeviceStore(count)
            entry=struct('state','IDLE','packetId',0,'attemptId',0,'attemptNumber',0, ...
                'lifetimeAttempt',0,'occasionId',0,'nInit',-1,'token',uint64(0), ...
                'rnti',0,'raRnti',0,'timingAdvanceSeconds',0,'deadlineTick',Inf, ...
                'monitorStartTick',Inf,'nextAllowedTick',0,'progressDeadlineTick',Inf, ...
                'fragmentIndex',0,'ndi',-1,'encoderState',[],'raSucceeded',false, ...
                'ulBusyStartTick',-Inf,'ulBusyUntilTick',-Inf);
            obj.entries=repmat(entry,count,1);
        end
        function entry=get(obj,ueId), entry=obj.entries(ueId); end
        function set(obj,ueId,entry), obj.entries(ueId)=entry; end
        % reset - вернуть UE в IDLE после завершения сообщения; общий
        % счётчик попыток и занятость передатчика сохраняются.
        function reset(obj,ueId)
            lifetime=obj.entries(ueId).lifetimeAttempt;
            busyStart=obj.entries(ueId).ulBusyStartTick; busyEnd=obj.entries(ueId).ulBusyUntilTick;
            fresh=nbiot.devices.DeviceStore(1); obj.entries(ueId)=fresh.entries;
            obj.entries(ueId).lifetimeAttempt=lifetime;
            obj.entries(ueId).ulBusyStartTick=busyStart; obj.entries(ueId).ulBusyUntilTick=busyEnd;
        end
        % counts - сколько UE сейчас в процедуре доступа и сколько не в IDLE.
        function [ra,active]=counts(obj)
            state=string({obj.entries.state});
            ra=sum(ismember(state,["WAIT_RA","WAIT_RAR","WAIT_MSG4","BACKOFF"]));
            active=sum(state~="IDLE");
        end
    end
end
