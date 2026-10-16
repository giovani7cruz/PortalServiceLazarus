unit PortalCliente.Queue.Repository;

{$mode delphi}

interface

uses
  PortalCliente.Db, DB;

type
  TPortalFilaAcao = (pfaInserido, pfaAtualizado, pfaIgnoradoEnviado,
    pfaIgnoradoErro);

  TPortalFilaItem = record
    InternalCod: Int64;
    IDExterno: string;
    Payload: string;
    Tentativas: Integer;
  end;

  TPortalFilaRepository = class
  private
    FConnection: TPortalConexao;
    function Salvar(const ACodigoEmpresa: Integer; const ATipoEntidade: string;
      const AIDOrigem: Int64; const AIDExterno, APayload, AErro: string;
      const AValido, AReabrirErro: Boolean): TPortalFilaAcao;
    function ContarPendentes(const ACodigoEmpresa: Integer;
      const ATipoEntidade: string): Integer;
    procedure RecuperarReservas(const ACodigoEmpresa, AMinutos: Integer;
      const ATipoEntidade: string);
    function Reservar(const ACodigoEmpresa, ALimite: Integer;
      const ATipoEntidade, ALockID: string): TArray<TPortalFilaItem>;
  public
    constructor Create(AConnection: TPortalConexao);
    function SalvarCliente(const ACodigoEmpresa, AIDOrigem: Integer;
      const AIDExterno, APayload, AErro: string;
      const AValido: Boolean;
      const AReabrirErro: Boolean = True): TPortalFilaAcao;
    function SalvarTitulo(const ACodigoEmpresa: Integer;
      const AIDOrigem: Int64; const AIDExterno, APayload, AErro: string;
      const AValido: Boolean;
      const AReabrirErro: Boolean = True): TPortalFilaAcao;
    function TentarObterTitulo(const ACodigoEmpresa: Integer;
      const AIDOrigem: Int64; out AIDExterno, APayload: string): Boolean;
    function ContarClientesPendentes(const ACodigoEmpresa: Integer): Integer;
    function ContarTitulosPendentes(const ACodigoEmpresa: Integer): Integer;
    procedure RecuperarReservasExpiradas(const ACodigoEmpresa,
      AMinutos: Integer);
    procedure RecuperarReservasTitulosExpiradas(const ACodigoEmpresa,
      AMinutos: Integer);
    function ReservarClientes(const ACodigoEmpresa, ALimite: Integer;
      const ALockID: string): TArray<TPortalFilaItem>;
    function ReservarTitulos(const ACodigoEmpresa, ALimite: Integer;
      const ALockID: string): TArray<TPortalFilaItem>;
    procedure MarcarEnviado(const AInternalCod: Int64);
    procedure MarcarErroDefinitivo(const AInternalCod: Int64;
      const AErro: string);
    procedure MarcarFalhaTransitoria(const AInternalCod: Int64;
      const AErro: string; const AEsperaSegundos, AMaxTentativas: Integer);
  end;

implementation

uses
  DateUtils,
  Generics.Collections,
  SysUtils,
  Types;

constructor TPortalFilaRepository.Create(AConnection: TPortalConexao);
begin
  inherited Create;
  if not Assigned(AConnection) then
    raise EArgumentNilException.Create('AConnection');
  FConnection := AConnection;
end;

function TPortalFilaRepository.SalvarCliente(const ACodigoEmpresa,
  AIDOrigem: Integer; const AIDExterno, APayload, AErro: string;
  const AValido, AReabrirErro: Boolean): TPortalFilaAcao;
begin
  Result := Salvar(ACodigoEmpresa, 'CLIENTE', AIDOrigem, AIDExterno,
    APayload, AErro, AValido, AReabrirErro);
end;

function TPortalFilaRepository.SalvarTitulo(const ACodigoEmpresa: Integer;
  const AIDOrigem: Int64; const AIDExterno, APayload, AErro: string;
  const AValido, AReabrirErro: Boolean): TPortalFilaAcao;
