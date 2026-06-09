unit uCalcFpu;

{$mode Delphi}{$H+}
{$ASMMODE INTEL}

// ============================================================================
// uCalcFpu.pas
//
// Nucleo de calculo da calculadora. Toda operacao aritmetica e trigonometrica
// e implementada em ASSEMBLY x87 (FPU), atraves do assembler embutido do
// Free Pascal (blocos "asm ... end;"). Sao instrucoes reais da FPU: FLD, FSTP,
// FADD, FSUB, FMUL, FDIV, FCHS, FSIN, FCOS, FPTAN, FPATAN, FSQRT, FLD1, FXCH.
//
// Diretivas do compilador FPC:
//   - {$mode Delphi}    -> dialeto Object Pascal (records, out, etc.).
//   - {$ASMMODE INTEL}  -> blocos asm em sintaxe Intel ("FLD QWORD PTR [...]").
//                          Sem ela, o FPC usaria sintaxe AT&T por padrao.
//
// Conforme a aula 29, a pilha de avaliacao da NPR vive em SOFTWARE (vetor de
// 200 doubles), e a FPU eh usada apenas para fazer cada calculo individual,
// devolvendo o resultado para a pilha de software. Assim a pilha x87 (apenas
// 8 niveis) nunca eh sobrecarregada, independente do tamanho da expressao.
//
// Layout da pilha software:
//   SwStack: array [0..199] of Double;
//   SwTop:   indice do topo (-1 = vazia, 0 = um elemento, ...)
//
// Cada operador binario consome SwStack[SwTop-1] (operando A, empilhado
// primeiro) e SwStack[SwTop] (operando B, empilhado depois), produzindo
// A op B e colocando o resultado em SwStack[SwTop-1]; SwTop e decrementado.
//
// Cada operador unario (~, sin, cos, ...) consome SwStack[SwTop], computa
// o resultado e o coloca de volta em SwStack[SwTop] (sem alterar SwTop).
// ============================================================================

interface

uses
  uRpnParser;

const
  EVAL_OK          = 0;
  EVAL_ERR_STACK   = 1;   // sub/sobrefluxo da pilha de software
  EVAL_ERR_DIVZERO = 2;   // divisao por zero
  EVAL_ERR_DOMAIN  = 3;   // operando fora do dominio (asin/acos)

// Avalia uma lista de tokens em NPR. AngleDegrees = True ativa o modo Graus
// para as funcoes trigonometricas. Retorna um codigo (EVAL_OK ou EVAL_ERR_*)
// e, em caso de sucesso, escreve o resultado em R.
function EvalRpn(const Tokens: TRpnTokens; AngleDegrees: Boolean;
                 out R: Double): Integer;

implementation

// ----------------------------------------------------------------------------
// Pilha em software (200 posicoes) e constantes de conversao de angulo.
// As constantes sao globais tipadas para que seus enderecos sejam acessiveis
// nos blocos asm via FMUL QWORD PTR [...].
// ----------------------------------------------------------------------------

const
  STACK_CAPACITY = 200;

  // pi / 180 = 0.01745329251994329576923690768489
  DEG_TO_RAD: Double = 0.01745329251994329577;
  // 180 / pi = 57.29577951308232087679815481410
  RAD_TO_DEG: Double = 57.29577951308232088;

var
  SwStack: array[0..STACK_CAPACITY - 1] of Double;
  SwTop: Integer;  // indice do topo; -1 quando a pilha esta vazia

// ============================================================================
// Rotinas em Assembly x87. Cada uma representa UMA "operacao" no sentido do
// trabalho: ela retira operandos da pilha de software, executa o calculo na
// FPU e devolve o resultado para a pilha de software.
// ============================================================================

// ----------------------------------------------------------------------------
// FpuInit
// Reinicia a FPU em um estado conhecido (mascara de excecoes padrao,
// arredondamento "round to nearest", precisao estendida).
// ----------------------------------------------------------------------------
procedure FpuInit;
asm
  FINIT
end;

