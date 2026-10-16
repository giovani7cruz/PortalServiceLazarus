unit Aguia.Database.Config;

{$mode delphi}

interface

type
  TAguiaDatabaseConfig = record
    ServiceConfigFile: string;
    ServerConfigDir: string;
    ParamsFile: string;
  end;

  TAguiaDatabaseConfigLoader = class sealed
  private
    class function ResolverCaminho(const ABaseDir, ACaminho: string): string; static;
  public
    class function Carregar: TAguiaDatabaseConfig; static;
  end;

implementation

uses
  IniFiles,
  PortalCliente.IOUtils,
  SysUtils,
  PortalCliente.Plataforma;

class function TAguiaDatabaseConfigLoader.ResolverCaminho(
  const ABaseDir, ACaminho: string): string;
begin
  if TPath.IsPathRooted(ACaminho) then
    Result := TPath.GetFullPath(TPortalPlataforma.NormalizarCaminho(ACaminho))
  else
    Result := TPath.GetFullPath(TPath.Combine(ABaseDir,
      TPortalPlataforma.NormalizarCaminho(ACaminho)));
end;

class function TAguiaDatabaseConfigLoader.Carregar: TAguiaDatabaseConfig;
var
  AppDir: string;
  ConfigDir: string;
  ParamsFileName: string;
  Valor: string;
  Ini: TIniFile;
begin
  AppDir := ExcludeTrailingPathDelimiter(TPortalPlataforma.PastaApp);
  Result.ServiceConfigFile := TPath.Combine(AppDir, 'AguiaPortalService.ini');

  { O AguiaServer fica em Server\bin\Win32|Win64 e usa ..\.. para chegar
    ao diretorio que contem configFirebird.ini. }
  ConfigDir := TPath.GetFullPath(TPath.Combine(AppDir, '..' + PathDelim + '..'));
  ParamsFileName := 'configFirebird.ini';

  if TFile.Exists(Result.ServiceConfigFile) then
  begin
    Ini := TIniFile.Create(Result.ServiceConfigFile);
    try
      Valor := Ini.ReadString('AguiaServer', 'ConfigDir', '').Trim;
      if not Valor.IsEmpty then
        ConfigDir := Valor;

      Valor := Ini.ReadString('AguiaServer', 'ParamsFile', '').Trim;
      if not Valor.IsEmpty then
        ParamsFileName := Valor;
    finally
      Ini.Free;
    end;
  end;

  Result.ServerConfigDir := ResolverCaminho(AppDir, ConfigDir);
  Result.ParamsFile := ResolverCaminho(Result.ServerConfigDir, ParamsFileName);

  if not TFile.Exists(Result.ParamsFile) then
    raise Exception.CreateFmt('Arquivo de conexao do AguiaServer nao encontrado: %s',
      [Result.ParamsFile]);
end;

end.
