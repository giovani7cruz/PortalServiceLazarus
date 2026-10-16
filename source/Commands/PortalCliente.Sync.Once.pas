unit PortalCliente.Sync.Once;

{$mode delphi}

interface

type
  TPortalSyncOnce = class sealed
  private
    class function Confirmar: Boolean; static;
  public
    class function Executar: Integer; static;
  end;

implementation

uses
  Classes,
  SysUtils,
  PortalCliente.Db,
  Aguia.Database,
  Aguia.Database.Config,
  PortalCliente.Config.Repository,
  PortalCliente.Sync.Engine;

type
  TSaidaConsole = class
  public
    procedure Log(const AMensagem: string);
    function Esperar(const AMilissegundos: Cardinal): Boolean;
  end;

procedure TSaidaConsole.Log(const AMensagem: string);
begin
  WriteLn(AMensagem);
end;

function TSaidaConsole.Esperar(const AMilissegundos: Cardinal): Boolean;
begin
  if AMilissegundos > 0 then
    Sleep(AMilissegundos);
  Result := False;
end;

class function TPortalSyncOnce.Confirmar: Boolean;
var
  Entrada: string;
begin
  WriteLn('Este comando executa um ciclo completo e pode enviar dados ao portal.');
  Write('Continuar? [S/N]: ');
  ReadLn(Entrada);
  Result := SameText(Entrada.Trim, 'S');
end;

class function TPortalSyncOnce.Executar: Integer;
var
  Saida: TSaidaConsole;
  Config: TAguiaDatabaseConfig;
  Configuracoes: TArray<TPortalConfiguracao>;
  ConfigRepository: TPortalConfigRepository;
  Connection: TPortalConexao;
  Engine: TPortalSyncEngine;
  ErroCiclo: string;
  I: Integer;
  Resumo: TPortalSyncResumo;
begin
  Result := 1;
  Connection := nil;
  ConfigRepository := nil;
  Engine := nil;
  Saida := TSaidaConsole.Create;
  try
    try
      WriteLn('AguiaPortalService - execucao de ciclo unico');
      if not Confirmar then
      begin
        WriteLn('Operacao cancelada.');
        Exit(0);
      end;
      WriteLn;

      Config := TAguiaDatabaseConfigLoader.Carregar;
      Connection := TAguiaDatabase.AbrirConexao(Config);
      ConfigRepository := TPortalConfigRepository.Create(Connection);
      Engine := TPortalSyncEngine.Create(Connection, Saida.Log, Saida.Esperar);
      Configuracoes := ConfigRepository.Listar(True);
      if Length(Configuracoes) = 0 then
        raise Exception.Create(
          'Nenhuma empresa ativa em PORTAL_CONFIG. Execute /configurar.');

      for I := 0 to High(Configuracoes) do
      begin
        ErroCiclo := '';
        try
          Resumo := Engine.ProcessarEmpresa(Configuracoes[I]);
          WriteLn(Format(
            'Empresa %d: clientes fila=%d enviados=%d; ' +
            'titulos fila=%d enviados=%d; erros=%d; requisicoes=%d.',
            [Configuracoes[I].CodigoEmpresa,
             Resumo.ClientesCarregados, Resumo.ClientesEnviados,
             Resumo.TitulosCarregados, Resumo.TitulosEnviados,
             Resumo.Erros, Resumo.Requisicoes]));
        except
          on E: Exception do
          begin
            ErroCiclo := E.Message;
            WriteLn(Format('Empresa %d: ERRO: %s',
              [Configuracoes[I].CodigoEmpresa, ErroCiclo]));
          end;
        end;
        ConfigRepository.RegistrarCiclo(
          Configuracoes[I].CodigoEmpresa, ErroCiclo);
      end;
      Result := 0;
    except
      on E: Exception do
        WriteLn('ERRO: ' + E.Message);
    end;
  finally
    Saida.Free;
    Engine.Free;
    ConfigRepository.Free;
    Connection.Free;
  end;
end;

end.
