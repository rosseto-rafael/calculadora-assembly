program Calc;

{$mode objfpc}{$H+}
// uRpnParser e uCalcFpu sao usadas por uMainForm; listamos aqui para deixar
// a estrutura do projeto explicita. 5023 = "unit nao usada diretamente" (hint).
{$WARN 5023 OFF}

// ============================================================================
// Trabalho da disciplina de Microprocessadores - UNESP
// Calculadora cientifica em Free Pascal/Lazarus com nucleo de avaliacao em
// Assembly x87 (FPU) usando Notacao Polonesa Reversa (NPR) - aula 29.
//
// Estrutura de diretorios:
//   src/  - fontes (este arquivo, units, .lfm, Calc.lpi)
//   bin/  - Calc.exe e artefatos de compilacao (.o, .ppu, ...)
//   rel/  - relatorio em Markdown para impressao (rel/relatorio.md)
//
// "Interfaces" no uses ativa o widgetset do LCL (win32 no Windows).
// ============================================================================

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,
  Forms,
  uMainForm,
  uRpnParser,
  uCalcFpu;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Title := 'Calculadora FPU';
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
