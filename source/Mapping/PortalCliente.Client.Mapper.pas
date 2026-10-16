unit PortalCliente.Client.Mapper;

{$mode delphi}

interface

uses
  fpjson, jsonparser, PortalCliente.Json,
  PortalCliente.Client.Repository,
  PortalCliente.DTO;

type
  TPortalClienteMapResult = record
    Cliente: TPortalClienteEnvio;
    Erros: TArray<string>;
    function Valido: Boolean;
  end;

  TPortalClienteMapper = class sealed
  private
    class function ApenasDigitos(const AValor: string): string; static;
    class function CPFValido(const ACPF: string): Boolean; static;
    class function CNPJValido(const ACNPJ: string): Boolean; static;
    class function DocumentoValido(const ADocumento: string): Boolean; static;
    class function EmailValido(const AEmail: string): Boolean; static;
    class function TipoPessoaTexto(const ATipo: TPortalTipoPessoa): string; static;
    class function StatusTexto(const AStatus: TPortalClienteStatus): string; static;
    class procedure AdicionarOpcional(const AJSON: TJSONObject;
      const ANome, AValor: string); static;
  public
    class function Mapear(
      const AOrigem: TPortalClienteOrigem): TPortalClienteMapResult; static;
    class function ParaJSON(
      const ACliente: TPortalClienteEnvio): TJSONObject; static;
    class function DoJSON(
      const APayload: string): TPortalClienteEnvio; static;
  end;

implementation

uses
  Generics.Collections,
  SysUtils;

function TPortalClienteMapResult.Valido: Boolean;
begin
  Result := Length(Erros) = 0;
end;

class function TPortalClienteMapper.ApenasDigitos(const AValor: string): string;
var
  C: Char;
begin
  Result := '';
  for C in AValor do
    if CharInSet(C, ['0'..'9']) then
      Result := Result + C;
end;

class function TPortalClienteMapper.CPFValido(const ACPF: string): Boolean;
var
  Digito1: Integer;
  Digito2: Integer;
  I: Integer;
  Soma: Integer;
begin
  Result := False;
  if Length(ACPF) <> 11 then
    Exit;
  if ACPF = StringOfChar(ACPF[1], Length(ACPF)) then
    Exit;

  Soma := 0;
  for I := 1 to 9 do
    Inc(Soma, (Ord(ACPF[I]) - Ord('0')) * (11 - I));
  Digito1 := 11 - (Soma mod 11);
  if Digito1 >= 10 then
    Digito1 := 0;

  Soma := 0;
  for I := 1 to 10 do
    Inc(Soma, (Ord(ACPF[I]) - Ord('0')) * (12 - I));
  Digito2 := 11 - (Soma mod 11);
  if Digito2 >= 10 then
    Digito2 := 0;

  Result := (Digito1 = Ord(ACPF[10]) - Ord('0')) and
    (Digito2 = Ord(ACPF[11]) - Ord('0'));
end;

class function TPortalClienteMapper.CNPJValido(const ACNPJ: string): Boolean;
const
  PESOS1: array[1..12] of Integer = (5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2);
  PESOS2: array[1..13] of Integer = (6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2);
var
  Digito1: Integer;
  Digito2: Integer;
  I: Integer;
  Resto: Integer;
  Soma: Integer;
begin
  Result := False;
  if Length(ACNPJ) <> 14 then
    Exit;
  if ACNPJ = StringOfChar(ACNPJ[1], Length(ACNPJ)) then
    Exit;

  Soma := 0;
  for I := 1 to 12 do
    Inc(Soma, (Ord(ACNPJ[I]) - Ord('0')) * PESOS1[I]);
  Resto := Soma mod 11;
  if Resto < 2 then
    Digito1 := 0
  else
    Digito1 := 11 - Resto;

  Soma := 0;
  for I := 1 to 13 do
    Inc(Soma, (Ord(ACNPJ[I]) - Ord('0')) * PESOS2[I]);
  Resto := Soma mod 11;
  if Resto < 2 then
    Digito2 := 0
  else
    Digito2 := 11 - Resto;

  Result := (Digito1 = Ord(ACNPJ[13]) - Ord('0')) and
    (Digito2 = Ord(ACNPJ[14]) - Ord('0'));
