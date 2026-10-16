unit PortalCliente.Plataforma;

{ Tudo que depende do Linux no PortalService fica aqui: pasta do executavel,
  caminhos escritos com '\', leitura dos .ini ANSI 1252, entrada oculta de
  senha e os sinais de encerramento do daemon. }

{$mode delphi}

interface

uses
  Classes, SysUtils;

type
  TPortalPlataforma = class sealed
  public
    { Pasta do executavel, com o separador no fim (/proc/self/exe). }
    class function PastaApp: string; static;

    { Caminho relativo a PastaApp escrito como sempre foi ('..\..\x'): as
      barras viram '/' e o '..' e resolvido. }
    class function NaPastaApp(const ARelativo: string): string; static;

    { Barras de um caminho vindo de .ini (escrito no Windows) para '/'. }
    class function NormalizarCaminho(const ACaminho: string): string; static;

    { Texto ANSI 1252 -> UTF-8 (bytes 128..255). }
    class function Cp1252ParaUtf8(const ATexto: RawByteString): string; static;

    { Le o arquivo em ANSI 1252 (ou UTF-8, se tiver BOM) e devolve as linhas
      em UTF-8. }
    class procedure CarregarLinhas(const AArquivo: string;
      ALinhas: TStrings); static;

    { Bytes do arquivo, sem nenhuma conversao. }
    class function LerBytes(const AArquivo: string): RawByteString; static;

    { ReadLn sem eco no terminal (token). Sem terminal, le a linha normal. }
    class function LerLinhaOculta: string; static;

    { Daemon: SIGTERM/SIGINT viram EncerramentoSolicitado; SIGPIPE ignorado. }
    class procedure InstalarSinaisDeEncerramento; static;
    class function EncerramentoSolicitado: Boolean; static;
  end;

implementation

uses
  BaseUnix, termio;

var
  GSinalRecebido: LongInt = 0;

procedure TratarSinal(ASinal: CInt); cdecl;
begin
  GSinalRecebido := ASinal;
end;

class function TPortalPlataforma.PastaApp: string;
var
  Caminho: RawByteString;
begin
  Caminho := fpReadLink('/proc/self/exe');
  if Caminho = '' then
    Caminho := ExpandFileName(ParamStr(0));
  Result := ExtractFilePath(Caminho);
end;

class function TPortalPlataforma.NormalizarCaminho(
  const ACaminho: string): string;
begin
  Result := StringReplace(ACaminho, '\', '/', [rfReplaceAll]);
end;

class function TPortalPlataforma.NaPastaApp(const ARelativo: string): string;
begin
  Result := ExpandFileName(PastaApp + NormalizarCaminho(ARelativo));
end;

class function TPortalPlataforma.Cp1252ParaUtf8(
  const ATexto: RawByteString): string;
const
  { 0x80..0x9F da Windows-1252 em Unicode (0 = indefinido). }
  ALTA: array[0..31] of Word = (
    $20AC, 0, $201A, $0192, $201E, $2026, $2020, $2021,
    $02C6, $2030, $0160, $2039, $0152, 0, $017D, 0,
    0, $2018, $2019, $201C, $201D, $2022, $2013, $2014,
    $02DC, $2122, $0161, $203A, $0153, 0, $017E, $0178);
var
  I: Integer;
  B: Byte;
  U: Word;
begin
  Result := '';
  for I := 1 to Length(ATexto) do
  begin
    B := Byte(ATexto[I]);
    if B < $80 then
      Result := Result + Chr(B)
    else
    begin
      if B < $A0 then
      begin
        U := ALTA[B - $80];
        if U = 0 then
          U := B;
      end
      else
        U := B;
      if U < $800 then
        Result := Result + Chr($C0 or (U shr 6)) + Chr($80 or (U and $3F))
      else
        Result := Result + Chr($E0 or (U shr 12)) +
          Chr($80 or ((U shr 6) and $3F)) + Chr($80 or (U and $3F));
    end;
  end;
end;

class function TPortalPlataforma.LerBytes(
  const AArquivo: string): RawByteString;
var
  F: TFileStream;
begin
  F := TFileStream.Create(AArquivo, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, F.Size);
    if Length(Result) > 0 then
      F.ReadBuffer(Result[1], Length(Result));
  finally
    F.Free;
  end;
end;

class procedure TPortalPlataforma.CarregarLinhas(const AArquivo: string;
  ALinhas: TStrings);
var
  Bruto: RawByteString;
begin
  Bruto := LerBytes(AArquivo);
  if (Length(Bruto) >= 3) and (Bruto[1] = #$EF) and (Bruto[2] = #$BB) and
    (Bruto[3] = #$BF) then
    ALinhas.Text := Copy(Bruto, 4, MaxInt)
  else
    ALinhas.Text := Cp1252ParaUtf8(Bruto);
end;

class function TPortalPlataforma.LerLinhaOculta: string;
var
  Atual, SemEco: Termios;
  Oculta: Boolean;
begin
  Oculta := (TCGetAttr(0, Atual) = 0);
  if Oculta then
  begin
    SemEco := Atual;
    SemEco.c_lflag := SemEco.c_lflag and not ECHO;
    TCSetAttr(0, TCSANOW, SemEco);
  end;
  try
    ReadLn(Result);
  finally
    if Oculta then
      TCSetAttr(0, TCSANOW, Atual);
  end;
end;

class procedure TPortalPlataforma.InstalarSinaisDeEncerramento;
var
  Acao: SigActionRec;
begin
  FillChar(Acao, SizeOf(Acao), 0);
  Acao.sa_handler := SigActionHandler(@TratarSinal);
  FpSigEmptySet(Acao.sa_mask);
  { SA_RESTART: nao interrompe as chamadas do fbclient e do TLS no meio. }
  Acao.sa_flags := SA_RESTART;
  FpSigAction(SIGTERM, @Acao, nil);
  FpSigAction(SIGINT, @Acao, nil);
  { Escrita em socket fechado gera SIGPIPE, que por padrao derruba o processo. }
  FpSignal(SIGPIPE, SignalHandler(SIG_IGN));
end;

class function TPortalPlataforma.EncerramentoSolicitado: Boolean;
begin
  Result := GSinalRecebido <> 0;
end;

end.
