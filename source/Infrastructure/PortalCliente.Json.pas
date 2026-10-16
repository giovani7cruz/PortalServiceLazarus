unit PortalCliente.Json;

{ Metodos no estilo do System.JSON do Delphi sobre o fpjson do FPC, para o
  codigo do PortalService (AddPair, GetValue, ToJSON, ParseJSONValue) ficar
  igual nos dois projetos. Um helper so, em TJSONData: o FPC usa um helper
  por tipo e o de TJSONObject esconderia o do pai. }

{$mode delphi}

interface

uses
  Classes, SysUtils, fpjson, jsonparser;

type
  TJSONValue = TJSONData;

  TJSONDataHelper = class helper for TJSONData
  public
    { Objeto }
    function AddPair(const ANome, AValor: string): TJSONObject; overload;
    function AddPair(const ANome: string; AValor: TJSONData): TJSONObject; overload;
    function GetValue(const ANome: string): TJSONData;
    { Array }
    procedure AddElement(AValor: TJSONData);
    function ToJSON: string;
    class function ParseJSONValue(const AJson: string): TJSONData;
    { Texto do valor; nil ou JSON null viram ''. }
    function Texto: string;
  end;

function TJSONNumero(const AValor: Currency): TJSONData;

implementation

type
  { Numero com o texto decimal exato (2 casas): o TJSONFloatNumber do FPC
    escreveria 1.2345599999999999E+003. }
  TJSONMoeda = class(TJSONFloatNumber)
  private
    FTexto: string;
  protected
    function GetAsJSON: TJSONStringType; override;
  public
    constructor CreateMoeda(const AValor: Currency);
  end;

constructor TJSONMoeda.CreateMoeda(const AValor: Currency);
var
  FS: TFormatSettings;
begin
  inherited Create(AValor);
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  FTexto := CurrToStrF(AValor, ffFixed, 2, FS);
end;

function TJSONMoeda.GetAsJSON: TJSONStringType;
begin
  Result := FTexto;
end;

function TJSONDataHelper.AddPair(const ANome, AValor: string): TJSONObject;
begin
  Result := Self as TJSONObject;
  Result.Add(ANome, AValor);
end;

function TJSONDataHelper.AddPair(const ANome: string;
  AValor: TJSONData): TJSONObject;
begin
  Result := Self as TJSONObject;
  Result.Add(ANome, AValor);
end;

function TJSONDataHelper.GetValue(const ANome: string): TJSONData;
begin
  Result := (Self as TJSONObject).Find(ANome);
end;

procedure TJSONDataHelper.AddElement(AValor: TJSONData);
begin
  (Self as TJSONArray).Add(AValor);
end;

function TJSONDataHelper.ToJSON: string;
begin
  Result := AsJSON;
end;

class function TJSONDataHelper.ParseJSONValue(const AJson: string): TJSONData;
begin
  try
    Result := GetJSON(AJson);
  except
    Result := nil;
  end;
end;

function TJSONDataHelper.Texto: string;
begin
  if (Self = nil) or (JSONType = jtNull) then
    Result := ''
  else
    Result := AsString;
end;

function TJSONNumero(const AValor: Currency): TJSONData;
begin
  Result := TJSONMoeda.CreateMoeda(AValor);
end;

end.
