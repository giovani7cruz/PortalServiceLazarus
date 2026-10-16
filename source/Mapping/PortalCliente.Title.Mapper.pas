unit PortalCliente.Title.Mapper;

{$mode delphi}

interface

uses
  fpjson, jsonparser, PortalCliente.Json,
  PortalCliente.DTO,
  PortalCliente.Title.Repository;

type
  TPortalTituloMapResult = record
    Titulo: TPortalTituloEnvio;
    Erros: TArray<string>;
    function Valido: Boolean;
  end;

  TPortalTituloMapper = class sealed
  private
    class function DataISO(const AData: TDateTime): string; static;
    class procedure AdicionarOpcional(const AJSON: TJSONObject;
      const ANome, AValor: string); static;
  public
    class function Mapear(
      const AOrigem: TPortalTituloOrigem): TPortalTituloMapResult; static;
    class procedure PreservarDocumentos(
      const AAnterior: TPortalTituloEnvio;
      var AAtual: TPortalTituloEnvio); static;
    class function ParaJSON(
      const ATitulo: TPortalTituloEnvio): TJSONObject; static;
    class function DoJSON(
      const APayload: string): TPortalTituloEnvio; static;
  end;

implementation

uses
  Generics.Collections,
  SysUtils;

function TPortalTituloMapResult.Valido: Boolean;
begin
  Result := Length(Erros) = 0;
end;

