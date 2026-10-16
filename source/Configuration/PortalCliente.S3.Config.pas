unit PortalCliente.S3.Config;

{$mode delphi}

interface

type
  TPortalS3Config = record
    Bucket: string;
    Region: string;
    AccessKeyId: string;
    SecretAccessKey: string;
    SessionToken: string;
    TimeoutMs: Integer;
  end;

  TPortalS3ConfigLoader = class sealed
  public
    class function Carregar(
      const AServiceConfigFile: string): TPortalS3Config; static;
  end;

implementation

uses
  Classes,
  IniFiles,
  SysUtils,
  PortalCliente.IOUtils;

const
  ARQUIVO_AMBIENTE = '/etc/aguia/portalservice.env';

{ Le CHAVE=valor do arquivo de ambiente (o mesmo EnvironmentFile do systemd).
  Os comandos manuais (sudo -u aguia ...) nao herdam o ambiente do servico. }
function ValorDoArquivo(const AArquivo, ANome: string): string;
var
  Linhas: TStringList;
  I, P: Integer;
  Linha: string;
begin
  Result := '';
  if (AArquivo = '') or not FileExists(AArquivo) then
    Exit;
  Linhas := TStringList.Create;
  try
    try
      Linhas.LoadFromFile(AArquivo);
    except
      Exit;
    end;
    for I := 0 to Linhas.Count - 1 do
    begin
      Linha := Trim(Linhas[I]);
      if (Linha = '') or (Linha[1] = '#') then
        Continue;
      P := Pos('=', Linha);
      if (P > 1) and SameText(Trim(Copy(Linha, 1, P - 1)), ANome) then
        Exit(Trim(Copy(Linha, P + 1, MaxInt)));
    end;
  finally
    Linhas.Free;
  end;
end;

class function TPortalS3ConfigLoader.Carregar(
  const AServiceConfigFile: string): TPortalS3Config;
var
  AccessKeyEnv: string;
  SecretKeyEnv: string;
  SessionTokenEnv: string;
  Ini: TIniFile;
begin
  Result := Default(TPortalS3Config);
  Result.Bucket := 'portal-cliente-infus';
  Result.Region := 'sa-east-1';
  Result.TimeoutMs := 60000;
  AccessKeyEnv := 'AWS_ACCESS_KEY_ID';
  SecretKeyEnv := 'AWS_SECRET_ACCESS_KEY';
  SessionTokenEnv := 'AWS_SESSION_TOKEN';

  if TFile.Exists(AServiceConfigFile) then
  begin
    Ini := TIniFile.Create(AServiceConfigFile);
    try
      Result.Bucket := Trim(Ini.ReadString('S3', 'Bucket', Result.Bucket));
      Result.Region := Trim(Ini.ReadString('S3', 'Region', Result.Region));
      Result.TimeoutMs := Ini.ReadInteger('S3', 'TimeoutMs', Result.TimeoutMs);
      AccessKeyEnv := Trim(Ini.ReadString('S3', 'AccessKeyEnvironmentVariable',
        AccessKeyEnv));
      SecretKeyEnv := Trim(Ini.ReadString('S3', 'SecretKeyEnvironmentVariable',
        SecretKeyEnv));
      SessionTokenEnv := Trim(Ini.ReadString('S3',
        'SessionTokenEnvironmentVariable', SessionTokenEnv));
    finally
      Ini.Free;
    end;
  end;

  if Result.Bucket = '' then
    raise Exception.Create('Bucket S3 nao informado.');
  if Result.Region = '' then
    raise Exception.Create('Regiao S3 nao informada.');
  if AccessKeyEnv = '' then
    raise Exception.Create('Nome da variavel da Access Key nao informado.');
  if SecretKeyEnv = '' then
    raise Exception.Create('Nome da variavel da Secret Key nao informado.');

  { No Linux as credenciais vem so de variaveis de ambiente
    (EnvironmentFile do systemd: /etc/aguia/portalservice.env, modo 0640). }
  Result.AccessKeyId := Trim(GetEnvironmentVariable(AccessKeyEnv));
  if Result.AccessKeyId = '' then
    Result.AccessKeyId := ValorDoArquivo(ARQUIVO_AMBIENTE, AccessKeyEnv);
  Result.SecretAccessKey := Trim(GetEnvironmentVariable(SecretKeyEnv));
  if Result.SecretAccessKey = '' then
    Result.SecretAccessKey := ValorDoArquivo(ARQUIVO_AMBIENTE, SecretKeyEnv);
  if SessionTokenEnv <> '' then
  begin
    Result.SessionToken := Trim(GetEnvironmentVariable(SessionTokenEnv));
    if Result.SessionToken = '' then
      Result.SessionToken := ValorDoArquivo(ARQUIVO_AMBIENTE, SessionTokenEnv);
  end;

  if Result.AccessKeyId = '' then
    raise Exception.CreateFmt(
      'Credencial S3 nao configurada: defina %s em ' +
      '/etc/aguia/portalservice.env.', [AccessKeyEnv]);
  if Result.SecretAccessKey = '' then
    raise Exception.CreateFmt(
      'Credencial secreta S3 nao configurada: defina %s em ' +
      '/etc/aguia/portalservice.env.', [SecretKeyEnv]);

  if Result.TimeoutMs < 1000 then
    Result.TimeoutMs := 1000
  else if Result.TimeoutMs > 300000 then
    Result.TimeoutMs := 300000;
end;

end.
