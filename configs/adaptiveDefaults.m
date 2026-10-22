function policy=adaptiveDefaults()
%ADAPTIVEDEFAULTS Provisional development-only load thresholds.
% Пояснение (рус.): пороги контроллера по умолчанию. Нагрузка - ML-оценка
% среднего числа UE в процедуре доступа.
% Adaptive-P: нагрузка <=1 -> P=1; <=3 -> 0,75; <=6 -> 0,5; <=10 -> 0,25; иначе 0,1.
% Adaptive-RA/DT: <=1 -> RA/DT 10/90; <=5 -> 20/80; иначе 30/70.
% Внимание: значения временные (status='development-provisional'), только
% для отладки; научные пороги должны подбираться на реальных validation-данных.
policy=struct();
policy.windowTicks=500;
policy.staticAccessProbability=1;
policy.staticRaShare=0.1;
% Initial monotone levels for development tests; tune only on real validation IDs.
policy.accessLoadThresholds=[1 3 6 10];
policy.accessProbabilityLevels=[1 0.75 0.5 0.25 0.1];
policy.raLoadThresholds=[1 5];
policy.raShareLevels=[0.1 0.2 0.3];
policy.maximumLoad=100000;
policy.status='development-provisional';
end
