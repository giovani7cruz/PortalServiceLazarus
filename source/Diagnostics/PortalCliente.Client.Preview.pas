unit PortalCliente.Client.Preview;

{$mode delphi}

interface

type
  TPortalClientePreview = class sealed
  private
    class function Juntar(const AValores: TArray<string>): string; static;
  public
    class function Executar: Integer; static;
  end;

implementation

uses
  fpjson, jsonparser, PortalCliente.Json,
  SysUtils,
  PortalCliente.Db,
  Aguia.Database,
  Aguia.Database.Config,
  PortalCliente.Client.Mapper,
  PortalCliente.Client.Repository,
  PortalCliente.Config.Repository;

class function TPortalClientePreview.Juntar(
  const AValores: TArray<string>): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AValores) do
  begin
    if not Result.IsEmpty then
      Result := Result + '; ';
    Result := Result + AValores[I];
  end;
end;

class function TPortalClientePreview.Executar: Integer;
const
  LIMITE_AMOSTRAS_JSON = 3;
  LIMITE_ERROS_EXIBIDOS = 20;
var
  AOrigem: TPortalClienteOrigem;
  Origens: TArray<TPortalClienteOrigem>;
  IndiceOrigem: Integer;
  JSON: TJSONObject;
  Amostras: TJSONArray;
  Config: TAguiaDatabaseConfig;
  Configuracoes: TArray<TPortalConfiguracao>;
  ConfigRepository: TPortalConfigRepository;
  Connection: TPortalConexao;
  ErrosExibidos: Integer;
  I: Integer;
  Invalidos: Integer;
  MapResult: TPortalClienteMapResult;
  Repository: TPortalClienteRepository;
  Total: Integer;
  Validos: Integer;
begin
  Result := 1;
  Connection := nil;
  ConfigRepository := nil;
  Repository := nil;
  try
    try
      WriteLn('AguiaPortalService - pre-visualizacao de clientes');
      WriteLn('Nenhum dado sera enviado ou alterado.');
      WriteLn;

      Config := TAguiaDatabaseConfigLoader.Carregar;
      Connection := TAguiaDatabase.AbrirConexao(Config);
      ConfigRepository := TPortalConfigRepository.Create(Connection);
      Repository := TPortalClienteRepository.Create(Connection);
      Configuracoes := ConfigRepository.Listar(True);

      if Length(Configuracoes) = 0 then
        raise Exception.Create(
          'Nenhuma empresa ativa em PORTAL_CONFIG. Execute /configurar.');

      for I := 0 to High(Configuracoes) do
      begin
        Total := 0;
        Validos := 0;
        Invalidos := 0;
        ErrosExibidos := 0;
        Amostras := TJSONArray.Create;
        try
          WriteLn(Format('Empresa %d', [Configuracoes[I].CodigoEmpresa]));
          Origens := Repository.Listar;
          for IndiceOrigem := 0 to High(Origens) do
          begin
            AOrigem := Origens[IndiceOrigem];
              Inc(Total);
              MapResult := TPortalClienteMapper.Mapear(AOrigem);
              if MapResult.Valido then
              begin
                Inc(Validos);
                if Amostras.Count < LIMITE_AMOSTRAS_JSON then
                  Amostras.AddElement(
                    TPortalClienteMapper.ParaJSON(MapResult.Cliente));
              end
              else
              begin
                Inc(Invalidos);
                if ErrosExibidos < LIMITE_ERROS_EXIBIDOS then
                begin
                  WriteLn(Format('  INVALIDO %s | %s | %s',
                    [MapResult.Cliente.IDExterno,
                     MapResult.Cliente.NomeRazaoSocial,
                     Juntar(MapResult.Erros)]));
                  Inc(ErrosExibidos);
                end;
              end;
          end;

          WriteLn(Format('  Encontrados: %d', [Total]));
          WriteLn(Format('  Validos: %d', [Validos]));
          WriteLn(Format('  Invalidos: %d', [Invalidos]));
          if Invalidos > ErrosExibidos then
            WriteLn(Format('  Outros erros omitidos: %d',
              [Invalidos - ErrosExibidos]));

          if Amostras.Count > 0 then
          begin
            WriteLn('  Amostra JSON:');
            WriteLn(Amostras.ToJSON);
          end;
          WriteLn;
        finally
          Amostras.Free;
        end;
      end;

      WriteLn('Pre-visualizacao concluida. Nenhum dado foi enviado.');
      Result := 0;
    except
      on E: Exception do
        WriteLn('ERRO: ' + E.Message);
    end;
  finally
    Repository.Free;
    ConfigRepository.Free;
    Connection.Free;
  end;
end;

end.
