function diagnostics=radioDiagnostics(truthEvents,observedEvents,receptionEvents,options)
%RADIODIAGNOSTICS Compare post-reception observations with simulation truth.
% Truth is joined only after the detector/receiver has produced its result.
validateEvents(truthEvents,'truthEvents');
validateEvents(observedEvents,'observedEvents');
validateEvents(receptionEvents,'receptionEvents');
if ~isstruct(options)||~isscalar(options)|| ...
        ~all(isfield(options,{'actualTick','nInitValues'}))
    error('nbiot:metrics:RadioDiagnosticsOptions', ...
        'Options require actualTick and nInitValues.');
end
validateattributes(options.actualTick,{'numeric'}, ...
    {'scalar','real','finite','integer','nonnegative'});
validateattributes(options.nInitValues,{'numeric'}, ...
    {'vector','real','finite','integer','nonnegative','nonempty'});
nInitValues=double(options.nInitValues(:));
if numel(unique(nInitValues))~=numel(nInitValues)
    error('nbiot:metrics:RadioDiagnosticsOptions', ...
        'nInitValues must contain unique preamble indices.');
end
horizon=double(options.actualTick);

% A detection event also records empty decisions, so it defines one complete
% occasion. The decision at H is complete; decisions after H are censored.
completeOccasions=zeros(0,1);
candidateRows=zeros(0,2);
candidateEstimates=repmat(candidateTemplate(),0,1);
for k=1:numel(observedEvents)
    e=observedEvents(k);
    if ~strcmp(e.kind,'nprach_detection')||e.tick<0||e.tick>horizon, continue; end
    f=e.fields;
    requireFields(f,{'occasionId','candidates'},'nprach_detection');
    readyTick=double(e.tick);
    if isfield(f,'readyTick'), readyTick=double(f.readyTick); end
    if ~isscalar(readyTick)||~isfinite(readyTick)||readyTick>horizon, continue; end
    occasionId=validInteger(f.occasionId,'occasionId',0);
    completeOccasions(end+1,1)=occasionId; %#ok<AGROW>
    candidates=f.candidates;
    if ~isstruct(candidates)
        error('nbiot:metrics:RadioDiagnosticsEvent', ...
            'NPRACH candidates must be a struct array.');
    end
    for j=1:numel(candidates)
        requireFields(candidates(j),{'nInit','delaySeconds','cfoHz'},'NPRACH candidate');
        nInit=validInteger(candidates(j).nInit,'nInit',0);
        if ~ismember(nInit,nInitValues)
            error('nbiot:metrics:RadioDiagnosticsEvent', ...
                'An NPRACH candidate has an unconfigured preamble index.');
        end
        candidateRows(end+1,:)=[occasionId nInit]; %#ok<AGROW>
        candidateEstimates(end+1)=struct('occasionId',occasionId,'nInit',nInit, ...
            'estimatedDelaySeconds',finiteOrNaN(candidates(j).delaySeconds), ...
            'estimatedCfoHz',finiteOrNaN(candidates(j).cfoHz)); %#ok<AGROW>
    end
end
completeOccasions=unique(completeOccasions);
if size(unique(candidateRows,'rows'),1)~=size(candidateRows,1)
    error('nbiot:metrics:RadioDiagnosticsEvent', ...
        'The receiver logged a duplicate candidate for one occasion and preamble.');
end

% Truth attempts are included only when their NPRACH occasion was fully
% observed. One truth key is one transmitted preamble index, not one UE.
attempts=repmat(attemptTemplate(),0,1);
for k=1:numel(truthEvents)
    e=truthEvents(k);
    if ~strcmp(e.kind,'msg1')||e.tick<0||e.tick>=horizon, continue; end
    f=e.fields; requireFields(f,{'attemptId','ueId','occasionId','nInit'},'msg1');
    occasionId=validInteger(f.occasionId,'occasionId',0);
    if ~ismember(occasionId,completeOccasions), continue; end
    attemptId=validInteger(f.attemptId,'attemptId',1);
    ueId=validInteger(f.ueId,'ueId',1);
    nInit=validInteger(f.nInit,'nInit',0);
    if ~ismember(nInit,nInitValues)
        error('nbiot:metrics:RadioDiagnosticsEvent', ...
            'A transmitted preamble index is outside nInitValues.');
    end
    attempts(end+1)=struct('attemptId',attemptId,'ueId',ueId, ...
        'occasionId',occasionId,'nInit',nInit); %#ok<AGROW>
