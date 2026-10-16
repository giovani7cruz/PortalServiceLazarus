unit PortalCliente.Boleto.ObjectKey;

{$mode delphi}

interface

uses
  PortalCliente.Boleto.Repository;

type
  TPortalBoletoObjectKey = class sealed
  private
    class function SomenteNumeros(const AValor: string): string; static;
  public
    class function Montar(
      const AIdentificacao: TPortalBoletoIdentificacao): string; static;
  end;

implementation

uses
  SysUtils;

class function TPortalBoletoObjectKey.SomenteNumeros(
  const AValor: string): string;
var
  C: Char;
begin
  Result := '';
  for C in AValor do
    if CharInSet(C, ['0'..'9']) then
      Result := Result + C;
end;

class function TPortalBoletoObjectKey.Montar(
  const AIdentificacao: TPortalBoletoIdentificacao): string;
var
  CNPJ: string;
begin
  CNPJ := SomenteNumeros(AIdentificacao.EmpresaCNPJ);
  if CNPJ = '' then
    raise EArgumentException.Create(
      'CNPJ da empresa ausente; nao e seguro montar o Object Key sem ele.');
  if AIdentificacao.PessoaId <= 0 then
    raise EArgumentException.Create('Identificador do cliente invalido.');
  if AIdentificacao.ContaReceberId <= 0 then
    raise EArgumentException.Create('Identificador do titulo invalido.');

  { O CNPJ evita colisao entre bases/empresas. Os dois identificadores AGUIA
    sao os mesmos enviados hoje ao PortalCliente.Client/Title.Mapper. }
  Result := Format(
    'empresas/%s/clientes/AGUIA-CLI-%d/titulos/AGUIA-TIT-%d/boleto.pdf',
    [CNPJ, AIdentificacao.PessoaId, AIdentificacao.ContaReceberId]);
end;

end.
