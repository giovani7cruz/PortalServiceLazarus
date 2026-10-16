unit PortalCliente.Db;

{ Acesso ao Firebird pelo SQLdb (FPC). Reproduz o pedaco do FireDAC que o
  PortalService usa (TFDConnection/TFDQuery): conexao com StartTransaction,
  Commit, Rollback, InTransaction e Ping; consulta com SQL, ParamByName,
  Open, ExecSQL, FieldByName, RowsAffected. Fora de uma transacao explicita
  cada ExecSQL e confirmado na hora (autocommit, como no FireDAC) e a
  transacao de leitura e encerrada quando a ultima consulta e liberada. }

{$mode delphi}

interface

uses
  Classes, SysUtils, DB, SQLDB, IBConnection;

type
  TPortalConexao = class
  private
    FConn: TIBConnection;
    FTrans: TSQLTransaction;
    FExplicita: Boolean;
    FConsultas: Integer;
    function GetInTransaction: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    { Parametros no formato do configFirebird.ini (Server, Port, Database,
      User_Name, Password, CharacterSet) e conecta. }
    procedure Abrir(AParams: TStrings);
    procedure StartTransaction;
    procedure Commit;
    procedure Rollback;
    function Ping: Boolean;
    { Encerra a transacao de leitura aberta por consultas sem transacao
      explicita (chamar entre ciclos do daemon). }
    procedure EncerrarLeitura;
    property InTransaction: Boolean read GetInTransaction;
    property Explicita: Boolean read FExplicita;
    property Conn: TIBConnection read FConn;
    property Transacao: TSQLTransaction read FTrans;
  end;

  TPortalQuery = class(TSQLQuery)
  private
    FConexao: TPortalConexao;
    procedure SetConexao(AValue: TPortalConexao);
  public
    destructor Destroy; override;
    procedure ExecSQL; override;
    property Connection: TPortalConexao read FConexao write SetConexao;
  end;

implementation

{ TPortalConexao }

constructor TPortalConexao.Create;
begin
  inherited Create;
  FConn := TIBConnection.Create(nil);
  FTrans := TSQLTransaction.Create(nil);
  FTrans.DataBase := FConn;
  FConn.Transaction := FTrans;
  FConn.LoginPrompt := False;
end;

destructor TPortalConexao.Destroy;
begin
  try
    if FTrans.Active then
      FTrans.Rollback;
    FConn.Connected := False;
  except
    { desligando: erro de rede aqui nao muda nada }
  end;
  FTrans.Free;
  FConn.Free;
  inherited;
end;

procedure TPortalConexao.Abrir(AParams: TStrings);
var
  Servidor, Porta: string;
begin
  Servidor := Trim(AParams.Values['Server']);
  Porta := Trim(AParams.Values['Port']);
  if Porta = '' then
    Porta := Trim(AParams.Values['PORT']);
  FConn.DatabaseName := Trim(AParams.Values['Database']);
  FConn.HostName := Servidor;
  if (Porta <> '') and (StrToIntDef(Porta, 0) > 0) then
    FConn.Params.Values['Port'] := Porta;
  FConn.UserName := Trim(AParams.Values['User_Name']);
  FConn.Password := AParams.Values['Password'];
  FConn.CharSet := Trim(AParams.Values['CharacterSet']);
  if FConn.CharSet = '' then
    FConn.CharSet := 'UTF8';
  FConn.Connected := True;
end;

function TPortalConexao.GetInTransaction: Boolean;
begin
  Result := FExplicita and FTrans.Active;
end;

procedure TPortalConexao.StartTransaction;
begin
  if FTrans.Active then
    FTrans.Commit;
  FTrans.StartTransaction;
  FExplicita := True;
end;

procedure TPortalConexao.Commit;
begin
  try
    if FTrans.Active then
      FTrans.Commit;
  finally
    FExplicita := False;
  end;
end;

procedure TPortalConexao.Rollback;
begin
  try
    if FTrans.Active then
      FTrans.Rollback;
  finally
    FExplicita := False;
  end;
end;

procedure TPortalConexao.EncerrarLeitura;
begin
  if (not FExplicita) and FTrans.Active then
    FTrans.Commit;
end;

function TPortalConexao.Ping: Boolean;
var
  Q: TPortalQuery;
begin
  Result := False;
  try
    Q := TPortalQuery.Create(nil);
    try
      Q.Connection := Self;
      Q.SQL.Text := 'select 1 as UM from RDB$DATABASE';
      Q.Open;
      Result := not Q.IsEmpty;
    finally
      Q.Free;
    end;
  except
    Result := False;
  end;
end;

{ TPortalQuery }

destructor TPortalQuery.Destroy;
var
  Conexao: TPortalConexao;
begin
  Conexao := FConexao;
  if Conexao <> nil then
    Dec(Conexao.FConsultas);
  inherited;
  if (Conexao <> nil) and (not Conexao.FExplicita) and
    Conexao.FTrans.Active and (Conexao.FConsultas = 0) then
    try
      Conexao.FTrans.Commit;
    except
    end;
end;

procedure TPortalQuery.SetConexao(AValue: TPortalConexao);
begin
  if FConexao <> nil then
    Dec(FConexao.FConsultas);
  FConexao := AValue;
  if AValue <> nil then
    Inc(AValue.FConsultas);
  if AValue = nil then
  begin
    DataBase := nil;
    Transaction := nil;
  end
  else
  begin
    DataBase := AValue.Conn;
    Transaction := AValue.Transacao;
  end;
end;

procedure TPortalQuery.ExecSQL;
begin
  inherited ExecSQL;
  if (FConexao <> nil) and (not FConexao.FExplicita) then
    FConexao.FTrans.CommitRetaining;
end;

end.