begin
  Result := Salvar(ACodigoEmpresa, 'TITULO', AIDOrigem, AIDExterno,
    APayload, AErro, AValido, AReabrirErro);
end;

function TPortalFilaRepository.TentarObterTitulo(
  const ACodigoEmpresa: Integer; const AIDOrigem: Int64;
  out AIDExterno, APayload: string): Boolean;
var
  Query: TPortalQuery;
begin
  AIDExterno := '';
  APayload := '';
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'select ID_EXTERNO, PAYLOAD from PORTAL_SYNC_FILA ' +
      'where COD_EMPRESA = :COD_EMPRESA ' +
      '  and TIPO_ENTIDADE = ''TITULO'' ' +
      '  and ID_ORIGEM = :ID_ORIGEM';
    Query.ParamByName('COD_EMPRESA').AsInteger := ACodigoEmpresa;
    Query.ParamByName('ID_ORIGEM').AsLargeInt := AIDOrigem;
    Query.Open;
    Result := not Query.IsEmpty;
    if Result then
    begin
      AIDExterno := Query.FieldByName('ID_EXTERNO').AsString;
      APayload := Query.FieldByName('PAYLOAD').AsString;
    end;
  finally
    Query.Free;
  end;
end;

function TPortalFilaRepository.Salvar(const ACodigoEmpresa: Integer;
  const ATipoEntidade: string; const AIDOrigem: Int64;
  const AIDExterno, APayload, AErro: string;
  const AValido, AReabrirErro: Boolean): TPortalFilaAcao;
var
  Existe: Boolean;
  PayloadAtual: string;
  Query: TPortalQuery;
  SituacaoNova: Integer;
  SituacaoAtual: Integer;
begin
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'select SITUACAO, PAYLOAD from PORTAL_SYNC_FILA ' +
      'where COD_EMPRESA = :COD_EMPRESA ' +
      '  and TIPO_ENTIDADE = :TIPO_ENTIDADE ' +
      '  and ID_ORIGEM = :ID_ORIGEM';
    Query.ParamByName('COD_EMPRESA').AsInteger := ACodigoEmpresa;
    Query.ParamByName('TIPO_ENTIDADE').AsString := ATipoEntidade;
    Query.ParamByName('ID_ORIGEM').AsLargeInt := AIDOrigem;
    Query.Open;
    Existe := not Query.IsEmpty;
    if Existe then
    begin
      SituacaoAtual := Query.FieldByName('SITUACAO').AsInteger;
      PayloadAtual := Query.FieldByName('PAYLOAD').AsString;
    end
    else
    begin
      SituacaoAtual := -1;
      PayloadAtual := '';
    end;
    Query.Close;

    { Confirmados so voltam para a fila quando o conteudo enviado mudou. }
    if AValido and Existe and (SituacaoAtual = 2) and
      (PayloadAtual = APayload) then
      Exit(pfaIgnoradoEnviado);
    if Existe and (SituacaoAtual = 3) and (PayloadAtual = APayload) and
      not AReabrirErro then
      Exit(pfaIgnoradoErro);

    if Existe then
    begin
      Query.SQL.Text :=
        'update PORTAL_SYNC_FILA set ' +
        '  ID_EXTERNO = :ID_EXTERNO, PRIORIDADE = 10, ' +
        '  SITUACAO = :SITUACAO, TENTATIVAS = 0, ' +
        '  PROXIMA_TENTATIVA = null, LOCK_ID = null, DATA_LOCK = null, ' +
        '  PAYLOAD = :PAYLOAD, ULTIMO_ERRO = :ULTIMO_ERRO, ' +
        '  DATA_ALTERACAO = current_timestamp, DATA_PROCESSAMENTO = null ' +
        'where COD_EMPRESA = :COD_EMPRESA ' +
        '  and TIPO_ENTIDADE = :TIPO_ENTIDADE ' +
        '  and ID_ORIGEM = :ID_ORIGEM';
      Result := pfaAtualizado;
    end
    else
    begin
      Query.SQL.Text :=
        'insert into PORTAL_SYNC_FILA (' +
        '  COD_EMPRESA, TIPO_ENTIDADE, ID_ORIGEM, ID_EXTERNO, ' +
        '  PRIORIDADE, SITUACAO, TENTATIVAS, PAYLOAD, ULTIMO_ERRO' +
        ') values (' +
        '  :COD_EMPRESA, :TIPO_ENTIDADE, :ID_ORIGEM, :ID_EXTERNO, ' +
        '  10, :SITUACAO, 0, :PAYLOAD, :ULTIMO_ERRO' +
        ')';
      Result := pfaInserido;
    end;

    Query.ParamByName('COD_EMPRESA').AsInteger := ACodigoEmpresa;
    Query.ParamByName('TIPO_ENTIDADE').AsString := ATipoEntidade;
    Query.ParamByName('ID_ORIGEM').AsLargeInt := AIDOrigem;
    Query.ParamByName('ID_EXTERNO').AsString := AIDExterno;
    if AValido then
      SituacaoNova := 0
    else
      SituacaoNova := 3;
    Query.ParamByName('SITUACAO').AsInteger := SituacaoNova;
    Query.ParamByName('PAYLOAD').AsString := APayload;
    if AErro.IsEmpty then
      Query.ParamByName('ULTIMO_ERRO').Clear
    else
      Query.ParamByName('ULTIMO_ERRO').AsString := AErro;
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