end
if numel(unique([attempts.attemptId]))~=numel(attempts)
    error('nbiot:metrics:RadioDiagnosticsEvent', ...
        'A truth attempt ID must be unique.');
end
trueKeys=zeros(0,2);
if ~isempty(attempts), trueKeys=unique([[attempts.occasionId].',[attempts.nInit].'],'rows'); end
detectedKeys=unique(candidateRows,'rows');
detectedTrueMask=ismember(trueKeys,detectedKeys,'rows');
falseAlarmMask=~ismember(detectedKeys,trueKeys,'rows');
misses=sum(~detectedTrueMask);
falseAlarms=sum(falseAlarmMask);
falseAlarmOpportunities=numel(completeOccasions)*numel(nInitValues)-size(trueKeys,1);
diagnostics=struct();
diagnostics.available=~isempty(completeOccasions);
diagnostics.actualTick=horizon;
diagnostics.preamble=struct( ...
    'transmittedAttempts',numel(attempts), ...
    'transmittedKeys',size(trueKeys,1), ...
    'detectedCandidates',size(candidateRows,1), ...
    'detectedKeys',sum(detectedTrueMask), ...
    'misses',misses, ...
    'falseAlarms',falseAlarms, ...
    'falseAlarmOpportunities',falseAlarmOpportunities, ...
    'detectionProbability',ratio(sum(detectedTrueMask),size(trueKeys,1)), ...
    'missProbability',ratio(misses,size(trueKeys,1)), ...
    'falseAlarmProbability',ratio(falseAlarms,falseAlarmOpportunities));

% Logical collision is a shared preamble choice. It does not imply that the
% received signal intervals actually overlap.
logicalCounts=zeros(0,1);
if ~isempty(attempts)
    attemptKeys=[[attempts.occasionId].',[attempts.nInit].'];
    [~,~,keyGroup]=unique(attemptKeys,'rows');
    logicalCounts=accumarray(keyGroup,1);
end
logicalGroups=sum(logicalCounts>1);
logicalAttempts=sum(logicalCounts(logicalCounts>1));

components=repmat(componentTemplate(),0,1);
for k=1:numel(receptionEvents)
    e=receptionEvents(k);
    if ~strcmp(e.kind,'nprach_component')||e.tick<0||e.tick>horizon, continue; end
    f=e.fields;
    componentFields={'occasionId','attemptId','ueId','nInit','startSample', ...
        'endSampleExclusive','signalPowerW','interferencePowerW','noisePowerW', ...
        'configuredDelaySeconds','configuredCfoHz'};
    requireFields(f,componentFields,'nprach_component');
    occasionId=validInteger(f.occasionId,'occasionId',0);
    if ~ismember(occasionId,completeOccasions), continue; end
    attemptId=validInteger(f.attemptId,'attemptId',1);
    if ~any([attempts.attemptId]==attemptId), continue; end
    startSample=validInteger(f.startSample,'startSample',0);
    endSample=validInteger(f.endSampleExclusive,'endSampleExclusive',1);
    if endSample<=startSample
        error('nbiot:metrics:RadioDiagnosticsEvent', ...
            'Received signal support must be a nonempty half-open interval.');
    end
    components(end+1)=struct('occasionId',occasionId,'attemptId',attemptId, ...
        'ueId',validInteger(f.ueId,'ueId',1), ...
        'nInit',validInteger(f.nInit,'nInit',0), ...
        'startSample',startSample,'endSampleExclusive',endSample, ...
        'signalPowerW',nonnegativeFinite(f.signalPowerW,'signalPowerW'), ...
        'interferencePowerW',nonnegativeFinite(f.interferencePowerW,'interferencePowerW'), ...
        'noisePowerW',nonnegativeFinite(f.noisePowerW,'noisePowerW'), ...
        'configuredDelaySeconds',finiteOrNaN(f.configuredDelaySeconds), ...
        'configuredCfoHz',finiteOrNaN(f.configuredCfoHz)); %#ok<AGROW>
