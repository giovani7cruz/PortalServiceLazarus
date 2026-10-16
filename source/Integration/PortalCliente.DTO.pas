unit PortalCliente.DTO;

{$mode delphi}

interface

type
  TPortalClienteStatus = (pcsNaoInformado, pcsAtivo, pcsInativo, pcsBloqueado);
  TPortalTipoPessoa = (ptpNaoInformado, ptpFisica, ptpJuridica);
  TPortalTituloStatus = (ptsNaoInformado, ptsAberto, ptsPago, ptsCancelado);

  TPortalPaginacao = record
    Total: Integer;
    TotalRetornado: Integer;
    Pagina: Integer;
    Limite: Integer;
    TotalPaginas: Integer;
  end;

  TPortalClienteFiltro = record
    Pagina: Integer;
    Quantidade: Integer;
    ID: Int64;
    IDExterno: string;
    CPFCNPJ: string;
    NomeRazaoSocial: string;
    BuscaGeral: string;
    Email: string;
    Status: TPortalClienteStatus;
    TipoPessoa: TPortalTipoPessoa;
  end;

  TPortalClienteEnvio = record
    IDExterno: string;
    TipoPessoa: TPortalTipoPessoa;
    CPFCNPJ: string;
    NomeRazaoSocial: string;
    NomeFantasia: string;
    Email: string;
    Telefone: string;
    EnderecoLogradouro: string;
    EnderecoNumero: string;
    EnderecoComplemento: string;
    EnderecoBairro: string;
    EnderecoCEP: string;
    EnderecoCidadeCodigoIBGE: string;
    Status: TPortalClienteStatus;
    Observacoes: string;
  end;

  TPortalCliente = record
    ID: Int64;
    IDExterno: string;
    TipoPessoa: string;
    CPFCNPJ: string;
    NomeRazaoSocial: string;
    NomeFantasia: string;
    Email: string;
    Telefone: string;
    Status: string;
    CreatedAt: string;
    UpdatedAt: string;
  end;

  TPortalClientePagina = record
    Lista: TArray<TPortalCliente>;
    Paginacao: TPortalPaginacao;
  end;

  TPortalTituloFiltro = record
    Pagina: Integer;
    Quantidade: Integer;
    ID: Int64;
    IDExterno: string;
    Descricao: string;
    Status: string;
    DataVencimentoInicio: string;
    DataPagamentoInicio: string;
  end;

  TPortalTituloEnvio = record
    IDExterno: string;
    ClienteIDExterno: string;
    FormaPagamento: string;
    Documento: string;
    Descricao: string;
    Valor: Currency;
    DataEmissao: string;
    DataVencimento: string;
    DataPagamento: string;
    Status: TPortalTituloStatus;
    PixCopiaCola: string;
    BoletoChaveS3: string;
    BoletoLinhaDigitavel: string;
    BoletoNossoNumero: string;
    NotaFiscalNumero: string;
    NotaFiscalChaveS3: string;
    NotaFiscalXMLChaveS3: string;
    Observacoes: string;
  end;

  TPortalTitulo = record
    ID: Int64;
    IDExterno: string;
    EntidadeID: Int64;
    ClienteIDExterno: string;
    Documento: string;
    Descricao: string;
    Valor: Currency;
    DataEmissao: string;
    DataVencimento: string;
    DataPagamento: string;
    Status: string;
    StatusEfetivo: string;
    PixCopiaCola: string;
    BoletoChaveS3: string;
    BoletoLinhaDigitavel: string;
    BoletoNossoNumero: string;
    NotaFiscalNumero: string;
    NotaFiscalChaveS3: string;
    NotaFiscalXMLChaveS3: string;
    Observacoes: string;
    FormaPagamento: string;
    CreatedAt: string;
    UpdatedAt: string;
  end;

  TPortalTituloPagina = record
    Lista: TArray<TPortalTitulo>;
    Paginacao: TPortalPaginacao;
  end;

  TPortalResultadoItem = record
    Indice: Integer;
    IDExterno: string;
    ID: Int64;
    Acao: string;
    Erros: TArray<string>;
    function Sucesso: Boolean;
  end;

  TPortalResumoLote = record
    Total: Integer;
    Criados: Integer;
    Atualizados: Integer;
    Erros: Integer;
  end;

  TPortalResultadoLote = record
    Resumo: TPortalResumoLote;
    Resultados: TArray<TPortalResultadoItem>;
  end;

function PortalClienteStatusToString(const AStatus: TPortalClienteStatus): string;
function PortalTipoPessoaToString(const ATipo: TPortalTipoPessoa): string;
function PortalTituloStatusToString(const AStatus: TPortalTituloStatus): string;

implementation

uses
  SysUtils;

function TPortalResultadoItem.Sucesso: Boolean;
begin
  Result := SameText(Acao, 'criado') or SameText(Acao, 'atualizado');
end;

function PortalClienteStatusToString(
  const AStatus: TPortalClienteStatus): string;
begin
  case AStatus of
    pcsAtivo: Result := 'ativo';
    pcsInativo: Result := 'inativo';
    pcsBloqueado: Result := 'bloqueado';
  else
    Result := '';
  end;
end;

function PortalTipoPessoaToString(const ATipo: TPortalTipoPessoa): string;
begin
  case ATipo of
    ptpFisica: Result := 'fisica';
    ptpJuridica: Result := 'juridica';
  else
    Result := '';
  end;
end;

function PortalTituloStatusToString(
  const AStatus: TPortalTituloStatus): string;
begin
  case AStatus of
    ptsAberto: Result := 'aberto';
    ptsPago: Result := 'pago';
    ptsCancelado: Result := 'cancelado';
  else
    Result := '';
  end;
end;

end.
