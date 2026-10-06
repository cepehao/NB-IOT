% === ПРОВЕРКА NB-IoT (LTE Toolbox) ===
% 1. Проверка установки LTE Toolbox
v = ver('lte');
if isempty(v)
    error('LTE Toolbox не найден. NB-IoT недоступен.');
else
    fprintf('LTE Toolbox установлен, версия: %s\n', v.Version);
end

% 2. Проверка наличия ключевых NB-IoT функций
nbiotFunctions = {'lteNPRACH', 'lteNPUSCH', 'lteNPDSCH'};
for i = 1:length(nbiotFunctions)
    if exist(nbiotFunctions{i}, 'file') == 2
        fprintf('Функция %s доступна.\n', nbiotFunctions{i});
    else
        fprintf('Функция %s НЕ найдена.\n', nbiotFunctions{i});
    end
end

% 3. Генерация сигнала NPRACH (физический случайный доступ)
ue = struct();
ue.DuplexMode = 'FDD';                % Режим дуплекса
ue.NNCellID = 1;                      % ID соты
ue.NBULSubcarrierSpacing = '3.75kHz'; % Разнос поднесущих в восходящей линии

chs = struct();
chs.NPRACHFormat = '0';               % Формат преамбулы
chs.Periodicity = 80;                 % Периодичность, мс
chs.SubcarrierOffset = 0;             % Смещение поднесущих
chs.NumSubcarriers = 12;              % Количество поднесущих
chs.NRep = 1;                         % Количество повторений
chs.StartTime = 8;                    % Стартовый подкадр (допустимые: 8,16,32,64,128,256,512,1024)
chs.NInit = 0;                        % Начальное значение для скремблера
chs.NPRACHPower = 0;                  % Мощность в дБм

fprintf('Генерация NPRACH waveform...\n');
[waveform, info] = lteNPRACH(ue, chs);

fprintf('Длина сгенерированного сигнала: %d отсчётов\n', length(waveform));
fprintf('Информация о сигнале (структура info):\n');
disp(info);

% Если есть параметры преамбулы, выведем их отдельно
if isfield(info, 'PreambleParameters')
    fprintf('Параметры преамбулы:\n');
    disp(info.PreambleParameters);
end

% Визуализация спектра сигнала
figure;
plot(20*log10(abs(fft(waveform))));
title('Спектр сгенерированного NB-IoT сигнала (NPRACH)');
xlabel('Частота (отсчёты БПФ)');
ylabel('Мощность, дБ');
grid on;

disp('=== Проверка NB-IoT успешно завершена ===');