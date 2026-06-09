unit uRpnParser;

{$mode Delphi}{$H+}

// ============================================================================
// uRpnParser.pas
//
// Converte a string infixa digitada pelo usuario na Notacao Polonesa Reversa
// (NPR) seguindo EXATAMENTE o algoritmo descrito na aula 29:
//
//   - Uma pilha temporaria P1 (de operadores e parenteses).
//   - Uma lista L1 (saida na NPR).
//
// Regras:
//   1) Numero -> vai direto para L1.
//   2) Operador "op" -> antes de empilhar, transfere de P1 para L1 todos os
//      operadores com precedencia maior ou igual a "op".
//   3) "("  -> empilha em P1.
//   4) ")"  -> transfere de P1 para L1 ate encontrar "(" (descarta ambos).
//   5) Funcao (sin/cos/tan/asin/acos/atan): empilhada em P1 e, quando o ")"
//      correspondente fecha o seu parametro, ela e transferida para L1.
//
// Precedencias da aula 29:
//   6) ~      (negativo unario)
//   5) ^      (potencia - reservada; nao ha botao no escopo minimo)
//   4) * /    (produto e divisao)
//   3) + -    (soma e subtracao)
//   1) (      (parentese esquerdo)
//
// Observacao sobre associatividade:
//   O texto usa o criterio >= para todos os operadores. Para o operador
//   unario "~" (associativo a direita) usamos comparacao estrita (>) para
//   permitir cadeias como "~~3" sem que o primeiro "~" seja consumido antes
//   de ter operando.
// ============================================================================

interface

type
  // Tipos de token que aparecem tanto na entrada quanto na saida NPR.
  TOpKind = (
    okNumber,                              // valor numerico
    okAdd, okSub, okMul, okDiv,            // operadores binarios
    okNeg,                                 // ~ negativo unario
    okLParen, okRParen,                    // parenteses (usados apenas na entrada)
    okSin, okCos, okTan,                   // funcoes trigonometricas
    okASin, okACos, okATan                 // funcoes trigonometricas inversas
  );

  TRpnToken = record
    Kind: TOpKind;
    Value: Double;   // valido somente quando Kind = okNumber
  end;

  TRpnTokens = array of TRpnToken;

  TParseError = (
    peNone,
    peEmpty,
    peUnknownToken,
    peUnbalancedParen
  );

// Converte uma expressao infixa em NPR. Em caso de erro, retorna array vazio
// e preenche Err com o motivo.
function InfixToRpn(const Expr: string; out Err: TParseError): TRpnTokens;

implementation

uses
  SysUtils;

// ----------------------------------------------------------------------------
// Funcoes auxiliares sobre os tipos de token.
// ----------------------------------------------------------------------------

function IsFunctionKind(K: TOpKind): Boolean;
begin
  Result := K in [okSin, okCos, okTan, okASin, okACos, okATan];
end;

function Precedence(K: TOpKind): Integer;
begin
  // Tabela de precedencias da aula 29 (com funcoes acima de tudo).
  case K of
    okSin, okCos, okTan, okASin, okACos, okATan: Result := 7;
    okNeg:                                       Result := 6;
    okMul, okDiv:                                Result := 4;
    okAdd, okSub:                                Result := 3;
    okLParen:                                    Result := 1;
  else
    Result := 0;
  end;
end;

function IsRightAssoc(K: TOpKind): Boolean;
begin
  // O negativo unario eh associativo a direita: aplicado da direita para a
  // esquerda quando aparecem varios em sequencia (ex.: "~~3" = -(-3) = 3).
  Result := K = okNeg;
end;

// ----------------------------------------------------------------------------
// Lexer: percorre a string e produz a lista de tokens infixos.
//
// O ponto sensivel eh distinguir o "-" unario do binario: ele eh unario
// quando aparece no inicio da expressao, logo apos um "(", apos uma funcao
// ou apos outro operador. Nesses casos emitimos okNeg ("~"); senao, okSub.
// ----------------------------------------------------------------------------
function Lex(const Expr: string; out Err: TParseError): TRpnTokens;
var
  i, N, StartI, Code: Integer;
  Ch: Char;
  S, NumStr: string;
  Number: Double;
  PrevKind: TOpKind;
  HasPrev: Boolean;

  procedure Push(K: TOpKind; const V: Double);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)].Kind := K;
    Result[High(Result)].Value := V;
    PrevKind := K;
    HasPrev := True;
  end;

