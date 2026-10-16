unit Aguia.Database;

{ Conexao com o Firebird a partir do configFirebird.ini do AguiaServer (mesmo
  arquivo, ANSI 1252, senha embaralhada: cada byte + 118). }

{$mode delphi}

interface

uses
  Classes, SysUtils,
  PortalCliente.Db,
  Aguia.Database.Config;

type
  TAguiaDatabase = class sealed
  private
    const CHAVE_CONFIG_AGUIA = 118;
    class function Desembaralhar(const ABytes: RawByteString): string; static;
  public
    class function AbrirConexao(
      const AConfig: TAguiaDatabaseConfig): TPortalConexao; static;
  end;

implementation

uses
  PortalCliente.Plataforma;

class function TAguiaDatabase.Desembaralhar(
  const ABytes: RawByteString): string;
var
  I, V: Integer;
  Claro: RawByteString;
begin
  if (Trim(ABytes) = '') or SameText(ABytes, 'masterkey') then
    Exit(string(ABytes));

  { Fora de 32..254 conta como 255, como no Rule.ServidorUtil do servidor. }
  SetLength(Claro, Length(ABytes));
  for I := 1 to Length(ABytes) do
  begin
    V := Byte(ABytes[I]);
    if (V < 32) or (V > 254) then
      V := 255;
    Claro[I] := Chr((V - CHAVE_CONFIG_AGUIA) and $FF);
  end;
  Result := TPortalPlataforma.Cp1252ParaUtf8(Claro);
end;

class function TAguiaDatabase.AbrirConexao(
  const AConfig: TAguiaDatabaseConfig): TPortalConexao;
var
  Bruto: RawByteString;
  Linhas: TStringList;
  Params: TStringList;
  I, P: Integer;
  Chave, Valor: RawByteString;
begin
  Params := TStringList.Create;
  Linhas := TStringList.Create;
  Result := TPortalConexao.Create;
  try
    Bruto := TPortalPlataforma.LerBytes(AConfig.ParamsFile);
    Linhas.Text := Bruto;
    for I := 0 to Linhas.Count - 1 do
    begin
      P := Pos('=', Linhas[I]);
      if P < 2 then
        Continue;
      Chave := Trim(Copy(Linhas[I], 1, P - 1));
      Valor := Copy(Linhas[I], P + 1, MaxInt);
      if SameText(Chave, 'Password') then
        Params.Values['Password'] := Desembaralhar(Valor)
      else
        Params.Values[Chave] := TPortalPlataforma.Cp1252ParaUtf8(Valor);
    end;
    Result.Abrir(Params);
  except
    Result.Free;
    raise;
  end;
  Linhas.Free;
  Params.Free;
end;

end.
