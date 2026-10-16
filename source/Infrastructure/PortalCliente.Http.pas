unit PortalCliente.Http;

{ Cliente HTTP(S) minimo sobre o Synapse (httpsend) com TLS pelo OpenSSL 3
  (ssl_openssl3): o openssl do FPC 3.2.2 nao carrega a libssl.so.3 dos Linux
  atuais ("Could not initialize OpenSSL library"). O que o PortalService
  precisa do THTTPClient do Delphi: GET, POST e PUT com cabecalhos, timeout,
  status e corpo. Qualquer status volta ao chamador; so falha de comunicacao
  vira excecao. }

{$mode delphi}

interface

uses
  Classes, SysUtils;

type
  TPortalHttpResposta = record
    Status: Integer;
    Texto: string;
    Corpo: string;
    ETag: string;
    VersionId: string;
  end;

  TPortalHttp = class
  private
    FTimeoutMs: Integer;
    FUserAgent: string;
    FCabecalhos: TStringList;
    function Executar(const AMetodo, AUrl: string;
      ACorpo: TStream): TPortalHttpResposta;
  public
    constructor Create;
    destructor Destroy; override;
    procedure LimparCabecalhos;
    procedure AdicionarCabecalho(const ANome, AValor: string);
    function Get(const AUrl: string): TPortalHttpResposta;
    function Post(const AUrl: string; ACorpo: TStream): TPortalHttpResposta;
    function Put(const AUrl: string; ACorpo: TStream): TPortalHttpResposta;
    property TimeoutMs: Integer read FTimeoutMs write FTimeoutMs;
    property UserAgent: string read FUserAgent write FUserAgent;
  end;

{ Codificacao de percentual (RFC 3986), UTF-8. }
function UrlCodificar(const AValor: string): string;

implementation

uses
  blcksock, httpsend, ssl_openssl3;

function UrlCodificar(const AValor: string): string;
const
  HEX: array[0..15] of Char = '0123456789ABCDEF';
var
  I: Integer;
  B: Byte;
begin
  Result := '';
  for I := 1 to Length(AValor) do
  begin
    B := Byte(AValor[I]);
    if ((B >= Ord('A')) and (B <= Ord('Z'))) or
       ((B >= Ord('a')) and (B <= Ord('z'))) or
       ((B >= Ord('0')) and (B <= Ord('9'))) or
       (B in [Ord('-'), Ord('_'), Ord('.'), Ord('~')]) then
      Result := Result + Chr(B)
    else
      Result := Result + '%' + HEX[B shr 4] + HEX[B and $0F];
  end;
end;

constructor TPortalHttp.Create;
begin
  inherited Create;
  FCabecalhos := TStringList.Create;
  FTimeoutMs := 60000;
  FUserAgent := 'AguiaPortalService/1.0';
end;

destructor TPortalHttp.Destroy;
begin
  FCabecalhos.Free;
  inherited;
end;

procedure TPortalHttp.LimparCabecalhos;
begin
  FCabecalhos.Clear;
end;

procedure TPortalHttp.AdicionarCabecalho(const ANome, AValor: string);
begin
  FCabecalhos.Add(ANome + ': ' + AValor);
end;

function TPortalHttp.Executar(const AMetodo, AUrl: string;
  ACorpo: TStream): TPortalHttpResposta;
var
  Http: THTTPSend;
  I, P: Integer;
  Linha, Nome, Valor: string;
begin
  Result := Default(TPortalHttpResposta);
  { O Synapse escolhe o plugin de TLS por esta variavel global; outras units
    do ACBr podem ter registrado outro. }
  SSLImplementation := TSSLOpenSSL3;

  Http := THTTPSend.Create;
  try
    Http.Timeout := FTimeoutMs;
    Http.UserAgent := FUserAgent;
    Http.Protocol := '1.1';
    Http.Headers.Clear;
    for I := 0 to FCabecalhos.Count - 1 do
    begin
      Linha := FCabecalhos[I];
      P := Pos(': ', Linha);
      if P = 0 then
        Continue;
      Nome := Copy(Linha, 1, P - 1);
      Valor := Copy(Linha, P + 2, MaxInt);
      if SameText(Nome, 'Content-Type') then
        Http.MimeType := Valor
      else
        Http.Headers.Add(Nome + ': ' + Valor);
    end;
    if ACorpo <> nil then
    begin
      ACorpo.Position := 0;
      Http.Document.CopyFrom(ACorpo, 0);
      Http.Document.Position := 0;
    end;

    if not Http.HTTPMethod(AMetodo, AUrl) then
      raise Exception.CreateFmt('Falha de conexao com %s (%s)',
        [AUrl, Http.Sock.LastErrorDesc]);

    Result.Status := Http.ResultCode;
    Result.Texto := Http.ResultString;
    SetLength(Result.Corpo, Http.Document.Size);
    if Http.Document.Size > 0 then
    begin
      Http.Document.Position := 0;
      Http.Document.ReadBuffer(Result.Corpo[1], Http.Document.Size);
    end;
    for I := 0 to Http.Headers.Count - 1 do
    begin
      Linha := Http.Headers[I];
      P := Pos(':', Linha);
      if P = 0 then
        Continue;
      Nome := Trim(Copy(Linha, 1, P - 1));
      Valor := Trim(Copy(Linha, P + 1, MaxInt));
      if SameText(Nome, 'ETag') then
        Result.ETag := Valor
      else if SameText(Nome, 'x-amz-version-id') then
        Result.VersionId := Valor;
    end;
  finally
    Http.Free;
  end;
end;

function TPortalHttp.Get(const AUrl: string): TPortalHttpResposta;
begin
  Result := Executar('GET', AUrl, nil);
end;

function TPortalHttp.Post(const AUrl: string;
  ACorpo: TStream): TPortalHttpResposta;
begin
  Result := Executar('POST', AUrl, ACorpo);
end;

function TPortalHttp.Put(const AUrl: string;
  ACorpo: TStream): TPortalHttpResposta;
begin
  Result := Executar('PUT', AUrl, ACorpo);
end;

end.
