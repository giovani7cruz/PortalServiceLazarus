unit PortalCliente.Boleto.Repository;

{$mode delphi}

interface

uses
  PortalCliente.Db;

type
  TPortalBoletoIdentificacao = record
    ContaReceberId: Int64;
    PessoaId: Int64;
    EmpresaId: Integer;
    EmpresaCNPJ: string;
  end;

  TPortalBoletoRepository = class sealed
  public
    class function ListarPorVencimento(AConnection: TPortalConexao;
      const ADataInicial, ADataFinalExclusiva: TDateTime): TArray<Integer>; static;
    class function CarregarTitulo(AConnection: TPortalConexao;
      const AContaReceberId: Integer): TPortalQuery; static;
    class function CarregarUltimoRetorno(AConnection: TPortalConexao;
      const AContaReceberId: Integer): TPortalQuery; static;
    class function CarregarIdentificacao(AConnection: TPortalConexao;
      const AContaReceberId: Integer): TPortalBoletoIdentificacao; static;
  end;

implementation

uses
  Generics.Collections,
  SysUtils,
  DB,
  Types;

class function TPortalBoletoRepository.ListarPorVencimento(
  AConnection: TPortalConexao;
  const ADataInicial, ADataFinalExclusiva: TDateTime): TArray<Integer>;
var
  IDs: TList<Integer>;
  Query: TPortalQuery;
begin
  if ADataFinalExclusiva <= ADataInicial then
    raise EArgumentOutOfRangeException.Create(
      'O periodo de vencimento informado e invalido.');

  IDs := TList<Integer>.Create;
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text :=
      'select cr.INTERNAL_COD ' +
      'from CONTARECEBER cr ' +
      'where cr.DATA_VENCIMENTO >= :DATA_INICIAL ' +
      '  and cr.DATA_VENCIMENTO < :DATA_FINAL ' +
      '  and cr.COD_FORMA_PAGAMENTO = 6 ' +
      '  and exists (select 1 from PORTAL_CONFIG pc ' +
      '               where pc.COD_EMPRESA = cr.COD_EMPRESA ' +
      '                 and pc.ATIVO = 1) ' +
      '  and exists (select 1 from PORTAL_SYNC_FILA f ' +
      '               where f.COD_EMPRESA = cr.COD_EMPRESA ' +
      '                 and f.TIPO_ENTIDADE = ''TITULO'' ' +
      '                 and f.ID_ORIGEM = cr.INTERNAL_COD) ' +
      'order by cr.COD_EMPRESA, cr.INTERNAL_COD';
    Query.ParamByName('DATA_INICIAL').AsDateTime := ADataInicial;
    Query.ParamByName('DATA_FINAL').AsDateTime := ADataFinalExclusiva;
    Query.Open;
    while not Query.Eof do
    begin
      IDs.Add(Query.FieldByName('INTERNAL_COD').AsInteger);
      Query.Next;
    end;
    Result := IDs.ToArray;
  finally
    Query.Free;
    IDs.Free;
  end;
end;

class function TPortalBoletoRepository.CarregarIdentificacao(
  AConnection: TPortalConexao;
  const AContaReceberId: Integer): TPortalBoletoIdentificacao;
var
  Query: TPortalQuery;
begin
  Result := Default(TPortalBoletoIdentificacao);
  Query := TPortalQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text :=
      'select cr.INTERNAL_COD, cr.COD_PESSOA, cr.COD_EMPRESA, e.CNPJ ' +
      'from CONTARECEBER cr ' +
      'join EMPRESA e on e.INTERNAL_COD = cr.COD_EMPRESA ' +
      'where cr.INTERNAL_COD = :ID';
    Query.ParamByName('ID').AsInteger := AContaReceberId;
    Query.Open;
    if Query.IsEmpty then
      raise Exception.CreateFmt('Titulo %d nao encontrado.',
        [AContaReceberId]);
    Result.ContaReceberId := Query.FieldByName('INTERNAL_COD').AsLargeInt;
    Result.PessoaId := Query.FieldByName('COD_PESSOA').AsLargeInt;
    Result.EmpresaId := Query.FieldByName('COD_EMPRESA').AsInteger;
    Result.EmpresaCNPJ := Query.FieldByName('CNPJ').AsString;
  finally
    Query.Free;
  end;
end;

class function TPortalBoletoRepository.CarregarTitulo(
  AConnection: TPortalConexao; const AContaReceberId: Integer): TPortalQuery;
