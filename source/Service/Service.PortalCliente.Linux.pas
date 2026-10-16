unit Service.PortalCliente.Linux;

{ Entrada do PortalService como daemon do systemd: sobe o TPortalClienteWorker
  e espera SIGTERM/SIGINT. O log vai para a saida padrao (journald) e para
  Logs/ ao lado do executavel. }

{$mode delphi}

interface

type
  TPortalDaemon = class sealed
  public
    class function Executar: Integer; static;
  end;

implementation

uses
  Classes, SysUtils, SyncObjs,
  PortalCliente.IOUtils,
  PortalCliente.Plataforma,
  PortalCliente.Worker;

type
  TSaidaDoDaemon = class
  private
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Escrever(const AMensagem: string);
  end;

constructor TSaidaDoDaemon.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TSaidaDoDaemon.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TSaidaDoDaemon.Escrever(const AMensagem: string);
var
  Arquivo, Linha, Pasta: string;
begin
  Linha := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' - ' + AMensagem;
  FLock.Acquire;
  try
    WriteLn(Linha);
    Flush(Output);
    try
      Pasta := TPath.Combine(TPortalPlataforma.PastaApp, 'Logs');
      Arquivo := TPath.Combine(Pasta, 'AguiaPortalService-' +
        FormatDateTime('yyyy-mm-dd', Date) + '.log');
      ForceDirectories(Pasta);
      TFile.AppendAllText(Arquivo, Linha + LineEnding);
    except
      { Log em arquivo e acessorio: o journal ja tem a linha. }
    end;
  finally
    FLock.Release;
  end;
end;

class function TPortalDaemon.Executar: Integer;
var
  Saida: TSaidaDoDaemon;
  Worker: TPortalClienteWorker;
begin
  TPortalPlataforma.InstalarSinaisDeEncerramento;
  Saida := TSaidaDoDaemon.Create;
  Worker := TPortalClienteWorker.Create(Saida.Escrever);
  try
    Worker.Start;
    Saida.Escrever('AguiaPortalService iniciado.');
    while (not TPortalPlataforma.EncerramentoSolicitado) and
      (not Worker.Finished) do
      Sleep(200);
    Saida.Escrever('Encerrando AguiaPortalService...');
    Worker.SolicitarParada;
    Worker.WaitFor;
    Saida.Escrever('AguiaPortalService parado.');
  finally
    Worker.Free;
    Saida.Free;
  end;
  Result := 0;
end;

end.
