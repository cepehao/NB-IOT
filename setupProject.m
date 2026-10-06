function root=setupProject()
%SETUPPROJECT Add only public source/examples/configs, never every subfolder.
root=fileparts(mfilename('fullpath'));
addpath(fullfile(root,'src'),fullfile(root,'configs'),fullfile(root,'examples'),fullfile(root,'experiments'));
end
