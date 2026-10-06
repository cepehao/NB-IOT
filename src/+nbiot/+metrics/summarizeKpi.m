function k=summarizeKpi(cfg,packets,attempts,observed,truth,usage,actualTick,harqJournal,queueSamples)
%SUMMARIZEKPI Retain explicit numerators, denominators and censored work.
k=struct('created',numel(packets),'delivered',0,'dropped',0,'unfinished',0);
if ~isempty(packets)
    k.delivered=sum(strcmp({packets.status},'delivered')); k.dropped=sum(strcmp({packets.status},'dropped'));
    k.unfinished=sum(strcmp({packets.status},'unfinished'));
end
assert(k.created==k.delivered+k.dropped+k.unfinished,'nbiot:metrics:Balance','Packet balance broken.');
k.raStarted=numel(attempts); k.raSuccess=0; k.raFailed=0; k.raUnfinished=0; k.collidingAttempts=0;
if ~isempty(attempts)
    k.raSuccess=sum(strcmp({attempts.status},'success')); k.raFailed=sum(strcmp({attempts.status},'failure'));
    k.raUnfinished=k.raStarted-k.raSuccess-k.raFailed; k.collidingAttempts=sum([attempts.collision]);
end
k.raSuccessProbability=ratio(k.raSuccess,k.raStarted);
k.raSuccessCompletedProbability=ratio(k.raSuccess,k.raSuccess+k.raFailed);
k.deliveryProbability=ratio(k.delivered,k.created); k.dropProbability=ratio(k.dropped,k.created);
k.deliveryCompletedProbability=ratio(k.delivered,k.delivered+k.dropped);
k.collisionAttemptProbability=ratio(k.collidingAttempts,k.raStarted);
k.deliveredPayloadBits=k.delivered*cfg.traffic.packetBytes*8;
k.durationSeconds=actualTick*cfg.simulation.tickSeconds;
k.throughputBitsPerSecond=ratio(k.deliveredPayloadBits,k.durationSeconds);
delays=[];
for p=packets
    if strcmp(p.status,'delivered'), delays(end+1)=double(p.deliveredTick)-double(p.createdTick); end %#ok<AGROW>
end
k.delayCount=numel(delays); k.meanDelayTicks=mean(delays); k.p95DelayTicks=percentile(delays,.95);
k.msg3Decoded=0; k.msg3CrcFailures=0; k.dataDecoded=0; k.dataCrcFailures=0;
decodes=observed(strcmp({observed.kind},'phy_decode'));
for e=reshape(decodes,1,[])
    f=e.fields;
    if f.hasCrc && strcmp(f.channel,'Msg3')
        k.msg3Decoded=k.msg3Decoded+1; k.msg3CrcFailures=k.msg3CrcFailures+double(f.crcError~=0);
    elseif f.hasCrc && strcmp(f.channel,'Data')
        k.dataDecoded=k.dataDecoded+1; k.dataCrcFailures=k.dataCrcFailures+double(f.crcError~=0);
    end
end
k.msg3Bler=ratio(k.msg3CrcFailures,k.msg3Decoded); k.dataBler=ratio(k.dataCrcFailures,k.dataDecoded);
% Occupancy is the union of actually used allocation envelopes, not bookings.
n=max(0,min(actualTick,cfg.simulation.durationTicks)); ul=false(2*n,48); dl=false(n,1);
for e=reshape(truth(strcmp({truth.kind},'transmission')),1,[])
    f=e.fields; ticks=f.ticks(f.ticks<n & f.ticks>=0); if isempty(ticks), continue; end
    if strcmpi(f.direction,'UL')
        rows=reshape([2*ticks(:)+1 2*ticks(:)+2].',[],1);
        bins=f.frequencyStartHz/3750+(1:f.bandwidthHz/3750); ul(rows,bins)=true;
    else, dl(ticks+1)=true; end
end
mask=nbiot.scheduler.mandatoryDlMask(n,cfg.cell.cellId);
k.ulOccupiedUnits=sum(ul,'all'); k.ulAvailableUnits=numel(ul); k.ulOccupancy=ratio(k.ulOccupiedUnits,k.ulAvailableUnits);
k.dlOccupiedUnits=sum(dl & ~mask(:)); k.dlAvailableUnits=sum(~mask); k.dlOccupancy=ratio(k.dlOccupiedUnits,k.dlAvailableUnits);
k.occupancyDefinition='Union of transmitted resource allocation envelopes; mandatory DL excluded; NPRACH reserved band is 45 kHz.';
k.resourceBudgets=usage;
k.meanRaAttempts=ratio(k.raStarted,k.created);
k.deliveredFraction=k.deliveryProbability;
k.meanDelaySeconds=k.meanDelayTicks*cfg.simulation.tickSeconds;
k.p95DelaySeconds=k.p95DelayTicks*cfg.simulation.tickSeconds;
nprach=false(2*n,12);
for e=reshape(truth(strcmp({truth.kind},'transmission')),1,[])
    f=e.fields;
    if ~isfield(f,'channel') || ~strcmp(f.channel,'NPRACH'), continue; end
    ticks=f.ticks(f.ticks<n & f.ticks>=0);
    rows=reshape([2*ticks(:)+1 2*ticks(:)+2].',[],1);
    nprach(rows,:)=true;
end
k.nprachOccupiedUnits=sum(nprach,'all'); k.nprachAvailableUnits=numel(nprach);
k.nprachOccupancy=ratio(k.nprachOccupiedUnits,k.nprachAvailableUnits);
k.nprachEnvelopeOccupancy=k.nprachOccupancy;
k.nprachOccupancyDefinition='Union of transmitted 45 kHz NPRACH allocation envelopes, divided by 45 kHz horizon; not instantaneous hopping-tone occupancy.';
queues=[];
for e=reshape(observed(strcmp({observed.kind},'bs_queue')),1,[])
    if e.tick>=0 && e.tick<actualTick, queues(end+1)=e.fields.pendingRequests; end %#ok<AGROW>
end
k.meanBsQueueLength=mean(queues); k.maxBsQueueLength=maximum(queues);
k.meanUeQueueLength=NaN; k.maxUeQueueLength=NaN; k.ueQueueSamples=0;
if nargin>=9 && ~isempty(queueSamples)
    q=queueSamples(queueSamples(:,1)<actualTick,:);
    k.ueQueueSamples=size(q,1);
    k.meanUeQueueLength=ratio(sum(q(:,2)),cfg.simulation.numUE*size(q,1));
    k.maxUeQueueLength=maximum(q(:,3));
end
if nargin<8, harqJournal=[]; end
k.harq=nbiot.metrics.harqSummary(harqJournal,actualTick);
k.controller=struct('applicable',false,'decisions',NaN,'configurationSwitches',NaN, ...
    'reason','controller-not-implemented');
end

function v=maximum(x)
if isempty(x), v=NaN; else, v=max(x); end
end
function value=ratio(a,b), if b==0, value=NaN; else, value=a/b; end, end
function value=percentile(x,p)
if isempty(x), value=NaN; return; end
x=sort(x); r=1+(numel(x)-1)*p; a=floor(r); b=ceil(r); value=x(a)+(r-a)*(x(b)-x(a));
end
