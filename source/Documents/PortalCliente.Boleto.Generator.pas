unit PortalCliente.Boleto.Generator;

{$mode delphi}

interface

uses
  Classes,
  PortalCliente.Db;

type
  TPortalBoletoRenderer = (brFortes, brFPDF, brFastReport);

  TPortalBoletoRenderConfig = record
    LogoDir: string;
    MargemSuperior: Integer;
    MargemInferior: Integer;
    MargemEsquerda: Integer;
    MargemDireita: Integer;
    Escala: Integer;
    Renderer: TPortalBoletoRenderer;
    FastReportFile: string;
  end;

  TPortalBoletoGenerator = class sealed
  private
    FConfig: TPortalBoletoRenderConfig;
  public
    constructor Create(const AConfig: TPortalBoletoRenderConfig);
    procedure GerarPDF(AConnection: TPortalConexao;
      const AContaReceberId: Integer; ADestino: TStream); overload;
    procedure GerarPDF(AConnection: TPortalConexao;
      const AContaReceberId: Integer; ADestino: TStream;
      const ARenderer: TPortalBoletoRenderer); overload;
  end;

function PortalBoletoRendererToString(
  const ARenderer: TPortalBoletoRenderer): string;

implementation

uses
  PortalCliente.IOUtils,
  Math,
  SysUtils,
  DB,
    ACBrBoleto,
  ACBrBoletoConversao,
  ACBrBoletoFPDF,
  PortalCliente.Boleto.Repository;

function PortalBoletoRendererToString(
  const ARenderer: TPortalBoletoRenderer): string;
begin
  case ARenderer of
    brFortes: Result := 'Fortes';
    brFPDF: Result := 'FPDF';
    brFastReport: Result := 'FastReport';
  else
    Result := 'Desconhecido';
  end;
end;

function PrepararLogoFPDF(const ALogoDir: string;
  const ANumeroBanco: Integer): string;
var
  Arquivo: string;
begin
  { Sem VCL no Linux nao ha conversao BMP/JPG -> PNG: os logotipos do pacote
    ja precisam estar em PNG (logos/NNN.png). }
  Arquivo := TPath.Combine(ALogoDir,
    FormatFloat('000', ANumeroBanco) + '.png');
  if not TFile.Exists(Arquivo) then
    raise Exception.CreateFmt(
      'Logotipo do banco %s nao encontrado em %s. No Linux e esperado PNG.',
      [FormatFloat('000', ANumeroBanco), ALogoDir]);
  Result := ALogoDir;
end;

function SemAcentos(const ATexto: string): string;
const
  { Equivalente ao best-fit do Windows para US-ASCII (code page 20127), que o
    projeto Delphi usa: U+00C0..U+00FF -> letra sem acento. }
  BASE: string = 'AAAAAAACEEEEIIIIDNOOOOOxOUUUUYTsaaaaaaaceeeeiiiidnooooo/ouuuuyty';
var
  I, N, Extra: Integer;
  B, B1: Byte;
  CP: Cardinal;
begin
  Result := '';
  I := 1;
  N := Length(ATexto);
  while I <= N do
  begin
    B := Byte(ATexto[I]);
    if B < $80 then
    begin
      Result := Result + Char(B);
      Inc(I);
      Continue;
    end;
    { sequencia UTF-8 }
    if (B and $E0) = $C0 then begin CP := B and $1F; Extra := 1; end
    else if (B and $F0) = $E0 then begin CP := B and $0F; Extra := 2; end
    else if (B and $F8) = $F0 then begin CP := B and $07; Extra := 3; end
    else begin CP := B; Extra := 0; end;
    Inc(I);
    while (Extra > 0) and (I <= N) do
    begin
      B1 := Byte(ATexto[I]);
      CP := (CP shl 6) or (B1 and $3F);
      Inc(I);
      Dec(Extra);
    end;
    if (CP >= $C0) and (CP <= $FF) then
      Result := Result + BASE[CP - $C0 + 1]
    else
      Result := Result + '?';
  end;
end;

function SomenteNumeros(const ATexto: string): string;
var
  C: Char;
begin
  Result := '';
  for C in ATexto do
    if CharInSet(C, ['0'..'9']) then
      Result := Result + C;
end;

