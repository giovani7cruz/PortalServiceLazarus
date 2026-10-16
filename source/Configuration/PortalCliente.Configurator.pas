unit PortalCliente.Configurator;

{$mode delphi}

interface

uses
  PortalCliente.Db;

type
  TPortalClienteConfigurator = class sealed
  private
    class function LerInteiro(const APrompt: string;
      const ADefault, AMinimo, AMaximo: Integer): Integer; static;
    class function LerSimNao(const APrompt: string;
      const ADefault: Boolean): Boolean; static;
    class function LerTexto(const APrompt, ADefault: string): string; static;
    class function LerTokenOculto(const AJaConfigurado: Boolean): string; static;
  public
    class function Executar: Integer; static;
  end;

implementation

uses
  SysUtils,
  Types,
  PortalCliente.Plataforma,
  Aguia.Database,
  Aguia.Database.Config,
  PortalCliente.Api,
  PortalCliente.Config.Repository,
  PortalCliente.DTO,
  PortalCliente.TokenProtector;

class function TPortalClienteConfigurator.LerInteiro(const APrompt: string;
  const ADefault, AMinimo, AMaximo: Integer): Integer;
var
  Entrada: string;
begin
  while True do
  begin
    Write(Format('%s [%d]: ', [APrompt, ADefault]));
    ReadLn(Entrada);
    Entrada := Entrada.Trim;
    if Entrada.IsEmpty then
      Exit(ADefault);
    if TryStrToInt(Entrada, Result) and (Result >= AMinimo) and
      (Result <= AMaximo) then
      Exit;
    WriteLn(Format('Informe um numero entre %d e %d.', [AMinimo, AMaximo]));
  end;
end;

class function TPortalClienteConfigurator.LerSimNao(const APrompt: string;
  const ADefault: Boolean): Boolean;
var
  Entrada: string;
  Padrao: string;
begin
  if ADefault then
    Padrao := 'S'
  else
    Padrao := 'N';
  while True do
  begin
    Write(Format('%s [S/N, padrao %s]: ', [APrompt, Padrao]));
    ReadLn(Entrada);
    Entrada := Entrada.Trim;
    if Entrada.IsEmpty then
      Exit(ADefault);
    if SameText(Entrada, 'S') then
      Exit(True);
    if SameText(Entrada, 'N') then
      Exit(False);
    WriteLn('Responda S ou N.');
  end;
end;

class function TPortalClienteConfigurator.LerTexto(const APrompt,
  ADefault: string): string;
var
  Entrada: string;
begin
  Write(Format('%s [%s]: ', [APrompt, ADefault]));
  ReadLn(Entrada);
  Result := Entrada.Trim;
  if Result.IsEmpty then
    Result := ADefault;
end;

class function TPortalClienteConfigurator.LerTokenOculto(
  const AJaConfigurado: Boolean): string;
var
  Prompt: string;
begin
  if AJaConfigurado then
    Prompt := 'Token (ENTER mantem o atual): '
  else
    Prompt := 'Token: ';
  Write(Prompt);
  try
    Result := TPortalPlataforma.LerLinhaOculta;
  finally
    WriteLn;
  end;
  Result := Result.Trim;
  if not Result.IsEmpty then
    WriteLn(Format('Token recebido (%d caracteres).', [Length(Result)]));
end;

class function TPortalClienteConfigurator.Executar: Integer;
var
  Api: TPortalClienteApi;
  CodigoEmpresa: Integer;
  Config: TAguiaDatabaseConfig;
  Configuracao: TPortalConfiguracao;
  Connection: TPortalConexao;
  ExisteConfiguracao: Boolean;
  Filtro: TPortalClienteFiltro;
  Query: TPortalQuery;
  Repository: TPortalConfigRepository;
  Token: string;
