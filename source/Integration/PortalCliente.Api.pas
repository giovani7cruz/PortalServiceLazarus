unit PortalCliente.Api;

{$mode delphi}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, PortalCliente.Json,
  PortalCliente.Http,
  PortalCliente.DTO;

type
  EPortalClienteApi = class(Exception)
  private
    FHTTPStatus: Integer;
    FResposta: string;
    FErros: TArray<string>;
  public
    constructor Create(const AHTTPStatus: Integer; const AMensagem,
      AResposta: string; const AErros: TArray<string>);
    property HTTPStatus: Integer read FHTTPStatus;
    property Resposta: string read FResposta;
    property Erros: TArray<string> read FErros;
  end;

  TPortalLogProc = procedure(const AMensagem: string) of object;

  TPortalClienteApi = class
  private
    FBaseURL: string;
    FToken: string;
    FHTTP: TPortalHttp;
    FOnLog: TPortalLogProc;
    function Executar(const AMetodo, ARota, ABody: string): TJSONObject;
    function MontarQueryClientes(const AFiltro: TPortalClienteFiltro): string;
    function MontarQueryTitulos(const AFiltro: TPortalTituloFiltro): string;
    function MontarClientes(
      const AClientes: TArray<TPortalClienteEnvio>): string;
    function MontarTitulos(
      const ATitulos: TArray<TPortalTituloEnvio>): string;
    function LerResultadoLote(const ARaiz: TJSONObject): TPortalResultadoLote;
    class function LerErros(const AValor: TJSONValue): TArray<string>; static;
    class function LerPaginacao(const AObjeto: TJSONObject): TPortalPaginacao; static;
    class function LerCliente(const AObjeto: TJSONObject): TPortalCliente; static;
    class function LerTitulo(const AObjeto: TJSONObject): TPortalTitulo; static;
    class function Texto(const AObjeto: TJSONObject;
      const ANome: string): string; static;
    class function Inteiro64(const AObjeto: TJSONObject;
      const ANome: string): Int64; static;
    class function Moeda(const AObjeto: TJSONObject;
      const ANome: string): Currency; static;
    class procedure AdicionarOpcional(const AObjeto: TJSONObject;
      const ANome, AValor: string); static;
    class function JuntarErros(const AErros: TArray<string>): string; static;
  public
    constructor Create(const AToken: string;
      const ABaseURL: string = 'https://portal.infus.inf.br/api';
      const ATimeoutMs: Integer = 60000);
    destructor Destroy; override;

    function ListarClientes(
      const AFiltro: TPortalClienteFiltro): TPortalClientePagina;
    function SalvarClientes(
      const AClientes: TArray<TPortalClienteEnvio>): TPortalResultadoLote;
    function ListarTitulos(
      const AFiltro: TPortalTituloFiltro): TPortalTituloPagina;
    function SalvarTitulos(
      const ATitulos: TArray<TPortalTituloEnvio>): TPortalResultadoLote;

    property BaseURL: string read FBaseURL;
    property OnLog: TPortalLogProc read FOnLog write FOnLog;
  end;

implementation

uses
  Generics.Collections;

type
  TPortalQueryBuilder = record
  private
    FValor: string;
  public
    procedure Adicionar(const ANome, AValor: string); overload;
    procedure Adicionar(const ANome: string; const AValor: Int64); overload;
    function ToString: string;
  end;

{ TPortalQueryBuilder }

procedure TPortalQueryBuilder.Adicionar(const ANome, AValor: string);
begin
  if Trim(AValor) = '' then
    Exit;

  if FValor <> '' then
    FValor := FValor + '&';
  FValor := FValor + UrlCodificar(ANome) + '=' +
    UrlCodificar(AValor);
end;

procedure TPortalQueryBuilder.Adicionar(const ANome: string;
  const AValor: Int64);
begin
  if AValor > 0 then
    Adicionar(ANome, IntToStr(AValor));
end;

function TPortalQueryBuilder.ToString: string;
begin
  if FValor = '' then
    Result := ''
  else
    Result := '?' + FValor;
end;

{ EPortalClienteApi }