// ----------------------------------------------------------------------------
// FpuPushNumber
// Empilha o valor V na pilha de software. Parametros Double sao passados
// por valor na pilha de chamada; o assembler embutido do FPC resolve "V"
// para o endereco correto pelo nome do parametro.
//   passos: SwTop++, SwStack[SwTop] <- V
// ----------------------------------------------------------------------------
procedure FpuPushNumber(V: Double);
asm
  MOV     ECX, [SwTop]
  INC     ECX
  MOV     [SwTop], ECX
  FLD     V                                // ST(0) = V  (asm resolve V)
  FSTP    QWORD PTR [SwStack + ECX*8]      // SwStack[SwTop] = V; libera ST(0)
end;

// ----------------------------------------------------------------------------
// FpuAdd  (operador "+")
// SwStack[SwTop-1] := SwStack[SwTop-1] + SwStack[SwTop];  SwTop--
// ----------------------------------------------------------------------------
procedure FpuAdd;
asm
  MOV     ECX, [SwTop]
  DEC     ECX
  FLD     QWORD PTR [SwStack + ECX*8]     // ST(0) = A  (primeiro empilhado)
  INC     ECX
  FADD    QWORD PTR [SwStack + ECX*8]     // ST(0) = A + B
  DEC     ECX
  MOV     [SwTop], ECX
  FSTP    QWORD PTR [SwStack + ECX*8]     // grava em SwStack[SwTop-1]
end;

// ----------------------------------------------------------------------------
// FpuSub  (operador "-")
// SwStack[SwTop-1] := SwStack[SwTop-1] - SwStack[SwTop];  SwTop--
// ----------------------------------------------------------------------------
procedure FpuSub;
asm
  MOV     ECX, [SwTop]
  DEC     ECX
  FLD     QWORD PTR [SwStack + ECX*8]     // ST(0) = A
  INC     ECX
  FSUB    QWORD PTR [SwStack + ECX*8]     // ST(0) = A - B
  DEC     ECX
  MOV     [SwTop], ECX
  FSTP    QWORD PTR [SwStack + ECX*8]
end;

// ----------------------------------------------------------------------------
// FpuMul  (operador "*")
// ----------------------------------------------------------------------------
procedure FpuMul;
asm
  MOV     ECX, [SwTop]
  DEC     ECX
  FLD     QWORD PTR [SwStack + ECX*8]     // ST(0) = A
  INC     ECX
  FMUL    QWORD PTR [SwStack + ECX*8]     // ST(0) = A * B
  DEC     ECX
  MOV     [SwTop], ECX
  FSTP    QWORD PTR [SwStack + ECX*8]
end;

// ----------------------------------------------------------------------------
// FpuDiv  (operador "/")
// O caller (EvalRpn) verifica divisor != 0 antes de chamar.
// ----------------------------------------------------------------------------
procedure FpuDiv;
asm
  MOV     ECX, [SwTop]
  DEC     ECX
  FLD     QWORD PTR [SwStack + ECX*8]     // ST(0) = A
  INC     ECX
  FDIV    QWORD PTR [SwStack + ECX*8]     // ST(0) = A / B
  DEC     ECX
  MOV     [SwTop], ECX
  FSTP    QWORD PTR [SwStack + ECX*8]
end;

// ----------------------------------------------------------------------------
// FpuNeg  (operador unario "~")
// Inverte o sinal do topo. FCHS troca o bit de sinal do ST(0).
// ----------------------------------------------------------------------------
procedure FpuNeg;
asm
  MOV     ECX, [SwTop]
  FLD     QWORD PTR [SwStack + ECX*8]     // ST(0) = topo
  FCHS                                     // ST(0) = -topo
  FSTP    QWORD PTR [SwStack + ECX*8]
end;

// ----------------------------------------------------------------------------
// Conversoes graus <-> radianos. Multiplicam o topo pela constante adequada.
// Sao chamadas antes das funcoes trigonometricas diretas (entrada em graus)
// e depois das inversas (saida em radianos).
// ----------------------------------------------------------------------------
procedure FpuTopDegToRad;
asm
  MOV     ECX, [SwTop]
  FLD     QWORD PTR [SwStack + ECX*8]
  FMUL    QWORD PTR [DEG_TO_RAD]
  FSTP    QWORD PTR [SwStack + ECX*8]
end;

procedure FpuTopRadToDeg;
asm
  MOV     ECX, [SwTop]
  FLD     QWORD PTR [SwStack + ECX*8]
  FMUL    QWORD PTR [RAD_TO_DEG]
  FSTP    QWORD PTR [SwStack + ECX*8]
