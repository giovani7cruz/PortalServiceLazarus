unit PortalCliente.Config.Repository;

{$mode delphi}

interface

uses
  PortalCliente.Db, DB;

type
  TPortalConfiguracao = record
    CodigoEmpresa: Integer;
    Ativo: Boolean;
    BaseUrl: string;
    TokenProtegido: string;
    IntervaloSegundos: Integer;
    TamanhoLote: Integer;
    TimeoutMs: Integer;
    function TemToken: Boolean;
  end;

  TPortalConfigRepository = class
  private
    FConnection: TPortalConexao;
  public
    constructor Create(AConnection: TPortalConexao);
    function Listar(const ASomenteAtivas: Boolean = True): TArray<TPortalConfiguracao>;
    function TentarObter(const ACodigoEmpresa: Integer;
      out AConfiguracao: TPortalConfiguracao): Boolean;
    procedure Salvar(const AConfiguracao: TPortalConfiguracao);
    procedure RegistrarCiclo(const ACodigoEmpresa: Integer;
      const AErro: string);
  end;

implementation

uses
  Generics.Collections,
  SysUtils;

function TPortalConfiguracao.TemToken: Boolean;
begin
  Result := not TokenProtegido.Trim.IsEmpty;
end;

constructor TPortalConfigRepository.Create(AConnection: TPortalConexao);
begin
  inherited Create;
  if not Assigned(AConnection) then
    raise EArgumentNilException.Create('AConnection');
  FConnection := AConnection;
end;

function TPortalConfigRepository.Listar(
  const ASomenteAtivas: Boolean): TArray<TPortalConfiguracao>;
var
  Configuracao: TPortalConfiguracao;
  Lista: TList<TPortalConfiguracao>;
  Query: TPortalQuery;
begin
  Lista := TList<TPortalConfiguracao>.Create;
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'select COD_EMPRESA, ATIVO, BASE_URL, TOKEN_PROTEGIDO, ' +
      '       INTERVALO_SEGUNDOS, TAMANHO_LOTE, TIMEOUT_MS ' +
      '  from PORTAL_CONFIG ';
    if ASomenteAtivas then
      Query.SQL.Add(' where ATIVO = 1 ');
    Query.SQL.Add(' order by COD_EMPRESA ');
    Query.Open;

    while not Query.Eof do
    begin
      Configuracao := Default(TPortalConfiguracao);
      Configuracao.CodigoEmpresa := Query.FieldByName('COD_EMPRESA').AsInteger;
      Configuracao.Ativo := Query.FieldByName('ATIVO').AsInteger = 1;
      Configuracao.BaseUrl := Query.FieldByName('BASE_URL').AsString;
      Configuracao.TokenProtegido := Query.FieldByName('TOKEN_PROTEGIDO').AsString;
      Configuracao.IntervaloSegundos :=
        Query.FieldByName('INTERVALO_SEGUNDOS').AsInteger;
      Configuracao.TamanhoLote := Query.FieldByName('TAMANHO_LOTE').AsInteger;
      Configuracao.TimeoutMs := Query.FieldByName('TIMEOUT_MS').AsInteger;
      Lista.Add(Configuracao);
      Query.Next;
    end;

    Result := Lista.ToArray;
  finally
    Query.Free;
    Lista.Free;
  end;
end;

procedure TPortalConfigRepository.Salvar(
  const AConfiguracao: TPortalConfiguracao);
var
  IniciouTransacao: Boolean;
  Query: TPortalQuery;
