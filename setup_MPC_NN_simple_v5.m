%% setup_mpc_nn_v3.m  —  MPC + NN  (Ts = 1 s)

clearvars -except nn_horno_predict net net_horno_rnn
clc

%% Parámetros básicos
Ts   = 1;            % tiempo de muestreo [s]
SP_C = 200;          % setpoint típico (para calibrar BIAS_NN)
hum0 = 50; esp0 = 25.4; vel0 = 25; dTamb0 = 0;  % condiciones nominales

%% Planta de DISEÑO (tu transferencia en lazo directo, signo negativo)
Gs_c = tf(-2.028e-4, [1 0.02251 5.11e-05], 'inputname','u', 'outputname','y');
Gz   = c2d(Gs_c, Ts, 'zoh');
Kdc  = dcgain(Gz);                        % ≈ -3.9687

% Escalado para que MV=1 ⇒ y≈220 °C (ganancia "objetivo")
Kmv   = 220 / Kdc;                        % incluye signo
Gz_es = series(tf(Kmv,1,Ts), Gz);
fprintf('Kdc (discreto) = %.4f | Kmv aplicado = %.4f\n', Kdc, Kmv);

% Espacio de estados y ampliación a 1 MV + 4 MD
Pss = ss(Gz_es);
A = Pss.A; B = Pss.B; C = Pss.C; D = Pss.D;
Amd  = A;
Bm   = B;                          % columna MV
Bmd  = zeros(size(B,1),4);         % 4 MD
B_all = [Bm Bmd];
Cmd  = C;
D_all = zeros(size(C,1),1+4);

plant = ss(Amd, B_all, Cmd, D_all, Ts, ...
  'inputname',{'mv','hum','esp','vel','dTamb'}, 'outputname','y');
plant = setmpcsignals(plant,'MV',1,'MD',2:5);

fprintf('dcgain(plant(:,1)) [MV->y] ≈ %.1f °C/pu\n', dcgain(plant(:,1)));

%% MPC (horizontes y pesos)
Np = 18; Nc = 6;
mpcobj_nn = mpc(plant, Ts, Np, Nc);

% Límites de MV (agresivo). Recuerda: EN SIMULINK u = 1 - MV
mpcobj_nn.MV.Min     = 0;
mpcobj_nn.MV.Max     = 1.8;     % puedes subir/bajar según hardware
mpcobj_nn.MV.RateMin = -0.8;
mpcobj_nn.MV.RateMax =  0.8;

% Pesos (puedes afinar)
mpcobj_nn.Weights.OutputVariables          = 1.5;
mpcobj_nn.Weights.ManipulatedVariables     = 0;
mpcobj_nn.Weights.ManipulatedVariablesRate = 0.02;

% Integrador en la salida (tracking sin error estacionario)
setoutdist(mpcobj_nn,'model', tf(1,[1 0],Ts));
disp('Offset-free tracking ACTIVADO (integrador en salida).');

%% Calibración BIAS_NN (para que con u=1 estemos en SP_C)
% IMPORTANTE: u que usa la NN es EN PU [0..1], no pases fuera de rango.
try
    y_nom   = nn_horno_predict([1, hum0, esp0, vel0, dTamb0]);  % u=1
    BIAS_NN = SP_C - y_nom;
catch
    warning('No pude llamar a nn_horno_predict. Uso BIAS_NN=0.');
    BIAS_NN = 0;
end
fprintf('BIAS_NN = %.3f °C (y_nom con u=1 fue %.3f °C)\n', BIAS_NN, SP_C-BIAS_NN);

%% Señales de prueba opcionales (timeseries, Ts=1)
Tf = 4000; t = (0:Tf).';
sp    = timeseries(SP_C*ones(numel(t),1), t);
hum   = timeseries(hum0*ones(numel(t),1), t);
esp   = timeseries(esp0*ones(numel(t),1), t);
vel   = timeseries(vel0*ones(numel(t),1), t);
dTamb = timeseries(filter(1,[1 -0.995], 0.5*randn(numel(t),1)), t);

%% Exportar al workspace (Simulink)
assignin('base','Ts',Ts);
assignin('base','Amd',Amd);
assignin('base','B_all',B_all);
assignin('base','Cmd',Cmd);
assignin('base','D_all',D_all);
assignin('base','mpcobj_nn',mpcobj_nn);
assignin('base','BIAS_NN',BIAS_NN);

assignin('base','sp',sp);
assignin('base','hum_ts',hum);
assignin('base','esp_ts',esp);
assignin('base','vel_ts',vel);
assignin('base','ta_ts',dTamb);

disp('--- Listo: usa "mpcobj_nn" en el bloque MPC. ---');
disp('--- En Simulink: u = 1 - MV  → Saturation [0..1] → NN_PLANT.u ---');
disp('--- y_cal = y_raw + BIAS_NN  → UnitDelay(Ts=1) → mo del MPC. ---');