function TPortalFilaRepository.ContarClientesPendentes(
  const ACodigoEmpresa: Integer): Integer;
begin
  Result := ContarPendentes(ACodigoEmpresa, 'CLIENTE');
end;

function TPortalFilaRepository.ContarTitulosPendentes(
  const ACodigoEmpresa: Integer): Integer;
begin
  Result := ContarPendentes(ACodigoEmpresa, 'TITULO');
end;

function TPortalFilaRepository.ContarPendentes(
  const ACodigoEmpresa: Integer; const ATipoEntidade: string): Integer;
var
  Query: TPortalQuery;
begin
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'select count(*) as TOTAL from PORTAL_SYNC_FILA ' +
      'where COD_EMPRESA = :COD_EMPRESA ' +
      '  and TIPO_ENTIDADE = :TIPO_ENTIDADE and SITUACAO = 0 ' +
      '  and (PROXIMA_TENTATIVA is null or ' +
      '       PROXIMA_TENTATIVA <= current_timestamp)';
    Query.ParamByName('COD_EMPRESA').AsInteger := ACodigoEmpresa;
    Query.ParamByName('TIPO_ENTIDADE').AsString := ATipoEntidade;
    Query.Open;
    Result := Query.FieldByName('TOTAL').AsInteger;
  finally
    Query.Free;
  end;
end;

procedure TPortalFilaRepository.RecuperarReservasExpiradas(
  const ACodigoEmpresa, AMinutos: Integer);
begin
  RecuperarReservas(ACodigoEmpresa, AMinutos, 'CLIENTE');
end;

procedure TPortalFilaRepository.RecuperarReservasTitulosExpiradas(
  const ACodigoEmpresa, AMinutos: Integer);
begin
  RecuperarReservas(ACodigoEmpresa, AMinutos, 'TITULO');
end;

procedure TPortalFilaRepository.RecuperarReservas(
  const ACodigoEmpresa, AMinutos: Integer; const ATipoEntidade: string);
var
  Minutos: Integer;
  Query: TPortalQuery;
