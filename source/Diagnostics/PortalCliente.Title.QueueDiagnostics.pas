unit PortalCliente.Title.QueueDiagnostics;

{$mode delphi}

interface

type
  TPortalTituloQueueDiagnostics = class sealed
  public
    class function Executar: Integer; static;
  end;

implementation

uses
  Generics.Collections,
  fpjson, jsonparser, PortalCliente.Json,
  SysUtils,
  PortalCliente.Db,
  Aguia.Database,
  Aguia.Database.Config,
  PortalCliente.Config.Repository;

class function TPortalTituloQueueDiagnostics.Executar: Integer;
const
  LIMITE_ERROS = 100;
var
  Config: TAguiaDatabaseConfig;
  Configuracoes: TArray<TPortalConfiguracao>;
  ConfigRepository: TPortalConfigRepository;
  Connection: TPortalConexao;
  ErrosExibidos: Integer;
  I: Integer;
  Forma: string;
  Formas: TDictionary<string, Integer>;
  Par: TPair<string, Integer>;
  Payload: string;
  Query: TPortalQuery;
  TotalErros: Integer;

  function ExtrairFormaPagamento(const AJSON: string): string;
  var
    Objeto: TJSONObject;
    Raiz: TJSONValue;
    Valor: TJSONValue;
  begin
    Result := '';
    Raiz := TJSONObject.ParseJSONValue(AJSON);
    try
      if Raiz is TJSONObject then
      begin
        Objeto := TJSONObject(Raiz);
        Valor := Objeto.GetValue('forma_pagamento');
        if Assigned(Valor) and not (Valor is TJSONNull) then
          Result := Valor.AsString;
      end;
    finally
      Raiz.Free;
    end;
  end;

begin
  Result := 1;
  Connection := nil;
  ConfigRepository := nil;
  Query := nil;
  try
    try
      WriteLn('AguiaPortalService - diagnostico da fila de titulos');
      WriteLn('Nenhum dado sera enviado ou alterado.');
      WriteLn;

      Config := TAguiaDatabaseConfigLoader.Carregar;
      Connection := TAguiaDatabase.AbrirConexao(Config);
      ConfigRepository := TPortalConfigRepository.Create(Connection);
      Query := TPortalQuery.Create(nil);
      Query.Connection := Connection;
      Configuracoes := ConfigRepository.Listar(True);
      if Length(Configuracoes) = 0 then
        raise Exception.Create(
          'Nenhuma empresa ativa em PORTAL_CONFIG. Execute /configurar.');

      for I := 0 to High(Configuracoes) do
      begin
        Formas := TDictionary<string, Integer>.Create;
        try
        WriteLn(Format('Empresa %d:', [Configuracoes[I].CodigoEmpresa]));
        Query.SQL.Text :=
          'select SITUACAO, count(*) TOTAL from PORTAL_SYNC_FILA ' +
          'where COD_EMPRESA = :COD_EMPRESA ' +
          '  and TIPO_ENTIDADE = ''TITULO'' group by SITUACAO ' +
          'order by SITUACAO';
        Query.ParamByName('COD_EMPRESA').AsInteger :=
          Configuracoes[I].CodigoEmpresa;
        Query.Open;
        while not Query.Eof do
        begin
          case Query.FieldByName('SITUACAO').AsInteger of
            0: WriteLn(Format('  Pendentes: %d',
                 [Query.FieldByName('TOTAL').AsInteger]));
            1: WriteLn(Format('  Processando: %d',
                 [Query.FieldByName('TOTAL').AsInteger]));
            2: WriteLn(Format('  Enviados: %d',
                 [Query.FieldByName('TOTAL').AsInteger]));
            3: WriteLn(Format('  Com erro: %d',
                 [Query.FieldByName('TOTAL').AsInteger]));
          end;
          Query.Next;
        end;
        Query.Close;

        Query.SQL.Text :=
          'select count(*) TOTAL from PORTAL_SYNC_FILA ' +
          'where COD_EMPRESA = :COD_EMPRESA ' +
          '  and TIPO_ENTIDADE = ''TITULO'' and SITUACAO = 3';
        Query.ParamByName('COD_EMPRESA').AsInteger :=
          Configuracoes[I].CodigoEmpresa;
        Query.Open;
        TotalErros := Query.FieldByName('TOTAL').AsInteger;
        Query.Close;

        if TotalErros > 0 then
        begin
          ErrosExibidos := 0;
          WriteLn('  Erros registrados:');
          Query.SQL.Text :=
            'select ID_EXTERNO, PAYLOAD, ' +
            '       cast(ULTIMO_ERRO as varchar(4000)) ERRO ' +
            'from PORTAL_SYNC_FILA where COD_EMPRESA = :COD_EMPRESA ' +
            '  and TIPO_ENTIDADE = ''TITULO'' and SITUACAO = 3 ' +
            'order by INTERNAL_COD';
          Query.ParamByName('COD_EMPRESA').AsInteger :=
            Configuracoes[I].CodigoEmpresa;
          Query.Open;
          while not Query.Eof do
          begin
            Payload := Query.FieldByName('PAYLOAD').AsString;
            Forma := ExtrairFormaPagamento(Payload);
            if Forma.IsEmpty then
              Forma := '(nao informada)';
            if Formas.ContainsKey(Forma) then
              Formas[Forma] := Formas[Forma] + 1
            else
              Formas.Add(Forma, 1);
            if ErrosExibidos < LIMITE_ERROS then
            begin
              WriteLn(Format('    %s | forma: %s | %s',
                [Query.FieldByName('ID_EXTERNO').AsString,
                 Forma,
                 Query.FieldByName('ERRO').AsString]));
              Inc(ErrosExibidos);
            end;
            Query.Next;
          end;
          Query.Close;
          if TotalErros > ErrosExibidos then
            WriteLn(Format('    Outros erros omitidos: %d',
              [TotalErros - ErrosExibidos]));

          if Formas.Count > 0 then
          begin
            WriteLn('  Formas de pagamento em todos os erros:');
            for Par in Formas do
              WriteLn(Format('    %s: %d titulo(s)',
                [Par.Key, Par.Value]));
          end;
        end;
        WriteLn;
        finally
          Formas.Free;
        end;
      end;
      WriteLn('Diagnostico concluido. Nenhum dado foi alterado.');
      Result := 0;
    except
      on E: Exception do
        WriteLn('ERRO: ' + E.Message);
    end;
  finally
    Query.Free;
    ConfigRepository.Free;
    Connection.Free;
  end;
end;

end.
