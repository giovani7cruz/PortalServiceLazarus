unit PortalCliente.S3;

{ Upload (PUT) de objeto no S3 com assinatura AWS Signature V4. }

{$mode delphi}

interface

uses
  Classes, SysUtils,
  PortalCliente.S3.Config;

type
  EPortalS3 = class(Exception)
  private
    FHTTPStatus: Integer;
    FResponseBody: string;
  public
    constructor Create(const AHTTPStatus: Integer;
      const AMensagem, AResponseBody: string);
    property HTTPStatus: Integer read FHTTPStatus;
    property ResponseBody: string read FResponseBody;
  end;

  TPortalS3UploadResult = record
    ObjectKey: string;
    ETag: string;
    VersionId: string;
  end;

  TPortalS3 = class sealed
  private
    FConfig: TPortalS3Config;
    class function UriEncode(const AValue: string;
      const AEncodeSlash: Boolean): string; static;
    class function NormalizarObjectKey(const AObjectKey: string): string; static;
    function Assinatura(const AObjectKey, APayloadHash, AAmzDate,
      ADateStamp: string; out AAuthorization, ASignedHeaders,
      ACanonicalURI: string): string;
  public
    constructor Create(const AConfig: TPortalS3Config);
    function UploadS3(AConteudo: TStream; const AObjectKey: string;
      const AContentType: string = 'application/pdf'): TPortalS3UploadResult;
  end;

implementation

uses
  DateUtils,
  PortalCliente.Http,
  PortalCliente.Sha256;

constructor EPortalS3.Create(const AHTTPStatus: Integer;
  const AMensagem, AResponseBody: string);
begin
  inherited Create(AMensagem);
  FHTTPStatus := AHTTPStatus;
  FResponseBody := AResponseBody;
end;

constructor TPortalS3.Create(const AConfig: TPortalS3Config);
begin
  inherited Create;
  FConfig := AConfig;
end;

class function TPortalS3.UriEncode(const AValue: string;
  const AEncodeSlash: Boolean): string;
const
  HEX: array[0..15] of Char = '0123456789ABCDEF';
var
  I: Integer;
  B: Byte;
begin
  Result := '';
  for I := 1 to Length(AValue) do
  begin
    B := Byte(AValue[I]);
    if ((B >= Ord('A')) and (B <= Ord('Z'))) or
       ((B >= Ord('a')) and (B <= Ord('z'))) or
       ((B >= Ord('0')) and (B <= Ord('9'))) or
       (Char(B) in ['-', '_', '.', '~']) or
       ((B = Ord('/')) and not AEncodeSlash) then
      Result := Result + Char(B)
    else
      Result := Result + '%' + HEX[B shr 4] + HEX[B and $0F];
  end;
end;

class function TPortalS3.NormalizarObjectKey(
  const AObjectKey: string): string;
