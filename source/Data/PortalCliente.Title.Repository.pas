unit PortalCliente.Title.Repository;

{$mode delphi}

interface

uses
  PortalCliente.Db;

type
  TPortalTituloOrigem = record
    Codigo: Int64;
    CodigoPessoa: Int64;
    Documento: string;
    ValorOriginal: Currency;
    Saldo: Currency;
    DataEmissao: TDateTime;
    TemDataEmissao: Boolean;
    DataVencimento: TDateTime;
    TemDataVencimento: Boolean;
    DataPagamento: TDateTime;
    TemDataPagamento: Boolean;
    FormaPagamento: string;
    NossoNumero: string;
    NotaFiscalNumero: string;
    Observacoes: string;
  end;


  TPortalTituloRepository = class
  private
    FConnection: TPortalConexao;
  public
    constructor Create(AConnection: TPortalConexao);
    function Listar(const ACodigoEmpresa: Integer): TArray<TPortalTituloOrigem>;
    function ContarSemClienteEnviado(const ACodigoEmpresa: Integer): Integer;
  end;

implementation

uses
  SysUtils, Generics.Collections,
  Types;

constructor TPortalTituloRepository.Create(AConnection: TPortalConexao);
begin
  inherited Create;
  if not Assigned(AConnection) then
    raise EArgumentNilException.Create('AConnection');
  FConnection := AConnection;
end;

function TPortalTituloRepository.Listar(const ACodigoEmpresa: Integer): TArray<TPortalTituloOrigem>;
var
  Query: TPortalQuery;
  Titulo: TPortalTituloOrigem;
  Lista: TList<TPortalTituloOrigem>;
begin

  Lista := TList<TPortalTituloOrigem>.Create;
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'select cr.INTERNAL_COD, cr.COD_PESSOA, cr.DOCUMENTO, ' +
      '       cr.VALOR_ORIGINAL, cr.SALDO, cr.DATA_EMISSAO, ' +
      '       cr.DATA_VENCIMENTO, ' +
      '       coalesce(cr.DATA_PAGAMENTO, ' +
      '         (select max(pg.DATA) from CONTARECEBER_PGTO pg ' +
      '           where pg.COD_CONTAREC = cr.INTERNAL_COD)) DATA_PAGAMENTO, ' +
      '       fp.DESCRICAO FORMA_PAGAMENTO, ' +
      '       coalesce(nullif(trim(cr.COMPLETO_NN), ''''), ' +
      '         cast(cr.NOSSO_NUMERO as varchar(100))) NOSSO_NUMERO, ' +
      '       cast(nf.NUMERO as varchar(100)) NOTA_FISCAL_NUMERO, cr.OBS ' +
      '  from CONTARECEBER cr ' +
      '  left join FORMA_PAGAMENTO fp ' +
      '    on fp.INTERNAL_COD = cr.COD_FORMA_PAGAMENTO ' +
      '  left join NOTAFISCAL nf on nf.INTERNAL_COD = cr.COD_NOTA ' +
      ' where cr.COD_EMPRESA = :COD_EMPRESA ' +
      '   and cr.DATA_VENCIMENTO >= date ''2026-01-01'' ' +
      '   and exists (select 1 from PORTAL_SYNC_FILA f ' +
      '                where f.COD_EMPRESA = :COD_EMPRESA ' +
      '                  and f.TIPO_ENTIDADE = ''CLIENTE'' ' +
      '                  and f.ID_ORIGEM = cr.COD_PESSOA ' +
      '                  and f.SITUACAO = 2) ' +
      ' order by cr.INTERNAL_COD';
    Query.ParamByName('COD_EMPRESA').AsInteger := ACodigoEmpresa;
    Query.Open;

    while not Query.Eof do
    begin
      Titulo := Default(TPortalTituloOrigem);
      Titulo.Codigo := Query.FieldByName('INTERNAL_COD').AsLargeInt;
      Titulo.CodigoPessoa := Query.FieldByName('COD_PESSOA').AsLargeInt;
      Titulo.Documento := Query.FieldByName('DOCUMENTO').AsString;
      Titulo.ValorOriginal := Query.FieldByName('VALOR_ORIGINAL').AsCurrency;
      Titulo.Saldo := Query.FieldByName('SALDO').AsCurrency;
      Titulo.TemDataEmissao := not Query.FieldByName('DATA_EMISSAO').IsNull;
      if Titulo.TemDataEmissao then
        Titulo.DataEmissao := Query.FieldByName('DATA_EMISSAO').AsDateTime;
      Titulo.TemDataVencimento :=
        not Query.FieldByName('DATA_VENCIMENTO').IsNull;
      if Titulo.TemDataVencimento then
        Titulo.DataVencimento :=
          Query.FieldByName('DATA_VENCIMENTO').AsDateTime;
      Titulo.TemDataPagamento :=
        not Query.FieldByName('DATA_PAGAMENTO').IsNull;
      if Titulo.TemDataPagamento then
        Titulo.DataPagamento := Query.FieldByName('DATA_PAGAMENTO').AsDateTime;
      Titulo.FormaPagamento := Query.FieldByName('FORMA_PAGAMENTO').AsString;
      Titulo.NossoNumero := Query.FieldByName('NOSSO_NUMERO').AsString;
      Titulo.NotaFiscalNumero :=
        Query.FieldByName('NOTA_FISCAL_NUMERO').AsString;
      Titulo.Observacoes := Query.FieldByName('OBS').AsString;
      Lista.Add(Titulo);
      Query.Next;
    end;
  finally
    Query.Free;
    Result := Lista.ToArray;
    Lista.Free;
  end;
end;

function TPortalTituloRepository.ContarSemClienteEnviado(
  const ACodigoEmpresa: Integer): Integer;
var
  Query: TPortalQuery;
begin
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'select count(*) TOTAL from CONTARECEBER cr ' +
      'where cr.COD_EMPRESA = :COD_EMPRESA ' +
      '  and cr.DATA_VENCIMENTO >= date ''2026-01-01'' ' +
      '  and not exists (select 1 from PORTAL_SYNC_FILA f ' +
      '                   where f.COD_EMPRESA = :COD_EMPRESA ' +
      '                     and f.TIPO_ENTIDADE = ''CLIENTE'' ' +
      '                     and f.ID_ORIGEM = cr.COD_PESSOA ' +
      '                     and f.SITUACAO = 2)';
    Query.ParamByName('COD_EMPRESA').AsInteger := ACodigoEmpresa;
    Query.Open;
    Result := Query.FieldByName('TOTAL').AsInteger;
  finally
    Query.Free;
  end;
end;

end.