begin
  Minutos := AMinutos;
  if Minutos < 1 then
    Minutos := 1;
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'update PORTAL_SYNC_FILA set SITUACAO = 0, LOCK_ID = null, ' +
      'DATA_LOCK = null, DATA_ALTERACAO = current_timestamp ' +
      'where COD_EMPRESA = :COD_EMPRESA ' +
      '  and TIPO_ENTIDADE = :TIPO_ENTIDADE and SITUACAO = 1 ' +
      '  and DATA_LOCK < :DATA_LIMITE';
    Query.ParamByName('COD_EMPRESA').AsInteger := ACodigoEmpresa;
    Query.ParamByName('TIPO_ENTIDADE').AsString := ATipoEntidade;
    Query.ParamByName('DATA_LIMITE').AsDateTime :=
      IncMinute(Now, -Minutos);
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

function TPortalFilaRepository.ReservarClientes(const ACodigoEmpresa,
  ALimite: Integer; const ALockID: string): TArray<TPortalFilaItem>;
begin
  Result := Reservar(ACodigoEmpresa, ALimite, 'CLIENTE', ALockID);
end;

function TPortalFilaRepository.ReservarTitulos(const ACodigoEmpresa,
  ALimite: Integer; const ALockID: string): TArray<TPortalFilaItem>;
begin
  Result := Reservar(ACodigoEmpresa, ALimite, 'TITULO', ALockID);
end;

function TPortalFilaRepository.Reservar(const ACodigoEmpresa,
  ALimite: Integer; const ATipoEntidade,
  ALockID: string): TArray<TPortalFilaItem>;
var
  Candidatos: TPortalQuery;
  IniciouTransacao: Boolean;
  Item: TPortalFilaItem;
  Limite: Integer;
  Lista: TList<TPortalFilaItem>;
  Update: TPortalQuery;
begin
  if ALockID.Trim.IsEmpty then
    raise EArgumentException.Create('O identificador do processamento e obrigatorio.');
  Limite := ALimite;
  if Limite < 1 then
    Limite := 1
  else if Limite > 100 then
    Limite := 100;

  Lista := TList<TPortalFilaItem>.Create;
  Candidatos := TPortalQuery.Create(nil);
  Update := TPortalQuery.Create(nil);
  IniciouTransacao := not FConnection.InTransaction;
  try
    Candidatos.Connection := FConnection;
    Update.Connection := FConnection;
    Candidatos.SQL.Text := Format(
      'select INTERNAL_COD, ID_EXTERNO, PAYLOAD, TENTATIVAS ' +
      'from PORTAL_SYNC_FILA ' +
      'where COD_EMPRESA = :COD_EMPRESA ' +
      '  and TIPO_ENTIDADE = :TIPO_ENTIDADE and SITUACAO = 0 ' +
      '  and (PROXIMA_TENTATIVA is null or ' +
      '       PROXIMA_TENTATIVA <= current_timestamp) ' +
      'order by PRIORIDADE desc, INTERNAL_COD rows %d', [Limite]);
    Candidatos.ParamByName('COD_EMPRESA').AsInteger := ACodigoEmpresa;
    Candidatos.ParamByName('TIPO_ENTIDADE').AsString := ATipoEntidade;
    Update.SQL.Text :=
      'update PORTAL_SYNC_FILA set SITUACAO = 1, LOCK_ID = :LOCK_ID, ' +
      'DATA_LOCK = current_timestamp, DATA_ALTERACAO = current_timestamp ' +
      'where INTERNAL_COD = :INTERNAL_COD and SITUACAO = 0';

    if IniciouTransacao then
      FConnection.StartTransaction;
    try
      Candidatos.Open;
      while not Candidatos.Eof do
      begin
        Update.ParamByName('LOCK_ID').AsString := ALockID;
        Update.ParamByName('INTERNAL_COD').AsLargeInt :=
          Candidatos.FieldByName('INTERNAL_COD').AsLargeInt;
        Update.ExecSQL;
        if Update.RowsAffected = 1 then
        begin
          Item := Default(TPortalFilaItem);
          Item.InternalCod := Candidatos.FieldByName('INTERNAL_COD').AsLargeInt;
          Item.IDExterno := Candidatos.FieldByName('ID_EXTERNO').AsString;
          Item.Payload := Candidatos.FieldByName('PAYLOAD').AsString;
          Item.Tentativas := Candidatos.FieldByName('TENTATIVAS').AsInteger;
          Lista.Add(Item);
        end;
        Candidatos.Next;
      end;
      if IniciouTransacao then
        FConnection.Commit;
    except
      if IniciouTransacao and FConnection.InTransaction then
        FConnection.Rollback;
      raise;
    end;
    Result := Lista.ToArray;
  finally
    Update.Free;
    Candidatos.Free;
    Lista.Free;
  end;
