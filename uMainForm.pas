unit uMainForm;

{$mode Delphi}{$H+}
// Handlers de evento do LCL recebem "Sender: TObject" por contrato; alguns
// nao precisam do parametro - silenciamos o hint cosmetico 5024.
{$HINTS OFF}

// ============================================================================
// uMainForm.pas
// Formulario principal da calculadora. Toda a interacao com o usuario passa
// por aqui: insercao de tokens no display, modos Graus/Radianos, modo Inv
// (funcoes trigonometricas inversas), Backspace/CE/C, e o botao "=" que
// dispara a conversao para Notacao Polonesa Reversa e o calculo em Assembly.
//
// Interface grafica em Lazarus/LCL (TForm, TEdit, TButton, TRadioGroup,
// TCheckBox, TLabel).
// ============================================================================

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls;

type
  TMainForm = class(TForm)
    edtDisplay: TEdit;
    rgModo: TRadioGroup;
    chkInv: TCheckBox;
    btnBackspace: TButton;
    btnCE: TButton;
    btnC: TButton;
    btnSin: TButton;
    btnCos: TButton;
    btnTan: TButton;
    btnOpenParen: TButton;
    btnCloseParen: TButton;
    btn7: TButton;
    btn8: TButton;
    btn9: TButton;
    btnDiv: TButton;
    btn4: TButton;
    btn5: TButton;
    btn6: TButton;
    btnMul: TButton;
    btn1: TButton;
    btn2: TButton;
    btn3: TButton;
    btnSub: TButton;
    btn0: TButton;
    btnDot: TButton;
    btnEquals: TButton;
    btnAdd: TButton;
    lblInvHint: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure DigitClick(Sender: TObject);
    procedure OperatorClick(Sender: TObject);
    procedure ParenClick(Sender: TObject);
    procedure TrigClick(Sender: TObject);
    procedure btnBackspaceClick(Sender: TObject);
    procedure btnCEClick(Sender: TObject);
    procedure btnCClick(Sender: TObject);
    procedure btnEqualsClick(Sender: TObject);
    procedure chkInvClick(Sender: TObject);
  private
    FResultShown: Boolean;
    procedure AppendText(const S: string);
    procedure StartFreshIfShowingResult;
    procedure UpdateInvHint;
  end;

var
  MainForm: TMainForm;

implementation

uses
  uRpnParser, uCalcFpu;

{$R *.lfm}

// ----------------------------------------------------------------------------
// FormCreate
// Inicializa o estado da calculadora.
// ----------------------------------------------------------------------------
procedure TMainForm.FormCreate(Sender: TObject);
begin
  edtDisplay.Text := '';
  FResultShown := False;
  rgModo.ItemIndex := 0; // 0 = Graus, 1 = Radianos
  chkInv.Checked := False;
  UpdateInvHint;
end;

// ----------------------------------------------------------------------------
// StartFreshIfShowingResult
// Se acabou de exibir um resultado e o usuario clica em um digito,
// limpa o display antes de inserir o novo numero (comportamento padrao
// de calculadora). Se for operador, mantem o resultado como primeiro operando.
// ----------------------------------------------------------------------------
procedure TMainForm.StartFreshIfShowingResult;
begin
  if FResultShown then
  begin
    edtDisplay.Text := '';
    FResultShown := False;
  end;
end;

// ----------------------------------------------------------------------------
// AppendText
// Acrescenta uma string ao final do display. Trata o caso de "ja existe
// resultado mostrado" para iniciar nova expressao quando necessario.
// ----------------------------------------------------------------------------
procedure TMainForm.AppendText(const S: string);
begin
  edtDisplay.Text := edtDisplay.Text + S;
  edtDisplay.SelStart := Length(edtDisplay.Text);
end;

// ----------------------------------------------------------------------------
// DigitClick
// Handler comum para 0-9 e ponto decimal. Identifica o botao pela Caption.
// ----------------------------------------------------------------------------
procedure TMainForm.DigitClick(Sender: TObject);
begin
  StartFreshIfShowingResult;
  AppendText((Sender as TButton).Caption);
end;

// ----------------------------------------------------------------------------
// OperatorClick
// Handler comum para + - * / . Apos clicar em "=" e ter um resultado,
// o operador continua a partir do resultado (nao limpa o display).
// ----------------------------------------------------------------------------
procedure TMainForm.OperatorClick(Sender: TObject);
begin
  FResultShown := False;
  AppendText((Sender as TButton).Caption);
end;

// ----------------------------------------------------------------------------
// ParenClick
// Handler dos parenteses ( e ).
// ----------------------------------------------------------------------------
procedure TMainForm.ParenClick(Sender: TObject);
begin
  StartFreshIfShowingResult;
  AppendText((Sender as TButton).Caption);
end;

// ----------------------------------------------------------------------------
// TrigClick
// Handler de sin/cos/tan. Se o modo Inv estiver ativo, insere a versao
// inversa (asin/acos/atan). Em ambos os casos, abre o parentese da funcao,
// que o usuario fecha digitando o operando + ")".
// ----------------------------------------------------------------------------
procedure TMainForm.TrigClick(Sender: TObject);
var
  Token: string;
