unit PortalCliente.TokenProtector;

{ Protecao do token do portal gravado em PORTAL_CONFIG.TOKEN_PROTEGIDO.

  Aqui nao ha DPAPI (Windows). O token e cifrado com uma chave aleatoria de
  32 bytes guardada ao lado do executavel (portalservice.key, modo 0600,
  gerada na primeira vez): fluxo de blocos HMAC-SHA256 em modo contador +
  etiqueta HMAC-SHA256 (cifra e depois autentica). Formato 'L1:' + base64 de
  nonce(16) + cifrado + etiqueta(32) - o mesmo do projeto Delphi/Linux, entao
  os dois executaveis leem o token um do outro quando usam a mesma chave. }

{$mode delphi}

interface

type
  TPortalTokenProtector = class sealed
  public
    class function Proteger(const AToken: string): string; static;
    class function Desproteger(const ATokenProtegido: string): string; static;
  end;

implementation

uses
  Classes, SysUtils, base64, BaseUnix,
  PortalCliente.IOUtils,
  PortalCliente.Plataforma,
  PortalCliente.Sha256;

const
  PREFIXO_LINUX = 'L1:';
  TAMANHO_NONCE = 16;
  TAMANHO_TAG = 32;
  ARQUIVO_CHAVE = 'portalservice.key';

function Aleatorio(const AQuantidade: Integer): TBytes;
var
  F: TFileStream;
begin
  SetLength(Result, AQuantidade);
  F := TFileStream.Create('/dev/urandom', fmOpenRead or fmShareDenyNone);
  try
    F.ReadBuffer(Result[0], AQuantidade);
  finally
    F.Free;
  end;
end;

function LerOuCriarChave(const ACriar: Boolean): TBytes;
var
  Arquivo: string;
begin
  Arquivo := TPortalPlataforma.PastaApp + ARQUIVO_CHAVE;
  if TFile.Exists(Arquivo) then
  begin
    Result := TFile.ReadAllBytes(Arquivo);
    if Length(Result) <> 32 then
      raise Exception.CreateFmt('Chave de protecao invalida: %s', [Arquivo]);
    Exit;
  end;
  if not ACriar then
    raise Exception.CreateFmt(
      'Chave de protecao do token nao encontrada: %s. Rode /configurar ' +
      'neste servidor.', [Arquivo]);

  Result := Aleatorio(32);
  TFile.WriteAllBytes(Arquivo, Result);
  FpChmod(Arquivo, S_IRUSR or S_IWUSR);
end;

function Subchave(const AChave: TBytes; const ARotulo: string): TBytes;
begin
  Result := HmacSha256Bytes(TextoParaBytes(ARotulo), AChave);
end;

function Mascara(const AChaveCifra, ANonce: TBytes;
  const ATamanho: Integer): TBytes;
var
  Bloco, Entrada: TBytes;
  Contador: LongWord;
  Copiar, Pos: Integer;
begin
  SetLength(Result, ATamanho);
  SetLength(Entrada, Length(ANonce) + 4);
  Move(ANonce[0], Entrada[0], Length(ANonce));
  Pos := 0;
  Contador := 0;
  while Pos < ATamanho do
  begin
    Entrada[Length(ANonce)] := Byte(Contador shr 24);
    Entrada[Length(ANonce) + 1] := Byte(Contador shr 16);
    Entrada[Length(ANonce) + 2] := Byte(Contador shr 8);
    Entrada[Length(ANonce) + 3] := Byte(Contador);
    Bloco := HmacSha256Bytes(Entrada, AChaveCifra);
    Copiar := ATamanho - Pos;
    if Copiar > Length(Bloco) then
      Copiar := Length(Bloco);
    Move(Bloco[0], Result[Pos], Copiar);
    Inc(Pos, Copiar);
    Inc(Contador);
  end;
end;

function Etiqueta(const AChaveMac, ANonce, ACifrado: TBytes): TBytes;
var
  Dados: TBytes;
begin
  SetLength(Dados, Length(ANonce) + Length(ACifrado));
  Move(ANonce[0], Dados[0], Length(ANonce));
  if Length(ACifrado) > 0 then
    Move(ACifrado[0], Dados[Length(ANonce)], Length(ACifrado));
  Result := HmacSha256Bytes(Dados, AChaveMac);
end;