procedure DefinirBanco(ABoleto: TACBrBoleto; const ANumeroBanco: Integer);
begin
  case ANumeroBanco of
    1: ABoleto.Banco.TipoCobranca := cobBancoDoBrasil;
    4: ABoleto.Banco.TipoCobranca := cobBancoDoNordeste;
    33, 353: ABoleto.Banco.TipoCobranca := cobSantander;
    41: ABoleto.Banco.TipoCobranca := cobBanrisul;
    70: ABoleto.Banco.TipoCobranca := cobBRB;
    77: ABoleto.Banco.TipoCobranca := cobBancoInter;
    85: ABoleto.Banco.TipoCobranca := cobBancoCECRED;
    99: ABoleto.Banco.TipoCobranca := cobUniprime;
    104: ABoleto.Banco.TipoCobranca := cobCaixaSicob;
    1041: ABoleto.Banco.TipoCobranca := cobCaixaEconomica;
    133: ABoleto.Banco.TipoCobranca := cobBancoCresol;
    237: ABoleto.Banco.TipoCobranca := cobBradesco;
    341: ABoleto.Banco.TipoCobranca := cobItau;
    389: ABoleto.Banco.TipoCobranca := cobBancoMercantil;
    399: ABoleto.Banco.TipoCobranca := cobHSBC;
    748: ABoleto.Banco.TipoCobranca := cobSicred;
    756: ABoleto.Banco.TipoCobranca := cobBancoob;
  else
    raise Exception.CreateFmt('Banco %d nao suportado para gerar boleto pelo ACBr.',
      [ANumeroBanco]);
  end;
end;

procedure ConfigurarCedente(ABoleto: TACBrBoleto; AData: TDataSet);
begin
  with ABoleto.Cedente do
  begin
    Agencia := AData.FieldByName('CEDENTEAGENCIA').AsString;
    AgenciaDigito := AData.FieldByName('CEDENTEAGENCIADIGITO').AsString;
    if ABoleto.Banco.TipoCobranca = cobBanrisul then
      AgenciaDigito := '';
    if ABoleto.Banco.TipoCobranca = cobBancoob then
      DigitoVerificadorAgenciaConta := '0';

    Bairro := AData.FieldByName('CEDENTEBAIRRO').AsString;
    case AData.FieldByName('CEDENTECARACTITULO').AsInteger of
      0: CaracTitulo := tcCaucionada;
      1: CaracTitulo := tcDescontada;
      2: CaracTitulo := tcSimples;
      3: CaracTitulo := tcVendor;
      4: CaracTitulo := tcVinculada;
      5: CaracTitulo := tcSimplesRapComReg;
      6: CaracTitulo := tcCaucionadaRapComReg;
    end;
    Cep := AData.FieldByName('CEDENTECEP').AsString;
    Cidade := SemAcentos(AData.FieldByName('CEDENTECIDADE').AsString);
    CNPJCPF := AData.FieldByName('CEDENTECNPJCPF').AsString;
    CodigoCedente := AData.FieldByName('CEDENTECODIGOCEDENTE').AsString;

    if ABoleto.Banco.TipoCobranca = cobCaixaEconomica then
      if Length(CodigoCedente) = 7 then
      begin
        ABoleto.Banco.LayoutVersaoArquivo := 107;
        ABoleto.Banco.LayoutVersaoLote := 67;
      end
      else
      begin
        ABoleto.Banco.LayoutVersaoArquivo := 101;
        ABoleto.Banco.LayoutVersaoLote := 60;
      end;

    CodigoTransmissao := AData.FieldByName('CEDENTECODIGOTRANSMISSAO').AsString;
    Complemento := AData.FieldByName('CEDENTECOMPLEMENTO').AsString;
    Conta := AData.FieldByName('CEDENTECONTA').AsString;
    ContaDigito := AData.FieldByName('CEDENTECONTADIGITO').AsString;
    Convenio := AData.FieldByName('CEDENTECONVENIO').AsString;
    Logradouro := SemAcentos(AData.FieldByName('CEDENTELOGRADOURO').AsString);
    Modalidade := AData.FieldByName('CEDENTEMODALIDADE').AsString;
    Nome := SemAcentos(AData.FieldByName('CEDENTENOME').AsString);
    NumeroRes := AData.FieldByName('CEDENTENUMERORES').AsString;

    case AData.FieldByName('CEDENTERESPONEMISSAO').AsInteger of
      0: begin ResponEmissao := tbBancoEmite; IdentDistribuicao := tbBancoDistribui; end;
      1: begin ResponEmissao := tbBancoNaoReemite; IdentDistribuicao := tbBancoDistribui; end;
      2: begin ResponEmissao := tbBancoReemite; IdentDistribuicao := tbBancoDistribui; end;
      3: begin ResponEmissao := tbCliEmite; IdentDistribuicao := tbClienteDistribui; end;
    end;
    TipoInscricao := pJuridica;
    UF := AData.FieldByName('CEDENTEUF').AsString;
    TipoCarteira := tctSimples;
    if AData.FieldByName('CEDENTETIPOCARTEIRA').AsInteger = 1 then
      TipoCarteira := tctRegistrada;
  end;