end;

procedure TPortalFilaRepository.MarcarEnviado(const AInternalCod: Int64);
var
  Query: TPortalQuery;
begin
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'update PORTAL_SYNC_FILA set SITUACAO = 2, LOCK_ID = null, ' +
      'DATA_LOCK = null, PROXIMA_TENTATIVA = null, ULTIMO_ERRO = null, ' +
      'DATA_PROCESSAMENTO = current_timestamp, ' +
      'DATA_ALTERACAO = current_timestamp where INTERNAL_COD = :ID';
    Query.ParamByName('ID').AsLargeInt := AInternalCod;
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

procedure TPortalFilaRepository.MarcarErroDefinitivo(
  const AInternalCod: Int64; const AErro: string);
var
  Query: TPortalQuery;
begin
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'update PORTAL_SYNC_FILA set SITUACAO = 3, ' +
      'TENTATIVAS = TENTATIVAS + 1, LOCK_ID = null, DATA_LOCK = null, ' +
      'PROXIMA_TENTATIVA = null, ULTIMO_ERRO = :ERRO, ' +
      'DATA_PROCESSAMENTO = current_timestamp, ' +
      'DATA_ALTERACAO = current_timestamp where INTERNAL_COD = :ID';
    Query.ParamByName('ID').AsLargeInt := AInternalCod;
    Query.ParamByName('ERRO').AsString := Copy(AErro, 1, 8000);
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

procedure TPortalFilaRepository.MarcarFalhaTransitoria(
  const AInternalCod: Int64; const AErro: string;
  const AEsperaSegundos, AMaxTentativas: Integer);
var
  Espera: Integer;
  MaxTentativas: Integer;
  Query: TPortalQuery;
begin
  Espera := AEsperaSegundos;
  if Espera < 1 then
    Espera := 1;
  MaxTentativas := AMaxTentativas;
  if MaxTentativas < 1 then
    MaxTentativas := 1;

  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'update PORTAL_SYNC_FILA set ' +
      'SITUACAO = case when TENTATIVAS + 1 >= :MAX_TENTATIVAS ' +
      '                then 3 else 0 end, ' +
      'TENTATIVAS = TENTATIVAS + 1, LOCK_ID = null, DATA_LOCK = null, ' +
      'PROXIMA_TENTATIVA = case ' +
      '  when TENTATIVAS + 1 >= :MAX_TENTATIVAS then null ' +
      '  else dateadd(second, :ESPERA, current_timestamp) end, ' +
      'ULTIMO_ERRO = :ERRO, DATA_PROCESSAMENTO = current_timestamp, ' +
      'DATA_ALTERACAO = current_timestamp where INTERNAL_COD = :ID';
    Query.ParamByName('MAX_TENTATIVAS').AsInteger := MaxTentativas;
    Query.ParamByName('ESPERA').AsInteger := Espera;
    Query.ParamByName('ERRO').AsString := Copy(AErro, 1, 8000);
    Query.ParamByName('ID').AsLargeInt := AInternalCod;
    Query.ExecSQL;
  finally
    Query.Free;
  end;
end;

end.