begin
  Err := peNone;
  SetLength(Result, 0);
  HasPrev := False;
  PrevKind := okAdd; // valor inicial irrelevante
  i := 1;
  N := Length(Expr);

  while i <= N do
  begin
    Ch := Expr[i];

    // Ignora espacos em branco.
    if (Ch = ' ') or (Ch = #9) then
    begin
      Inc(i);
      Continue;
    end;

    // ----- Numero (inteiro ou fracionario) -----
    if (Ch >= '0') and (Ch <= '9') or (Ch = '.') or (Ch = ',') then
    begin
      StartI := i;
      while (i <= N) and
            (((Expr[i] >= '0') and (Expr[i] <= '9'))
             or (Expr[i] = '.') or (Expr[i] = ',')) do
        Inc(i);
      NumStr := Copy(Expr, StartI, i - StartI);
      // Normaliza separador decimal para "." (independente do locale).
      NumStr := StringReplace(NumStr, ',', '.', [rfReplaceAll]);
      // Val sempre usa "." e nao depende de FormatSettings; Code = 0 indica sucesso.
      Val(NumStr, Number, Code);
      if Code <> 0 then
      begin
        Err := peUnknownToken;
        Exit;
      end;
      Push(okNumber, Number);
      Continue;
    end;

    // ----- Identificador: nome de funcao -----
    if ((Ch >= 'a') and (Ch <= 'z')) or ((Ch >= 'A') and (Ch <= 'Z')) then
    begin
      StartI := i;
      while (i <= N) and
            ((Expr[i] >= 'a') and (Expr[i] <= 'z') or
             (Expr[i] >= 'A') and (Expr[i] <= 'Z')) do
        Inc(i);
      S := LowerCase(Copy(Expr, StartI, i - StartI));
      if      S = 'sin'  then Push(okSin,  0)
      else if S = 'cos'  then Push(okCos,  0)
      else if S = 'tan'  then Push(okTan,  0)
      else if S = 'asin' then Push(okASin, 0)
      else if S = 'acos' then Push(okACos, 0)
      else if S = 'atan' then Push(okATan, 0)
      else
      begin
        Err := peUnknownToken;
        Exit;
      end;
      Continue;
    end;

    // ----- Operadores e parenteses (um caractere) -----
    case Ch of
      '+': Push(okAdd, 0);
      '-':
        begin
          // unario quando esta no inicio, logo apos um operador, parentese
          // esquerdo ou nome de funcao
          if (not HasPrev)
             or (PrevKind = okLParen)
             or (PrevKind = okAdd) or (PrevKind = okSub)
             or (PrevKind = okMul) or (PrevKind = okDiv)
             or (PrevKind = okNeg)
             or IsFunctionKind(PrevKind) then
            Push(okNeg, 0)
          else
            Push(okSub, 0);
        end;
      '*': Push(okMul, 0);
      '/': Push(okDiv, 0);
      '(': Push(okLParen, 0);
      ')': Push(okRParen, 0);
    else
      Err := peUnknownToken;
      Exit;
    end;
    Inc(i);
  end;
end;

// ----------------------------------------------------------------------------
// Algoritmo do shunting-yard (Dijkstra), refletindo passo a passo o que a
// aula 29 chama de pilha P1 (operadores) e lista L1 (saida).
// ----------------------------------------------------------------------------
function ShuntingYard(const InTokens: TRpnTokens;
                      out Err: TParseError): TRpnTokens;
var
  OpStack: TRpnTokens;       // pilha P1
  OpTop: Integer;
  i: Integer;
  Tok, TopTok: TRpnToken;
  ShouldPop: Boolean;

  procedure PushOp(const T: TRpnToken);
  begin
    Inc(OpTop);
    if OpTop >= Length(OpStack) then
      SetLength(OpStack, Length(OpStack) + 32);
    OpStack[OpTop] := T;
  end;

  function PopOp: TRpnToken;
  begin
    Result := OpStack[OpTop];
    Dec(OpTop);
  end;

  procedure EmitTok(const T: TRpnToken);
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := T;
  end;

begin
  Err := peNone;
  SetLength(Result, 0);
  SetLength(OpStack, 32);
  OpTop := -1;

  for i := 0 to High(InTokens) do
  begin
    Tok := InTokens[i];

    case Tok.Kind of

      // (1) Numero -> direto para L1.
      okNumber:
        EmitTok(Tok);

      // Funcao -> empilha em P1. Sera transferida para L1 quando o ")" do
      // seu parametro for processado.
      okSin, okCos, okTan, okASin, okACos, okATan:
        PushOp(Tok);

      // (3) "(" -> empilha em P1.
      okLParen:
        PushOp(Tok);

      // (4) ")" -> transfere de P1 para L1 ate achar "(". Descarta ambos.
      // Se o topo agora eh uma funcao, transfere a funcao tambem.
      okRParen:
        begin
          while (OpTop >= 0) and (OpStack[OpTop].Kind <> okLParen) do
            EmitTok(PopOp);
          if OpTop < 0 then
          begin
            Err := peUnbalancedParen;
            Exit;
          end;
          PopOp; // descarta o "("
          if (OpTop >= 0) and IsFunctionKind(OpStack[OpTop].Kind) then
            EmitTok(PopOp);
        end;

      // (2) Operador binario ou unario: transfere de P1 enquanto a
      // precedencia do topo for >= a deste (ou estritamente > se for
      // associativo a direita).
      okAdd, okSub, okMul, okDiv, okNeg:
        begin
          while OpTop >= 0 do
          begin
            TopTok := OpStack[OpTop];
            if TopTok.Kind = okLParen then Break;
            if IsRightAssoc(Tok.Kind) then
              ShouldPop := Precedence(TopTok.Kind) > Precedence(Tok.Kind)
            else
              ShouldPop := Precedence(TopTok.Kind) >= Precedence(Tok.Kind);
            if not ShouldPop then Break;
            EmitTok(PopOp);
          end;
          PushOp(Tok);
        end;
    end;
  end;

  // Fim da expressao: descarrega o que restou em P1 para L1.
  while OpTop >= 0 do
  begin
    TopTok := PopOp;
    if TopTok.Kind = okLParen then
    begin
      Err := peUnbalancedParen;
      Exit;
    end;
    EmitTok(TopTok);
  end;
end;

// ----------------------------------------------------------------------------
// Funcao publica.
// ----------------------------------------------------------------------------
function InfixToRpn(const Expr: string; out Err: TParseError): TRpnTokens;
var
  Lexed: TRpnTokens;
begin
  Result := nil;             // inicializa o array gerenciado (silencia FPC W5093)
  Lexed := Lex(Expr, Err);
  if Err <> peNone then Exit;
  if Length(Lexed) = 0 then
  begin
    Err := peEmpty;
    Exit;
  end;
  Result := ShuntingYard(Lexed, Err);
end;

end.