end;

function CriarTitulo(ABoleto: TACBrBoleto; AData: TDataSet): TACBrTitulo;
begin
  Result := ABoleto.CriarTituloNaLista;
  with Result do
  begin
    CodigoGeracao := AData.FieldByName('TITULOCODIGOGERACAO').AsString;
    TotalParcelas := AData.FieldByName('TOTAL_PARCELA').AsInteger;
    Parcela := AData.FieldByName('PARCELA').AsInteger;
    Vencimento := AData.FieldByName('TITULOVENCIMENTO').AsDateTime;
    DataDocumento := AData.FieldByName('TITULODATADOCUMENTO').AsDateTime;
    if ABoleto.Banco.TipoCobranca <> cobBanrisul then
      DataLimitePagto := Vencimento + 30;
    SeuNumero := AData.FieldByName('TITULOSEUNUMERO').AsString;
    NumeroDocumento := AData.FieldByName('TITULONUMERODOCUMENTO').AsString;
    if ABoleto.Banco.TipoCobranca = cobCaixaEconomica then
      SeuNumero := NumeroDocumento;
    EspecieDoc := AData.FieldByName('TITULOESPECIEDOC').AsString;
    EspecieMod := AData.FieldByName('TITULOESPECIEMOD').AsString;
    CodigoMoraJuros := cjValorDia;
    if AData.FieldByName('TITULOACEITE').AsInteger = 1 then
      Aceite := atSim
    else
      Aceite := atNao;
    DataProcessamento := AData.FieldByName('TITULODATAPROCESSAMENTO').AsDateTime;
    Carteira := AData.FieldByName('TITULOCARTEIRA').AsString;
    if ABoleto.Banco.TipoCobranca = cobBancoInter then
      NossoNumero := AData.FieldByName('COMPLETO_NN').AsString
    else
      NossoNumero := AData.FieldByName('TITULONOSSONUMERO').AsString;
    NossoNumeroCorrespondente := AData.FieldByName('NOSSONUMEROCORRESPONDENTE').AsString;
    ValorDocumento := AData.FieldByName('TITULOVALORDOCUMENTO').AsCurrency;

    Sacado.NomeSacado := SemAcentos(AData.FieldByName('SACADONOMESACADO').AsString);
    Sacado.CNPJCPF := AData.FieldByName('SACADOCNPJCPF').AsString;
    Sacado.Pessoa := pJuridica;
    if Length(Trim(Sacado.CNPJCPF)) <= 11 then
      Sacado.Pessoa := pFisica;
    Sacado.Avalista := AData.FieldByName('SACADOAVALISTA').AsString;
    Sacado.Numero := AData.FieldByName('SACADONUMERO').AsString;
    Sacado.Complemento := SemAcentos(AData.FieldByName('SACADOCOMPLEMENTO').AsString);
    Sacado.Logradouro := Copy(SemAcentos(AData.FieldByName('SACADOLOGRADOURO').AsString), 1, 40);
    Sacado.Bairro := Copy(SemAcentos(AData.FieldByName('SACADOBAIRRO').AsString), 1, 20);
    Sacado.Cep := AData.FieldByName('SACADOCEP').AsString;
    Sacado.Cidade := SemAcentos(AData.FieldByName('SACADOCIDADE').AsString);
    Sacado.UF := AData.FieldByName('SACADOUF').AsString;
    Sacado.Email := AData.FieldByName('SACADOEMAIL').AsString;
    Sacado.Fone := SomenteNumeros(AData.FieldByName('SACADOFONE').AsString);
    if ABoleto.Banco.TipoCobranca in [cobCaixaEconomica, cobBancoInter] then
      Sacado.Fone := '';

    LocalPagamento := AData.FieldByName('TITULOLOCALPAGAMENTO').AsString;
    ValorMoraJuros := SimpleRoundTo(AData.FieldByName('TITULOVALORMORAJUROS').AsCurrency, -2);
    QtdePagamentoParcial := 1;
    TipoPagamento := tpNao_Aceita_Valor_Divergente;
    CodigoDesconto := cdValorFixo;
    ValorDesconto := AData.FieldByName('TITULOVALORDESCONTO').AsCurrency;
    if (ValorDesconto > 0) and not AData.FieldByName('TITULODATADESCONTO').IsNull then
      DataDesconto := AData.FieldByName('TITULODATADESCONTO').AsDateTime;
    ValorAbatimento := AData.FieldByName('TITULOVALORABATIMENTO').AsCurrency;
    if not AData.FieldByName('TITULODATAABATIMENTO').IsNull then
      DataAbatimento := AData.FieldByName('TITULODATAABATIMENTO').AsDateTime;
    if not AData.FieldByName('TITULODATAPROTESTO').IsNull then
      DataProtesto := AData.FieldByName('TITULODATAPROTESTO').AsDateTime;
    TipoDiasProtesto := diUteis;
    DiasDeProtesto := AData.FieldByName('TITULODIASDEPROTESTO').AsInteger;
    if (DiasDeProtesto > 5) or (ABoleto.Banco.TipoCobranca = cobBanrisul) then
      TipoDiasProtesto := diCorridos;
    if AData.FieldByName('TITULODIASDEVOLUCAO').AsInteger > 0 then
      DataBaixa := Vencimento + AData.FieldByName('TITULODIASDEVOLUCAO').AsInteger;
    TipoDiasNegativacao := diUteis;
    DiasDeNegativacao := AData.FieldByName('TITULODIASNEGATIVACAO').AsInteger;
    if DiasDeNegativacao > 5 then
      TipoDiasNegativacao := diCorridos;
    if DiasDeNegativacao > 0 then
    begin
      DataNegativacao := Vencimento + DiasDeNegativacao;
      if ABoleto.Banco.TipoCobranca = cobBancoob then
        CodigoNegativacao := cnNegativar;
    end;
    PercentualMulta := AData.FieldByName('TITULOPERCENTUALMULTA').AsCurrency;
    if PercentualMulta > 0 then
    begin
      CodigoMulta := cmPercentual;
      DataMulta := AData.FieldByName('TITULODATAMORAJUROS').AsDateTime;
      DataMoraJuros := DataMulta;
    end;
    Mensagem.Text := AData.FieldByName('TITULOMENSAGEM').AsString;
    OcorrenciaOriginal.Tipo := toRemessaRegistrar;
    Instrucao1 := AData.FieldByName('TITULOINSTRUCAO1').AsString;
    Instrucao2 := AData.FieldByName('TITULOINSTRUCAO2').AsString;

    if not AData.FieldByName('COD_NOTA').IsNull then
      with CriarNFeNaLista do
      begin
        NumNFe := AData.FieldByName('NUMNFE').AsString;
        ValorNFe := AData.FieldByName('VALORNFE').AsCurrency;
        EmissaoNFe := AData.FieldByName('EMISSAONFE').AsDateTime;
        ChaveNFe := AData.FieldByName('CHAVENFE').AsString;
      end;
  end;
