unit PortalCliente.Boleto.UploadTest;

{$mode delphi}

interface

type
  TPortalBoletoUploadTest = class sealed
  public
    class function Executar(const AContaReceberIdTexto: string): Integer; static;
  end;

implementation

uses
  PortalCliente.IOUtils,
  SysUtils,
  PortalCliente.Db,
  Aguia.Database,
  Aguia.Database.Config,
  PortalCliente.Boleto.Config,
  PortalCliente.Boleto.Generator,
  PortalCliente.Boleto.Uploader,
  PortalCliente.S3.Config,
  PortalCliente.Queue.Repository;

class function TPortalBoletoUploadTest.Executar(
  const AContaReceberIdTexto: string): Integer;
var
  BoletoConfig: TPortalBoletoRenderConfig;
  Connection: TPortalConexao;
  ContaReceberId: Integer;
  DBConfig: TAguiaDatabaseConfig;
  HomologacaoDir: string;
  Envio: TPortalBoletoEnvioResultado;
  S3Config: TPortalS3Config;
  Uploader: TPortalBoletoUploader;
begin
  if not TryStrToInt(AContaReceberIdTexto, ContaReceberId) or
     (ContaReceberId <= 0) then
  begin
    Writeln('Uso: AguiaPortalService /testar-upload-boleto <CONTARECEBER.INTERNAL_COD>');
    Exit(2);
  end;

  try
    DBConfig := TAguiaDatabaseConfigLoader.Carregar;
    BoletoConfig := TPortalBoletoConfigLoader.Carregar(
      DBConfig.ServiceConfigFile, HomologacaoDir);
    if not TDirectory.Exists(BoletoConfig.LogoDir) then
      raise Exception.CreateFmt('Pasta de logotipos do boleto nao encontrada: %s',
        [BoletoConfig.LogoDir]);
    S3Config := TPortalS3ConfigLoader.Carregar(DBConfig.ServiceConfigFile);

    Connection := TAguiaDatabase.AbrirConexao(DBConfig);
    try
      Uploader := TPortalBoletoUploader.Create(Connection, BoletoConfig,
        S3Config);
      try
        Envio := Uploader.Enviar(ContaReceberId);
      finally
        Uploader.Free;
      end;
    finally
      Connection.Free;
    end;

    Writeln('Boleto gerado em memoria e enviado ao S3 privado.');
    Writeln('Object Key: ' + Envio.ObjectKey);
    if Envio.ETag <> '' then
      Writeln('ETag: ' + Envio.ETag);
    if Envio.VersionId <> '' then
      Writeln('VersionId: ' + Envio.VersionId);
    if Envio.FilaAcao = pfaIgnoradoEnviado then
      Writeln('O titulo ja estava enviado com esta mesma boleto_chave_s3.')
    else
    begin
      Writeln('Titulo recolocado na fila com boleto_chave_s3 = Object Key.');
      Writeln('Execute /enviar-titulos para transmitir a alteracao ao Portal.');
    end;
    Result := 0;
  except
    on E: Exception do
    begin
      Writeln('Falha ao gerar/enviar boleto: ' + E.Message);
      Result := 1;
    end;
  end;
end;

end.