constructor EPortalClienteApi.Create(const AHTTPStatus: Integer;
  const AMensagem, AResposta: string; const AErros: TArray<string>);
begin
  inherited Create(AMensagem);
  FHTTPStatus := AHTTPStatus;
  FResposta := AResposta;
  FErros := Copy(AErros, 0, Length(AErros));
end;

{ TPortalClienteApi }

constructor TPortalClienteApi.Create(const AToken, ABaseURL: string;
  const ATimeoutMs: Integer);
var
  Timeout: Integer;
begin
  inherited Create;
  FToken := Trim(AToken);
  if FToken = '' then
    raise EArgumentException.Create('O token do portal nao foi informado.');

  FBaseURL := Trim(ABaseURL);
  while (FBaseURL <> '') and (FBaseURL[Length(FBaseURL)] = '/') do
    Delete(FBaseURL, Length(FBaseURL), 1);
  if FBaseURL = '' then
    raise EArgumentException.Create('A URL do portal nao foi informada.');

  FHTTP := TPortalHttp.Create;
  Timeout := ATimeoutMs;
  if Timeout < 1000 then
    Timeout := 1000
  else if Timeout > 300000 then
    Timeout := 300000;
  FHTTP.TimeoutMs := Timeout;
end;

destructor TPortalClienteApi.Destroy;
begin
  FHTTP.Free;
  inherited;
end;

class procedure TPortalClienteApi.AdicionarOpcional(const AObjeto: TJSONObject;
  const ANome, AValor: string);
begin
  if Trim(AValor) <> '' then
    AObjeto.AddPair(ANome, AValor);
end;

class function TPortalClienteApi.Texto(const AObjeto: TJSONObject;
  const ANome: string): string;
var
  Valor: TJSONValue;
begin
  Result := '';
  if not Assigned(AObjeto) then
    Exit;
  Valor := AObjeto.GetValue(ANome);
  if Assigned(Valor) and not (Valor is TJSONNull) then
    Result := Valor.AsString;
end;

class function TPortalClienteApi.Inteiro64(const AObjeto: TJSONObject;
  const ANome: string): Int64;
begin
  Result := StrToInt64Def(Texto(AObjeto, ANome), 0);
end;

class function TPortalClienteApi.Moeda(const AObjeto: TJSONObject;
  const ANome: string): Currency;
var
  Formato: TFormatSettings;
begin
  Formato := DefaultFormatSettings;
  Formato.DecimalSeparator := '.';
  if not TryStrToCurr(Texto(AObjeto, ANome), Result, Formato) then
    Result := 0;
end;

class function TPortalClienteApi.LerErros(
  const AValor: TJSONValue): TArray<string>;
var
  Lista: TJSONArray;
  I: Integer;
begin
  Result := nil;
  if not (AValor is TJSONArray) then
    Exit;

  Lista := TJSONArray(AValor);
  SetLength(Result, Lista.Count);
  for I := 0 to Lista.Count - 1 do
    Result[I] := Lista.Items[I].AsString;
end;

class function TPortalClienteApi.JuntarErros(
  const AErros: TArray<string>): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AErros) do
  begin
    if Result <> '' then
      Result := Result + '; ';
    Result := Result + AErros[I];
  end;
end;

function TPortalClienteApi.Executar(const AMetodo, ARota,
  ABody: string): TJSONObject;
var
  Resposta: TPortalHttpResposta;
  Stream: TStringStream;
  Valor: TJSONData;
  Erros: TArray<string>;
  Mensagem, Conteudo: string;
  Sucesso: Boolean;