end;

procedure AplicarRetorno(ATitulo: TACBrTitulo; ARetorno: TDataSet);
begin
  if not ARetorno.FieldByName('DATA_VENCIMENTO').IsNull then
    ATitulo.Vencimento := ARetorno.FieldByName('DATA_VENCIMENTO').AsDateTime;
  if (not ARetorno.FieldByName('VALOR_DOCUMENTO').IsNull) and
     (ARetorno.FieldByName('VALOR_DOCUMENTO').AsCurrency > 0) then
    ATitulo.ValorDocumento := ARetorno.FieldByName('VALOR_DOCUMENTO').AsCurrency;
  if Trim(ARetorno.FieldByName('QRCODE').AsString) <> '' then
    ATitulo.QrCode.emv := ARetorno.FieldByName('QRCODE').AsString;
  if Trim(ARetorno.FieldByName('TXID').AsString) <> '' then
    ATitulo.QrCode.txId := ARetorno.FieldByName('TXID').AsString;
  if Trim(ARetorno.FieldByName('URL_PIX').AsString) <> '' then
    ATitulo.QrCode.url := ARetorno.FieldByName('URL_PIX').AsString;
end;

procedure ConferirLinhaDigitavel(ABoleto: TACBrBoleto; ATitulo: TACBrTitulo;
  ARetorno: TDataSet);
var
  DoBanco: string;
  Calculada: string;
begin
  DoBanco := SomenteNumeros(Trim(ARetorno.FieldByName('LINHADIGITAVEL').AsString));
  if DoBanco = '' then
    Exit;
  Calculada := SomenteNumeros(ABoleto.Banco.MontarLinhaDigitavel(
    ABoleto.Banco.MontarCodigoBarras(ATitulo), ATitulo));
  if Calculada <> DoBanco then
    raise Exception.CreateFmt(
      'A linha digitavel calculada nao confere com o retorno do banco.' + sLineBreak +
      'Banco: %s' + sLineBreak + 'Sistema: %s', [DoBanco, Calculada]);