end;

// ----------------------------------------------------------------------------
// FpuSin / FpuCos
// Aplicam diretamente as instrucoes FSIN / FCOS sobre o topo (em radianos).
// ----------------------------------------------------------------------------
procedure FpuSin;
asm
  MOV     ECX, [SwTop]
  FLD     QWORD PTR [SwStack + ECX*8]
  FSIN
  FSTP    QWORD PTR [SwStack + ECX*8]
end;

procedure FpuCos;
asm
  MOV     ECX, [SwTop]
  FLD     QWORD PTR [SwStack + ECX*8]
  FCOS
  FSTP    QWORD PTR [SwStack + ECX*8]
end;

// ----------------------------------------------------------------------------
// FpuTan
// FPTAN (partial tangent) calcula tan(ST(0)) e empurra 1.0 no topo da FPU,
// deixando: ST(0) = 1.0, ST(1) = tan(x). Descartamos o 1.0 com FSTP ST(0).
// ----------------------------------------------------------------------------
procedure FpuTan;
asm
  MOV     ECX, [SwTop]
  FLD     QWORD PTR [SwStack + ECX*8]     // ST(0) = x
  FPTAN                                    // ST(0)=1.0, ST(1)=tan(x)
  FSTP    ST(0)                            // descarta 1.0
  FSTP    QWORD PTR [SwStack + ECX*8]      // grava tan(x)
end;

// ----------------------------------------------------------------------------
// FpuAtan
// FPATAN calcula arctan(ST(1) / ST(0)) (em radianos, faixa completa -pi..pi)
// e dropa ambos, deixando o resultado em ST(0).
// Para obter arctan(x), montamos ST(1)=x e ST(0)=1.
// ----------------------------------------------------------------------------
procedure FpuAtan;
asm
  MOV     ECX, [SwTop]
  FLD     QWORD PTR [SwStack + ECX*8]     // ST(0) = x
  FLD1                                     // ST(0) = 1, ST(1) = x
  FPATAN                                   // ST(0) = atan(x/1) = atan(x)
  FSTP    QWORD PTR [SwStack + ECX*8]
end;

// ----------------------------------------------------------------------------
// FpuAsin
// Identidade: asin(x) = atan( x / sqrt(1 - x*x) )
// O caller (EvalRpn) garante -1 <= x <= 1.
// ----------------------------------------------------------------------------
procedure FpuAsin;
asm
  MOV     ECX, [SwTop]
  FLD     QWORD PTR [SwStack + ECX*8]     // ST(0) = x
  FLD     ST(0)                            // ST(0) = x, ST(1) = x
  FMUL    ST(0), ST(0)                     // ST(0) = x*x, ST(1) = x
  FLD1                                     // ST(0) = 1, ST(1) = x*x, ST(2) = x
  FSUBRP  ST(1), ST(0)                     // ST(0) = 1 - x*x, ST(1) = x   (pop)
  FSQRT                                    // ST(0) = sqrt(1 - x*x), ST(1) = x
  FPATAN                                   // ST(0) = atan(x / sqrt(1-x*x)) (pop)
  FSTP    QWORD PTR [SwStack + ECX*8]
end;

// ----------------------------------------------------------------------------
// FpuAcos
// Identidade: acos(x) = atan2( sqrt(1 - x*x), x )
// FPATAN computa atan2(ST(1), ST(0)) em faixa completa, entao montamos
// ST(1) = sqrt(1 - x*x) e ST(0) = x.
// O caller garante -1 <= x <= 1.
// ----------------------------------------------------------------------------
procedure FpuAcos;
asm
  MOV     ECX, [SwTop]
  FLD     QWORD PTR [SwStack + ECX*8]     // ST(0) = x
  FLD     ST(0)                            // ST(0) = x, ST(1) = x
  FMUL    ST(0), ST(0)                     // ST(0) = x*x, ST(1) = x
  FLD1                                     // ST(0) = 1, ST(1) = x*x, ST(2) = x
  FSUBRP  ST(1), ST(0)                     // ST(0) = 1 - x*x, ST(1) = x
  FSQRT                                    // ST(0) = sqrt(1-x*x), ST(1) = x
  FXCH    ST(1)                            // ST(0) = x, ST(1) = sqrt(1-x*x)
  FPATAN                                   // ST(0) = atan2(sqrt(1-x*x), x) = acos(x)
  FSTP    QWORD PTR [SwStack + ECX*8]
