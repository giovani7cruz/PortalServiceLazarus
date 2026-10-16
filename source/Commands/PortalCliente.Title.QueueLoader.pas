unit PortalCliente.Title.QueueLoader;

{$mode delphi}

interface

type
  TPortalTituloQueueLoader = class sealed
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
  PortalCliente.Config.Repository,
  PortalCliente.DTO,
  PortalCliente.Queue.Repository,
  PortalCliente.Title.Mapper,
  PortalCliente.Title.Repository;

class function TPortalTituloQueueLoader.Confirmar: Boolean;
var
  Entrada: string;
begin
  Write('Gravar a fila de titulos financeiros no banco? [S/N]: ');
  ReadLn(Entrada);
  Result := SameText(Entrada.Trim, 'S');
end;

class function TPortalTituloQueueLoader.Juntar(
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

class function TPortalTituloQueueLoader.Executar: Integer;
var
  AOrigem: TPortalTituloOrigem;
  Origens: TArray<TPortalTituloOrigem>;
  IndiceOrigem: Integer;
  JSON: TJSONObject;
  Acao: TPortalFilaAcao;
  Atualizados: Integer;
  BloqueadosPorCliente: Integer;
  Config: TAguiaDatabaseConfig;
  Configuracoes: TArray<TPortalConfiguracao>;
  ConfigRepository: TPortalConfigRepository;
  Connection: TPortalConexao;
  EnviadosIgnorados: Integer;
  Erros: Integer;
  IDExternoAtual: string;
  I: Integer;
  Inseridos: Integer;
  MapResult: TPortalTituloMapResult;
  Payload: string;
  PayloadAtual: string;
  QueueRepository: TPortalFilaRepository;
  Repository: TPortalTituloRepository;
  Total: Integer;
  TituloAtual: TPortalTituloEnvio;
begin
  Result := 1;
  Connection := nil;
  ConfigRepository := nil;
  QueueRepository := nil;
  Repository := nil;
  try
    try
      WriteLn('AguiaPortalService - carga da fila de titulos financeiros');
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
      Repository := TPortalTituloRepository.Create(Connection);
      Configuracoes := ConfigRepository.Listar(True);
      if Length(Configuracoes) = 0 then
        raise Exception.Create(
          'Nenhuma empresa ativa em PORTAL_CONFIG. Execute /configurar.');

      for I := 0 to High(Configuracoes) do
      begin
        Total := 0;
        Inseridos := 0;
        Atualizados := 0;
        EnviadosIgnorados := 0;
        Erros := 0;
        BloqueadosPorCliente := Repository.ContarSemClienteEnviado(
          Configuracoes[I].CodigoEmpresa);

        Connection.StartTransaction;
        try
          Origens := Repository.Listar(Configuracoes[I].CodigoEmpresa);
          for IndiceOrigem := 0 to High(Origens) do
          begin
            AOrigem := Origens[IndiceOrigem];
              Inc(Total);
              MapResult := TPortalTituloMapper.Mapear(AOrigem);
              if QueueRepository.TentarObterTitulo(
                Configuracoes[I].CodigoEmpresa, AOrigem.Codigo,
                IDExternoAtual, PayloadAtual) then
              begin
                TituloAtual := TPortalTituloMapper.DoJSON(PayloadAtual);
                TPortalTituloMapper.PreservarDocumentos(TituloAtual,
                  MapResult.Titulo);
              end;
              JSON := TPortalTituloMapper.ParaJSON(MapResult.Titulo);
              try
                Payload := JSON.ToJSON;
              finally
                JSON.Free;
              end;

              Acao := QueueRepository.SalvarTitulo(
                Configuracoes[I].CodigoEmpresa,
                AOrigem.Codigo,
                MapResult.Titulo.IDExterno,
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

        WriteLn(Format('Empresa %d:', [Configuracoes[I].CodigoEmpresa]));
        WriteLn(Format('  Processados: %d', [Total]));
        WriteLn(Format('  Inseridos: %d', [Inseridos]));
        WriteLn(Format('  Atualizados: %d', [Atualizados]));
        WriteLn(Format('  Ja enviados preservados: %d', [EnviadosIgnorados]));
        WriteLn(Format('  Invalidos registrados: %d', [Erros]));
        WriteLn(Format('  Ignorados sem cliente enviado: %d',
          [BloqueadosPorCliente]));
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
