program AguiaPortalService;

{ AguiaPortalService para Linux (Lazarus/FPC, SQLdb). Sem parametro roda como
  daemon do systemd; com parametro executa um comando manual (/configurar,
  /testar-conexao, /executar-ciclo, /sincronizar-boletos...). O mesmo conjunto
  de comandos do projeto Delphi (Aguia\PortalService). }

{$mode delphi}
{$APPTYPE CONSOLE}

uses
  cthreads,
  Interfaces, // LCL sem tela: o ACBr depende da LCL
  Math, SysUtils, Classes,
  PortalCliente.Plataforma,
  PortalCliente.Db,
  PortalCliente.Json,
  PortalCliente.IOUtils,
  PortalCliente.Http,
  PortalCliente.Sha256,
  PortalCliente.DTO,
  PortalCliente.Api,
  Aguia.Database.Config,
  Aguia.Database,
  PortalCliente.Config.Repository,
  PortalCliente.Diagnostics,
  PortalCliente.TokenProtector,
  PortalCliente.Configurator,
  PortalCliente.Client.Repository,
  PortalCliente.Client.Mapper,
  PortalCliente.Client.Preview,
  PortalCliente.Queue.Repository,
  PortalCliente.Client.QueueLoader,
  PortalCliente.Client.Sender,
  PortalCliente.Title.Repository,
  PortalCliente.Title.Mapper,
  PortalCliente.Title.Preview,
  PortalCliente.Title.QueueLoader,
  PortalCliente.Title.Sender,
  PortalCliente.Title.QueueDiagnostics,
  PortalCliente.Sync.Engine,
  PortalCliente.Sync.Once,
  PortalCliente.Worker,
  PortalCliente.Boleto.Repository,
  PortalCliente.Boleto.Generator,
  PortalCliente.Boleto.Config,
  PortalCliente.Boleto.ObjectKey,
  PortalCliente.Boleto.GenerateTest,
  PortalCliente.S3.Config,
  PortalCliente.S3,
  PortalCliente.Boleto.Uploader,
  PortalCliente.Boleto.UploadTest,
  PortalCliente.Boleto.Batch,
  Service.PortalCliente.Linux;

var
  CodigoSaida: Integer;
  Saida: string;

function Comando(const ANome: string): Boolean;
begin
  Result := (ParamCount > 0) and SameText(ParamStr(1), ANome);
end;

function Argumento: string;
begin
  if ParamCount >= 2 then
    Result := ParamStr(2)
  else
    Result := '';
end;

begin
  { libxml2/OpenSSL (via ACBr) fazem aritmetica de ponto flutuante que o FPC
    trataria como excecao. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
  { O JSON e as consultas usam ponto decimal. }
  DefaultFormatSettings.DecimalSeparator := '.';
  DefaultFormatSettings.ThousandSeparator := ',';

  if Comando('/sincronizar-boletos') then
    Halt(TPortalBoletoBatch.Executar(Argumento));

  if Comando('/configurar-s3') then
  begin
    WriteLn('No Linux as credenciais do S3 ficam em ' +
      '/etc/aguia/portalservice.env (AWS_ACCESS_KEY_ID e ' +
      'AWS_SECRET_ACCESS_KEY).');
    Halt(2);
  end;

  if Comando('/testar-upload-boleto') then
    Halt(TPortalBoletoUploadTest.Executar(Argumento));

  if Comando('/testar-geracao-boleto') then
    Halt(TPortalBoletoGenerateTest.Executar(Argumento));

  if Comando('/testar-geracao-boleto-fpdf') then
    Halt(TPortalBoletoGenerateTest.ExecutarFPDF(Argumento));

  if Comando('/testar-conexao') then
  begin
    CodigoSaida := TPortalClienteDiagnostics.Executar(Saida);
    Write(Saida);
    Halt(CodigoSaida);
  end;

  if Comando('/configurar') then
    Halt(TPortalClienteConfigurator.Executar);

  if Comando('/testar-clientes') then
    Halt(TPortalClientePreview.Executar);

  if Comando('/carregar-fila-clientes') then
    Halt(TPortalClienteQueueLoader.Executar);

  if Comando('/enviar-clientes') then
    Halt(TPortalClienteSender.Executar);

  if Comando('/testar-titulos') then
    Halt(TPortalTituloPreview.Executar);

  if Comando('/carregar-fila-titulos') then
    Halt(TPortalTituloQueueLoader.Executar);

  if Comando('/enviar-titulos') then
    Halt(TPortalTituloSender.Executar);

  if Comando('/diagnosticar-fila-titulos') then
    Halt(TPortalTituloQueueDiagnostics.Executar);

  if Comando('/executar-ciclo') then
    Halt(TPortalSyncOnce.Executar);

  { Sem parametro: daemon (systemd). }
  Halt(TPortalDaemon.Executar);
end.
