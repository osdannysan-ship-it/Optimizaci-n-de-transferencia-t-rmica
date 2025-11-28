function y = nn_horno_predict(phi)
% =========================================================================
% nn_horno_predict(phi)
% Si no se pasa argumento, usa valores por defecto para probar el modelo.
% Devuelve la temperatura predicha (°C)
% =========================================================================

persistent NET MU SIGMA MUy SIGy

% --- CARGA UNA SOLA VEZ ---
if isempty(NET)
    S = load('net_horno_rnn.mat');
    NET  = S.net;
    MU    = S.norm.muX(:);     % vector 5x1
    SIGMA = S.norm.sigX(:);
    MUy   = S.norm.Ymu;
    SIGy  = S.norm.Ysig;
end

% --- Si no se pasa entrada, usa valores de prueba ---
if nargin == 0
    phi = [1; 50; 25.4; 25; 0];   % [u, Hum, Esp, Vel, Ta]
    disp('⚙️  No se pasó argumento, usando vector de prueba.');
end

% --- Asegura vector columna 5x1 ---
phi = double(phi(:));

% --- Normaliza entradas ---
x = (phi - MU) ./ SIGMA;

% --- Predice con la red neuronal ---
y_norm = predict(NET, {x});
y_norm = double(cell2mat(y_norm));   % ✅ Convierte celda a número

% --- Desnormaliza salida ---
y = y_norm * SIGy + MUy;

% --- Muestra resultado si fue llamada sin argumentos ---
if nargin == 0
    fprintf('Predicción NN: %.2f °C\n', y);
end

end