begin
  Result := 1;
  Connection := nil;
  Query := nil;
  Repository := nil;
  Api := nil;
  Token := '';
  try
    try
      WriteLn('AguiaPortalService - configuracao do portal');
      WriteLn;

      Config := TAguiaDatabaseConfigLoader.Carregar;
      Connection := TAguiaDatabase.AbrirConexao(Config);
      Repository := TPortalConfigRepository.Create(Connection);

      Query := TPortalQuery.Create(nil);
      Query.Connection := Connection;
      Query.SQL.Text :=
        'select INTERNAL_COD, RAZAO_SOCIAL, NOME_FANTASIA ' +
        'from EMPRESA order by INTERNAL_COD';
      Query.Open;
      WriteLn('Empresas disponiveis:');
      while not Query.Eof do
      begin
        WriteLn(Format('  %d - %s (%s)',
          [Query.FieldByName('INTERNAL_COD').AsInteger,
           Query.FieldByName('RAZAO_SOCIAL').AsString,
           Query.FieldByName('NOME_FANTASIA').AsString]));
        Query.Next;
      end;
      WriteLn;

      CodigoEmpresa := LerInteiro('Codigo da empresa', 1, 1, MaxInt);
      Query.Close;
      Query.SQL.Text :=
        'select count(*) as TOTAL from EMPRESA where INTERNAL_COD = :CODIGO';
      Query.ParamByName('CODIGO').AsInteger := CodigoEmpresa;
      Query.Open;
      if Query.FieldByName('TOTAL').AsInteger <> 1 then
        raise Exception.CreateFmt('Empresa %d nao encontrada.', [CodigoEmpresa]);

      ExisteConfiguracao := Repository.TentarObter(CodigoEmpresa, Configuracao);
      if not ExisteConfiguracao then
      begin
        Configuracao := Default(TPortalConfiguracao);
        Configuracao.CodigoEmpresa := CodigoEmpresa;
        Configuracao.Ativo := True;
        Configuracao.BaseUrl := 'https://portal.infus.inf.br/api';
        Configuracao.IntervaloSegundos := 60;
        Configuracao.TamanhoLote := 100;
        Configuracao.TimeoutMs := 30000;
      end;

      if Configuracao.TemToken and
        (Copy(Configuracao.TokenProtegido, 1, 3) <> 'L1:') then
      begin
        WriteLn('Atencao: o token gravado foi protegido no Windows (DPAPI) e nao ' +
          'pode ser lido no Linux.');
        WriteLn('Informe o token do portal agora (ele sera gravado no formato do Linux).');
        WriteLn;
        Configuracao.TokenProtegido := '';
      end;

      Configuracao.BaseUrl := LerTexto('URL da API', Configuracao.BaseUrl);
      Configuracao.IntervaloSegundos := LerInteiro('Intervalo em segundos',
        Configuracao.IntervaloSegundos, 10, 86400);
      Configuracao.TamanhoLote := LerInteiro('Tamanho do lote',
        Configuracao.TamanhoLote, 1, 100);
      Configuracao.TimeoutMs := LerInteiro('Timeout HTTP em ms',
        Configuracao.TimeoutMs, 1000, 300000);
      Configuracao.Ativo := LerSimNao('Ativar integracao', Configuracao.Ativo);

      Token := LerTokenOculto(Configuracao.TemToken);
      if not Token.IsEmpty then
        Configuracao.TokenProtegido := TPortalTokenProtector.Proteger(Token)
      else if not Configuracao.TemToken then
        raise Exception.Create('O token precisa ser informado.');

      if Token.IsEmpty then
        Token := TPortalTokenProtector.Desproteger(Configuracao.TokenProtegido);

      Write('Testando autenticacao no portal... ');
      Api := TPortalClienteApi.Create(Token, Configuracao.BaseUrl);
      Filtro := Default(TPortalClienteFiltro);
      Filtro.Pagina := 1;
      Filtro.Quantidade := 1;
      Api.ListarClientes(Filtro);
      WriteLn('OK');

      Repository.Salvar(Configuracao);
      WriteLn('Configuracao gravada com sucesso.');
      Result := 0;
    except
      on E: Exception do
        WriteLn('ERRO: ' + E.Message);
    end;
  finally
    Token := '';
    Api.Free;
    Query.Free;
    Repository.Free;
    Connection.Free;
  end;
end;

end.