begin
  Result := TPortalQuery.Create(nil);
  try
    Result.Connection := AConnection;
    Result.SQL.Text :=
      'select ' +
      '  ccr.INTERNAL_COD, ccr.NOSSONUMEROCORRESPONDENTE, ccr.COMPLETO_NN, ' +
      '  ccr.COD_CONTACORRENTE as COD_CONTA, b.NUMERO as CEDENTETIPOCOBRANCA, ' +
      '  c.AGENCIA as CEDENTEAGENCIA, c.DV_AGENCIA as CEDENTEAGENCIADIGITO, ' +
      '  ep.BAIRRO as CEDENTEBAIRRO, c.TIPO_TITULO as CEDENTECARACTITULO, ' +
      '  ep.CEP as CEDENTECEP, cide.NOME as CEDENTECIDADE, ' +
      '  ep.CNPJ as CEDENTECNPJCPF, c.COD_CEDENTE as CEDENTECODIGOCEDENTE, ' +
      '  c.COD_TRANSMISSAO as CEDENTECODIGOTRANSMISSAO, ' +
      '  ep.COMPLEMENTO as CEDENTECOMPLEMENTO, c.NUMERO as CEDENTECONTA, ' +
      '  c.DV_NUMERO as CEDENTECONTADIGITO, c.CONVENIO as CEDENTECONVENIO, ' +
      '  ep.LOGRADOURO as CEDENTELOGRADOURO, c.MODALIDADE as CEDENTEMODALIDADE, ' +
      '  ep.RAZAO_SOCIAL as CEDENTENOME, ep.NUMERO as CEDENTENUMERORES, ' +
      '  c.RESP_EMISSAO as CEDENTERESPONEMISSAO, trim(ue.SIGLA) as CEDENTEUF, ' +
      '  c.REGISTRADO as CEDENTETIPOCARTEIRA, ' +
      '  ''2'' as TITULOCODIGOGERACAO, ccr.DATA_EMISSAO as TITULODATADOCUMENTO, ' +
      '  ccr.DATA_VENCIMENTO as TITULOVENCIMENTO, ' +
      '  ccr.INTERNAL_COD as TITULOSEUNUMERO, ' +
      '  iif(coalesce(ccr.COD_NOTA, 0) > 0, nnf.NUMERO||''/''|| ' +
      '    cast(substring(ccr.DOCUMENTO from position(''/'' in ccr.DOCUMENTO) + 1 for 2) as integer), ' +
      '    ccr.INTERNAL_COD) as TITULONUMERODOCUMENTO, ' +
      '  iif(position(''/'' in ccr.DOCUMENTO) > 0, ' +
      '    substring(ccr.DOCUMENTO from position(''/'' in ccr.DOCUMENTO) + 1 for 2), 1) as PARCELA, ' +
      '  iif(position(''/'' in ccr.DOCUMENTO) > 0, ' +
      '    substring(ccr.DOCUMENTO from position(''/'' in ccr.DOCUMENTO) + 3 for 2), 1) as TOTAL_PARCELA, ' +
      '  c.DIAS_DEVOLUCAO as TITULODIASDEVOLUCAO, c.ESPECIE_DOC as TITULOESPECIEDOC, ' +
      '  ''R$'' as TITULOESPECIEMOD, c.ACEITE as TITULOACEITE, ' +
      '  ccr.DATA_EMISSAO as TITULODATAPROCESSAMENTO, c.CARTEIRA as TITULOCARTEIRA, ' +
      '  ccr.NOSSO_NUMERO as TITULONOSSONUMERO, ccr.VALOR_ORIGINAL as TITULOVALORDOCUMENTO, ' +
      '  c.LOCAL_PGTO as TITULOLOCALPAGAMENTO, ' +
      '  cast(ccr.VALOR_ORIGINAL / 100.00 * c.PERC_JURO / 30.00 as numeric(18,2)) as TITULOVALORMORAJUROS, ' +
      '  ccr.DESCONTO as TITULOVALORDESCONTO, ' +
      '  case when ccr.DESCONTO > 0 then ccr.DATA_VENCIMENTO - c.DIAS_DESCONTO else null end as TITULODATADESCONTO, ' +
      '  0.00 as TITULOVALORABATIMENTO, ' +
      '  case when c.DIAS_ABATIMENTO > 0 then ccr.DATA_VENCIMENTO - c.DIAS_ABATIMENTO else null end as TITULODATAABATIMENTO, ' +
      '  case when c.DIAS_PROTESTO > 0 then ccr.DATA_VENCIMENTO + c.DIAS_PROTESTO else null end as TITULODATAPROTESTO, ' +
      '  c.DIAS_PROTESTO as TITULODIASDEPROTESTO, c.PERC_MULTA as TITULOPERCENTUALMULTA, ' +
      '  ccr.DATA_VENCIMENTO + c.DIAS_MULTA as TITULODATAMORAJUROS, ' +
      '  ''Doc Controle = ''||ccr.DOCUMENTO||iif(ccr.COD_NOTA is null, '''', '' NF = ''||nnf.NUMERO)|| ' +
      '    '' ''||coalesce(c.MENSAGEM, '''') as TITULOMENSAGEM, ' +
      '  c.INSTRUCAO1 as TITULOINSTRUCAO1, c.INSTRUCAO2 as TITULOINSTRUCAO2, ' +
      '  c.DIAS_NEGATIVACAO as TITULODIASNEGATIVACAO, ' +
      '  sa.RAZAO_SOCIAL as SACADONOMESACADO, sa.CNPJ_CPF as SACADOCNPJCPF, ' +
      '  cast(null as varchar(100)) as SACADOAVALISTA, sa.NUMERO as SACADONUMERO, ' +
      '  sa.COMPLEMENTO as SACADOCOMPLEMENTO, sa.LOGRADOURO as SACADOLOGRADOURO, ' +
      '  sa.BAIRRO as SACADOBAIRRO, sa.CEP as SACADOCEP, cids.NOME as SACADOCIDADE, ' +
      '  trim(us.SIGLA) as SACADOUF, ' +
      '  (select first 1 ppe.EMAIL from PESSOA_EMAIL ppe where ppe.COD_PESSOA = sa.INTERNAL_COD) as SACADOEMAIL, ' +
      '  (select first 1 tl.DDD||tl.FONE from TELEFONE tl where tl.COD_PESSOA = sa.INTERNAL_COD) as SACADOFONE, ' +
      '  ccr.COD_NOTA, dd.CHAVE as CHAVENFE, nnf.DATA_EMISSAO as EMISSAONFE, ' +
      '  nnf.NUMERO as NUMNFE, nnf.VL_TOTAL_NOTA as VALORNFE ' +
      'from CONTARECEBER ccr ' +
      'join CONTA c on ccr.COD_CONTACORRENTE = c.INTERNAL_COD ' +
      'join BANCO b on c.COD_BANCO = b.INTERNAL_COD ' +
      'join EMPRESA ep on ccr.COD_EMPRESA = ep.INTERNAL_COD ' +
      'join CIDADE cide on ep.COD_CIDADE = cide.INTERNAL_COD ' +
      'join UF ue on cide.COD_UF = ue.INTERNAL_COD ' +
      'join PESSOA sa on ccr.COD_PESSOA = sa.INTERNAL_COD ' +
      'join CIDADE cids on sa.COD_CIDADE = cids.INTERNAL_COD ' +
      'join UF us on cids.COD_UF = us.INTERNAL_COD ' +
      'left join NOTAFISCAL nnf on ccr.COD_NOTA = nnf.INTERNAL_COD ' +
      'left join NFE_DADOS dd on nnf.INTERNAL_COD = dd.COD_NOTAFISCAL ' +
      'where ccr.INTERNAL_COD = :ID and ccr.COD_FORMA_PAGAMENTO = 6';
    Result.ParamByName('ID').AsInteger := AContaReceberId;
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

class function TPortalBoletoRepository.CarregarUltimoRetorno(
  AConnection: TPortalConexao; const AContaReceberId: Integer): TPortalQuery;
begin
  Result := TPortalQuery.Create(nil);
  try
    Result.Connection := AConnection;
    Result.SQL.Text :=
      'select first 1 e.NOSSONUMERO, e.NOSSONUMEROCORRESPONDENTE, ' +
      '  e.TXID, e.QRCODE, e.URL_PIX, e.VALOR_DOCUMENTO, ' +
      '  e.DATA_VENCIMENTO, e.LINHADIGITAVEL, e.CODIGOBARRAS ' +
      'from CONTAREC_EVENTO e ' +
      'where e.COD_CONTAREC = :ID and e.TIPO_EVENTO = ''RETORNO'' ' +
      '  and coalesce(e.SUCESSO, 1) = 1 ' +
      '  and (e.LINHADIGITAVEL is not null or e.CODIGOBARRAS is not null or e.QRCODE is not null) ' +
      'order by e.DATA_HORA desc';
    Result.ParamByName('ID').AsInteger := AContaReceberId;
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

end.