begin
  Result := StringReplace(Trim(AObjectKey), '\', '/', [rfReplaceAll]);
  while (Result <> '') and (Result[1] = '/') do
    Delete(Result, 1, 1);
  if Result = '' then
    raise EArgumentException.Create('Object Key S3 nao informado.');
  if Pos('//', Result) > 0 then
    raise EArgumentException.Create('Object Key S3 contem segmento vazio.');
  if Result[Length(Result)] = '/' then
    raise EArgumentException.Create('Object Key S3 nao pode terminar com barra.');
end;

function TPortalS3.Assinatura(const AObjectKey, APayloadHash, AAmzDate,
  ADateStamp: string; out AAuthorization, ASignedHeaders,
  ACanonicalURI: string): string;
var
  CanonicalHeaders: string;
  CanonicalRequest: string;
  CredentialScope: string;
  Host: string;
  KDate, KRegion, KService, KSigning: TBytes;
  StringToSign: string;
begin
  Host := FConfig.Bucket + '.s3.' + FConfig.Region + '.amazonaws.com';
  ACanonicalURI := '/' + UriEncode(AObjectKey, False);
  CanonicalHeaders :=
    'host:' + Host + #10 +
    'x-amz-content-sha256:' + APayloadHash + #10 +
    'x-amz-date:' + AAmzDate + #10;
  ASignedHeaders := 'host;x-amz-content-sha256;x-amz-date';

  if FConfig.SessionToken <> '' then
  begin
    CanonicalHeaders := CanonicalHeaders +
      'x-amz-security-token:' + FConfig.SessionToken + #10;
    ASignedHeaders := ASignedHeaders + ';x-amz-security-token';
  end;

  CanonicalRequest :=
    'PUT' + #10 +
    ACanonicalURI + #10 +
    '' + #10 +
    CanonicalHeaders + #10 +
    ASignedHeaders + #10 +
    APayloadHash;
  CredentialScope := ADateStamp + '/' + FConfig.Region + '/s3/aws4_request';
  StringToSign :=
    'AWS4-HMAC-SHA256' + #10 +
    AAmzDate + #10 +
    CredentialScope + #10 +
    BytesParaHex(Sha256Bytes(TextoParaBytes(CanonicalRequest)));

  KDate := HmacSha256Bytes(TextoParaBytes(ADateStamp),
    TextoParaBytes('AWS4' + FConfig.SecretAccessKey));
  KRegion := HmacSha256Bytes(TextoParaBytes(FConfig.Region), KDate);
  KService := HmacSha256Bytes(TextoParaBytes('s3'), KRegion);
  KSigning := HmacSha256Bytes(TextoParaBytes('aws4_request'), KService);
  Result := BytesParaHex(HmacSha256Bytes(TextoParaBytes(StringToSign),
    KSigning));

  AAuthorization :=
    'AWS4-HMAC-SHA256 Credential=' + FConfig.AccessKeyId + '/' +
    CredentialScope + ', SignedHeaders=' + ASignedHeaders +
    ', Signature=' + Result;
end;

function TPortalS3.UploadS3(AConteudo: TStream; const AObjectKey,
  AContentType: string): TPortalS3UploadResult;
var
  AmzDate: string;
  Authorization: string;
  CanonicalURI: string;
  Content: TBytes;
  ContentStream: TBytesStream;
  DateStamp: string;
  Host: string;
  Http: TPortalHttp;
  Key: string;
  OriginalPosition: Int64;
  PayloadHash: string;
  Resposta: TPortalHttpResposta;
  SignedHeaders: string;
  UtcNow: TDateTime;
  URL: string;
begin
  Result := Default(TPortalS3UploadResult);
  if not Assigned(AConteudo) then
    raise EArgumentNilException.Create('AConteudo');

  Key := NormalizarObjectKey(AObjectKey);
  OriginalPosition := AConteudo.Position;
  try
    SetLength(Content, AConteudo.Size - AConteudo.Position);
    if Length(Content) > 0 then
      AConteudo.ReadBuffer(Content[0], Length(Content));
  finally
    AConteudo.Position := OriginalPosition;
  end;
  if Length(Content) = 0 then
    raise EArgumentException.Create('Conteudo vazio para upload S3.');

  PayloadHash := BytesParaHex(Sha256Bytes(Content));
  UtcNow := LocalTimeToUniversal(Now);
  DateStamp := FormatDateTime('yyyymmdd', UtcNow);
  AmzDate := FormatDateTime('yyyymmdd"T"hhnnss"Z"', UtcNow);
  Assinatura(Key, PayloadHash, AmzDate, DateStamp, Authorization,
    SignedHeaders, CanonicalURI);

  Host := FConfig.Bucket + '.s3.' + FConfig.Region + '.amazonaws.com';
  URL := 'https://' + Host + CanonicalURI;

  Http := TPortalHttp.Create;
  ContentStream := TBytesStream.Create(Content);
  try
    Http.TimeoutMs := FConfig.TimeoutMs;
    Http.AdicionarCabecalho('Authorization', Authorization);
    Http.AdicionarCabecalho('Content-Type', AContentType);
    Http.AdicionarCabecalho('x-amz-content-sha256', PayloadHash);
    Http.AdicionarCabecalho('x-amz-date', AmzDate);
    if FConfig.SessionToken <> '' then
      Http.AdicionarCabecalho('x-amz-security-token', FConfig.SessionToken);
    try
      Resposta := Http.Put(URL, ContentStream);
    except
      on E: Exception do
        raise EPortalS3.Create(0, 'Falha de comunicacao com o S3: ' +
          E.Message, '');
    end;
  finally
    ContentStream.Free;
    Http.Free;
  end;

  if (Resposta.Status < 200) or (Resposta.Status >= 300) then
    raise EPortalS3.Create(Resposta.Status,
      Format('S3 devolveu HTTP %d: %s', [Resposta.Status, Resposta.Texto]),
      Resposta.Corpo);

  Result.ObjectKey := Key;
  Result.ETag := StringReplace(Resposta.ETag, '"', '', [rfReplaceAll]);
  Result.VersionId := Resposta.VersionId;
end;

end.