begin
  Result := nil;
  FHTTP.LimparCabecalhos;
  FHTTP.AdicionarCabecalho('Authorization', 'Bearer ' + FToken);
  FHTTP.AdicionarCabecalho('Accept', 'application/json');

  if Assigned(FOnLog) then
    FOnLog(Format('>>> %s %s%s', [AMetodo, FBaseURL, ARota]));

  try
    if SameText(AMetodo, 'GET') then
      Resposta := FHTTP.Get(FBaseURL + ARota)
    else if SameText(AMetodo, 'POST') then
    begin
      FHTTP.AdicionarCabecalho('Content-Type', 'application/json');
      Stream := TStringStream.Create(ABody);
      try
        Resposta := FHTTP.Post(FBaseURL + ARota, Stream);
      finally
        Stream.Free;
      end;
    end
    else
      raise EArgumentException.CreateFmt('Metodo HTTP nao suportado: %s',
        [AMetodo]);
  except
    on E: EPortalClienteApi do
      raise;
    on E: Exception do
      raise EPortalClienteApi.Create(0,
        'Falha de comunicacao com o portal: ' + E.Message, '', nil);
  end;

  Conteudo := Resposta.Corpo;
  if Assigned(FOnLog) then
    FOnLog(Format('<<< HTTP %d', [Resposta.Status]));

  Valor := TJSONObject.ParseJSONValue(Conteudo);
  if not (Valor is TJSONObject) then
  begin
    Valor.Free;
    raise EPortalClienteApi.Create(Resposta.Status,
      'O portal devolveu uma resposta JSON invalida.', Conteudo, nil);
  end;

  Result := TJSONObject(Valor);
  Erros := LerErros(Result.GetValue('erros'));
  Sucesso := SameText(Texto(Result, 'sucesso'), 'true');

  if (Resposta.Status < 200) or (Resposta.Status >= 300) or
     not Sucesso then
  begin
    Mensagem := JuntarErros(Erros);
    if Mensagem = '' then
      Mensagem := Format('O portal devolveu HTTP %d.', [Resposta.Status]);
    FreeAndNil(Result);
    raise EPortalClienteApi.Create(Resposta.Status, Mensagem,
      Conteudo, Erros);
  end;
end;

function TPortalClienteApi.MontarQueryClientes(
  const AFiltro: TPortalClienteFiltro): string;
var
  Query: TPortalQueryBuilder;
begin
  Query := Default(TPortalQueryBuilder);
  Query.Adicionar('pagina', AFiltro.Pagina);
  Query.Adicionar('quantidade', AFiltro.Quantidade);
  Query.Adicionar('id', AFiltro.ID);
  Query.Adicionar('id_externo', AFiltro.IDExterno);
  Query.Adicionar('cpf_cnpj', AFiltro.CPFCNPJ);
  Query.Adicionar('nome_razao_social', AFiltro.NomeRazaoSocial);
  Query.Adicionar('busca_geral', AFiltro.BuscaGeral);
  Query.Adicionar('email', AFiltro.Email);
  Query.Adicionar('status', PortalClienteStatusToString(AFiltro.Status));
  Query.Adicionar('tipo_pessoa', PortalTipoPessoaToString(AFiltro.TipoPessoa));
  Result := Query.ToString;
end;

function TPortalClienteApi.MontarQueryTitulos(
  const AFiltro: TPortalTituloFiltro): string;
var
  Query: TPortalQueryBuilder;
begin
  Query := Default(TPortalQueryBuilder);
  Query.Adicionar('pagina', AFiltro.Pagina);
  Query.Adicionar('quantidade', AFiltro.Quantidade);
  Query.Adicionar('id', AFiltro.ID);
  Query.Adicionar('id_externo', AFiltro.IDExterno);
  Query.Adicionar('descricao', AFiltro.Descricao);
  Query.Adicionar('status', AFiltro.Status);
  Query.Adicionar('data_vencimento_inicio', AFiltro.DataVencimentoInicio);
  Query.Adicionar('data_pagamento_inicio', AFiltro.DataPagamentoInicio);
  Result := Query.ToString;
end;

function TPortalClienteApi.MontarClientes(
  const AClientes: TArray<TPortalClienteEnvio>): string;
var
  Lista: TJSONArray;
  Item: TJSONObject;
  Cliente: TPortalClienteEnvio;
