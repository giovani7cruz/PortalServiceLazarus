program TestesBase;

{ Testes sem banco nem rede: SHA-256/HMAC (vetores publicados), cifra do token
  (ida e volta, adulteracao, DPAPI recusado), JSON e conversao 1252.
  Compilar e rodar: tests/run-tests.sh }

{$mode delphi}

uses
  SysUtils, Classes,
  PortalCliente.Sha256,
  PortalCliente.TokenProtector,
  PortalCliente.Plataforma,
  PortalCliente.Json,
  fpjson;

var
  Falhas: Integer = 0;
  Total: Integer = 0;

procedure Confere(const ANome: string; const AObtido, AEsperado: string);
begin
  Inc(Total);
  if AObtido <> AEsperado then
  begin
    Inc(Falhas);
    WriteLn('FALHOU ', ANome, #10, '  esperado: ', AEsperado, #10,
      '  obtido:   ', AObtido);
  end;
end;

procedure ConfereTrue(const ANome: string; const ACondicao: Boolean);
begin
  Inc(Total);
  if not ACondicao then
  begin
    Inc(Falhas);
    WriteLn('FALHOU ', ANome);
  end;
end;

procedure TestarSha;
var
  Longo: string;
begin
  Confere('sha256 vazio',
    BytesParaHex(Sha256Bytes(TextoParaBytes(''))),
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
  Confere('sha256 abc',
    BytesParaHex(Sha256Bytes(TextoParaBytes('abc'))),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  Confere('sha256 448 bits',
    BytesParaHex(Sha256Bytes(TextoParaBytes(
      'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'))),
    '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1');
  Longo := StringOfChar('a', 1000000);
  Confere('sha256 1 milhao de a',
    BytesParaHex(Sha256Bytes(TextoParaBytes(Longo))),
    'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
  Confere('hmac key/fox',
    BytesParaHex(HmacSha256Bytes(
      TextoParaBytes('The quick brown fox jumps over the lazy dog'),
      TextoParaBytes('key'))),
    'f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8');
  { Chave maior que o bloco (RFC 4231, caso 6): 131 bytes $AA. }
  Confere('hmac chave longa',
    BytesParaHex(HmacSha256Bytes(
      TextoParaBytes('Test Using Larger Than Block-Size Key - Hash Key First'),
      TextoParaBytes(StringOfChar(#$AA, 131)))),
    '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54');
end;

procedure TestarToken;
var
  A, B, Sufixo: string;
begin
  A := TPortalTokenProtector.Proteger('token-secreto-123');
  B := TPortalTokenProtector.Proteger('token-secreto-123');
  ConfereTrue('prefixo L1', Copy(A, 1, 3) = 'L1:');
  ConfereTrue('nonce muda a cada vez', A <> B);
  Confere('ida e volta', TPortalTokenProtector.Desproteger(A),
    'token-secreto-123');
  Confere('vazio', TPortalTokenProtector.Desproteger(''), '');

  try
    TPortalTokenProtector.Desproteger('AQAAANCMnd8BFdERjHoAwE');
    ConfereTrue('dpapi deveria falhar', False);
  except
    on E: Exception do
      ConfereTrue('dpapi recusado', Pos('Windows', E.Message) > 0);
  end;

  { Adultera um caractere do corpo: a etiqueta tem que recusar. }
  Sufixo := A;
  if Sufixo[10] = 'A' then
    Sufixo[10] := 'B'
  else
    Sufixo[10] := 'A';
  try
    TPortalTokenProtector.Desproteger(Sufixo);
    ConfereTrue('adulterado deveria falhar', False);
  except
    on E: Exception do
      ConfereTrue('adulterado recusado', Pos('nao confere', E.Message) > 0);
  end;
end;

procedure TestarJson;
var
  Obj: TJSONObject;
  Lido: TJSONData;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('nome', 'Jose');
    Obj.AddPair('nulo', TJSONNull.Create);
    Obj.AddPair('valor', TJSONNumero(1234.56));
    Confere('json', Obj.ToJSON,
      '{ "nome" : "Jose", "nulo" : null, "valor" : 1234.56 }');
  finally
    Obj.Free;
  end;
  Lido := TJSONObject.ParseJSONValue('{"a":"x","b":null}');
  try
    Confere('texto a', (Lido as TJSONObject).GetValue('a').Texto, 'x');
    Confere('texto null', (Lido as TJSONObject).GetValue('b').Texto, '');
  finally
    Lido.Free;
  end;
  ConfereTrue('json invalido -> nil',
    TJSONObject.ParseJSONValue('{nao json') = nil);
end;

procedure TestarEncoding;
begin
  { 'Jos' + e agudo (0xE9) e 'EUR' (0x80) em 1252 -> UTF-8. }
  Confere('1252 e agudo',
    TPortalPlataforma.Cp1252ParaUtf8('Jos'#$E9), 'Jos'#$C3#$A9);
  Confere('1252 euro',
    TPortalPlataforma.Cp1252ParaUtf8(#$80), #$E2#$82#$AC);
  Confere('barras', TPortalPlataforma.NormalizarCaminho('..\..\x\y'),
    '../../x/y');
end;

begin
  DefaultFormatSettings.DecimalSeparator := '.';
  TestarSha;
  TestarToken;
  TestarJson;
  TestarEncoding;
  WriteLn(Total, ' verificacoes, ', Falhas, ' falha(s).');
  if Falhas > 0 then
    Halt(1);
end.
