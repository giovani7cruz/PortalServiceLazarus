unit PortalCliente.Sync.Engine;

{$mode delphi}

interface

uses
  PortalCliente.Db,
  PortalCliente.Config.Repository;

type
  TPortalSyncLogProc = procedure(const AMensagem: string) of object;
  TPortalSyncWaitFunc = function(const AMilissegundos: Cardinal): Boolean of object;

  TPortalSyncResumo = record
    ClientesCarregados: Integer;
    ClientesEnviados: Integer;
    TitulosCarregados: Integer;
    TitulosEnviados: Integer;
    Erros: Integer;
    Requisicoes: Integer;
  end;

  TPortalSyncEngine = class
  private
    FConnection: TPortalConexao;
    FLog: TPortalSyncLogProc;
    FWait: TPortalSyncWaitFunc;
    procedure Log(const AMensagem: string);
    function PararSolicitado: Boolean;
    procedure CarregarClientes(const AConfig: TPortalConfiguracao;
      var AResumo: TPortalSyncResumo);
    procedure CarregarTitulos(const AConfig: TPortalConfiguracao;
      var AResumo: TPortalSyncResumo);
    procedure Enviar(const AConfig: TPortalConfiguracao;
      const AClientes: Boolean; var AResumo: TPortalSyncResumo);
    class function Juntar(const AValores: TArray<string>): string; static;
    class function EsperaTentativa(const ATentativas: Integer): Integer; static;
  public
    constructor Create(AConnection: TPortalConexao;
      const ALog: TPortalSyncLogProc; const AWait: TPortalSyncWaitFunc);
    function ProcessarEmpresa(
      const AConfig: TPortalConfiguracao): TPortalSyncResumo;
  end;

implementation

uses
  Generics.Collections,
  fpjson, jsonparser, PortalCliente.Json,
  SysUtils,
  PortalCliente.Api,
  PortalCliente.Client.Mapper,
  PortalCliente.Client.Repository,
  PortalCliente.DTO,
  PortalCliente.Queue.Repository,
  PortalCliente.Title.Mapper,
  PortalCliente.Title.Repository,
  PortalCliente.TokenProtector;

constructor TPortalSyncEngine.Create(AConnection: TPortalConexao;
  const ALog: TPortalSyncLogProc; const AWait: TPortalSyncWaitFunc);
begin
  inherited Create;
  if not Assigned(AConnection) then
    raise EArgumentNilException.Create('AConnection');
  FConnection := AConnection;
  FLog := ALog;
  FWait := AWait;
end;

procedure TPortalSyncEngine.Log(const AMensagem: string);
begin
  if Assigned(FLog) then
    FLog(AMensagem);
end;

function TPortalSyncEngine.PararSolicitado: Boolean;
begin
  Result := Assigned(FWait) and FWait(0);
end;