end;

// ============================================================================
// EvalRpn
// Percorre a lista de tokens NPR aplicando o "metodo da varredura unica":
// numero -> empilha; operador -> retira operandos, calcula na FPU, empilha
// o resultado. Ao final, o unico valor restante no topo eh o resultado.
// ============================================================================
function EvalRpn(const Tokens: TRpnTokens; AngleDegrees: Boolean;
                 out R: Double): Integer;
var
  i: Integer;
  Tok: TRpnToken;
begin
  Result := EVAL_OK;
  R := 0;
  SwTop := -1;        // pilha de software vazia
  FpuInit;             // FINIT: estado deterministico da FPU

  for i := 0 to High(Tokens) do
  begin
    Tok := Tokens[i];
    case Tok.Kind of

      okNumber:
        begin
          if SwTop >= STACK_CAPACITY - 1 then
          begin
            Result := EVAL_ERR_STACK;
            Exit;
          end;
          FpuPushNumber(Tok.Value);
        end;

      okAdd:
        begin
          if SwTop < 1 then begin Result := EVAL_ERR_STACK; Exit; end;
          FpuAdd;
        end;

      okSub:
        begin
          if SwTop < 1 then begin Result := EVAL_ERR_STACK; Exit; end;
          FpuSub;
        end;

      okMul:
        begin
          if SwTop < 1 then begin Result := EVAL_ERR_STACK; Exit; end;
          FpuMul;
        end;

      okDiv:
        begin
          if SwTop < 1 then begin Result := EVAL_ERR_STACK; Exit; end;
          if SwStack[SwTop] = 0.0 then
          begin
            Result := EVAL_ERR_DIVZERO;
            Exit;
          end;
          FpuDiv;
        end;

      okNeg:
        begin
          if SwTop < 0 then begin Result := EVAL_ERR_STACK; Exit; end;
          FpuNeg;
        end;

      okSin:
        begin
          if SwTop < 0 then begin Result := EVAL_ERR_STACK; Exit; end;
          if AngleDegrees then FpuTopDegToRad;
          FpuSin;
        end;

      okCos:
        begin
          if SwTop < 0 then begin Result := EVAL_ERR_STACK; Exit; end;
          if AngleDegrees then FpuTopDegToRad;
          FpuCos;
        end;

      okTan:
        begin
          if SwTop < 0 then begin Result := EVAL_ERR_STACK; Exit; end;
          if AngleDegrees then FpuTopDegToRad;
          FpuTan;
        end;

      okASin:
        begin
          if SwTop < 0 then begin Result := EVAL_ERR_STACK; Exit; end;
          if (SwStack[SwTop] < -1.0) or (SwStack[SwTop] > 1.0) then
          begin
            Result := EVAL_ERR_DOMAIN;
            Exit;
          end;
          FpuAsin;
          if AngleDegrees then FpuTopRadToDeg;
        end;

      okACos:
        begin
          if SwTop < 0 then begin Result := EVAL_ERR_STACK; Exit; end;
          if (SwStack[SwTop] < -1.0) or (SwStack[SwTop] > 1.0) then
          begin
            Result := EVAL_ERR_DOMAIN;
            Exit;
          end;
          FpuAcos;
          if AngleDegrees then FpuTopRadToDeg;
        end;

      okATan:
        begin
          if SwTop < 0 then begin Result := EVAL_ERR_STACK; Exit; end;
          FpuAtan;
          if AngleDegrees then FpuTopRadToDeg;
        end;

    else
      // okLParen / okRParen nao devem aparecer na NPR. Se aparecerem,
      // significa que o parser falhou; tratamos como erro de pilha.
      Result := EVAL_ERR_STACK;
      Exit;
    end;
  end;

  // Ao final, deve restar exatamente um valor na pilha de software.
  if SwTop <> 0 then
  begin
    Result := EVAL_ERR_STACK;
    Exit;
  end;
  R := SwStack[0];
end;

end.
