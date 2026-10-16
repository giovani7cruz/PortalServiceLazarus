unit PortalCliente.Worker;

{$mode delphi}

interface

uses
  Classes,
  SyncObjs;

type
  TPortalWorkerLogProc = procedure(const AMensagem: string) of object;

  TPortalClienteWorker = class(TThread)
  private
    FParar: TEvent;
    FOnLog: TPortalWorkerLogProc;
    procedure Log(const AMensagem: string);
    function EsperarParada(const AMilissegundos: Cardinal): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(const AOnLog: TPortalWorkerLogProc);
    destructor Destroy; override;
    procedure SolicitarParada;
  end;

implementation

uses
  SysUtils,
  PortalCliente.Db,
  Aguia.Database,
  Aguia.Database.Config,
  PortalCliente.Config.Repository,
  PortalCliente.Sync.Engine;

constructor TPortalClienteWorker.Create(const AOnLog: TPortalWorkerLogProc);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FOnLog := AOnLog;
  FParar := TEvent.Create(nil, True, False, '');
end;

destructor TPortalClienteWorker.Destroy;
begin
  FParar.Free;
  inherited;
end;

procedure TPortalClienteWorker.Log(const AMensagem: string);
begin
  if Assigned(FOnLog) then
    FOnLog(AMensagem);
end;

function TPortalClienteWorker.EsperarParada(
  const AMilissegundos: Cardinal): Boolean;
begin
  Result := FParar.WaitFor(AMilissegundos) = wrSignaled;
end;

procedure TPortalClienteWorker.Execute;
var
  Config: TAguiaDatabaseConfig;
  Configuracoes: TArray<TPortalConfiguracao>;
  Connection: TPortalConexao;
  Engine: TPortalSyncEngine;
  ErroCiclo: string;
  I: Integer;
  IntervaloEspera: Integer;
  Repository: TPortalConfigRepository;
  Resumo: TPortalSyncResumo;
begin
  Log('Worker iniciado.');
  while not Terminated do
  begin
    Connection := nil;
    Engine := nil;
    Repository := nil;
    try
      try
        Config := TAguiaDatabaseConfigLoader.Carregar;
        Connection := TAguiaDatabase.AbrirConexao(Config);
        Repository := TPortalConfigRepository.Create(Connection);
        Engine := TPortalSyncEngine.Create(Connection, Log, EsperarParada);
        Log('Firebird conectado.');

        while not Terminated do
        begin
          Connection.EncerrarLeitura;
          if not Connection.Ping then
            raise Exception.Create('A conexao com o Firebird foi perdida.');
          Configuracoes := Repository.Listar(True);
          if Length(Configuracoes) = 0 then
          begin
            Log('Nenhuma empresa ativa em PORTAL_CONFIG.');
            if FParar.WaitFor(30000) = wrSignaled then
              Break;
            Continue;
          end;

          IntervaloEspera := 86400;
          for I := 0 to High(Configuracoes) do
          begin
            if Terminated then
              Break;
            ErroCiclo := '';
            try
              Resumo := Engine.ProcessarEmpresa(Configuracoes[I]);
              Log(Format(
                'Empresa %d: ciclo concluido. Clientes fila=%d enviados=%d; ' +
                'titulos fila=%d enviados=%d; erros=%d; requisicoes=%d.',
                [Configuracoes[I].CodigoEmpresa,
                 Resumo.ClientesCarregados, Resumo.ClientesEnviados,
                 Resumo.TitulosCarregados, Resumo.TitulosEnviados,
                 Resumo.Erros, Resumo.Requisicoes]));
            except
              on E: Exception do
              begin
                ErroCiclo := E.Message;
                Log(Format('Empresa %d: ciclo falhou: %s',
                  [Configuracoes[I].CodigoEmpresa, ErroCiclo]));
              end;
            end;
            Repository.RegistrarCiclo(
              Configuracoes[I].CodigoEmpresa, ErroCiclo);
            if Configuracoes[I].IntervaloSegundos < IntervaloEspera then
              IntervaloEspera := Configuracoes[I].IntervaloSegundos;
          end;

          if IntervaloEspera < 10 then
            IntervaloEspera := 10;
          if FParar.WaitFor(Cardinal(IntervaloEspera) * 1000) = wrSignaled then
            Break;
        end;
      except
        on E: Exception do
        begin
          Log('Falha na conexao Firebird: ' + E.Message);
          if FParar.WaitFor(30000) = wrSignaled then
            Break;
        end;
      end;
    finally
      Engine.Free;
      Repository.Free;
      Connection.Free;
    end;
  end;
  Log('Worker finalizado.');
end;

procedure TPortalClienteWorker.SolicitarParada;
begin
  Terminate;
  FParar.SetEvent;
end;

end.