end;

class function TPortalClienteMapper.DocumentoValido(
  const ADocumento: string): Boolean;
begin
  case Length(ADocumento) of
    11: Result := CPFValido(ADocumento);
    14: Result := CNPJValido(ADocumento);
  else
    Result := False;
  end;
end;

class function TPortalClienteMapper.EmailValido(const AEmail: string): Boolean;
var
  Arroba: Integer;
  Ponto: Integer;
begin
  Arroba := Pos('@', AEmail);
  Ponto := LastDelimiter('.', AEmail);
  Result := (Arroba > 1) and (Ponto > Arroba + 1) and
    (Ponto < Length(AEmail)) and (Pos(' ', AEmail) = 0);
end;

class function TPortalClienteMapper.Mapear(
  const AOrigem: TPortalClienteOrigem): TPortalClienteMapResult;
var
  Erros: TList<string>;
begin
  Result := Default(TPortalClienteMapResult);
  Erros := TList<string>.Create;
  try
    Result.Cliente.IDExterno := Format('AGUIA-CLI-%d', [AOrigem.Codigo]);
    case AOrigem.TipoPessoa of
      0: Result.Cliente.TipoPessoa := ptpFisica;
      1: Result.Cliente.TipoPessoa := ptpJuridica;
    else
      begin
        Result.Cliente.TipoPessoa := ptpNaoInformado;
        Erros.Add('tipo de pessoa nao suportado pela API');
      end;
    end;

    Result.Cliente.CPFCNPJ := ApenasDigitos(AOrigem.CPFCNPJ);
    Result.Cliente.NomeRazaoSocial := AOrigem.RazaoSocial.Trim;
    Result.Cliente.NomeFantasia := AOrigem.NomeFantasia.Trim;
    Result.Cliente.Email := AOrigem.Email.Trim;
    Result.Cliente.Telefone := ApenasDigitos(AOrigem.Telefone);
    Result.Cliente.EnderecoLogradouro := AOrigem.Logradouro.Trim;
    Result.Cliente.EnderecoNumero := AOrigem.Numero.Trim;
    Result.Cliente.EnderecoComplemento := AOrigem.Complemento.Trim;
    Result.Cliente.EnderecoBairro := AOrigem.Bairro.Trim;
    Result.Cliente.EnderecoCEP := ApenasDigitos(AOrigem.CEP);
    Result.Cliente.EnderecoCidadeCodigoIBGE := ApenasDigitos(AOrigem.CodigoIBGE);
    Result.Cliente.Observacoes := AOrigem.Observacoes.Trim;

    case AOrigem.CodigoStatus of
      1: Result.Cliente.Status := pcsAtivo;
      4: Result.Cliente.Status := pcsBloqueado;
    else
      Result.Cliente.Status := pcsInativo;
    end;

    if not DocumentoValido(Result.Cliente.CPFCNPJ) then
      Erros.Add('CPF/CNPJ invalido');
    if Result.Cliente.NomeRazaoSocial.IsEmpty then
      Erros.Add('razao social vazia');
    if not EmailValido(Result.Cliente.Email) then
      Erros.Add('e-mail ausente ou invalido');
    if Result.Cliente.Telefone.IsEmpty then
      Erros.Add('telefone ausente');
    if Result.Cliente.EnderecoCidadeCodigoIBGE.IsEmpty then
      Erros.Add('codigo IBGE da cidade ausente');
    if (not Result.Cliente.EnderecoCEP.IsEmpty) and
      (Length(Result.Cliente.EnderecoCEP) <> 8) then
      Erros.Add('CEP deve possuir 8 digitos');

    Result.Erros := Erros.ToArray;
  finally
    Erros.Free;
  end;
end;

class procedure TPortalClienteMapper.AdicionarOpcional(const AJSON: TJSONObject;
  const ANome, AValor: string);
begin
  if not AValor.IsEmpty then
    AJSON.AddPair(ANome, AValor);
end;

