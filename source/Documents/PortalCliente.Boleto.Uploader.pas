unit PortalCliente.Boleto.Uploader;

{$mode delphi}

interface

uses
  PortalCliente.Db,
  PortalCliente.Boleto.Generator,
  PortalCliente.Queue.Repository,
  PortalCliente.S3,
  PortalCliente.S3.Config;

type
  TPortalBoletoEnvioResultado = record
    ObjectKey: string;
    ETag: string;
    VersionId: string;
    FilaAcao: TPortalFilaAcao;
  end;

  TPortalBoletoUploader = class sealed
  private
    FConnection: TPortalConexao;
    FGenerator: TPortalBoletoGenerator;
    FQueue: TPortalFilaRepository;
    FS3: TPortalS3;
  public
    constructor Create(AConnection: TPortalConexao;
      const ABoletoConfig: TPortalBoletoRenderConfig;
      const AS3Config: TPortalS3Config);
    destructor Destroy; override;
    function Enviar(const AContaReceberId: Integer):
      TPortalBoletoEnvioResultado;
  end;

implementation

uses
  Classes,
  fpjson, jsonparser, PortalCliente.Json,
  SysUtils,
  PortalCliente.Boleto.ObjectKey,
  PortalCliente.Boleto.Repository,
  PortalCliente.DTO,
  PortalCliente.Title.Mapper;

constructor TPortalBoletoUploader.Create(AConnection: TPortalConexao;
  const ABoletoConfig: TPortalBoletoRenderConfig;
  const AS3Config: TPortalS3Config);
begin
  inherited Create;
  if not Assigned(AConnection) then
    raise EArgumentNilException.Create('AConnection');
  FConnection := AConnection;
  FGenerator := TPortalBoletoGenerator.Create(ABoletoConfig);
  FQueue := TPortalFilaRepository.Create(AConnection);
  FS3 := TPortalS3.Create(AS3Config);
end;

destructor TPortalBoletoUploader.Destroy;
begin
  FS3.Free;
  FQueue.Free;
  FGenerator.Free;
  inherited;
end;

function TPortalBoletoUploader.Enviar(
  const AContaReceberId: Integer): TPortalBoletoEnvioResultado;
var
  IDExterno: string;
  Identificacao: TPortalBoletoIdentificacao;
  IniciouTransacao: Boolean;
  JSON: TJSONObject;
  Payload: string;
  PDF: TMemoryStream;
  Titulo: TPortalTituloEnvio;
  Upload: TPortalS3UploadResult;
begin
  Result := Default(TPortalBoletoEnvioResultado);
  Identificacao := TPortalBoletoRepository.CarregarIdentificacao(
    FConnection, AContaReceberId);
  Result.ObjectKey := TPortalBoletoObjectKey.Montar(Identificacao);

  { Validar a fila antes do PutObject evita criar objetos sem titulo associado. }
  if not FQueue.TentarObterTitulo(Identificacao.EmpresaId,
    AContaReceberId, IDExterno, Payload) then
    raise Exception.CreateFmt(
      'Titulo %d nao existe em PORTAL_SYNC_FILA. Carregue a fila de titulos primeiro.',
      [AContaReceberId]);

  PDF := TMemoryStream.Create;
  try
    FGenerator.GerarPDF(FConnection, AContaReceberId, PDF);
    Upload := FS3.UploadS3(PDF, Result.ObjectKey, 'application/pdf');
  finally
    PDF.Free;
  end;
  Result.ETag := Upload.ETag;
  Result.VersionId := Upload.VersionId;

  Titulo := TPortalTituloMapper.DoJSON(Payload);
  Titulo.BoletoChaveS3 := Result.ObjectKey;
  JSON := TPortalTituloMapper.ParaJSON(Titulo);
  try
    Payload := JSON.ToJSON;
  finally
    JSON.Free;
  end;

  IniciouTransacao := not FConnection.InTransaction;
  if IniciouTransacao then
    FConnection.StartTransaction;
  try
    Result.FilaAcao := FQueue.SalvarTitulo(Identificacao.EmpresaId,
      AContaReceberId, IDExterno, Payload, '', True);
    if IniciouTransacao then
      FConnection.Commit;
  except
    if IniciouTransacao and FConnection.InTransaction then
      FConnection.Rollback;
    raise;
  end;
end;

end.
