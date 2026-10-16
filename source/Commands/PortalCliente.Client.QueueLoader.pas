unit PortalCliente.Client.QueueLoader;

{$mode delphi}

interface

type
  TPortalClienteQueueLoader = class sealed
  private
    class function Confirmar: Boolean; static;
    class function Juntar(const AValores: TArray<string>): string; static;
  public
    class function Executar: Integer; static;
  end;

implementation

uses
  fpjson, jsonparser, PortalCliente.Json,
  SysUtils,
  PortalCliente.Db,
  Aguia.Database,
  Aguia.Database.Config,
  PortalCliente.Client.Mapper,
  PortalCliente.Client.Repository,
  PortalCliente.Config.Repository,
  PortalCliente.Queue.Repository;

class function TPortalClienteQueueLoader.Confirmar: Boolean;
var
  Entrada: string;
begin
  Write('Gravar a fila de clientes no banco? [S/N]: ');
  ReadLn(Entrada);
  Result := SameText(Entrada.Trim, 'S');
end;

class function TPortalClienteQueueLoader.Juntar(
  const AValores: TArray<string>): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AValores) do
  begin
    if not Result.IsEmpty then
      Result := Result + '; ';
    Result := Result + AValores[I];
  end;
end;

class function TPortalClienteQueueLoader.Executar: Integer;
var
  AOrigem: TPortalClienteOrigem;
  Origens: TArray<TPortalClienteOrigem>;
  IndiceOrigem: Integer;
  JSON: TJSONObject;
  Acao: TPortalFilaAcao;
  Atualizados: Integer;
  Config: TAguiaDatabaseConfig;
  Configuracoes: TArray<TPortalConfiguracao>;
  ConfigRepository: TPortalConfigRepository;
  Connection: TPortalConexao;
  CodigoEmpresa: Integer;
  EnviadosIgnorados: Integer;
  Erros: Integer;
  I: Integer;
  Inseridos: Integer;
  MapResult: TPortalClienteMapResult;
  Payload: string;
  QueueRepository: TPortalFilaRepository;
  Repository: TPortalClienteRepository;
  Total: Integer;
begin
  Result := 1;
  Connection := nil;
  ConfigRepository := nil;
  QueueRepository := nil;
  Repository := nil;
  try
    try
      WriteLn('AguiaPortalService - carga da fila de clientes');
      WriteLn('Esta operacao grava somente PORTAL_SYNC_FILA.');
      WriteLn('Nenhuma requisicao sera enviada ao portal.');
      WriteLn;
      if not Confirmar then
      begin
        WriteLn('Operacao cancelada.');
        Exit(0);
      end;

      Config := TAguiaDatabaseConfigLoader.Carregar;
      Connection := TAguiaDatabase.AbrirConexao(Config);
      ConfigRepository := TPortalConfigRepository.Create(Connection);
      QueueRepository := TPortalFilaRepository.Create(Connection);
      Repository := TPortalClienteRepository.Create(Connection);
      Configuracoes := ConfigRepository.Listar(True);
      if Length(Configuracoes) = 0 then
        raise Exception.Create(
          'Nenhuma empresa ativa em PORTAL_CONFIG. Execute /configurar.');

      for I := 0 to High(Configuracoes) do
      begin
        CodigoEmpresa := Configuracoes[I].CodigoEmpresa;
        Total := 0;
        Inseridos := 0;
        Atualizados := 0;
        EnviadosIgnorados := 0;
        Erros := 0;

        Connection.StartTransaction;
        try
          Origens := Repository.Listar;
          for IndiceOrigem := 0 to High(Origens) do
          begin
            AOrigem := Origens[IndiceOrigem];
              Inc(Total);
              MapResult := TPortalClienteMapper.Mapear(AOrigem);
              JSON := TPortalClienteMapper.ParaJSON(MapResult.Cliente);
              try
                Payload := JSON.ToJSON;
              finally
                JSON.Free;
              end;

              Acao := QueueRepository.SalvarCliente(
                CodigoEmpresa,
                AOrigem.Codigo,
                MapResult.Cliente.IDExterno,
                Payload,
                Juntar(MapResult.Erros),
                MapResult.Valido);

              case Acao of
                pfaInserido: Inc(Inseridos);
                pfaAtualizado: Inc(Atualizados);
                pfaIgnoradoEnviado: Inc(EnviadosIgnorados);
              end;
              if not MapResult.Valido then
                Inc(Erros);
          end;
          Connection.Commit;
        except
          if Connection.InTransaction then
            Connection.Rollback;
          raise;
        end;

        WriteLn(Format('Empresa %d:', [CodigoEmpresa]));
        WriteLn(Format('  Processados: %d', [Total]));
        WriteLn(Format('  Inseridos: %d', [Inseridos]));
        WriteLn(Format('  Atualizados: %d', [Atualizados]));
        WriteLn(Format('  Ja enviados preservados: %d', [EnviadosIgnorados]));
        WriteLn(Format('  Invalidos registrados: %d', [Erros]));
      end;

      WriteLn('Carga da fila concluida. Nenhuma requisicao foi enviada.');
      Result := 0;
    except
      on E: Exception do
        WriteLn('ERRO: ' + E.Message);
    end;
  finally
    Repository.Free;
    QueueRepository.Free;
    ConfigRepository.Free;
    Connection.Free;
  end;
end;

end.