begin
  StartFreshIfShowingResult;
  if chkInv.Checked then
    Token := 'a' + LowerCase((Sender as TButton).Caption) + '('
  else
    Token := LowerCase((Sender as TButton).Caption) + '(';
  AppendText(Token);
end;

// ----------------------------------------------------------------------------
// btnBackspaceClick
// Remove o ultimo caractere. Se for parte de um token "sin(", "asin(", etc.,
// remove o token inteiro para evitar deixar a expressao em estado invalido.
// ----------------------------------------------------------------------------
procedure TMainForm.btnBackspaceClick(Sender: TObject);
var
  S: string;
  Triggers: array[0..5] of string;
  i, L: Integer;
  Removed: Boolean;
begin
  FResultShown := False;
  S := edtDisplay.Text;
  if S = '' then Exit;

  Triggers[0] := 'sin(';
  Triggers[1] := 'cos(';
  Triggers[2] := 'tan(';
  Triggers[3] := 'asin(';
  Triggers[4] := 'acos(';
  Triggers[5] := 'atan(';

  Removed := False;
  for i := 0 to High(Triggers) do
  begin
    L := Length(Triggers[i]);
    if (Length(S) >= L) and (Copy(S, Length(S) - L + 1, L) = Triggers[i]) then
    begin
      S := Copy(S, 1, Length(S) - L);
      Removed := True;
      Break;
    end;
  end;
  if not Removed then
    S := Copy(S, 1, Length(S) - 1);

  edtDisplay.Text := S;
  edtDisplay.SelStart := Length(S);
end;

// ----------------------------------------------------------------------------
// btnCEClick
// Clear Entry: apaga o ultimo numero/token inserido (ate o operador anterior).
// ----------------------------------------------------------------------------
procedure TMainForm.btnCEClick(Sender: TObject);
var
  S: string;
  i: Integer;
begin
  FResultShown := False;
  S := edtDisplay.Text;
  i := Length(S);
  // recua enquanto for digito, ponto ou virgula
  while (i >= 1) and (S[i] in ['0'..'9', '.', ',']) do
    Dec(i);
  edtDisplay.Text := Copy(S, 1, i);
  edtDisplay.SelStart := Length(edtDisplay.Text);
end;

// ----------------------------------------------------------------------------
// btnCClick
// Clear: limpa o display por completo.
// ----------------------------------------------------------------------------
procedure TMainForm.btnCClick(Sender: TObject);
begin
  edtDisplay.Text := '';
  FResultShown := False;
end;

// ----------------------------------------------------------------------------
// btnEqualsClick
// Dispara a avaliacao da expressao:
//   1) Lexer + algoritmo de shunting-yard (uRpnParser) -> lista de tokens NPR
//   2) Avaliacao da NPR em Assembly via FPU (uCalcFpu)
//   3) Atualiza o display com o resultado ou mensagem de erro
// ----------------------------------------------------------------------------
procedure TMainForm.btnEqualsClick(Sender: TObject);
var
  Tokens: TRpnTokens;
  ParseErr: TParseError;
  ErrCode: Integer;
  R: Double;
  S: string;
begin
  if Trim(edtDisplay.Text) = '' then Exit;

  Tokens := InfixToRpn(edtDisplay.Text, ParseErr);
  if ParseErr <> peNone then
  begin
    case ParseErr of
      peUnbalancedParen: S := 'Erro: parenteses desbalanceados';
      peUnknownToken:    S := 'Erro: simbolo desconhecido';
      peEmpty:           S := 'Erro: expressao vazia';
    else
      S := 'Erro de sintaxe';
    end;
    edtDisplay.Text := S;
    FResultShown := True;
    Exit;
  end;

  ErrCode := EvalRpn(Tokens, rgModo.ItemIndex = 0, R);
  case ErrCode of
    EVAL_OK:
      begin
        // formata o resultado com ate 12 digitos significativos, removendo
        // zeros a direita para uma apresentacao mais limpa
        S := FloatToStrF(R, ffGeneral, 12, 0);
        // normaliza separador decimal para "." na exibicao (independente do locale)
        S := StringReplace(S, ',', '.', [rfReplaceAll]);
        edtDisplay.Text := S;
      end;
    EVAL_ERR_STACK:    edtDisplay.Text := 'Erro: pilha';
    EVAL_ERR_DIVZERO:  edtDisplay.Text := 'Erro: divisao por zero';
    EVAL_ERR_DOMAIN:   edtDisplay.Text := 'Erro: dominio invalido';
  else
    edtDisplay.Text := 'Erro de calculo';
  end;
  FResultShown := True;
end;

// ----------------------------------------------------------------------------
// chkInvClick
// Atualiza o rotulo de dica que mostra ao usuario se Inv esta ativo.
// ----------------------------------------------------------------------------
procedure TMainForm.chkInvClick(Sender: TObject);
begin
  UpdateInvHint;
end;

procedure TMainForm.UpdateInvHint;
begin
  if chkInv.Checked then
    lblInvHint.Caption := 'Inv: sin/cos/tan inserem asin/acos/atan'
  else
    lblInvHint.Caption := '';
end;

end.