function IguaisEmTempoConstante(const A, B: TBytes): Boolean;
var
  I: Integer;
  Dif: Byte;
begin
  if Length(A) <> Length(B) then
    Exit(False);
  Dif := 0;
  for I := 0 to High(A) do
    Dif := Dif or (A[I] xor B[I]);
  Result := Dif = 0;
end;

class function TPortalTokenProtector.Proteger(const AToken: string): string;
var
  Chave, ChaveCifra, ChaveMac, Claro, Cifrado, Nonce, Mask, Tag, Saida: TBytes;
  I: Integer;
  Texto: string;
begin
  if AToken = '' then
    raise EArgumentException.Create('O token nao pode ser vazio.');

  Chave := LerOuCriarChave(True);
  ChaveCifra := Subchave(Chave, 'cifra');
  ChaveMac := Subchave(Chave, 'mac');
  Nonce := Aleatorio(TAMANHO_NONCE);

  Claro := TextoParaBytes(AToken);
  Mask := Mascara(ChaveCifra, Nonce, Length(Claro));
  SetLength(Cifrado, Length(Claro));
  for I := 0 to High(Claro) do
    Cifrado[I] := Claro[I] xor Mask[I];
  Tag := Etiqueta(ChaveMac, Nonce, Cifrado);

  SetLength(Saida, TAMANHO_NONCE + Length(Cifrado) + TAMANHO_TAG);
  Move(Nonce[0], Saida[0], TAMANHO_NONCE);
  if Length(Cifrado) > 0 then
    Move(Cifrado[0], Saida[TAMANHO_NONCE], Length(Cifrado));
  Move(Tag[0], Saida[TAMANHO_NONCE + Length(Cifrado)], TAMANHO_TAG);
  SetLength(Texto, Length(Saida));
  Move(Saida[0], Texto[1], Length(Saida));
  Result := PREFIXO_LINUX + EncodeStringBase64(Texto);
end;

class function TPortalTokenProtector.Desproteger(
  const ATokenProtegido: string): string;
var
  Bruto, Chave, ChaveCifra, ChaveMac, Cifrado, Nonce, Mask, Claro, Tag: TBytes;
  TamanhoCifrado, I: Integer;
  Texto: string;
begin
  if Trim(ATokenProtegido) = '' then
    Exit('');
  if Copy(ATokenProtegido, 1, Length(PREFIXO_LINUX)) <> PREFIXO_LINUX then
    raise Exception.Create('O token foi protegido no Windows (DPAPI) e nao ' +
      'pode ser lido no Linux. Rode /configurar neste servidor e informe o ' +
      'token de novo.');

  Texto := DecodeStringBase64(Copy(ATokenProtegido,
    Length(PREFIXO_LINUX) + 1, MaxInt));
  Bruto := TextoParaBytes(Texto);
  if Length(Bruto) < TAMANHO_NONCE + TAMANHO_TAG + 1 then
    raise Exception.Create('Token protegido invalido.');

  Chave := LerOuCriarChave(False);
  ChaveCifra := Subchave(Chave, 'cifra');
  ChaveMac := Subchave(Chave, 'mac');

  TamanhoCifrado := Length(Bruto) - TAMANHO_NONCE - TAMANHO_TAG;
  SetLength(Nonce, TAMANHO_NONCE);
  Move(Bruto[0], Nonce[0], TAMANHO_NONCE);
  SetLength(Cifrado, TamanhoCifrado);
  Move(Bruto[TAMANHO_NONCE], Cifrado[0], TamanhoCifrado);
  SetLength(Tag, TAMANHO_TAG);
  Move(Bruto[TAMANHO_NONCE + TamanhoCifrado], Tag[0], TAMANHO_TAG);

  if not IguaisEmTempoConstante(Etiqueta(ChaveMac, Nonce, Cifrado), Tag) then
    raise Exception.Create('Token protegido nao confere com a chave deste ' +
      'servidor (portalservice.key). Rode /configurar de novo.');

  Mask := Mascara(ChaveCifra, Nonce, TamanhoCifrado);
  SetLength(Claro, TamanhoCifrado);
  for I := 0 to TamanhoCifrado - 1 do
    Claro[I] := Cifrado[I] xor Mask[I];
  SetLength(Result, TamanhoCifrado);
  if TamanhoCifrado > 0 then
    Move(Claro[0], Result[1], TamanhoCifrado);
end;

end.
