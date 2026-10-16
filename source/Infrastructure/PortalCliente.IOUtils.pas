unit PortalCliente.IOUtils;

{ TPath, TFile e TDirectory com os nomes e o comportamento que o PortalService
  usa do System.IOUtils do Delphi (o FPC 3.2.2 nao tem). }

{$mode delphi}

interface

uses
  Classes, SysUtils;

type
  TPath = class sealed
  public
    class function Combine(const A, B: string): string; static;
    class function GetFullPath(const ACaminho: string): string; static;
    class function IsPathRooted(const ACaminho: string): Boolean; static;
    class function GetTempPath: string; static;
  end;

  TFile = class sealed
  public
    class function Exists(const AArquivo: string): Boolean; static;
    class function ReadAllBytes(const AArquivo: string): TBytes; static;
    class procedure WriteAllBytes(const AArquivo: string;
      const ABytes: TBytes); static;
    class procedure AppendAllText(const AArquivo, ATexto: string); static;
    class function GetLastWriteTimeUtc(const AArquivo: string): TDateTime; static;
  end;

  TDirectory = class sealed
  public
    class function Exists(const APasta: string): Boolean; static;
  end;

implementation

class function TPath.Combine(const A, B: string): string;
begin
  if B = '' then
    Exit(A);
  if (A = '') or IsPathRooted(B) then
    Exit(B);
  Result := IncludeTrailingPathDelimiter(A) + B;
end;

class function TPath.GetFullPath(const ACaminho: string): string;
begin
  Result := ExpandFileName(ACaminho);
end;

class function TPath.IsPathRooted(const ACaminho: string): Boolean;
begin
  Result := (ACaminho <> '') and (ACaminho[1] = PathDelim);
end;

class function TPath.GetTempPath: string;
begin
  Result := GetTempDir(False);
end;

class function TFile.Exists(const AArquivo: string): Boolean;
begin
  Result := FileExists(AArquivo);
end;

class function TFile.ReadAllBytes(const AArquivo: string): TBytes;
var
  F: TFileStream;
begin
  F := TFileStream.Create(AArquivo, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if Length(Result) > 0 then
      F.ReadBuffer(Result[0], Length(Result));
  finally
    F.Free;
  end;
end;

class procedure TFile.WriteAllBytes(const AArquivo: string;
  const ABytes: TBytes);
var
  F: TFileStream;
begin
  F := TFileStream.Create(AArquivo, fmCreate);
  try
    if Length(ABytes) > 0 then
      F.WriteBuffer(ABytes[0], Length(ABytes));
  finally
    F.Free;
  end;
end;

class procedure TFile.AppendAllText(const AArquivo, ATexto: string);
var
  F: TFileStream;
  Modo: Word;
begin
  Modo := fmOpenWrite or fmShareDenyNone;
  if not FileExists(AArquivo) then
    Modo := fmCreate;
  F := TFileStream.Create(AArquivo, Modo);
  try
    F.Seek(0, soEnd);
    if ATexto <> '' then
      F.WriteBuffer(ATexto[1], Length(ATexto));
  finally
    F.Free;
  end;
end;

class function TFile.GetLastWriteTimeUtc(const AArquivo: string): TDateTime;
begin
  Result := FileDateToDateTime(FileAge(AArquivo));
end;

class function TDirectory.Exists(const APasta: string): Boolean;
begin
  Result := DirectoryExists(APasta);
end;

end.
