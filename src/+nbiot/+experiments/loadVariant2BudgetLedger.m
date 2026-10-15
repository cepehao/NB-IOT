function ledger=loadVariant2BudgetLedger(path,createIfMissing)
%LOADVARIANT2BUDGETLEDGER Read or initialize the shared Stage 2/Stage 3 budget.
if nargin<2, createIfMissing=false; end
if ~(ischar(path)||(isstring(path)&&isscalar(path)))|| ...
        isempty(char(path))||~(islogical(createIfMissing)&&isscalar(createIfMissing))
    error('nbiot:experiments:Variant2BudgetLedger','Invalid budget-ledger path or create flag.');
end
path=char(path);
if ~isfile(path)
    if ~createIfMissing
        error('nbiot:experiments:Variant2BudgetLedger', ...
            'The shared 57600-second compute ledger is missing: %s',path);
    end
    ledger=struct('schemaVersion',1,'budgetSeconds',57600,'elapsedSeconds',0, ...
        'startedAtUtc',utcNow(),'updatedAtUtc',utcNow(), ...
        'phaseTimes',struct('phase',{},'startedAtUtc',{},'finishedAtUtc',{}, ...
            'elapsedSeconds',{},'caseKey',{}), ...
        'warnings',struct('timestampUtc',{},'phase',{},'elapsedSeconds',{},'message',{}), ...
        'pendingCases',[],'activeCase',struct());
    nbiot.experiments.saveVariant2BudgetLedger(path,ledger);
    return
end
try
    ledger=jsondecode(fileread(path));
catch exception
    error('nbiot:experiments:Variant2BudgetLedger', ...
        'Cannot read the shared compute ledger: %s',exception.message);
end
required={'schemaVersion','budgetSeconds','elapsedSeconds','startedAtUtc', ...
    'updatedAtUtc','phaseTimes','warnings','pendingCases','activeCase'};
if ~isstruct(ledger)||~isscalar(ledger)||~all(isfield(ledger,required))|| ...
        ledger.schemaVersion~=1||ledger.budgetSeconds~=57600|| ...
        ~isnumeric(ledger.elapsedSeconds)||~isscalar(ledger.elapsedSeconds)|| ...
        ~isfinite(ledger.elapsedSeconds)||ledger.elapsedSeconds<0
    error('nbiot:experiments:Variant2BudgetLedger', ...
        'Shared compute ledger schema or elapsed budget is invalid.');
end
if isempty(ledger.phaseTimes)
    ledger.phaseTimes=struct('phase',{},'startedAtUtc',{},'finishedAtUtc',{}, ...
        'elapsedSeconds',{},'caseKey',{});
end
if isempty(ledger.warnings)
    ledger.warnings=struct('timestampUtc',{},'phase',{},'elapsedSeconds',{},'message',{});
end
if isempty(ledger.activeCase)
    ledger.activeCase=struct('caseKey','','numUE',0,'startedAtUtc','', ...
        'lastProgressAtUtc','','runFolder','');
end
end

function value=utcNow()
value=char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd HH:mm:ss.SSS'));
end