class function TPortalSyncEngine.Juntar(
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

class function TPortalSyncEngine.EsperaTentativa(
  const ATentativas: Integer): Integer;
var
  I: Integer;
begin
  Result := 30;
  for I := 1 to ATentativas do
  begin
    Result := Result * 2;
    if Result >= 900 then
      Exit(900);
  end;
end;

procedure TPortalSyncEngine.CarregarClientes(const AConfig: TPortalConfiguracao;
  var AResumo: TPortalSyncResumo);
var
  AOrigem: TPortalClienteOrigem;
  Origens: TArray<TPortalClienteOrigem>;
  Indice: Integer;
  Acao: TPortalFilaAcao;
  Carregados: Integer;
  JSON: TJSONObject;
  MapResult: TPortalClienteMapResult;
  Payload: string;
  Queue: TPortalFilaRepository;
  Repository: TPortalClienteRepository;
begin
  Carregados := 0;
  Queue := TPortalFilaRepository.Create(FConnection);
  Repository := TPortalClienteRepository.Create(FConnection);
  try
    FConnection.StartTransaction;
    try
      Origens := Repository.Listar;
      for Indice := 0 to High(Origens) do
        begin
          if PararSolicitado then
            Break;
          AOrigem := Origens[Indice];
          MapResult := TPortalClienteMapper.Mapear(AOrigem);
          JSON := TPortalClienteMapper.ParaJSON(MapResult.Cliente);
          try
            Payload := JSON.ToJSON;
          finally
            JSON.Free;
          end;
          Acao := Queue.SalvarCliente(AConfig.CodigoEmpresa, AOrigem.Codigo,
            MapResult.Cliente.IDExterno, Payload, Juntar(MapResult.Erros),
            MapResult.Valido, False);
          if Acao in [pfaInserido, pfaAtualizado] then
            Inc(Carregados);
        end;
      FConnection.Commit;
      Inc(AResumo.ClientesCarregados, Carregados);
    except
      if FConnection.InTransaction then
        FConnection.Rollback;
      raise;
    end;
  finally
    Repository.Free;
    Queue.Free;
  end;
end;

procedure TPortalSyncEngine.CarregarTitulos(const AConfig: TPortalConfiguracao;
  var AResumo: TPortalSyncResumo);
var
  AOrigem: TPortalTituloOrigem;
  Origens: TArray<TPortalTituloOrigem>;
  Indice: Integer;
  Acao: TPortalFilaAcao;
  Carregados: Integer;
  IDExternoAtual: string;
  JSON: TJSONObject;
  MapResult: TPortalTituloMapResult;
  Payload: string;
  PayloadAtual: string;
  Queue: TPortalFilaRepository;
  Repository: TPortalTituloRepository;
  TituloAtual: TPortalTituloEnvio;
begin
  Carregados := 0;
  Queue := TPortalFilaRepository.Create(FConnection);
  Repository := TPortalTituloRepository.Create(FConnection);
  try
    FConnection.StartTransaction;
    try
      Origens := Repository.Listar(AConfig.CodigoEmpresa);
      for Indice := 0 to High(Origens) do
        begin
          if PararSolicitado then
            Break;
          AOrigem := Origens[Indice];
          MapResult := TPortalTituloMapper.Mapear(AOrigem);
          if Queue.TentarObterTitulo(AConfig.CodigoEmpresa, AOrigem.Codigo,
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
          Acao := Queue.SalvarTitulo(AConfig.CodigoEmpresa, AOrigem.Codigo,
            MapResult.Titulo.IDExterno, Payload, Juntar(MapResult.Erros),
            MapResult.Valido, False);
          if Acao in [pfaInserido, pfaAtualizado] then
            Inc(Carregados);
        end;
      FConnection.Commit;
      Inc(AResumo.TitulosCarregados, Carregados);
    except
      if FConnection.InTransaction then
        FConnection.Rollback;
      raise;
    end;
  finally
    Repository.Free;
    Queue.Free;
  end;
end;

procedure TPortalSyncEngine.Enviar(const AConfig: TPortalConfiguracao;
  const AClientes: Boolean; var AResumo: TPortalSyncResumo);
const
  MAX_TENTATIVAS = 5;
  LOCK_EXPIRA_MINUTOS = 15;
  INTERVALO_REQUISICOES_MS = 2100;
var
  Api: TPortalClienteApi;
  Clientes: TArray<TPortalClienteEnvio>;
  ClientesLista: TList<TPortalClienteEnvio>;
  Definitiva: Boolean;
  Fila: TArray<TPortalFilaItem>;
  FilaEnvio: TArray<TPortalFilaItem>;
  FilaEnvioLista: TList<TPortalFilaItem>;
  I: Integer;
  Indice: Integer;
  LockID: string;
  Lote: TPortalResultadoLote;
  Mensagem: string;
  NovoGuid: TGUID;
  Processado: TArray<Boolean>;
  Queue: TPortalFilaRepository;
  ResultadoItem: TPortalResultadoItem;
  Titulos: TArray<TPortalTituloEnvio>;
  TitulosLista: TList<TPortalTituloEnvio>;
  Token: string;

  procedure IniciarAtualizacao;
  begin
    if not FConnection.InTransaction then
      FConnection.StartTransaction;
  end;

  procedure ConfirmarAtualizacao;
  begin
    if FConnection.InTransaction then
      FConnection.Commit;
  end;

  procedure DesfazerAtualizacao;
  begin
    if FConnection.InTransaction then
      FConnection.Rollback;
  end;

  procedure FalharLote(const AErro: string; const ADefinitiva: Boolean);
  var
    K: Integer;
  begin
    IniciarAtualizacao;
    try
      for K := 0 to High(FilaEnvio) do
      begin
        if ADefinitiva then
          Queue.MarcarErroDefinitivo(FilaEnvio[K].InternalCod, AErro)
        else
          Queue.MarcarFalhaTransitoria(FilaEnvio[K].InternalCod, AErro,
            EsperaTentativa(FilaEnvio[K].Tentativas), MAX_TENTATIVAS);
        Inc(AResumo.Erros);
      end;
      ConfirmarAtualizacao;
    except
      DesfazerAtualizacao;
      raise;
    end;
  end;

begin
  Queue := TPortalFilaRepository.Create(FConnection);
  Api := nil;
  ClientesLista := nil;
  TitulosLista := nil;
  FilaEnvioLista := nil;
  try
    if AClientes then
      Queue.RecuperarReservasExpiradas(AConfig.CodigoEmpresa,
        LOCK_EXPIRA_MINUTOS)
    else
      Queue.RecuperarReservasTitulosExpiradas(AConfig.CodigoEmpresa,
        LOCK_EXPIRA_MINUTOS);

    Token := TPortalTokenProtector.Desproteger(AConfig.TokenProtegido);
    Api := TPortalClienteApi.Create(Token, AConfig.BaseUrl, AConfig.TimeoutMs);
    while not PararSolicitado do
    begin
      if AResumo.Requisicoes > 0 then
        if Assigned(FWait) and FWait(INTERVALO_REQUISICOES_MS) then
          Break;

      CreateGUID(NovoGuid);
      LockID := GUIDToString(NovoGuid);
      if AClientes then
        Fila := Queue.ReservarClientes(AConfig.CodigoEmpresa,
          AConfig.TamanhoLote, LockID)
      else
        Fila := Queue.ReservarTitulos(AConfig.CodigoEmpresa,
          AConfig.TamanhoLote, LockID);
      if Length(Fila) = 0 then
        Break;

      ClientesLista := TList<TPortalClienteEnvio>.Create;
      TitulosLista := TList<TPortalTituloEnvio>.Create;
      FilaEnvioLista := TList<TPortalFilaItem>.Create;
      try
        IniciarAtualizacao;
        try
          for I := 0 to High(Fila) do
            try
              if AClientes then
                ClientesLista.Add(TPortalClienteMapper.DoJSON(Fila[I].Payload))
              else
                TitulosLista.Add(TPortalTituloMapper.DoJSON(Fila[I].Payload));
              FilaEnvioLista.Add(Fila[I]);
            except
              on E: Exception do
              begin
                Queue.MarcarErroDefinitivo(Fila[I].InternalCod,
                  'Payload local invalido: ' + E.Message);
                Inc(AResumo.Erros);
              end;
            end;
          ConfirmarAtualizacao;
        except
          DesfazerAtualizacao;
          raise;
        end;
        Clientes := ClientesLista.ToArray;
        Titulos := TitulosLista.ToArray;
        FilaEnvio := FilaEnvioLista.ToArray;
      finally
        FreeAndNil(FilaEnvioLista);
        FreeAndNil(TitulosLista);
        FreeAndNil(ClientesLista);
      end;

      if Length(FilaEnvio) = 0 then
        Continue;
      try
        Inc(AResumo.Requisicoes);
        if AClientes then
          Lote := Api.SalvarClientes(Clientes)
        else
          Lote := Api.SalvarTitulos(Titulos);
        SetLength(Processado, Length(FilaEnvio));
        for I := 0 to High(Processado) do
          Processado[I] := False;

        IniciarAtualizacao;
        try
          for ResultadoItem in Lote.Resultados do
          begin
            Indice := ResultadoItem.Indice;
            if (Indice < 0) or (Indice > High(FilaEnvio)) or
              Processado[Indice] or
              not SameText(ResultadoItem.IDExterno,
                FilaEnvio[Indice].IDExterno) then
              Continue;
            Processado[Indice] := True;
            if ResultadoItem.Sucesso then
            begin
              Queue.MarcarEnviado(FilaEnvio[Indice].InternalCod);
              if AClientes then
                Inc(AResumo.ClientesEnviados)
              else
                Inc(AResumo.TitulosEnviados);
            end
            else
            begin
              Mensagem := Juntar(ResultadoItem.Erros);
              if Mensagem.IsEmpty then
                Mensagem := 'O portal recusou o item sem informar o motivo.';
              Queue.MarcarErroDefinitivo(
                FilaEnvio[Indice].InternalCod, Mensagem);
              Inc(AResumo.Erros);
            end;
          end;
          for I := 0 to High(FilaEnvio) do
            if not Processado[I] then
            begin
              Queue.MarcarFalhaTransitoria(FilaEnvio[I].InternalCod,
                'O portal nao devolveu um resultado correspondente ao item.',
                EsperaTentativa(FilaEnvio[I].Tentativas), MAX_TENTATIVAS);
              Inc(AResumo.Erros);
            end;
          ConfirmarAtualizacao;
        except
          DesfazerAtualizacao;
          raise;
        end;
      except
        on E: EPortalClienteApi do
        begin
          Mensagem := E.Message;
          Definitiva := (E.HTTPStatus >= 400) and (E.HTTPStatus < 500) and
            (E.HTTPStatus <> 401) and (E.HTTPStatus <> 403) and
            (E.HTTPStatus <> 429);
          FalharLote(Mensagem, Definitiva);
          Log(Format('Empresa %d: falha HTTP %d: %s',
            [AConfig.CodigoEmpresa, E.HTTPStatus, Mensagem]));
          Break;
        end;
        on E: Exception do
        begin
          Mensagem := E.Message;
          FalharLote(Mensagem, False);
          Log(Format('Empresa %d: falha no envio: %s',
            [AConfig.CodigoEmpresa, Mensagem]));
          Break;
        end;
      end;
    end;
  finally
    FilaEnvioLista.Free;
    TitulosLista.Free;
    ClientesLista.Free;
    Api.Free;
    Queue.Free;
  end;
end;

function TPortalSyncEngine.ProcessarEmpresa(
  const AConfig: TPortalConfiguracao): TPortalSyncResumo;
begin
  Result := Default(TPortalSyncResumo);
  if PararSolicitado then
    Exit;
  CarregarClientes(AConfig, Result);
  if PararSolicitado then
    Exit;
  Enviar(AConfig, True, Result);
  if PararSolicitado then
    Exit;
  CarregarTitulos(AConfig, Result);
  if PararSolicitado then
    Exit;
  Enviar(AConfig, False, Result);
end;

end.