begin
  Query := TPortalQuery.Create(nil);
  IniciouTransacao := not FConnection.InTransaction;
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'update or insert into PORTAL_CONFIG (' +
      '  COD_EMPRESA, ATIVO, BASE_URL, TOKEN_PROTEGIDO, ' +
      '  INTERVALO_SEGUNDOS, TAMANHO_LOTE, TIMEOUT_MS, DATA_ALTERACAO' +
      ') values (' +
      '  :COD_EMPRESA, :ATIVO, :BASE_URL, :TOKEN_PROTEGIDO, ' +
      '  :INTERVALO_SEGUNDOS, :TAMANHO_LOTE, :TIMEOUT_MS, CURRENT_TIMESTAMP' +
      ') matching (COD_EMPRESA)';
    Query.ParamByName('COD_EMPRESA').AsInteger := AConfiguracao.CodigoEmpresa;
    Query.ParamByName('ATIVO').AsInteger := Ord(AConfiguracao.Ativo);
    Query.ParamByName('BASE_URL').AsString := AConfiguracao.BaseUrl;
    Query.ParamByName('TOKEN_PROTEGIDO').AsString :=
      AConfiguracao.TokenProtegido;
    Query.ParamByName('INTERVALO_SEGUNDOS').AsInteger :=
      AConfiguracao.IntervaloSegundos;
    Query.ParamByName('TAMANHO_LOTE').AsInteger := AConfiguracao.TamanhoLote;
    Query.ParamByName('TIMEOUT_MS').AsInteger := AConfiguracao.TimeoutMs;

    if IniciouTransacao then
      FConnection.StartTransaction;
    try
      Query.ExecSQL;
      if IniciouTransacao then
        FConnection.Commit;
    except
      if IniciouTransacao and FConnection.InTransaction then
        FConnection.Rollback;
      raise;
    end;
  finally
    Query.Free;
  end;
end;

procedure TPortalConfigRepository.RegistrarCiclo(const ACodigoEmpresa: Integer;
  const AErro: string);
var
  Query: TPortalQuery;
begin
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'update PORTAL_CONFIG set DATA_ULTIMO_CICLO = current_timestamp, ' +
      'ULTIMO_ERRO = :ULTIMO_ERRO, DATA_ALTERACAO = current_timestamp ' +
      'where COD_EMPRESA = :COD_EMPRESA';
    Query.ParamByName('COD_EMPRESA').AsInteger := ACodigoEmpresa;
    if AErro.Trim.IsEmpty then
      Query.ParamByName('ULTIMO_ERRO').Clear
    else
      Query.ParamByName('ULTIMO_ERRO').AsString := Copy(AErro, 1, 8000);
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

function TPortalConfigRepository.TentarObter(const ACodigoEmpresa: Integer;
  out AConfiguracao: TPortalConfiguracao): Boolean;
var
  Query: TPortalQuery;
begin
  AConfiguracao := Default(TPortalConfiguracao);
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'select COD_EMPRESA, ATIVO, BASE_URL, TOKEN_PROTEGIDO, ' +
      '       INTERVALO_SEGUNDOS, TAMANHO_LOTE, TIMEOUT_MS ' +
      '  from PORTAL_CONFIG where COD_EMPRESA = :COD_EMPRESA';
    Query.ParamByName('COD_EMPRESA').AsInteger := ACodigoEmpresa;
    Query.Open;
    Result := not Query.IsEmpty;
    if Result then
    begin
      AConfiguracao.CodigoEmpresa := Query.FieldByName('COD_EMPRESA').AsInteger;
      AConfiguracao.Ativo := Query.FieldByName('ATIVO').AsInteger = 1;
      AConfiguracao.BaseUrl := Query.FieldByName('BASE_URL').AsString;
      AConfiguracao.TokenProtegido :=
        Query.FieldByName('TOKEN_PROTEGIDO').AsString;
      AConfiguracao.IntervaloSegundos :=
        Query.FieldByName('INTERVALO_SEGUNDOS').AsInteger;
      AConfiguracao.TamanhoLote := Query.FieldByName('TAMANHO_LOTE').AsInteger;
      AConfiguracao.TimeoutMs := Query.FieldByName('TIMEOUT_MS').AsInteger;
    end;
  finally
    Query.Free;
  end;
end;

end.
