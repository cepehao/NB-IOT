function [obs,target]=closeWindow(observed,truth,first,last,raIntegral,activeIntegral,queueIntegral,realizationId,windowTicks)
%CLOSEWINDOW Finish an observation window without passing truth into features.
e=observed([observed.tick]>=first & [observed.tick]<last);
if nargin<9, windowTicks=500; end
t=truth([truth.tick]>=first & [truth.tick]<last);
det=0; peak=[]; maxPeak=[]; energy=[]; dec=0; failures=0; rar=0; grants=0; queues=[];
s=nbiot.dataset.featureSchema();
for k=1:numel(e)
    if ~ismember(e(k).kind,s.allowedObservationKinds), error('nbiot:dataset:Source','Unapproved observed source.'); end
    f=e(k).fields;
    switch e(k).kind
        case 'nprach_detection'
            det=det+f.count; peak(end+1)=f.meanMetric; maxPeak(end+1)=f.maxMetric; energy(end+1)=f.energyW; %#ok<AGROW>
        case 'phy_decode'
            if f.receiverId~=0, error('nbiot:dataset:Leakage','UE decoder outcome is not a BS observation.'); end
            if f.hasCrc, dec=dec+1; failures=failures+double(f.crcError~=0); end
        case 'rar_sent', rar=rar+1;
        case 'grant', grants=grants+1;
        case 'bs_queue', queues(end+1)=f.pendingRequests; %#ok<AGROW>
    end
end
windowId=floor(first/windowTicks)+1;
obs={realizationId,windowId,first,last,det,average(peak),maximum(maxPeak), ...
    average(energy),dec,failures,rar,grants,average(queues)};
msg=t(strcmp({t.kind},'msg1')); users=[];
for k=1:numel(msg), users(end+1)=msg(k).fields.ueId; end %#ok<AGROW>
width=last-first;
target={realizationId,windowId,first,last,raIntegral/width,activeIntegral/width, ...
    queueIntegral/width,numel(msg),numel(unique(users))};
end
function m=average(x), if isempty(x), m=0; else, m=mean(x); end, end
function m=maximum(x), if isempty(x), m=0; else, m=max(x); end, end
