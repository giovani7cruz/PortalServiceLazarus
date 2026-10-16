unit PortalCliente.Client.Repository;

{$mode delphi}

interface

uses
  PortalCliente.Db;

type
  TPortalClienteOrigem = record
    Codigo: Integer;
    TipoPessoa: Integer;
    CPFCNPJ: string;
    RazaoSocial: string;
    NomeFantasia: string;
    CodigoStatus: Integer;
    Logradouro: string;
    Numero: string;
    Complemento: string;
    Bairro: string;
    CEP: string;
    CodigoIBGE: string;
    Email: string;
    Telefone: string;
    Observacoes: string;
  end;


  TPortalClienteRepository = class
  private
    FConnection: TPortalConexao;
  public
    constructor Create(AConnection: TPortalConexao);
    function Listar: TArray<TPortalClienteOrigem>;
  end;

implementation

uses
  SysUtils, Generics.Collections;

constructor TPortalClienteRepository.Create(AConnection: TPortalConexao);
begin
  inherited Create;
  if not Assigned(AConnection) then
    raise EArgumentNilException.Create('AConnection');
  FConnection := AConnection;
end;

function TPortalClienteRepository.Listar: TArray<TPortalClienteOrigem>;
var
  Cliente: TPortalClienteOrigem;
  Lista: TList<TPortalClienteOrigem>;
  Query: TPortalQuery;
begin

  Lista := TList<TPortalClienteOrigem>.Create;
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := FConnection;
    Query.SQL.Text :=
      'select p.INTERNAL_COD, p.TIPO_PESSOA, p.CNPJ_CPF, ' +
      '       p.RAZAO_SOCIAL, p.NOME_FANTASIA, p.COD_STATUS, ' +
      '       p.LOGRADOURO, p.NUMERO, p.COMPLEMENTO, p.BAIRRO, p.CEP, ' +
      '       cast(c.COD_IBGE as varchar(20)) as COD_IBGE, p.OBS, ' +
      '       (select first 1 pe.EMAIL from PESSOA_EMAIL pe ' +
      '         where pe.COD_PESSOA = p.INTERNAL_COD ' +
      '         order by pe.SEQ, pe.INTERNAL_COD) as EMAIL, ' +
      '       (select first 1 coalesce(t.DDD, '''') || coalesce(t.FONE, '''') ' +
      '          from TELEFONE t where t.COD_PESSOA = p.INTERNAL_COD ' +
      '         order by t.SEQ, t.INTERNAL_COD) as TELEFONE ' +
      '  from PESSOA p ' +
      '  join CIDADE c on c.INTERNAL_COD = p.COD_CIDADE ' +
      ' where p.INTERNAL_COD > 0 ' +
      '   and p.E_FORNECEDOR = 0 ' +
      '   and p.E_TRANSPORTADOR = 0 ' +
      '   and p.E_VENDEDOR = 0 ' +
      '   and p.E_FUNCIONARIO = 0 ' +
      '   and ( ' +
      '     exists (select 1 from CONTRATO ct ' +
      '              where ct.COD_PESSOA = p.INTERNAL_COD ' +
      '                and ct.DATA_TERMINO >= date ''2026-01-01'') ' +
      '     or exists (select 1 from CONTARECEBER cr ' +
      '                 where cr.COD_PESSOA = p.INTERNAL_COD ' +
      '                   and cr.DATA_VENCIMENTO >= date ''2026-01-01'') ' +
      '   ) ' +
      ' order by p.INTERNAL_COD';
    Query.Open;

    while not Query.Eof do
    begin
      Cliente := Default(TPortalClienteOrigem);
      Cliente.Codigo := Query.FieldByName('INTERNAL_COD').AsInteger;
      Cliente.TipoPessoa := Query.FieldByName('TIPO_PESSOA').AsInteger;
      Cliente.CPFCNPJ := Query.FieldByName('CNPJ_CPF').AsString;
      Cliente.RazaoSocial := Query.FieldByName('RAZAO_SOCIAL').AsString;
      Cliente.NomeFantasia := Query.FieldByName('NOME_FANTASIA').AsString;
      Cliente.CodigoStatus := Query.FieldByName('COD_STATUS').AsInteger;
      Cliente.Logradouro := Query.FieldByName('LOGRADOURO').AsString;
      Cliente.Numero := Query.FieldByName('NUMERO').AsString;
      Cliente.Complemento := Query.FieldByName('COMPLEMENTO').AsString;
      Cliente.Bairro := Query.FieldByName('BAIRRO').AsString;
      Cliente.CEP := Query.FieldByName('CEP').AsString;
      Cliente.CodigoIBGE := Query.FieldByName('COD_IBGE').AsString;
      Cliente.Email := Query.FieldByName('EMAIL').AsString;
      Cliente.Telefone := Query.FieldByName('TELEFONE').AsString;
      Cliente.Observacoes := Query.FieldByName('OBS').AsString;
      Lista.Add(Cliente);
      Query.Next;
    end;
  finally
    Query.Free;
    Result := Lista.ToArray;
    Lista.Free;
  end;
end;

end.
