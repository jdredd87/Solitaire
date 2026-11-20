unit uDemo;

{ Self-running demonstration: the app plays every game by itself, at a pace a
  person can follow, through the board's own mouse/touch handlers. Meant for
  recording videos and for showing the app off.

    Windows:  Solitaire.exe -demo      (closes itself after the last game)
    Mobile:   put an empty file named demo.flag in the app's data folder and
              start the app; the flag is removed and the demo loops until the
              app is closed. On a debug Android build:
                adb shell run-as <package> touch files/demo.flag

  The demo keeps its deals and statistics in a "demo" subfolder, so the
  player's own statistics and saved games are never touched. }

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.IOUtils,
  System.Diagnostics, System.Math,
  FMX.Types, FMX.Forms,
  uCardGame, uGames, uStats, uBoard, uAutoPlay, uMain;

type
  TDemo = class
  private
    FForm: TMainForm;
    FTimer: TTimer;
    FPlayer: TAutoPlayer;
    FG, FStep: Integer;
    FStepWatch, FIdle, FDragWatch: TStopwatch;
    FDragging: Boolean;
    FDragFrom, FDragTo: TPointF;
    FQuitAtEnd: Boolean;
    FLimit: Integer;             // seconds this game is shown for; 0 = to the end
    procedure GoStep(AStep: Integer);
    procedure StartGame;
    procedure PlayOne;
    procedure ContinueDrag;
    procedure Tick(Sender: TObject);
  public
    constructor Create(AForm: TMainForm);
    destructor Destroy; override;
  end;

/// True when this run should be a demo (command-line switch or flag file).
function DemoRequested: Boolean;
/// Points the app at a private, empty data folder for the demo.
procedure PrepareDemoData;

implementation

type
  TDemoPlan = record
    Variant: Integer;
    Seconds: Integer;      // 0 = play a winnable deal to the end
    Effect: TWinEffect;
  end;

const
  // one entry per game in GAME_CLASSES; further games get the last entry
  PLAN: array[0..4] of TDemoPlan = (
    (Variant: 0; Seconds: 0;  Effect: weBounce),       // Klondike, draw 1
    (Variant: 1; Seconds: 28; Effect: weFireworks),    // Spider, 2 suits
    (Variant: 0; Seconds: 24; Effect: weFireworks),    // FreeCell
    (Variant: 0; Seconds: 0;  Effect: weFireworks),    // Pyramid
    (Variant: 0; Seconds: 0;  Effect: weFountain));    // TriPeaks
  FALLBACK_SECONDS = 40;   // for a "to the end" game when no winnable deal was found
  MOVE_PAUSE = 0.30;       // rest between moves
  DRAG_TIME = 0.34;        // how long a dragged card is in the air
  WIN_HOLD = 9.0;          // how long the win effect is shown
  ST_WAIT = 0;
  ST_DEAL = 1;
  ST_PLAY = 2;
  ST_WIN = 3;
  ST_NEXT = 4;

function DemoRequested: Boolean;
var
  Flag: string;
begin
  Result := FindCmdLineSwitch('demo');
  if Result then
    Exit;
  try
    Flag := TPath.Combine(AppDataDir, 'demo.flag');
    Result := TFile.Exists(Flag);
    if Result then
      TFile.Delete(Flag);
  except
    // an unreadable folder simply means no demo
  end;
end;

procedure PrepareDemoData;
var
  Dir, F: string;
begin
  Dir := TPath.Combine(AppDataDir, 'demo');
  DataDirOverride := Dir;
  ForceDirectories(Dir);
  for F in TDirectory.GetFiles(Dir) do
    try
      TFile.Delete(F);
    except
    end;
end;

{ TDemo }

constructor TDemo.Create(AForm: TMainForm);
begin
  inherited Create;
  FForm := AForm;
  FQuitAtEnd := FindCmdLineSwitch('demo');
  FStepWatch := TStopwatch.StartNew;
  FIdle := TStopwatch.StartNew;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 16;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TDemo.Destroy;
begin
  FTimer.Free;
  FPlayer.Free;
  inherited;
end;

procedure TDemo.GoStep(AStep: Integer);
begin
  FStep := AStep;
  FStepWatch := TStopwatch.StartNew;
end;

procedure TDemo.StartGame;
var
  Cls: TCardGameClass;
  P: TDemoPlan;
  Seed: Integer;
begin
  FForm.SwitchGame(FG);
  Cls := GAME_CLASSES[FG];
  P := PLAN[Min(FG, High(PLAN))];
  FForm.Stats.SetVariant(FForm.Game.GameId, P.Variant);
  Seed := 1;
  FLimit := P.Seconds;
  if FLimit = 0 then
  begin
    Seed := FindWinnableSeed(Cls, P.Variant, 1, 400);
    if Seed < 0 then
    begin
      Seed := 1;
      FLimit := FALLBACK_SECONDS;
    end;
  end;
  FForm.Board.WinEffect := P.Effect;
  FForm.StartNewGame(Seed);
  FreeAndNil(FPlayer);
  FPlayer := TAutoPlayer.Create(FForm.Game);
  FDragging := False;
end;

procedure TDemo.PlayOne;
var
  G: TCardGame;
  B: TSolitaireBoard;
  H: THint;
begin
  G := FForm.Game;
  B := FForm.Board;
  H := FPlayer.Choose;
  if H.Kind = hkNone then
  begin
    GoStep(ST_NEXT);   // stuck, or going round in circles
    Exit;
  end;
  if (H.Kind = hkTap) or ((G.PileKind(H.Dst) = pkFoundation) and G.FoundationsBuildUp) then
    B.SimulateTap(H.Src, H.Index)   // a tap sends a card to its foundation by itself
  else
  begin
    FDragFrom := B.CardCenter(H.Src, H.Index);
    FDragTo := B.DropCenter(H.Dst);
    B.SimulatePointer(0, FDragFrom);
    FDragging := True;
    FDragWatch := TStopwatch.StartNew;
  end;
end;

procedure TDemo.ContinueDrag;
var
  T: Single;
begin
  T := Min(1, FDragWatch.Elapsed.TotalSeconds / DRAG_TIME);
  if T < 1 then
  begin
    T := T * T * (3 - 2 * T);   // ease in and out
    FForm.Board.SimulatePointer(1, FDragFrom + (FDragTo - FDragFrom) * T);
  end
  else
  begin
    FForm.Board.SimulatePointer(1, FDragTo);
    FForm.Board.SimulatePointer(2, FDragTo);
    FDragging := False;
    FIdle := TStopwatch.StartNew;
  end;
end;

procedure TDemo.Tick(Sender: TObject);
var
  B: TSolitaireBoard;
  Limit: Integer;
begin
  B := FForm.Board;
  try
    case FStep of
      ST_WAIT:
        if FStepWatch.Elapsed.TotalSeconds > 1.5 then
        begin
          FG := 0;
          GoStep(ST_DEAL);
        end;

      ST_DEAL:
        begin
          StartGame;
          GoStep(ST_PLAY);
          FIdle := TStopwatch.StartNew;
        end;

      ST_PLAY:
        if B.WinActive then
          GoStep(ST_WIN)
        else if FDragging then
          ContinueDrag
        else if B.Animating or B.AutoCompleting then
          FIdle := TStopwatch.StartNew
        else if (FStepWatch.Elapsed.TotalSeconds > 1.5) and (FIdle.Elapsed.TotalSeconds >= MOVE_PAUSE) then
        begin
          Limit := FLimit;
          if Limit = 0 then
            Limit := 240;   // never let one game run for more than a few minutes
          if (Limit > 0) and (FStepWatch.Elapsed.TotalSeconds > Limit) then
            GoStep(ST_NEXT)
          else
          begin
            PlayOne;
            FIdle := TStopwatch.StartNew;
          end;
        end;

      ST_WIN:
        if FStepWatch.Elapsed.TotalSeconds > WIN_HOLD then
          GoStep(ST_NEXT);

      ST_NEXT:
        if FStepWatch.Elapsed.TotalSeconds > 1.5 then
        begin
          Inc(FG);
          if FG > High(GAME_CLASSES) then
          begin
            if FQuitAtEnd then
            begin
              FTimer.Enabled := False;
              Application.Terminate;
              Exit;
            end;
            FG := 0;
          end;
          GoStep(ST_DEAL);
        end;
    end;
  except
    // a demo must never take the app down; move on to the next game
    FDragging := False;
    GoStep(ST_NEXT);
  end;
end;

end.
