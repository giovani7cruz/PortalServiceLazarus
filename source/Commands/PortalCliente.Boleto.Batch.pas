unit PortalCliente.Boleto.Batch;

{$mode delphi}

interface

type
  TPortalBoletoBatch = class sealed
  private
    class function Confirmar(const ATotal: Integer;
      const AMes: string): Boolean; static;
    class function TentarLerMes(const ATexto: string;
      out ADataInicial, ADataFinalExclusiva: TDateTime): Boolean; static;
  public
    class function Executar(const AMes: string): Integer; static;
  end;

implementation

uses
  DateUtils,
  PortalCliente.IOUtils,
  SysUtils,
  PortalCliente.Db,
  Aguia.Database,
  Aguia.Database.Config,
  PortalCliente.Boleto.Config,
  PortalCliente.Boleto.Generator,
  PortalCliente.Boleto.Repository,
  PortalCliente.Boleto.Uploader,
  PortalCliente.Queue.Repository,
  PortalCliente.S3.Config;

class function TPortalBoletoBatch.Confirmar(const ATotal: Integer;
  const AMes: string): Boolean;
var
  Entrada: string;
begin
  WriteLn(Format('%d boleto(s) de %s serao gerados e enviados ao S3.',
    [ATotal, AMes]));
  Write('Continuar? [S/N]: ');
  ReadLn(Entrada);
  Result := SameText(Entrada.Trim, 'S');
end;

class function TPortalBoletoBatch.TentarLerMes(const ATexto: string;
  out ADataInicial, ADataFinalExclusiva: TDateTime): Boolean;
var
  Ano: Integer;
  Mes: Integer;
begin
  Result := (Length(ATexto) = 7) and (ATexto[5] = '-') and
    TryStrToInt(Copy(ATexto, 1, 4), Ano) and
    TryStrToInt(Copy(ATexto, 6, 2), Mes) and
    (Ano >= 2000) and (Mes >= 1) and (Mes <= 12);
  if not Result then
    Exit;
  try
    ADataInicial := EncodeDate(Ano, Mes, 1);
    ADataFinalExclusiva := IncMonth(ADataInicial, 1);
  except
    Result := False;
  end;
end;

class function TPortalBoletoBatch.Executar(const AMes: string): Integer;
var
  BoletoConfig: TPortalBoletoRenderConfig;
  Connection: TPortalConexao;
  DataFinal: TDateTime;
  DataInicial: TDateTime;
  DBConfig: TAguiaDatabaseConfig;
  Envio: TPortalBoletoEnvioResultado;
  Erros: Integer;
  HomologacaoDir: string;
  I: Integer;
  IDs: TArray<Integer>;
  Reabertos: Integer;
  S3Config: TPortalS3Config;
  Sucessos: Integer;
  Uploader: TPortalBoletoUploader;
begin
  Result := 1;
  if not TentarLerMes(AMes, DataInicial, DataFinal) then
  begin
    WriteLn('Uso: AguiaPortalService /sincronizar-boletos <AAAA-MM>');
    Exit(2);
  end;

  Connection := nil;
  Uploader := nil;
  try
    try
      WriteLn('AguiaPortalService - sincronizacao mensal de boletos');
      WriteLn('Criterios: vencimento no mes, forma de pagamento 6,');
      WriteLn('empresa ativa e titulo existente em PORTAL_SYNC_FILA.');
      WriteLn('Os PDFs sao processados sequencialmente e nao sao salvos em disco.');
      WriteLn;

      DBConfig := TAguiaDatabaseConfigLoader.Carregar;
      BoletoConfig := TPortalBoletoConfigLoader.Carregar(
        DBConfig.ServiceConfigFile, HomologacaoDir);
      if not TDirectory.Exists(BoletoConfig.LogoDir) then
        raise Exception.CreateFmt('Pasta de logotipos do boleto nao encontrada: %s',
          [BoletoConfig.LogoDir]);
      S3Config := TPortalS3ConfigLoader.Carregar(DBConfig.ServiceConfigFile);
      Connection := TAguiaDatabase.AbrirConexao(DBConfig);
      IDs := TPortalBoletoRepository.ListarPorVencimento(Connection,
        DataInicial, DataFinal);

      if Length(IDs) = 0 then
      begin
        WriteLn('Nenhum boleto elegivel encontrado para ' + AMes + '.');
        Exit(0);
      end;
      if not Confirmar(Length(IDs), AMes) then
      begin
        WriteLn('Operacao cancelada.');
        Exit(0);
      end;

      Uploader := TPortalBoletoUploader.Create(Connection, BoletoConfig,
        S3Config);
      Sucessos := 0;
      Reabertos := 0;
      Erros := 0;
      for I := 0 to High(IDs) do
      begin
        try
          Envio := Uploader.Enviar(IDs[I]);
          Inc(Sucessos);
          if Envio.FilaAcao <> pfaIgnoradoEnviado then
            Inc(Reabertos);
          WriteLn(Format('[%d/%d] Titulo %d: enviado (%s)',
            [I + 1, Length(IDs), IDs[I], Envio.ObjectKey]));
        except
          on E: Exception do
          begin
            Inc(Erros);
            WriteLn(Format('[%d/%d] Titulo %d: ERRO - %s',
              [I + 1, Length(IDs), IDs[I], E.Message]));
          end;
        end;
      end;

      WriteLn;
      WriteLn(Format('Boletos enviados ao S3: %d', [Sucessos]));
      WriteLn(Format('Titulos atualizados/reabertos na fila: %d', [Reabertos]));
      WriteLn(Format('Erros: %d', [Erros]));
      if Reabertos > 0 then
        WriteLn('Execute /enviar-titulos para transmitir as chaves ao Portal.');
      if Erros = 0 then
        Result := 0;
    except
      on E: Exception do
        WriteLn('ERRO: ' + E.Message);
    end;
  finally
    Uploader.Free;
    Connection.Free;
  end;
end;

end.