begin
  if (Length(AClientes) < 1) or (Length(AClientes) > 100) then
    raise EArgumentOutOfRangeException.Create(
      'O lote de clientes deve conter de 1 a 100 itens.');

  Lista := TJSONArray.Create;
  try
    for Cliente in AClientes do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('id_externo', Cliente.IDExterno);
      Item.AddPair('tipo_pessoa', PortalTipoPessoaToString(Cliente.TipoPessoa));
      Item.AddPair('cpf_cnpj', Cliente.CPFCNPJ);
      Item.AddPair('nome_razao_social', Cliente.NomeRazaoSocial);
      AdicionarOpcional(Item, 'nome_fantasia', Cliente.NomeFantasia);
      Item.AddPair('email', Cliente.Email);
      Item.AddPair('telefone', Cliente.Telefone);
      AdicionarOpcional(Item, 'endereco_logradouro', Cliente.EnderecoLogradouro);
      AdicionarOpcional(Item, 'endereco_numero', Cliente.EnderecoNumero);
      AdicionarOpcional(Item, 'endereco_complemento', Cliente.EnderecoComplemento);
      AdicionarOpcional(Item, 'endereco_bairro', Cliente.EnderecoBairro);
      AdicionarOpcional(Item, 'endereco_cep', Cliente.EnderecoCEP);
      Item.AddPair('endereco_cidade_codigo_ibge',
        Cliente.EnderecoCidadeCodigoIBGE);
      AdicionarOpcional(Item, 'status',
        PortalClienteStatusToString(Cliente.Status));
      AdicionarOpcional(Item, 'observacoes', Cliente.Observacoes);
      Lista.AddElement(Item);
    end;
    Result := Lista.ToJSON;
  finally
    Lista.Free;
  end;
end;

function TPortalClienteApi.MontarTitulos(
  const ATitulos: TArray<TPortalTituloEnvio>): string;
var
  Lista: TJSONArray;
  Item: TJSONObject;
  Titulo: TPortalTituloEnvio;
begin
  if (Length(ATitulos) < 1) or (Length(ATitulos) > 100) then
    raise EArgumentOutOfRangeException.Create(
      'O lote de titulos deve conter de 1 a 100 itens.');

  Lista := TJSONArray.Create;
  try
    for Titulo in ATitulos do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('id_externo', Titulo.IDExterno);
      Item.AddPair('cliente_id_externo', Titulo.ClienteIDExterno);
      Item.AddPair('forma_pagamento', Titulo.FormaPagamento);
      Item.AddPair('documento', Titulo.Documento);
      Item.AddPair('descricao', Titulo.Descricao);
      Item.AddPair('valor', TJSONNumero(Titulo.Valor));
      Item.AddPair('data_emissao', Titulo.DataEmissao);
      Item.AddPair('data_vencimento', Titulo.DataVencimento);
      if Trim(Titulo.DataPagamento) = '' then
        Item.AddPair('data_pagamento', TJSONNull.Create)
      else
        Item.AddPair('data_pagamento', Titulo.DataPagamento);
      AdicionarOpcional(Item, 'status',
        PortalTituloStatusToString(Titulo.Status));
      AdicionarOpcional(Item, 'pix_copia_cola', Titulo.PixCopiaCola);
      AdicionarOpcional(Item, 'boleto_chave_s3', Titulo.BoletoChaveS3);
      AdicionarOpcional(Item, 'boleto_linha_digitavel',
        Titulo.BoletoLinhaDigitavel);
      AdicionarOpcional(Item, 'boleto_nosso_numero',
        Titulo.BoletoNossoNumero);
      AdicionarOpcional(Item, 'nota_fiscal_numero', Titulo.NotaFiscalNumero);
      AdicionarOpcional(Item, 'nota_fiscal_chave_s3',
        Titulo.NotaFiscalChaveS3);
      AdicionarOpcional(Item, 'nota_fiscal_xml_chave_s3',
        Titulo.NotaFiscalXMLChaveS3);
      AdicionarOpcional(Item, 'observacoes', Titulo.Observacoes);
      Lista.AddElement(Item);
    end;
    Result := Lista.ToJSON;
  finally
    Lista.Free;
  end;
end;

class function TPortalClienteApi.LerPaginacao(
  const AObjeto: TJSONObject): TPortalPaginacao;