class function TPortalTituloMapper.DataISO(const AData: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd', AData);
end;

class function TPortalTituloMapper.Mapear(
  const AOrigem: TPortalTituloOrigem): TPortalTituloMapResult;
var
  Erros: TList<string>;
begin
  Result := Default(TPortalTituloMapResult);
  Erros := TList<string>.Create;
  try
    Result.Titulo.IDExterno := Format('AGUIA-TIT-%d', [AOrigem.Codigo]);
    Result.Titulo.ClienteIDExterno :=
      Format('AGUIA-CLI-%d', [AOrigem.CodigoPessoa]);
    Result.Titulo.FormaPagamento := Copy(AOrigem.FormaPagamento.Trim, 1, 64);
    Result.Titulo.Documento := Copy(AOrigem.Documento.Trim, 1, 25);
    Result.Titulo.Descricao := Copy(
      'Titulo financeiro ' + AOrigem.Documento.Trim, 1, 255);
    Result.Titulo.Valor := AOrigem.ValorOriginal;
    if AOrigem.TemDataEmissao then
      Result.Titulo.DataEmissao := DataISO(AOrigem.DataEmissao);
    if AOrigem.TemDataVencimento then
      Result.Titulo.DataVencimento := DataISO(AOrigem.DataVencimento);

    if AOrigem.Saldo <= 0 then
    begin
      Result.Titulo.Status := ptsPago;
      if AOrigem.TemDataPagamento then
        Result.Titulo.DataPagamento := DataISO(AOrigem.DataPagamento)
      else
        Erros.Add('titulo quitado sem data de pagamento');
    end
    else
      Result.Titulo.Status := ptsAberto;

    Result.Titulo.BoletoNossoNumero := AOrigem.NossoNumero.Trim;
    Result.Titulo.NotaFiscalNumero := AOrigem.NotaFiscalNumero.Trim;
    Result.Titulo.Observacoes := AOrigem.Observacoes.Trim;

    if Result.Titulo.ClienteIDExterno.IsEmpty then
      Erros.Add('cliente ausente');
    if Result.Titulo.FormaPagamento.IsEmpty then
      Erros.Add('forma de pagamento ausente');
    if Result.Titulo.Documento.IsEmpty then
      Erros.Add('documento ausente');
    if (Result.Titulo.Valor < 0.01) or
      (Result.Titulo.Valor > 99999999.99) then
      Erros.Add('valor fora do intervalo aceito pela API');
    if Result.Titulo.DataEmissao.IsEmpty then
      Erros.Add('data de emissao ausente');
    if Result.Titulo.DataVencimento.IsEmpty then
      Erros.Add('data de vencimento ausente');

    Result.Erros := Erros.ToArray;
  finally
    Erros.Free;
  end;
end;

class procedure TPortalTituloMapper.PreservarDocumentos(
  const AAnterior: TPortalTituloEnvio;
  var AAtual: TPortalTituloEnvio);
begin
  if AAtual.PixCopiaCola.IsEmpty then
    AAtual.PixCopiaCola := AAnterior.PixCopiaCola;
  if AAtual.BoletoChaveS3.IsEmpty then
    AAtual.BoletoChaveS3 := AAnterior.BoletoChaveS3;
  if AAtual.BoletoLinhaDigitavel.IsEmpty then
    AAtual.BoletoLinhaDigitavel := AAnterior.BoletoLinhaDigitavel;
  if AAtual.BoletoNossoNumero.IsEmpty then
    AAtual.BoletoNossoNumero := AAnterior.BoletoNossoNumero;
  if AAtual.NotaFiscalNumero.IsEmpty then
    AAtual.NotaFiscalNumero := AAnterior.NotaFiscalNumero;
  if AAtual.NotaFiscalChaveS3.IsEmpty then
    AAtual.NotaFiscalChaveS3 := AAnterior.NotaFiscalChaveS3;
  if AAtual.NotaFiscalXMLChaveS3.IsEmpty then
    AAtual.NotaFiscalXMLChaveS3 := AAnterior.NotaFiscalXMLChaveS3;
end;

class procedure TPortalTituloMapper.AdicionarOpcional(
  const AJSON: TJSONObject; const ANome, AValor: string);
begin
  if not AValor.IsEmpty then
    AJSON.AddPair(ANome, AValor);
end;

class function TPortalTituloMapper.ParaJSON(
  const ATitulo: TPortalTituloEnvio): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id_externo', ATitulo.IDExterno);
  Result.AddPair('cliente_id_externo', ATitulo.ClienteIDExterno);
  Result.AddPair('forma_pagamento', ATitulo.FormaPagamento);
  Result.AddPair('documento', ATitulo.Documento);
  Result.AddPair('descricao', ATitulo.Descricao);
  Result.AddPair('valor', TJSONNumero(ATitulo.Valor));
  Result.AddPair('data_emissao', ATitulo.DataEmissao);
  Result.AddPair('data_vencimento', ATitulo.DataVencimento);
  if ATitulo.DataPagamento.IsEmpty then
    Result.AddPair('data_pagamento', TJSONNull.Create)
  else
    Result.AddPair('data_pagamento', ATitulo.DataPagamento);
  Result.AddPair('status', PortalTituloStatusToString(ATitulo.Status));
  AdicionarOpcional(Result, 'pix_copia_cola', ATitulo.PixCopiaCola);
  AdicionarOpcional(Result, 'boleto_chave_s3', ATitulo.BoletoChaveS3);
  AdicionarOpcional(Result, 'boleto_linha_digitavel',
    ATitulo.BoletoLinhaDigitavel);
  AdicionarOpcional(Result, 'boleto_nosso_numero',
    ATitulo.BoletoNossoNumero);
  AdicionarOpcional(Result, 'nota_fiscal_numero',
    ATitulo.NotaFiscalNumero);
  AdicionarOpcional(Result, 'nota_fiscal_chave_s3',
    ATitulo.NotaFiscalChaveS3);
  AdicionarOpcional(Result, 'nota_fiscal_xml_chave_s3',
    ATitulo.NotaFiscalXMLChaveS3);
  AdicionarOpcional(Result, 'observacoes', ATitulo.Observacoes);
end;

class function TPortalTituloMapper.DoJSON(
  const APayload: string): TPortalTituloEnvio;
var
  Formato: TFormatSettings;
  Objeto: TJSONObject;
  Status: string;
  ValorJSON: TJSONData;

  function Texto(const ANome: string): string;
  var
    Valor: TJSONData;
  begin
    Result := '';
    Valor := Objeto.GetValue(ANome);
    if Assigned(Valor) and not (Valor is TJSONNull) then
      Result := Valor.AsString;
  end;

begin
  Result := Default(TPortalTituloEnvio);
  Objeto := TJSONObject.ParseJSONValue(APayload) as TJSONObject;
  if not Assigned(Objeto) then
    raise EConvertError.Create('Payload do titulo nao e um objeto JSON valido.');
  try
    Result.IDExterno := Texto('id_externo');
    Result.ClienteIDExterno := Texto('cliente_id_externo');
    Result.FormaPagamento := Texto('forma_pagamento');
    Result.Documento := Texto('documento');
    Result.Descricao := Texto('descricao');
    Formato := DefaultFormatSettings;
    Formato.DecimalSeparator := '.';
    ValorJSON := Objeto.GetValue('valor');
    if not Assigned(ValorJSON) or
      not TryStrToCurr(ValorJSON.AsString, Result.Valor, Formato) then
      raise EConvertError.Create('valor invalido no payload do titulo');
    Result.DataEmissao := Texto('data_emissao');
    Result.DataVencimento := Texto('data_vencimento');
    Result.DataPagamento := Texto('data_pagamento');
    Status := Texto('status');
    if SameText(Status, 'aberto') then
      Result.Status := ptsAberto
    else if SameText(Status, 'pago') then
      Result.Status := ptsPago
    else if SameText(Status, 'cancelado') then
      Result.Status := ptsCancelado
    else
      raise EConvertError.CreateFmt('status invalido: %s', [Status]);
    Result.PixCopiaCola := Texto('pix_copia_cola');
    Result.BoletoChaveS3 := Texto('boleto_chave_s3');
    if Result.BoletoChaveS3.IsEmpty then
      Result.BoletoChaveS3 := Texto('boleto_link');
    Result.BoletoLinhaDigitavel := Texto('boleto_linha_digitavel');
    Result.BoletoNossoNumero := Texto('boleto_nosso_numero');
    Result.NotaFiscalNumero := Texto('nota_fiscal_numero');
    Result.NotaFiscalChaveS3 := Texto('nota_fiscal_chave_s3');
    if Result.NotaFiscalChaveS3.IsEmpty then
      Result.NotaFiscalChaveS3 := Texto('nota_fiscal_link');
    Result.NotaFiscalXMLChaveS3 := Texto('nota_fiscal_xml_chave_s3');
    if Result.NotaFiscalXMLChaveS3.IsEmpty then
      Result.NotaFiscalXMLChaveS3 := Texto('nota_fiscal_xml_link');
    Result.Observacoes := Texto('observacoes');
  finally
    Objeto.Free;
  end;
end;

end.