end
if numel(unique([components.attemptId]))~=numel(components)
    error('nbiot:metrics:RadioDiagnosticsEvent', ...
        'One NPRACH attempt must have one receiver-component summary.');
end

overlaps=repmat(overlapTemplate(),0,1);
for k=1:numel(receptionEvents)
    e=receptionEvents(k);
    if ~strcmp(e.kind,'nprach_overlap')||e.tick<0||e.tick>horizon, continue; end
    f=e.fields;
    overlapFields={'occasionId','attemptIdA','attemptIdB','startSample', ...
        'endSampleExclusive','signalPowerAW','signalPowerBW'};
    requireFields(f,overlapFields,'nprach_overlap');
    occasionId=validInteger(f.occasionId,'occasionId',0);
    attemptIdA=validInteger(f.attemptIdA,'attemptIdA',1);
    attemptIdB=validInteger(f.attemptIdB,'attemptIdB',1);
    if attemptIdA==attemptIdB
        error('nbiot:metrics:RadioDiagnosticsEvent', ...
            'A physical overlap requires two distinct NPRACH attempts.');
    end
    ia=find([components.attemptId]==attemptIdA,1);
    ib=find([components.attemptId]==attemptIdB,1);
    if isempty(ia)||isempty(ib)||components(ia).occasionId~=occasionId|| ...
            components(ib).occasionId~=occasionId
        error('nbiot:metrics:RadioDiagnosticsEvent', ...
            'An overlap event must refer to two logged components in its occasion.');
    end
    startSample=validInteger(f.startSample,'startSample',0);
    endSample=validInteger(f.endSampleExclusive,'endSampleExclusive',1);
    expectedStart=max(components(ia).startSample,components(ib).startSample);
    expectedEnd=min(components(ia).endSampleExclusive,components(ib).endSampleExclusive);
    if endSample<=startSample||startSample~=expectedStart||endSample~=expectedEnd
        error('nbiot:metrics:RadioDiagnosticsEvent', ...
            'An overlap event must describe the exact shared half-open interval.');
    end
    pair=sort([attemptIdA attemptIdB]);
    if ~isempty(overlaps)&&any(arrayfun(@(x)isequal(sort([x.attemptIdA x.attemptIdB]),pair),overlaps))
        error('nbiot:metrics:RadioDiagnosticsEvent','A physical overlap pair was logged twice.');
    end
    overlaps(end+1)=struct('occasionId',occasionId,'attemptIdA',attemptIdA, ...
        'attemptIdB',attemptIdB,'startSample',startSample, ...
        'endSampleExclusive',endSample, ...
        'signalPowerAW',nonnegativeFinite(f.signalPowerAW,'signalPowerAW'), ...
        'signalPowerBW',nonnegativeFinite(f.signalPowerBW,'signalPowerBW')); %#ok<AGROW>
end

expectedPairs=zeros(0,2);
for i=1:numel(components)-1
    a=components(i);
    for j=i+1:numel(components)
        b=components(j);
        if a.occasionId==b.occasionId&& ...
                max(a.startSample,b.startSample)<min(a.endSampleExclusive,b.endSampleExclusive)
            expectedPairs(end+1,:)=sort([a.attemptId b.attemptId]); %#ok<AGROW>
        end
    end
end
loggedPairs=zeros(numel(overlaps),2);
for k=1:numel(overlaps), loggedPairs(k,:)=sort([overlaps(k).attemptIdA overlaps(k).attemptIdB]); end
if size(unique(expectedPairs,'rows'),1)~=size(unique(loggedPairs,'rows'),1)|| ...
        ~isempty(setxorRows(expectedPairs,loggedPairs))
    error('nbiot:metrics:RadioDiagnosticsEvent', ...
        'Physical overlap events must cover every and only overlapping component pair.');
end

physicalPairs=loggedPairs;
physicalAttemptIds=zeros(0,1);
if ~isempty(overlaps)
    physicalAttemptIds=[ [overlaps.attemptIdA].' ; [overlaps.attemptIdB].' ];
