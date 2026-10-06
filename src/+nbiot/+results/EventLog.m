classdef EventLog < handle
    %EVENTLOG Append-only semantic events; receiver features have a whitelist.
    properties (Access=private)
        buffer = cell(256,1)
        used = 0
    end
    methods
        function append(obj,tick,kind,fields)
            obj.used=obj.used+1;
            if obj.used>numel(obj.buffer), obj.buffer=[obj.buffer;cell(numel(obj.buffer),1)]; end
            obj.buffer{obj.used}=struct('tick',double(tick),'kind',char(kind),'fields',fields);
        end
        function events=all(obj)
            if obj.used==0, events=struct('tick',{},'kind',{},'fields',{});
            else, events=vertcat(obj.buffer{1:obj.used}); end
        end
    end
end