begin
  Result := Default(TPortalPaginacao);
  Result.Total := Inteiro64(AObjeto, 'total');
  Result.TotalRetornado := Inteiro64(AObjeto, 'total_retornado');
  Result.Pagina := Inteiro64(AObjeto, 'pagina');
  Result.Limite := Inteiro64(AObjeto, 'limite');
  Result.TotalPaginas := Inteiro64(AObjeto, 'total_paginas');
end;

class function TPortalClienteApi.LerCliente(
  const AObjeto: TJSONObject): TPortalCliente;
begin
  Result := Default(TPortalCliente);
  Result.ID := Inteiro64(AObjeto, 'id');
  Result.IDExterno := Texto(AObjeto, 'id_externo');
  Result.TipoPessoa := Texto(AObjeto, 'tipo_pessoa');
  Result.CPFCNPJ := Texto(AObjeto, 'cpf_cnpj');
  Result.NomeRazaoSocial := Texto(AObjeto, 'nome_razao_social');
  Result.NomeFantasia := Texto(AObjeto, 'nome_fantasia');
  Result.Email := Texto(AObjeto, 'email');
  Result.Telefone := Texto(AObjeto, 'telefone');
  Result.Status := Texto(AObjeto, 'status');
  Result.CreatedAt := Texto(AObjeto, 'created_at');
  Result.UpdatedAt := Texto(AObjeto, 'updated_at');
end;

class function TPortalClienteApi.LerTitulo(
  const AObjeto: TJSONObject): TPortalTitulo;
begin
  Result := Default(TPortalTitulo);
  Result.ID := Inteiro64(AObjeto, 'id');
  Result.IDExterno := Texto(AObjeto, 'id_externo');
  Result.EntidadeID := Inteiro64(AObjeto, 'entidade_id');
  Result.ClienteIDExterno := Texto(AObjeto, 'cliente_id_externo');
  Result.Documento := Texto(AObjeto, 'documento');
  Result.Descricao := Texto(AObjeto, 'descricao');
  Result.Valor := Moeda(AObjeto, 'valor');
  Result.DataEmissao := Texto(AObjeto, 'data_emissao');
  Result.DataVencimento := Texto(AObjeto, 'data_vencimento');
  Result.DataPagamento := Texto(AObjeto, 'data_pagamento');
  Result.Status := Texto(AObjeto, 'status');
  Result.StatusEfetivo := Texto(AObjeto, 'status_efetivo');
  Result.PixCopiaCola := Texto(AObjeto, 'pix_copia_cola');
  Result.BoletoChaveS3 := Texto(AObjeto, 'boleto_chave_s3');
  if Result.BoletoChaveS3.IsEmpty then
    Result.BoletoChaveS3 := Texto(AObjeto, 'boleto_link');
  Result.BoletoLinhaDigitavel := Texto(AObjeto, 'boleto_linha_digitavel');
  Result.BoletoNossoNumero := Texto(AObjeto, 'boleto_nosso_numero');
  Result.NotaFiscalNumero := Texto(AObjeto, 'nota_fiscal_numero');
  Result.NotaFiscalChaveS3 := Texto(AObjeto, 'nota_fiscal_chave_s3');
  if Result.NotaFiscalChaveS3.IsEmpty then
    Result.NotaFiscalChaveS3 := Texto(AObjeto, 'nota_fiscal_link');
  Result.NotaFiscalXMLChaveS3 := Texto(AObjeto,
    'nota_fiscal_xml_chave_s3');
  if Result.NotaFiscalXMLChaveS3.IsEmpty then
    Result.NotaFiscalXMLChaveS3 := Texto(AObjeto, 'nota_fiscal_xml_link');
  Result.Observacoes := Texto(AObjeto, 'observacoes');
  Result.FormaPagamento := Texto(AObjeto, 'forma_pagamento');
  Result.CreatedAt := Texto(AObjeto, 'created_at');
  Result.UpdatedAt := Texto(AObjeto, 'updated_at');
end;

function TPortalClienteApi.LerResultadoLote(
  const ARaiz: TJSONObject): TPortalResultadoLote;
var
  Dados, Resumo, Item: TJSONObject;
  Lista: TJSONArray;
  I: Integer;