end
eligiblePairs=0; censoredPairs=0; equalPowerPairs=0;
capturedPairs=0; strongSuccesses=0; weakSuccesses=0;
outcomeIds=zeros(0,1); outcomes=strings(0,1);
for k=1:numel(truthEvents)
    e=truthEvents(k);
    if e.tick<0||e.tick>horizon||~any(strcmp(e.kind,{'ra_success','ra_failure'})), continue; end
    requireFields(e.fields,{'attemptId'},e.kind);
    id=validInteger(e.fields.attemptId,'attemptId',1);
    outcome="success"; if strcmp(e.kind,'ra_failure'), outcome="failure"; end
    at=find(outcomeIds==id,1);
    if isempty(at), outcomeIds(end+1,1)=id; outcomes(end+1,1)=outcome; %#ok<AGROW>
    elseif outcomes(at)~=outcome
        error('nbiot:metrics:RadioDiagnosticsEvent', ...
            'An NPRACH attempt cannot both succeed and fail.');
    end
end
for k=1:numel(overlaps)
    pair=overlaps(k);
    deltaDb=powerDifferenceDb(pair.signalPowerAW,pair.signalPowerBW);
    if isnan(deltaDb)||abs(deltaDb)<=1e-9
        equalPowerPairs=equalPowerPairs+1;
        continue;
    end
    outcomeA=outcomeFor(pair.attemptIdA,outcomeIds,outcomes);
    outcomeB=outcomeFor(pair.attemptIdB,outcomeIds,outcomes);
    if outcomeA=="unknown"||outcomeB=="unknown"
        censoredPairs=censoredPairs+1;
        continue;
    end
    eligiblePairs=eligiblePairs+1;
    strongerSuccess=false; weakerSuccess=false;
    if deltaDb>0
        strongerSuccess=outcomeA=="success"; weakerSuccess=outcomeB=="success";
    else
        strongerSuccess=outcomeB=="success"; weakerSuccess=outcomeA=="success";
    end
    strongSuccesses=strongSuccesses+double(strongerSuccess);
    weakSuccesses=weakSuccesses+double(weakerSuccess);
    capturedPairs=capturedPairs+double(strongerSuccess&&~weakerSuccess);
end
physicalAttemptIds=unique(physicalAttemptIds);
diagnostics.collision=struct( ...
    'attempts',numel(attempts), ...
    'logicalGroups',logicalGroups, ...
    'logicalAttempts',logicalAttempts, ...
    'logicalAttemptProbability',ratio(logicalAttempts,numel(attempts)), ...
    'physicalOverlapPairs',size(physicalPairs,1), ...
    'physicalAttempts',numel(physicalAttemptIds), ...
    'physicalAttemptProbability',ratio(numel(physicalAttemptIds),numel(attempts)));
diagnostics.capture=struct( ...
    'eligiblePairs',eligiblePairs, ...
    'censoredPairs',censoredPairs, ...
    'equalPowerPairs',equalPowerPairs, ...
    'capturedPairs',capturedPairs, ...
    'probability',ratio(capturedPairs,eligiblePairs), ...
    'strongSuccessProbability',ratio(strongSuccesses,eligiblePairs), ...
    'weakSuccessProbability',ratio(weakSuccesses,eligiblePairs));

perAttempt=repmat(perAttemptTemplate(),0,1);
for k=1:numel(components)
    c=components(k);
    denominator=c.interferencePowerW+c.noisePowerW;
    sinrDb=NaN;
    if c.signalPowerW>0&&denominator>0
        sinrDb=10*log10(c.signalPowerW/denominator);
    end
    perAttempt(end+1)=struct('occasionId',c.occasionId,'attemptId',c.attemptId, ...
        'ueId',c.ueId,'nInit',c.nInit,'receivedPowerW',c.signalPowerW, ...
        'interferencePowerW',c.interferencePowerW,'noisePowerW',c.noisePowerW, ...
        'sinrDb',sinrDb,'provenance','diagnosticTruth'); %#ok<AGROW>
end
diagnostics.perAttempt=perAttempt;

