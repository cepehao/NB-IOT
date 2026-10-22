function root=setupProject()
%SETUPPROJECT Add explicit project folders and the shared test fixture helpers.
% Пояснение (рус.): добавить в путь MATLAB папки src, configs, examples,
% experiments и tests/helpers. Вызывается перед любой работой с проектом.
root=fileparts(mfilename('fullpath'));
addpath(fullfile(root,'src'),fullfile(root,'configs'),fullfile(root,'examples'), ...
    fullfile(root,'experiments'),fullfile(root,'tests','helpers'));
end
