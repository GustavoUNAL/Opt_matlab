
clear; clc;

% ---------- RUTAS RELATIVAS ----------
scriptDir  = fileparts(mfilename('fullpath'));              % carpeta del script
dataDir    = fullfile(scriptDir,'..','data');               % ../data
jsonFile   = fullfile(dataDir,'processed',...
                       'independent_relay_pairs_scenario_base_optimized.json');

resultsDir = fullfile(scriptDir,'..','test','results');     % ../test/results
if ~exist(resultsDir,'dir'), mkdir(resultsDir); end

% ---------- Parámetros ----------
CTI         = 0.20;               % Coordination Time Interval (s)
K           = 0.14;  N = 0.02;    % IEC Inverse Normal
pairsToPlot = 5;                  % Nº de pares graficados
tol         = 1e-4;               % tolerancia validación Time_out

% ---------- Cargar ----------
data = jsondecode(fileread(jsonFile));
n    = numel(data);

% ---------- Variables para la tabla resumen ----------
mainIDs = strings(n,1);  backIDs = strings(n,1);
delta_t = zeros(n,1);     isCoord = false(n,1);

% ---------- Loop principal ----------
for k = 1:n
    % Main relay
    Im  = data(k).main_relay.Ishc;
    Ip  = data(k).main_relay.pick_up;
    TDSm= data(k).main_relay.TDS;
    t_m = K*TDSm/((Im/Ip)^N - 1);

    % Backup relay
    Ib  = data(k).backup_relay.Ishc;
    Ipb = data(k).backup_relay.pick_up;
    TDSb= data(k).backup_relay.TDS;
    t_b = K*TDSb/((Ib/Ipb)^N - 1);

    % Coordinación
    delta_t(k) = t_b - t_m;
    isCoord(k) = delta_t(k) >= CTI;

    % IDs
    mainIDs(k) = data(k).main_relay.relay;
    backIDs(k) = data(k).backup_relay.relay;

    % -------- Graficar algunos pares --------
    if k <= pairsToPlot
        f = figure('Visible','off'); hold on;

        % rango de corrientes
        Imin = min([Ip Ipb])*1.01;
        Imax = max([Im Ib])*1.2;
        Ivec = logspace(log10(Imin),log10(Imax),200);

        % Curvas TCC
        Tm = K*TDSm./((Ivec/Ip).^N - 1);
        Tb = K*TDSb./((Ivec/Ipb).^N - 1);

        plot(Tm,Ivec,'b','LineWidth',1.4);
        plot(Tb,Ivec,'r','LineWidth',1.4);
        plot(t_m,Im,'ob','MarkerFaceColor','b');
        plot(t_b,Ib,'or','MarkerFaceColor','r');
        xline(t_m,'b--'); xline(t_b,'r--');

        set(gca,'XScale','log','YScale','log');
        xlabel('Tiempo de operación (s)');
        ylabel('Corriente (A)');
        status = "Descoordinado"; if isCoord(k), status="Coordinado"; end
        title(sprintf('Par %d – Main: %s | Backup: %s | %s',...
              k, mainIDs(k), backIDs(k), status));
        legend({'Main TCC','Backup TCC','Pto op main','Pto op back'},...
               'Location','best'); grid on; axis tight;

        % ---- Guardar figura ----
        saveas(f, fullfile(resultsDir, sprintf('pair_%02d.png',k)));
        close(f);
    end
end

% ---------- Tabla resumen ----------
T = table((1:n)', mainIDs, backIDs, delta_t, isCoord,...
          'VariableNames',{'PairID','Main','Backup','Delta_t','Coordinated'});

% Mostrar primeras 10 filas en pantalla
disp(T(1:min(10,n),:));

% Guardar CSV en results
csvPath = fullfile(resultsDir,'coordination_summary.csv');
writetable(T, csvPath);

fprintf('\nTotal pares: %d | Coordinados: %d | Descoordinados: %d\n',...
        n, sum(isCoord), sum(~isCoord));
fprintf('✅ Resultados guardados en: %s\n', resultsDir);