end;

constructor TPortalBoletoGenerator.Create(
  const AConfig: TPortalBoletoRenderConfig);
begin
  inherited Create;
  FConfig := AConfig;
end;

procedure TPortalBoletoGenerator.GerarPDF(AConnection: TPortalConexao;
  const AContaReceberId: Integer; ADestino: TStream);
begin
  GerarPDF(AConnection, AContaReceberId, ADestino, FConfig.Renderer);
end;

procedure TPortalBoletoGenerator.GerarPDF(AConnection: TPortalConexao;
  const AContaReceberId: Integer; ADestino: TStream;
  const ARenderer: TPortalBoletoRenderer);
var
  Boleto: TACBrBoleto;
  Report: TACBrBoletoFCClass;
  Titulo: TACBrTitulo;
  Dados: TPortalQuery;
  Retorno: TPortalQuery;
begin
  if not Assigned(ADestino) then
    raise EArgumentNilException.Create('ADestino');

  Dados := TPortalBoletoRepository.CarregarTitulo(AConnection, AContaReceberId);
  try
    if Dados.IsEmpty then
      raise Exception.CreateFmt(
        'Titulo %d nao encontrado ou nao esta configurado como boleto.',
        [AContaReceberId]);

    Retorno := TPortalBoletoRepository.CarregarUltimoRetorno(AConnection,
      AContaReceberId);
    try
      if Retorno.IsEmpty or
         ((Trim(Retorno.FieldByName('NOSSONUMERO').AsString) = '') and
          (Trim(Retorno.FieldByName('NOSSONUMEROCORRESPONDENTE').AsString) = '') and
          (Trim(Retorno.FieldByName('QRCODE').AsString) = '') and
          (Trim(Retorno.FieldByName('TXID').AsString) = '')) then
        raise Exception.Create(
          'Nao ha retorno do banco aproveitavel em CONTAREC_EVENTO para este titulo.');

      Boleto := TACBrBoleto.Create(nil);
      Report := nil;
      //ReportFortes := nil;
      try
        case ARenderer of
          brFPDF:
            Report := TACBrBoletoFPDF.Create(nil);
        else
          raise Exception.Create(
            'Renderizador de boleto nao suportado nesta plataforma.');
        end;

        Report.SoftwareHouse := 'Aguia Gestao Empresarial - www.infus.inf.br';
        Report.LayOut := lPadraoPIX;
        { O PortalService pode executar na sessao 0 do Windows Service. O
          Fortes exibe por padrao duas janelas de progresso (preparacao e
          filtro PDF), portanto esta opcao precisa ficar desligada aqui. }
        Report.MostrarProgresso := False;
        Report.MostrarPreview := False;
        Report.MostrarSetup := False;
//        if Assigned(ReportFortes) then
//          ReportFortes.IncorporarFontesPdf := True;
        Report.DirLogo := FConfig.LogoDir;
        Report.MargemSuperior := FConfig.MargemSuperior;
        Report.MargemInferior := FConfig.MargemInferior;
        Report.MargemEsquerda := FConfig.MargemEsquerda;
        Report.MargemDireita := FConfig.MargemDireita;
        Report.AlterarEscalaPadrao := True;
        Report.NovaEscala := FConfig.Escala;
        Boleto.ACBrBoletoFC := Report;
        Boleto.LayoutRemessa := c240;

        DefinirBanco(Boleto, Dados.FieldByName('CEDENTETIPOCOBRANCA').AsInteger);
        if ARenderer = brFPDF then
          Report.DirLogo := PrepararLogoFPDF(FConfig.LogoDir,
            Boleto.Banco.Numero);
        ConfigurarCedente(Boleto, Dados);
        Titulo := CriarTitulo(Boleto, Dados);
        AplicarRetorno(Titulo, Retorno);
        ConferirLinhaDigitavel(Boleto, Titulo, Retorno);

        ADestino.Size := 0;
        ADestino.Position := 0;
        Boleto.GerarPDF(ADestino);
        if ADestino.Size = 0 then
          raise Exception.Create('O ACBr nao produziu conteudo PDF.');
        ADestino.Position := 0;
      finally
        Boleto.Free;
        Report.Free;
      end;
    finally
      Retorno.Free;
    end;
  finally
    Dados.Free;
  end;
end;

end.
