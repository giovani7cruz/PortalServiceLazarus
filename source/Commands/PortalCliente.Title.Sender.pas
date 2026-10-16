unit PortalCliente.Title.Sender;

{$mode delphi}

interface

type
  TPortalTituloSender = class sealed
  private
    class function Confirmar(const ATotal: Integer): Boolean; static;
    class function Juntar(const AValores: TArray<string>): string; static;
    class function Espera(const ATentativas: Integer): Integer; static;
  public
    class function Executar: Integer; static;
  end;

implementation

uses
  Classes,
  Generics.Collections,
  SysUtils,
  PortalCliente.Db,
  Aguia.Database,
  Aguia.Database.Config,
  PortalCliente.Api,
  PortalCliente.Config.Repository,
  PortalCliente.DTO,
  PortalCliente.Queue.Repository,
  PortalCliente.Title.Mapper,
  PortalCliente.TokenProtector;

class function TPortalTituloSender.Confirmar(const ATotal: Integer): Boolean;
var
  Entrada: string;
begin
  WriteLn(Format('%d titulo(s) pendente(s) serao enviados ao portal.',
    [ATotal]));
  Write('Continuar? [S/N]: ');
  ReadLn(Entrada);
  Result := SameText(Entrada.Trim, 'S');
end;

class function TPortalTituloSender.Juntar(
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

class function TPortalTituloSender.Espera(const ATentativas: Integer): Integer;
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

class function TPortalTituloSender.Executar: Integer;
const
  MAX_TENTATIVAS = 5;
  LOCK_EXPIRA_MINUTOS = 15;
  INTERVALO_REQUISICOES_MS = 2100;
var
  Api: TPortalClienteApi;
  Config: TAguiaDatabaseConfig;
  Configuracoes: TArray<TPortalConfiguracao>;
  ConfigRepository: TPortalConfigRepository;
  Connection: TPortalConexao;
  DeveParar: Boolean;
  Enviados: Integer;
  Erros: Integer;
  Fila: TArray<TPortalFilaItem>;
  FilaEnvio: TArray<TPortalFilaItem>;
  FilaEnvioLista: TList<TPortalFilaItem>;
  FilaRepository: TPortalFilaRepository;
  I: Integer;
  J: Integer;
  LockID: string;
  Lote: TPortalResultadoLote;
  Mensagem: string;
  NovoGuid: TGUID;
  Pendentes: Integer;
  Processado: TArray<Boolean>;
  Requisicoes: Integer;
  ResultadoItem: TPortalResultadoItem;
  Titulos: TArray<TPortalTituloEnvio>;
  TitulosLista: TList<TPortalTituloEnvio>;
  Token: string;
  TotalPendentes: Integer;

  procedure IniciarAtualizacao;
  begin
    if not Connection.InTransaction then
      Connection.StartTransaction;
  end;

  procedure ConfirmarAtualizacao;
  begin
    if Connection.InTransaction then
      Connection.Commit;
  end;

  procedure DesfazerAtualizacao;
  begin
    if Connection.InTransaction then
      Connection.Rollback;
  end;

  procedure TratarFalhaDoLote(const AErro: string;
    const ADefinitiva: Boolean);
  var
    K: Integer;
  begin
    IniciarAtualizacao;
    try
      for K := 0 to High(FilaEnvio) do
      begin
        if ADefinitiva then
          FilaRepository.MarcarErroDefinitivo(
            FilaEnvio[K].InternalCod, AErro)
        else
          FilaRepository.MarcarFalhaTransitoria(
            FilaEnvio[K].InternalCod, AErro,
            Espera(FilaEnvio[K].Tentativas), MAX_TENTATIVAS);
        Inc(Erros);
      end;
      ConfirmarAtualizacao;
    except
      DesfazerAtualizacao;
      raise;
    end;
  end;

begin
  Result := 1;
  Connection := nil;
  ConfigRepository := nil;
  FilaRepository := nil;
  FilaEnvioLista := nil;
  TitulosLista := nil;
  try
    try
      WriteLn('AguiaPortalService - envio manual de titulos financeiros');
      WriteLn('Este comando envia os titulos pendentes para o portal.');
      WriteLn;

      Config := TAguiaDatabaseConfigLoader.Carregar;
      Connection := TAguiaDatabase.AbrirConexao(Config);
      ConfigRepository := TPortalConfigRepository.Create(Connection);
      FilaRepository := TPortalFilaRepository.Create(Connection);
      Configuracoes := ConfigRepository.Listar(True);
      if Length(Configuracoes) = 0 then
        raise Exception.Create(
          'Nenhuma empresa ativa em PORTAL_CONFIG. Execute /configurar.');

      TotalPendentes := 0;
      for I := 0 to High(Configuracoes) do
      begin
        FilaRepository.RecuperarReservasTitulosExpiradas(
          Configuracoes[I].CodigoEmpresa, LOCK_EXPIRA_MINUTOS);
        Inc(TotalPendentes, FilaRepository.ContarTitulosPendentes(
          Configuracoes[I].CodigoEmpresa));
      end;
      if TotalPendentes = 0 then
      begin
        WriteLn('Nao ha titulos pendentes para envio.');
        Exit(0);
      end;
      if not Confirmar(TotalPendentes) then
      begin
        WriteLn('Operacao cancelada.');
        Exit(0);
      end;

      Enviados := 0;
      Erros := 0;
      Requisicoes := 0;
      for I := 0 to High(Configuracoes) do
      begin
        Pendentes := FilaRepository.ContarTitulosPendentes(
          Configuracoes[I].CodigoEmpresa);
        if Pendentes = 0 then
          Continue;

        WriteLn(Format('Empresa %d: %d pendente(s).',
          [Configuracoes[I].CodigoEmpresa, Pendentes]));
        Token := TPortalTokenProtector.Desproteger(
          Configuracoes[I].TokenProtegido);
        Api := TPortalClienteApi.Create(Token, Configuracoes[I].BaseUrl,
          Configuracoes[I].TimeoutMs);
        try
          DeveParar := False;
          while not DeveParar do
          begin
            CreateGUID(NovoGuid);
            LockID := GUIDToString(NovoGuid);
            Fila := FilaRepository.ReservarTitulos(
              Configuracoes[I].CodigoEmpresa,
              Configuracoes[I].TamanhoLote, LockID);
            if Length(Fila) = 0 then
              Break;

            TitulosLista := TList<TPortalTituloEnvio>.Create;
            FilaEnvioLista := TList<TPortalFilaItem>.Create;
            try
              IniciarAtualizacao;
              try
                for J := 0 to High(Fila) do
                  try
                    TitulosLista.Add(
                      TPortalTituloMapper.DoJSON(Fila[J].Payload));
                    FilaEnvioLista.Add(Fila[J]);
                  except
                    on E: Exception do
                    begin
                      FilaRepository.MarcarErroDefinitivo(Fila[J].InternalCod,
                        'Payload local invalido: ' + E.Message);
                      Inc(Erros);
                    end;
                  end;
                ConfirmarAtualizacao;
              except
                DesfazerAtualizacao;
                raise;
              end;
              Titulos := TitulosLista.ToArray;
              FilaEnvio := FilaEnvioLista.ToArray;
            finally
              FreeAndNil(FilaEnvioLista);
              FreeAndNil(TitulosLista);
            end;

            if Length(Titulos) = 0 then
              Continue;
            if Requisicoes > 0 then
              TThread.Sleep(INTERVALO_REQUISICOES_MS);

            try
              Inc(Requisicoes);
              Lote := Api.SalvarTitulos(Titulos);
              SetLength(Processado, Length(FilaEnvio));
              for J := 0 to High(Processado) do
                Processado[J] := False;

              IniciarAtualizacao;
              try
                for ResultadoItem in Lote.Resultados do
                begin
                  J := ResultadoItem.Indice;
                  if (J < 0) or (J > High(FilaEnvio)) or Processado[J] or
                    not SameText(ResultadoItem.IDExterno,
                      FilaEnvio[J].IDExterno) then
                    Continue;
                  Processado[J] := True;
                  if ResultadoItem.Sucesso then
                  begin
                    FilaRepository.MarcarEnviado(FilaEnvio[J].InternalCod);
                    Inc(Enviados);
                  end
                  else
                  begin
                    Mensagem := Juntar(ResultadoItem.Erros);
                    if Mensagem.IsEmpty then
                      Mensagem := 'O portal recusou o item sem informar o motivo.';
                    FilaRepository.MarcarErroDefinitivo(
                      FilaEnvio[J].InternalCod, Mensagem);
                    Inc(Erros);
                  end;
                end;
                for J := 0 to High(FilaEnvio) do
                  if not Processado[J] then
                  begin
                    FilaRepository.MarcarFalhaTransitoria(
                      FilaEnvio[J].InternalCod,
                      'O portal nao devolveu um resultado correspondente ao item.',
                      Espera(FilaEnvio[J].Tentativas), MAX_TENTATIVAS);
                    Inc(Erros);
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
                TratarFalhaDoLote(Mensagem,
                  (E.HTTPStatus >= 400) and (E.HTTPStatus < 500) and
                  (E.HTTPStatus <> 401) and (E.HTTPStatus <> 403) and
                  (E.HTTPStatus <> 429));
                WriteLn(Format('  Falha HTTP %d: %s',
                  [E.HTTPStatus, Mensagem]));
                DeveParar := True;
              end;
              on E: Exception do
              begin
                Mensagem := E.Message;
                TratarFalhaDoLote(Mensagem, False);
                WriteLn('  Falha: ' + Mensagem);
                DeveParar := True;
              end;
            end;
          end;
        finally
          Api.Free;
        end;
      end;

      WriteLn;
      WriteLn(Format('Titulos enviados: %d', [Enviados]));
      WriteLn(Format('Itens com erro ou reagendados: %d', [Erros]));
      WriteLn(Format('Requisicoes realizadas: %d', [Requisicoes]));
      Result := 0;
    except
      on E: Exception do
        WriteLn('ERRO: ' + E.Message);
    end;
  finally
    FilaEnvioLista.Free;
    TitulosLista.Free;
    FilaRepository.Free;
    ConfigRepository.Free;
    Connection.Free;
  end;
end;

end.
