unit PortalCliente.Sha256;

{ SHA-256 (FIPS 180-4) e HMAC-SHA256 (RFC 2104), sem dependencia externa:
  usados pela assinatura SigV4 do S3 e pela cifra do token. }

{$mode delphi}
{$R-}{$Q-}

interface

uses
  SysUtils;

function Sha256Bytes(const ADados: TBytes): TBytes;
function HmacSha256Bytes(const ADados, AChave: TBytes): TBytes;
function BytesParaHex(const ADados: TBytes): string;
function TextoParaBytes(const ATexto: string): TBytes;

implementation

const
  K: array[0..63] of LongWord = (
    $428a2f98, $71374491, $b5c0fbcf, $e9b5dba5, $3956c25b, $59f111f1,
    $923f82a4, $ab1c5ed5, $d807aa98, $12835b01, $243185be, $550c7dc3,
    $72be5d74, $80deb1fe, $9bdc06a7, $c19bf174, $e49b69c1, $efbe4786,
    $0fc19dc6, $240ca1cc, $2de92c6f, $4a7484aa, $5cb0a9dc, $76f988da,
    $983e5152, $a831c66d, $b00327c8, $bf597fc7, $c6e00bf3, $d5a79147,
    $06ca6351, $14292967, $27b70a85, $2e1b2138, $4d2c6dfc, $53380d13,
    $650a7354, $766a0abb, $81c2c92e, $92722c85, $a2bfe8a1, $a81a664b,
    $c24b8b70, $c76c51a3, $d192e819, $d6990624, $f40e3585, $106aa070,
    $19a4c116, $1e376c08, $2748774c, $34b0bcb5, $391c0cb3, $4ed8aa4a,
    $5b9cca4f, $682e6ff3, $748f82ee, $78a5636f, $84c87814, $8cc70208,
    $90befffa, $a4506ceb, $bef9a3f7, $c67178f2);

function Ror(X: LongWord; N: Integer): LongWord; inline;
begin
  Result := (X shr N) or (X shl (32 - N));
end;

function Sha256Bytes(const ADados: TBytes): TBytes;
var
  H: array[0..7] of LongWord;
  W: array[0..63] of LongWord;
  Bloco: TBytes;
  TotalBits: QWord;
  Tam, Preenchido, Off, I, J: Integer;
  A, B, C, D, E, F, G, HH, T1, T2, S0, S1: LongWord;
begin
  H[0] := $6a09e667; H[1] := $bb67ae85; H[2] := $3c6ef372; H[3] := $a54ff53a;
  H[4] := $510e527f; H[5] := $9b05688c; H[6] := $1f83d9ab; H[7] := $5be0cd19;

  Tam := Length(ADados);
  TotalBits := QWord(Tam) * 8;
  Preenchido := ((Tam + 8) div 64 + 1) * 64;
  SetLength(Bloco, Preenchido);
  if Tam > 0 then
    Move(ADados[0], Bloco[0], Tam);
  Bloco[Tam] := $80;
  for I := 0 to 7 do
    Bloco[Preenchido - 1 - I] := Byte(TotalBits shr (8 * I));

  Off := 0;
  while Off < Preenchido do
  begin
    for I := 0 to 15 do
      W[I] := (LongWord(Bloco[Off + I * 4]) shl 24) or
        (LongWord(Bloco[Off + I * 4 + 1]) shl 16) or
        (LongWord(Bloco[Off + I * 4 + 2]) shl 8) or
        LongWord(Bloco[Off + I * 4 + 3]);
    for I := 16 to 63 do
    begin
      S0 := Ror(W[I - 15], 7) xor Ror(W[I - 15], 18) xor (W[I - 15] shr 3);
      S1 := Ror(W[I - 2], 17) xor Ror(W[I - 2], 19) xor (W[I - 2] shr 10);
      W[I] := W[I - 16] + S0 + W[I - 7] + S1;
    end;
    A := H[0]; B := H[1]; C := H[2]; D := H[3];
    E := H[4]; F := H[5]; G := H[6]; HH := H[7];
    for I := 0 to 63 do
    begin
      S1 := Ror(E, 6) xor Ror(E, 11) xor Ror(E, 25);
      T1 := HH + S1 + ((E and F) xor ((not E) and G)) + K[I] + W[I];
      S0 := Ror(A, 2) xor Ror(A, 13) xor Ror(A, 22);
      T2 := S0 + ((A and B) xor (A and C) xor (B and C));
      HH := G; G := F; F := E; E := D + T1;
      D := C; C := B; B := A; A := T1 + T2;
    end;
    H[0] := H[0] + A; H[1] := H[1] + B; H[2] := H[2] + C; H[3] := H[3] + D;
    H[4] := H[4] + E; H[5] := H[5] + F; H[6] := H[6] + G; H[7] := H[7] + HH;
    Inc(Off, 64);
  end;

  SetLength(Result, 32);
  for I := 0 to 7 do
    for J := 0 to 3 do
      Result[I * 4 + J] := Byte(H[I] shr (24 - 8 * J));
end;

function HmacSha256Bytes(const ADados, AChave: TBytes): TBytes;
var
  Chave, IPad, OPad, Interno: TBytes;
  I, N: Integer;
begin
  Chave := AChave;
  if Length(Chave) > 64 then
    Chave := Sha256Bytes(Chave);
  N := Length(Chave);
  SetLength(Chave, 64);
  for I := N to 63 do
    Chave[I] := 0;
  SetLength(IPad, 64 + Length(ADados));
  SetLength(OPad, 64 + 32);
  for I := 0 to 63 do
  begin
    IPad[I] := Chave[I] xor $36;
    OPad[I] := Chave[I] xor $5C;
  end;
  if Length(ADados) > 0 then
    Move(ADados[0], IPad[64], Length(ADados));
  Interno := Sha256Bytes(IPad);
  Move(Interno[0], OPad[64], 32);
  Result := Sha256Bytes(OPad);
end;

function BytesParaHex(const ADados: TBytes): string;
const
  HEX: array[0..15] of Char = '0123456789abcdef';
var
  I: Integer;
begin
  SetLength(Result, Length(ADados) * 2);
  for I := 0 to High(ADados) do
  begin
    Result[I * 2 + 1] := HEX[ADados[I] shr 4];
    Result[I * 2 + 2] := HEX[ADados[I] and $0F];
  end;
end;

function TextoParaBytes(const ATexto: string): TBytes;
begin
  SetLength(Result, Length(ATexto));
  if Length(ATexto) > 0 then
    Move(ATexto[1], Result[0], Length(ATexto));
end;

end.
