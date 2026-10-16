unit PortalCliente.Boleto.Config;

{$mode delphi}

interface

uses
  PortalCliente.Boleto.Generator;

type
  TPortalBoletoConfigLoader = class sealed
  public
    class function Carregar(const AServiceConfigFile: string;
      out AHomologacaoDir: string): TPortalBoletoRenderConfig; static;
  end;

implementation

uses
  IniFiles,
  PortalCliente.IOUtils,
  SysUtils,
  PortalCliente.Plataforma;

function StringToPortalBoletoRenderer(
  const AValor: string): TPortalBoletoRenderer;
var
  Valor: string;
begin
  Valor := Trim(AValor);
  if SameText(Valor, 'FPDF') then
    Exit(brFPDF);
  if SameText(Valor, 'FORTES') or SameText(Valor, 'FORTESREPORT') then
    Exit(brFortes);
  if SameText(Valor, 'FAST') or SameText(Valor, 'FASTREPORT') then
    Exit(brFastReport);

  raise Exception.CreateFmt(
    'Motor de boleto invalido: "%s". Use FPDF, Fortes ou FastReport.',
    [AValor]);
end;

procedure ValidarMotorDaPlataforma(const ARenderer: TPortalBoletoRenderer);
begin
    if ARenderer <> brFPDF then
    raise Exception.CreateFmt(
      'O motor de boleto %s so existe no Windows. No Linux use Motor=FPDF.',
      [PortalBoletoRendererToString(ARenderer)]);
  end;

class function TPortalBoletoConfigLoader.Carregar(
  const AServiceConfigFile: string;
  out AHomologacaoDir: string): TPortalBoletoRenderConfig;
var
  AppDir: string;
  Ini: TIniFile;
  Valor: string;
begin
  AppDir := ExcludeTrailingPathDelimiter(TPortalPlataforma.PastaApp);
    { No Linux os logotipos (PNG) vao junto do pacote, em logos/. }
  Result.LogoDir := TPath.Combine(AppDir, 'logos');
    AHomologacaoDir := TPath.Combine(AppDir,
    TPortalPlataforma.NormalizarCaminho('homologacao\boletos'));
  Result.MargemSuperior := 2;
  Result.MargemInferior := 2;
  Result.MargemEsquerda := 4;
  Result.MargemDireita := 2;
  Result.Escala := 96;
  { Mantem o comportamento existente durante a homologacao do FPDF. }
    Result.Renderer := brFPDF;
    Result.FastReportFile := TPath.GetFullPath(TPath.Combine(AppDir,
    TPortalPlataforma.NormalizarCaminho('..\..\Report\BoletoPIX.fr3')));

  if TFile.Exists(AServiceConfigFile) then
  begin
    Ini := TIniFile.Create(AServiceConfigFile);
    try
      Valor := Ini.ReadString('Boleto', 'LogoDir', '').Trim;
      if Valor <> '' then
        Result.LogoDir := TPortalPlataforma.NormalizarCaminho(Valor);
      Valor := Ini.ReadString('Boleto', 'HomologacaoDir', '').Trim;
      if Valor <> '' then
        AHomologacaoDir := TPortalPlataforma.NormalizarCaminho(Valor);
      Result.MargemSuperior := Ini.ReadInteger('Boleto', 'MargemSuperior', 2);
      Result.MargemInferior := Ini.ReadInteger('Boleto', 'MargemInferior', 2);
      Result.MargemEsquerda := Ini.ReadInteger('Boleto', 'MargemEsquerda', 4);
      Result.MargemDireita := Ini.ReadInteger('Boleto', 'MargemDireita', 2);
      Result.Escala := Ini.ReadInteger('Boleto', 'Escala', 96);
      Valor := Ini.ReadString('Boleto', 'Motor',
        PortalBoletoRendererToString(Result.Renderer)).Trim;
      Result.Renderer := StringToPortalBoletoRenderer(Valor);
      Valor := Ini.ReadString('Boleto', 'FastReportFile', '').Trim;
      if Valor <> '' then
        Result.FastReportFile := TPortalPlataforma.NormalizarCaminho(Valor);
    finally
      Ini.Free;
    end;
  end;

  ValidarMotorDaPlataforma(Result.Renderer);

  if not TPath.IsPathRooted(Result.LogoDir) then
    Result.LogoDir := TPath.GetFullPath(TPath.Combine(AppDir, Result.LogoDir));
  if not TPath.IsPathRooted(AHomologacaoDir) then
    AHomologacaoDir := TPath.GetFullPath(TPath.Combine(AppDir,
      AHomologacaoDir));
  if not TPath.IsPathRooted(Result.FastReportFile) then
    Result.FastReportFile := TPath.GetFullPath(TPath.Combine(AppDir,
      Result.FastReportFile));
end;

end.