begin
  Result := Default(TPortalResultadoLote);
  Dados := ARaiz.GetValue('dados') as TJSONObject;
  if not Assigned(Dados) then
    Exit;

  Resumo := Dados.GetValue('resumo') as TJSONObject;
  if Assigned(Resumo) then
  begin
    Result.Resumo.Total := Inteiro64(Resumo, 'total');
    Result.Resumo.Criados := Inteiro64(Resumo, 'criados');
    Result.Resumo.Atualizados := Inteiro64(Resumo, 'atualizados');
    Result.Resumo.Erros := Inteiro64(Resumo, 'erros');
  end;

  Lista := Dados.GetValue('resultados') as TJSONArray;
  if not Assigned(Lista) then
    Exit;
  SetLength(Result.Resultados, Lista.Count);
  for I := 0 to Lista.Count - 1 do
    if Lista.Items[I] is TJSONObject then
    begin
      Item := TJSONObject(Lista.Items[I]);
      Result.Resultados[I].Indice := Inteiro64(Item, 'indice');
      Result.Resultados[I].IDExterno := Texto(Item, 'id_externo');
      Result.Resultados[I].ID := Inteiro64(Item, 'id');
      Result.Resultados[I].Acao := Texto(Item, 'acao');
      Result.Resultados[I].Erros := LerErros(Item.GetValue('erros'));
    end;
end;

function TPortalClienteApi.ListarClientes(
  const AFiltro: TPortalClienteFiltro): TPortalClientePagina;
var
  Raiz, Dados: TJSONObject;
  Lista: TJSONArray;
  I: Integer;
begin
  Result := Default(TPortalClientePagina);
  Raiz := Executar('GET', '/clientes' + MontarQueryClientes(AFiltro), '');
  try
    Dados := Raiz.GetValue('dados') as TJSONObject;
    if not Assigned(Dados) then
      Exit;
    Lista := Dados.GetValue('lista') as TJSONArray;
    if Assigned(Lista) then
    begin
      SetLength(Result.Lista, Lista.Count);
      for I := 0 to Lista.Count - 1 do
        if Lista.Items[I] is TJSONObject then
          Result.Lista[I] := LerCliente(TJSONObject(Lista.Items[I]));
    end;
    Result.Paginacao := LerPaginacao(
      Dados.GetValue('paginacao') as TJSONObject);
  finally
    Raiz.Free;
  end;
end;

function TPortalClienteApi.SalvarClientes(
  const AClientes: TArray<TPortalClienteEnvio>): TPortalResultadoLote;
var
  Raiz: TJSONObject;
begin
  Raiz := Executar('POST', '/clientes', MontarClientes(AClientes));
  try
    Result := LerResultadoLote(Raiz);
  finally
    Raiz.Free;
  end;
end;

function TPortalClienteApi.ListarTitulos(
  const AFiltro: TPortalTituloFiltro): TPortalTituloPagina;
var
  Raiz, Dados: TJSONObject;
  Lista: TJSONArray;
  I: Integer;
begin
  Result := Default(TPortalTituloPagina);
  Raiz := Executar('GET',
    '/financeiro-titulos' + MontarQueryTitulos(AFiltro), '');
  try
    Dados := Raiz.GetValue('dados') as TJSONObject;
    if not Assigned(Dados) then
      Exit;
    Lista := Dados.GetValue('lista') as TJSONArray;
    if Assigned(Lista) then
    begin
      SetLength(Result.Lista, Lista.Count);
      for I := 0 to Lista.Count - 1 do
        if Lista.Items[I] is TJSONObject then
          Result.Lista[I] := LerTitulo(TJSONObject(Lista.Items[I]));
    end;
    Result.Paginacao := LerPaginacao(
      Dados.GetValue('paginacao') as TJSONObject);
  finally
    Raiz.Free;
  end;
end;

function TPortalClienteApi.SalvarTitulos(
  const ATitulos: TArray<TPortalTituloEnvio>): TPortalResultadoLote;
var
  Raiz: TJSONObject;
begin
  Raiz := Executar('POST', '/financeiro-titulos', MontarTitulos(ATitulos));
  try
    Result := LerResultadoLote(Raiz);
  finally
    Raiz.Free;
  end;
end;

end.
