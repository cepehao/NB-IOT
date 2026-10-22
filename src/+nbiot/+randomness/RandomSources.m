classdef RandomSources
    % Пояснение (рус.): источник всех случайных чисел симулятора.
    % Генератор mrg32k3a; номер реализации выбирает поток (stream), а каждая
    % комбинация «источник x направление x устройство x блок» - свой подпоток.
    % Источники: layout, traffic, shadowing, channel, CFO, timing, noise,
    % payload, access, backoff, token.
    % Зачем: если устройство в Adaptive-P пропустит окно доступа, у других
    % UE не сдвинутся ни шум, ни fading, ни трафик. Так разница между
    % Static и Adaptive определяется только алгоритмом управления (§43 ТЗ).
    properties (SetAccess=private)
        masterSeed
        realizationId
    end
    methods
        function obj=RandomSources(masterSeed,realizationId)
            validateattributes(masterSeed,{'numeric'},{'scalar','integer','>=',0,'<=',2^32-1});
            validateattributes(realizationId,{'numeric'},{'scalar','integer','>=',0,'<=',4095});
            obj.masterSeed=double(masterSeed); obj.realizationId=double(realizationId);
        end
        % stream - независимый генератор для одного источника и ключа.
        % Например, stream('noise',0,0,k) - шум приёмника BS в k-й миллисекунде.
        function s=stream(obj,name,direction,receiverId,blockId)
            key=nbiot.randomness.substreamKey(name,direction,receiverId,blockId);
            s=RandStream.create('mrg32k3a','NumStreams',4096,'StreamIndices',obj.realizationId+1,'Seed',obj.masterSeed);
            s.Substream=key;
        end
        function m=manifest(obj)
            m=struct('algorithm','mrg32k3a','masterSeed',obj.masterSeed,'externalRealizationId',obj.realizationId,'numStreams',4096,'streamIndex',obj.realizationId+1,'sourceNames',{{'layout','traffic','shadowing','channel','CFO','timing','noise','payload','access','backoff','token'}},'sourceCodes',1:11,'keyFormula','1+blockId+2^24*(receiverId+2^16*(direction+2*sourceCode))','directionCodes',[0 1],'staticBlockId',0);
        end
    end
end