estimates=repmat(receiverEstimateTemplate(),0,1);
for k=1:numel(candidateEstimates)
    c=candidateEstimates(k);
    matching=attempts([attempts.occasionId]==c.occasionId & [attempts.nInit]==c.nInit);
    configuredDelay=NaN; configuredCfo=NaN; attemptId=NaN; ueId=NaN; truthAvailable=false;
    if numel(matching)==1
        attemptId=matching.attemptId; ueId=matching.ueId;
        componentIndex=find([components.attemptId]==matching.attemptId,1);
        if ~isempty(componentIndex)
            configuredDelay=components(componentIndex).configuredDelaySeconds;
            configuredCfo=components(componentIndex).configuredCfoHz;
            truthAvailable=isfinite(configuredDelay)&&isfinite(configuredCfo);
        end
    end
    delayError=NaN; cfoError=NaN;
    if truthAvailable&&isfinite(c.estimatedDelaySeconds)
        delayError=c.estimatedDelaySeconds-configuredDelay;
    end
    if truthAvailable&&isfinite(c.estimatedCfoHz)
        cfoError=c.estimatedCfoHz-configuredCfo;
    end
    estimates(end+1)=struct('occasionId',c.occasionId,'nInit',c.nInit, ...
        'attemptId',attemptId,'ueId',ueId, ...
        'estimatedDelaySeconds',c.estimatedDelaySeconds, ...
        'configuredDelaySeconds',configuredDelay,'delayErrorSeconds',delayError, ...
        'estimatedCfoHz',c.estimatedCfoHz,'configuredCfoHz',configuredCfo, ...
        'cfoErrorHz',cfoError,'truthAvailable',truthAvailable); %#ok<AGROW>
end
diagnostics.receiverEstimates=estimates;

npuschEstimates=repmat(npuschEstimateTemplate(),0,1);
for k=1:numel(receptionEvents)
    e=receptionEvents(k);
    if ~strcmp(e.kind,'npusch_receiver')||e.tick<0||e.tick>horizon, continue; end
    f=e.fields;
    requireFields(f,{'contextId','occasionId','nInit','channel', ...
        'estimatedDelaySeconds','estimatedCfoHz','configuredDelaySeconds', ...
        'configuredCfoHz','noiseEstimate'},'npusch_receiver');
    attemptId=NaN; ueId=NaN;
    if isfield(f,'attemptId'), attemptId=finiteOrNaN(f.attemptId); end
    if isfield(f,'ueId'), ueId=finiteOrNaN(f.ueId); end
    estimatedDelay=finiteOrNaN(f.estimatedDelaySeconds);
    estimatedCfo=finiteOrNaN(f.estimatedCfoHz);
    truthDelay=finiteOrNaN(f.configuredDelaySeconds);
    truthCfo=finiteOrNaN(f.configuredCfoHz);
    delayError=NaN; cfoError=NaN;
    if isfinite(estimatedDelay)&&isfinite(truthDelay), delayError=estimatedDelay-truthDelay; end
    if isfinite(estimatedCfo)&&isfinite(truthCfo), cfoError=estimatedCfo-truthCfo; end
    npuschEstimates(end+1)=struct( ...
        'contextId',validInteger(f.contextId,'contextId',1), ...
        'occasionId',validInteger(f.occasionId,'occasionId',0), ...
        'nInit',validInteger(f.nInit,'nInit',0), ...
        'attemptId',attemptId,'ueId',ueId, ...
        'channel',char(string(f.channel)), ...
        'estimatedDelaySeconds',estimatedDelay, ...
        'configuredDelaySeconds',truthDelay, ...
        'delayErrorSeconds',delayError, ...
        'estimatedCfoHz',estimatedCfo, ...
        'configuredCfoHz',truthCfo, ...
        'cfoErrorHz',cfoError, ...
        'noiseEstimate',nonnegativeFinite(f.noiseEstimate,'noiseEstimate'), ...
        'truthAvailable',isfinite(truthDelay)&&isfinite(truthCfo)); %#ok<AGROW>
end
diagnostics.npuschReceiverEstimates=npuschEstimates;
end

function validateEvents(events,name)
if ~isstruct(events)||~all(isfield(events,{'tick','kind','fields'}))
    error('nbiot:metrics:RadioDiagnosticsEvent','%s must be an EventLog struct array.',name);
