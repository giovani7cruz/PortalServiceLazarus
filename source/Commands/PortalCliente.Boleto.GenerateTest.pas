unit PortalCliente.Boleto.GenerateTest;

{$mode delphi}

interface

type
  TPortalBoletoGenerateTest = class sealed
  private
    class function ExecutarInterno(const AContaReceberIdTexto: string;
      const AUsarFPDF: Boolean): Integer; static;
  public
    class function Executar(const AContaReceberIdTexto: string): Integer; static;
    class function ExecutarFPDF(
      const AContaReceberIdTexto: string): Integer; static;
  end;

implementation

uses
  Classes,
  PortalCliente.IOUtils,
  SysUtils,
  PortalCliente.Db,
  Aguia.Database,
  Aguia.Database.Config,
  PortalCliente.Boleto.Config,
  PortalCliente.Boleto.Generator;

class function TPortalBoletoGenerateTest.ExecutarInterno(
  const AContaReceberIdTexto: string; const AUsarFPDF: Boolean): Integer;
var
  ConfigDB: TAguiaDatabaseConfig;
  ConfigBoleto: TPortalBoletoRenderConfig;
  Connection: TPortalConexao;
  Generator: TPortalBoletoGenerator;
  PDF: TMemoryStream;
  ContaReceberId: Integer;
  Renderer: TPortalBoletoRenderer;
  HomologacaoDir: string;
  Arquivo: string;
begin
  if not TryStrToInt(AContaReceberIdTexto, ContaReceberId) or
     (ContaReceberId <= 0) then
  begin
    if AUsarFPDF then
      Writeln('Uso: AguiaPortalService /testar-geracao-boleto-fpdf <CONTARECEBER.INTERNAL_COD>')
    else
      Writeln('Uso: AguiaPortalService /testar-geracao-boleto <CONTARECEBER.INTERNAL_COD>');
    Exit(2);
  end;

  try
    ConfigDB := TAguiaDatabaseConfigLoader.Carregar;
    ConfigBoleto := TPortalBoletoConfigLoader.Carregar(
      ConfigDB.ServiceConfigFile, HomologacaoDir);
    if AUsarFPDF then
      Renderer := brFPDF
    else
      Renderer := ConfigBoleto.Renderer;
    if not TDirectory.Exists(ConfigBoleto.LogoDir) then
      raise Exception.CreateFmt('Pasta de logotipos do boleto nao encontrada: %s',
        [ConfigBoleto.LogoDir]);
    ForceDirectories(HomologacaoDir);
    if Renderer = brFPDF then
      Arquivo := TPath.Combine(HomologacaoDir,
        Format('boleto-contareceber-%d-fpdf.pdf', [ContaReceberId]))
    else if Renderer = brFastReport then
      Arquivo := TPath.Combine(HomologacaoDir,
        Format('boleto-contareceber-%d-fastreport.pdf', [ContaReceberId]))
    else
      Arquivo := TPath.Combine(HomologacaoDir,
        Format('boleto-contareceber-%d.pdf', [ContaReceberId]));

    Connection := TAguiaDatabase.AbrirConexao(ConfigDB);
    try
      Generator := TPortalBoletoGenerator.Create(ConfigBoleto);
      PDF := TMemoryStream.Create;
      try
        Generator.GerarPDF(Connection, ContaReceberId, PDF, Renderer);
        PDF.SaveToFile(Arquivo);
      finally
        PDF.Free;
        Generator.Free;
      end;
    finally
      Connection.Free;
    end;

    Writeln('Motor do boleto: ' + PortalBoletoRendererToString(Renderer));
    Writeln('Boleto gerado em memoria e salvo para homologacao:');
    Writeln(Arquivo);
    Result := 0;
  except
    on E: Exception do
    begin
      Writeln('Falha ao gerar boleto: ' + E.Message);
      Result := 1;
    end;
  end;
end;

class function TPortalBoletoGenerateTest.Executar(
  const AContaReceberIdTexto: string): Integer;
begin
  Result := ExecutarInterno(AContaReceberIdTexto, False);
end;

class function TPortalBoletoGenerateTest.ExecutarFPDF(
  const AContaReceberIdTexto: string): Integer;
begin
  Result := ExecutarInterno(AContaReceberIdTexto, True);
end;

end.
