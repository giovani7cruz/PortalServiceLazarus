unit PortalCliente.Diagnostics;

{$mode delphi}

interface

type
  TPortalClienteDiagnostics = class sealed
  public
    class function Executar(out ASaida: string): Integer; static;
  end;

implementation

uses
  Classes,
  StrUtils,
  SysUtils,
  PortalCliente.Db,
  Aguia.Database,
  Aguia.Database.Config,
  PortalCliente.Config.Repository;

class function TPortalClienteDiagnostics.Executar(out ASaida: string): Integer;
const
  TABELAS_ESPERADAS = 3;
var
  Config: TAguiaDatabaseConfig;
  Configuracoes: TArray<TPortalConfiguracao>;
  Connection: TPortalConexao;
  I: Integer;
  Query: TPortalQuery;
  Repository: TPortalConfigRepository;
  Saida: TStringList;
  TabelasEncontradas: Integer;
begin
  Result := 1;
  Saida := TStringList.Create;
  Connection := nil;
  Query := nil;
  Repository := nil;
  try
    try
      Saida.Add('AguiaPortalService - diagnostico de conexao');
      Config := TAguiaDatabaseConfigLoader.Carregar;
      Saida.Add('Configuracao Firebird: ' + Config.ParamsFile);

      Connection := TAguiaDatabase.AbrirConexao(Config);
      Saida.Add('Conexao Firebird: OK');
      Saida.Add('Banco: ' + Connection.Conn.DatabaseName);

      Query := TPortalQuery.Create(nil);
      Query.Connection := Connection;
      Query.SQL.Text :=
        'select rdb$get_context(''SYSTEM'', ''ENGINE_VERSION'') as VERSAO ' +
        'from rdb$database';
      Query.Open;
      Saida.Add('Firebird: ' + Query.FieldByName('VERSAO').AsString);

      Query.Close;
      Query.SQL.Text := 'select max(INTERNAL_COD) as VERSAO from VERSAO';
      Query.Open;
      Saida.Add('Versao do banco: ' + Query.FieldByName('VERSAO').AsString);

      Query.Close;
      Query.SQL.Text :=
        'select count(*) as TOTAL from RDB$RELATIONS ' +
        'where RDB$RELATION_NAME in (' +
        '''PORTAL_CONFIG'', ''PORTAL_SYNC_FILA'', ''PORTAL_SYNC_EXECUCAO'')';
      Query.Open;
      TabelasEncontradas := Query.FieldByName('TOTAL').AsInteger;
      Saida.Add(Format('Tabelas do portal: %d/%d',
        [TabelasEncontradas, TABELAS_ESPERADAS]));
      if TabelasEncontradas <> TABELAS_ESPERADAS then
        raise Exception.Create('Infraestrutura do script 000555 incompleta.');

      Repository := TPortalConfigRepository.Create(Connection);
      Configuracoes := Repository.Listar(True);

      if Length(Configuracoes) = 0 then
        Saida.Add('Empresas ativas: nenhuma configurada')
      else
      begin
        Saida.Add(Format('Empresas ativas: %d', [Length(Configuracoes)]));
        for I := 0 to High(Configuracoes) do
          Saida.Add(Format('  Empresa %d | URL: %s | Token: %s | Lote: %d',
            [Configuracoes[I].CodigoEmpresa,
             Configuracoes[I].BaseUrl,
             IfThen(Configuracoes[I].TemToken,
               IfThen(Copy(Configuracoes[I].TokenProtegido, 1, 3) = 'L1:',
                 'configurado (formato Linux)',
                 'configurado, MAS no formato do Windows: rode /configurar'),
               'nao configurado'),
             Configuracoes[I].TamanhoLote]));
      end;

      Saida.Add('Diagnostico concluido com sucesso.');
      Result := 0;
    except
      on E: Exception do
        Saida.Add('ERRO: ' + E.Message);
    end;
    ASaida := Saida.Text;
  finally
    Query.Free;
    Repository.Free;
    Connection.Free;
    Saida.Free;
  end;
end;

end.