end
for k=1:numel(events)
    if ~isnumeric(events(k).tick)||~isreal(events(k).tick)|| ...
            ~isscalar(events(k).tick)||~isfinite(events(k).tick)|| ...
            events(k).tick<0||~ischar(events(k).kind)||~isscalar(events(k).fields)|| ...
            ~isstruct(events(k).fields)
        error('nbiot:metrics:RadioDiagnosticsEvent','%s contains a malformed event.',name);
    end
end
end

function requireFields(s,names,label)
if ~isstruct(s)||~isscalar(s)||~all(isfield(s,names))
    error('nbiot:metrics:RadioDiagnosticsEvent','%s is missing required fields.',label);
end
end

function value=validInteger(value,name,minimum)
if ~isnumeric(value)||~isreal(value)||~isscalar(value)||~isfinite(value)|| ...
        value~=fix(value)||value<minimum
    error('nbiot:metrics:RadioDiagnosticsEvent','%s must be a valid integer.',name);
end
value=double(value);
end

function value=nonnegativeFinite(value,name)
if ~isnumeric(value)||~isreal(value)||~isscalar(value)||~isfinite(value)||value<0
    error('nbiot:metrics:RadioDiagnosticsEvent','%s must be finite and nonnegative.',name);
end
value=double(value);
end

function value=finiteOrNaN(value)
if ~isnumeric(value)||~isreal(value)||~isscalar(value)||isinf(value), value=NaN;
else, value=double(value); end
end

function value=ratio(numerator,denominator)
if denominator==0, value=NaN; else, value=numerator/denominator; end
end

function delta=powerDifferenceDb(first,second)
delta=NaN;
if first>0&&second>0, delta=10*log10(first/second);
elseif first>0, delta=Inf;
elseif second>0, delta=-Inf;
end
end

function outcome=outcomeFor(attemptId,ids,outcomes)
index=find(ids==attemptId,1);
if isempty(index), outcome="unknown"; else, outcome=outcomes(index); end
end

function rows=setxorRows(first,second)
if isempty(first), rows=unique(second,'rows'); return; end
if isempty(second), rows=unique(first,'rows'); return; end
rows=[setdiff(first,second,'rows');setdiff(second,first,'rows')];
rows=unique(rows,'rows');
end

function c=attemptTemplate()
c=struct('attemptId',0,'ueId',0,'occasionId',0,'nInit',0);
end

function c=candidateTemplate()
c=struct('occasionId',0,'nInit',0,'estimatedDelaySeconds',NaN,'estimatedCfoHz',NaN);
end

function c=componentTemplate()
c=struct('occasionId',0,'attemptId',0,'ueId',0,'nInit',0, ...
    'startSample',0,'endSampleExclusive',0,'signalPowerW',0, ...
    'interferencePowerW',0,'noisePowerW',0, ...
    'configuredDelaySeconds',NaN,'configuredCfoHz',NaN);
end

function c=perAttemptTemplate()
c=struct('occasionId',0,'attemptId',0,'ueId',0,'nInit',0, ...
    'receivedPowerW',NaN,'interferencePowerW',NaN,'noisePowerW',NaN, ...
    'sinrDb',NaN,'provenance','diagnosticTruth');
end

function c=receiverEstimateTemplate()
c=struct('occasionId',0,'nInit',0,'attemptId',NaN,'ueId',NaN, ...
    'estimatedDelaySeconds',NaN, ...
    'configuredDelaySeconds',NaN,'delayErrorSeconds',NaN, ...
    'estimatedCfoHz',NaN,'configuredCfoHz',NaN,'cfoErrorHz',NaN, ...
    'truthAvailable',false);
end

function c=overlapTemplate()
c=struct('occasionId',0,'attemptIdA',0,'attemptIdB',0, ...
    'startSample',0,'endSampleExclusive',0,'signalPowerAW',0,'signalPowerBW',0);
end

function c=npuschEstimateTemplate()
c=struct('contextId',0,'occasionId',0,'nInit',0,'attemptId',NaN,'ueId',NaN,'channel','', ...
    'estimatedDelaySeconds',NaN,'configuredDelaySeconds',NaN, ...
    'delayErrorSeconds',NaN,'estimatedCfoHz',NaN,'configuredCfoHz',NaN, ...
    'cfoErrorHz',NaN,'noiseEstimate',NaN,'truthAvailable',false);
end
