program Solitaire;

uses
  System.StartUpCopy,
  FMX.Forms,
  uMain in 'uMain.pas' {MainForm},
  uBoard in 'uBoard.pas',
  uCardGame in 'uCardGame.pas',
  uGameKlondike in 'uGameKlondike.pas',
  uGameSpider in 'uGameSpider.pas',
  uGameFreeCell in 'uGameFreeCell.pas',
  uGamePyramid in 'uGamePyramid.pas',
  uGameTriPeaks in 'uGameTriPeaks.pas',
  uGames in 'uGames.pas',
  uStats in 'uStats.pas',
  uAutoPlay in 'uAutoPlay.pas',
  uSelfTest in 'uSelfTest.pas',
  uDemo in 'uDemo.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.