class function TPortalClienteMapper.TipoPessoaTexto(
  const ATipo: TPortalTipoPessoa): string;
begin
  case ATipo of
    ptpFisica: Result := 'fisica';
    ptpJuridica: Result := 'juridica';
  else
    Result := '';
  end;
end;

class function TPortalClienteMapper.StatusTexto(
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

class function TPortalClienteMapper.ParaJSON(
  const ACliente: TPortalClienteEnvio): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id_externo', ACliente.IDExterno);
  Result.AddPair('tipo_pessoa', TipoPessoaTexto(ACliente.TipoPessoa));
  Result.AddPair('cpf_cnpj', ACliente.CPFCNPJ);
  Result.AddPair('nome_razao_social', ACliente.NomeRazaoSocial);
  AdicionarOpcional(Result, 'nome_fantasia', ACliente.NomeFantasia);
  Result.AddPair('email', ACliente.Email);
  Result.AddPair('telefone', ACliente.Telefone);
  AdicionarOpcional(Result, 'endereco_logradouro', ACliente.EnderecoLogradouro);
  AdicionarOpcional(Result, 'endereco_numero', ACliente.EnderecoNumero);
  AdicionarOpcional(Result, 'endereco_complemento', ACliente.EnderecoComplemento);
  AdicionarOpcional(Result, 'endereco_bairro', ACliente.EnderecoBairro);
  AdicionarOpcional(Result, 'endereco_cep', ACliente.EnderecoCEP);
  Result.AddPair('endereco_cidade_codigo_ibge',
    ACliente.EnderecoCidadeCodigoIBGE);
  Result.AddPair('status', StatusTexto(ACliente.Status));
  AdicionarOpcional(Result, 'observacoes', ACliente.Observacoes);
end;

class function TPortalClienteMapper.DoJSON(
  const APayload: string): TPortalClienteEnvio;
var
  Objeto: TJSONObject;
  TipoPessoa: string;
  Status: string;
  Valor: TJSONData;

  function Texto(const ANome: string): string;
  begin
    Result := '';
    Valor := Objeto.GetValue(ANome);
    if Assigned(Valor) and not (Valor is TJSONNull) then
      Result := Valor.AsString;
  end;

begin
  Result := Default(TPortalClienteEnvio);
  Objeto := TJSONObject.ParseJSONValue(APayload) as TJSONObject;
  if not Assigned(Objeto) then
    raise EConvertError.Create('Payload do cliente nao e um objeto JSON valido.');
  try
    Result.IDExterno := Texto('id_externo');
    TipoPessoa := Texto('tipo_pessoa');
    if SameText(TipoPessoa, 'fisica') then
      Result.TipoPessoa := ptpFisica
    else if SameText(TipoPessoa, 'juridica') then
      Result.TipoPessoa := ptpJuridica
    else
      raise EConvertError.CreateFmt('tipo_pessoa invalido: %s', [TipoPessoa]);

    Result.CPFCNPJ := Texto('cpf_cnpj');
    Result.NomeRazaoSocial := Texto('nome_razao_social');
    Result.NomeFantasia := Texto('nome_fantasia');
    Result.Email := Texto('email');
    Result.Telefone := Texto('telefone');
    Result.EnderecoLogradouro := Texto('endereco_logradouro');
    Result.EnderecoNumero := Texto('endereco_numero');
    Result.EnderecoComplemento := Texto('endereco_complemento');
    Result.EnderecoBairro := Texto('endereco_bairro');
    Result.EnderecoCEP := Texto('endereco_cep');
    Result.EnderecoCidadeCodigoIBGE :=
      Texto('endereco_cidade_codigo_ibge');
    Result.Observacoes := Texto('observacoes');

    Status := Texto('status');
    if SameText(Status, 'ativo') then
      Result.Status := pcsAtivo
    else if SameText(Status, 'inativo') then
      Result.Status := pcsInativo
    else if SameText(Status, 'bloqueado') then
      Result.Status := pcsBloqueado
    else
      raise EConvertError.CreateFmt('status invalido: %s', [Status]);
  finally
    Objeto.Free;
  end;
end;

end.
