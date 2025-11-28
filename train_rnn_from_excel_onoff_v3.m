function train_rnn_from_excel_onoff_v3()

clc; clear; close all

fname = 'DATOSFINAL.xlsx';
assert(isfile(fname), 'No se encuentra el archivo: %s', fname);

% ---------- LECTURA ----------
T = readtable(fname, 'VariableNamingRule','preserve');

% Mapea nombres tal cual están en tu archivo
Hum = str2double(strrep(string(T.("Humedad %")) ,",","."));   % %
Ta  = str2double(strrep(string(T.("Temp_Ambiente")),",",".")); % °C
Th  = str2double(strrep(string(T.("Temp_Horno")),",","."));    % °C
Vel = str2double(strrep(string(T.("Velocidad_M/M")),",",".")); % m/min
Esp = str2double(strrep(string(T.("Espesor_mm")),",","."));    % mm

% Limpia
Xraw = [Hum, Esp, Vel, Ta, Th];
mask = all(isfinite(Xraw),2);
Hum = Hum(mask); Esp = Esp(mask); Vel = Vel(mask); Ta = Ta(mask); Th = Th(mask);

% ---------- MV inferida (ON/OFF) ----------
if exist('mv_inferida.mat','file')
    S = load('mv_inferida.mat', 'mv');
    mv = S.mv;
    mv = mv(mask);
else
    mv = infer_mv_min(Th); % función mini abajo
    save('mv_inferida.mat','mv');
end

% ---------- Construye dataset ----------
% Entradas a la RNN (5 features): [u, hum, esp, vel, Ta]
% Salida a predecir: Temperatura del horno (Th)
u   = mv(:);            % 0/1
hum = Hum(:);
esp = Esp(:);
vel = Vel(:);
ta  = Ta(:);
y   = Th(:);

N = min([numel(u), numel(hum), numel(esp), numel(vel), numel(ta), numel(y)]);
u=u(1:N); hum=hum(1:N); esp=esp(1:N); vel=vel(1:N); ta=ta(1:N); y=y(1:N);

X = [u, hum, esp, vel, ta];  % N x 5

% ---------- Normalización (z-score por columna) ----------
muX  = mean(X,1);     sigX = std(X,0,1);   sigX(sigX==0) = 1;
Ymu  = mean(y);       Ysig = std(y);       if Ysig==0, Ysig=1; end

Xn = (X - muX)./sigX;
yn = (y - Ymu)./Ysig;

% ---------- Partición simple (entreno=100%) ----------
Xtr = Xn; Ytr = yn;

% La red se entrenó como "SeriesNetwork" con entrada 3D (features x 1 x batch)
% Prepara tensores 3D
Xtrain = permute(Xtr, [2 3 1]);  % [5 x 1 x N]
Ytrain = permute(Ytr, [2 3 1]);  % [1 x 1 x N]

% ---------- Arquitectura pequeña ----------
layers = [
    imageInputLayer([5 1 1], "Normalization","none")
    fullyConnectedLayer(16)
    reluLayer
    fullyConnectedLayer(8)
    reluLayer
    fullyConnectedLayer(1)
    regressionLayer];

opts = trainingOptions('adam', ...
    'MaxEpochs', 40, ...
    'MiniBatchSize', 256, ...
    'InitialLearnRate', 3e-3, ...
    'Shuffle','every-epoch', ...
    'Plots','training-progress', ...
    'Verbose',false);

net = trainNetwork(Xtrain, Ytrain, layers, opts);

% ---------- Guarda red + normalización ----------
norm.muX  = muX;
norm.sigX = sigX;
norm.Ymu  = Ymu;
norm.Ysig = Ysig;

save('net_horno_rnn.mat','net','norm','-v7.3');

% ---------- Chequeo rápido (misma serie) ----------
Yhat_n = predict(net, Xtrain);
Yhat   = Yhat_n * Ysig + Ymu;

figure('Name','Chequeo entrenamiento (misma serie)');
plot(y, 'b'); hold on
plot(Yhat(:),'r','LineWidth',1.2)
title('Chequeo entrenamiento (misma serie)')
legend('Temp medida','RNN predicha'); grid on

disp('Listo: net_horno_rnn.mat guardado con net y norm (muX/sigX/Ymu/Ysig).')

end

% ========= Helper super simple para MV ON/OFF =========
function mv = infer_mv_min(Th)
Th = Th(:);
Thf = movmedian(Th, 7);
dT  = [0; diff(Thf)];
thr_on  =  +0.008;
thr_off =  -0.004;

mv = zeros(size(Th));
state = 0;
for k = 2:numel(Th)
    if dT(k) > thr_on
        state = 1;
    elseif dT(k) < thr_off
        state = 0;
    end
    mv(k) = state;
end
end
