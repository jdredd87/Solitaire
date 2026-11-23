unit uSelfTest;

{ End-to-end test of the real FMX app. Start with:   Solitaire.exe -selftest

  For every game it deals a hand (one the auto-player is known to win, where
  such a deal can be found), plays it through the board's own mouse/touch
  handlers (taps and drags), and checks the move animations, undo, hints, the
  help screen, statistics, the layouts for phone/landscape/desktop windows and
  that no text is cut off. Klondike is also played to a win to check
  auto-complete and the win effects. Results go to
  <exe folder>\selftest-out\selftest.log together with screenshots; the process
  exit code is 0 when every check passed. }

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.IOUtils,
  System.Diagnostics, System.Math,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics,
  uCardGame, uGames, uStats, uBoard, uAutoPlay, uMain;

type
  TSelfTest = class
  private
    FForm: TMainForm;
    FTimer: TTimer;
    FLog: TStringList;
    FFails, FChecks: Integer;
    FStep, FSub: Integer;
    FStepWatch, FTotalWatch: TStopwatch;
    FPlayer: TAutoPlayer;
    FG: Integer;                 // game being tested
    FSeed: Integer;
    FWinnable: Boolean;
    FPlayed0, FWon0: Integer;
    FStartHash: string;
    FMovesPlayed, FAnimsSeen, FDrags, FTaps: Integer;
    FSawAutoComplete, FShotMid: Boolean;
    FFrames0, FObjects1: Integer;
    FKeepMoves: Integer;
    FKeepHash: string;
    FDone: Boolean;
    procedure Log(const S: string);
    procedure Check(Cond: Boolean; const Msg: string);
    procedure Shot(const Name: string);
    procedure ShotCourts;
    procedure ShotControl(C: TControl; const Name: string);
    procedure GoStep(AStep: Integer);
    function StepSecs: Double;
    function Tag: string;
    procedure Tick(Sender: TObject);
    procedure DoHintMove(const H: THint);
    procedure PlayOne;
    procedure Finish;
  public
    constructor Create(AForm: TMainForm);
    destructor Destroy; override;
  end;

/// Points the app at an empty, private data folder for the test run.
procedure PrepareSelfTestData;

implementation

const
  MAX_UI_MOVES = 450;
  ST_START = 1;
  ST_UNDO = 2;
  ST_PLAY = 3;
  ST_RESULT = 4;
  ST_HINT = 5;
  ST_HELP = 6;
  ST_SIZES = 7;
  ST_NEXT = 8;
  ST_SWITCH = 9;
  ST_EFFECTS = 10;
  ST_RANDOM = 11;
  ST_PANELS = 12;
  ST_FILES = 13;
  ST_END = 900;

function OutDir: string;
begin
  Result := TPath.Combine(ExtractFilePath(ParamStr(0)), 'selftest-out');
end;

procedure PrepareSelfTestData;
var
  F: string;
begin
  DataDirOverride := OutDir;
  ForceDirectories(OutDir);
  for F in TDirectory.GetFiles(OutDir) do
    try
      TFile.Delete(F);
    except
    end;
end;

{ TSelfTest }

constructor TSelfTest.Create(AForm: TMainForm);
begin
  inherited Create;
  FForm := AForm;
  FLog := TStringList.Create;
  FTotalWatch := TStopwatch.StartNew;
  FStepWatch := TStopwatch.StartNew;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 20;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  Log('Solitaire self-test started');
end;

destructor TSelfTest.Destroy;
begin
  FTimer.Free;
  FPlayer.Free;
  FLog.Free;
  inherited;
end;

procedure TSelfTest.Log(const S: string);
begin
  FLog.Add(Format('[%6.2fs] %s', [FTotalWatch.Elapsed.TotalSeconds, S]));
end;

procedure TSelfTest.Check(Cond: Boolean; const Msg: string);
begin
  Inc(FChecks);
  if Cond then
    Log('PASS  ' + Msg)
  else
  begin
    Inc(FFails);
    Log('FAIL  ' + Msg);
  end;
end;

procedure TSelfTest.ShotControl(C: TControl; const Name: string);
var
  B: TBitmap;
begin
  try
    B := C.MakeScreenshot;
    try
      B.SaveToFile(TPath.Combine(OutDir, Name + '.png'));
    finally
      B.Free;
    end;
  except
    on E: Exception do
      Check(False, 'screenshot ' + Name + ': ' + E.Message);
  end;
end;

procedure TSelfTest.ShotCourts;
var
  Cards: array[0..5] of TCard;
  I: Integer;
  B: TBitmap;
begin
  for I := 0 to 5 do
  begin
    Cards[I] := Default(TCard);
    Cards[I].Rank := 11 + I mod 3;
    if I < 3 then
      Cards[I].Suit := suSpades
    else
      Cards[I].Suit := suHearts;
    Cards[I].FaceUp := True;
  end;
  try
    B := FForm.Board.SampleCards(Cards, 2);
    try
      B.SaveToFile(TPath.Combine(OutDir, '9-classic-courts.png'));
    finally
      B.Free;
    end;
  except
    on E: Exception do
      Check(False, 'court card sample: ' + E.Message);
  end;
end;

procedure TSelfTest.Shot(const Name: string);
begin
  ShotControl(FForm.Board, Name);
end;

procedure TSelfTest.GoStep(AStep: Integer);
begin
  FStep := AStep;
  FSub := 0;
  FStepWatch := TStopwatch.StartNew;
end;

function TSelfTest.StepSecs: Double;
begin
  Result := FStepWatch.Elapsed.TotalSeconds;
end;

function TSelfTest.Tag: string;
begin
  Result := FForm.Game.Title;
end;

/// Carries a hint out through the board's mouse handlers.
procedure TSelfTest.DoHintMove(const H: THint);
begin
  if H.Kind = hkTap then
  begin
    FForm.Board.SimulateTap(H.Src, H.Index);
    Inc(FTaps);
  end
  else if (FForm.Game.PileKind(H.Dst) = pkFoundation) and FForm.Game.FoundationsBuildUp
    and (FTaps <= FDrags) then
  begin
    // a tap sends a card to its foundation by itself
    FForm.Board.SimulateTap(H.Src, H.Index);
    Inc(FTaps);
  end
  else
  begin
    FForm.Board.SimulateDrag(H.Src, H.Index, H.Dst);
    Inc(FDrags);
  end;
end;

procedure TSelfTest.PlayOne;
var
  G: TCardGame;
  B: TSolitaireBoard;
  H: THint;
  Before, TapsBefore: Integer;
  Msg: string;
begin
  G := FForm.Game;
  B := FForm.Board;
  H := FPlayer.Choose;
  if (H.Kind = hkNone) or (FMovesPlayed >= MAX_UI_MOVES) then
  begin
    GoStep(ST_RESULT);
    Exit;
  end;
  Before := G.Moves;
  TapsBefore := FTaps;
  DoHintMove(H);
  Inc(FMovesPlayed);
  if G.Moves <> Before + 1 then
  begin
    Check(False, Format('%s: move %d (%d[%d] -> %d) was not carried out by the board',
      [Tag, FMovesPlayed, H.Src, H.Index, H.Dst]));
    GoStep(ST_RESULT);
    Exit;
  end;
  if not G.CheckIntegrity(Msg) then
  begin
    Check(False, Format('%s: integrity after move %d: %s', [Tag, FMovesPlayed, Msg]));
    GoStep(ST_RESULT);
    Exit;
  end;
  if B.Animating or B.WinActive or B.AutoCompleting then
    Inc(FAnimsSeen)
  else if FTaps > TapsBefore then
    // a tapped card always has to travel; a dragged one may already be
    // exactly where it belongs when it is dropped
    Check(False, Format('%s: no animation started for tap move %d', [Tag, FMovesPlayed]));
end;

procedure TSelfTest.Tick(Sender: TObject);
var
  G: TCardGame;
  B: TSolitaireBoard;
  Cls: TCardGameClass;
  I, Before: Integer;
  H: THint;
  E: TWinEffect;
  M: TModeStats;
  Msg: string;
  Seen: array[0..2] of TWinEffect;
const
  PREVIEW: array[0..1] of TWinEffect = (weFireworks, weFountain);
  SIZES: array[0..2] of record Name: string; W, H: Integer; end = (
    (Name: 'portrait';  W: 390;  H: 800),
    (Name: 'landscape'; W: 820;  H: 380),
    (Name: 'desktop';   W: 1000; H: 720));
  PANEL_NAMES: array[TPanelKind] of string = ('', 'menu', 'games', 'help', 'options');
begin
  if FDone then
    Exit;
  G := FForm.Game;
  B := FForm.Board;
  try
    if FTotalWatch.Elapsed.TotalSeconds > 900 then
    begin
      Check(False, Format('timed out in step %d', [FStep]));
      FStep := ST_END;
    end;

    case FStep of
      0:
        if StepSecs > 0.5 then
        begin
          FForm.WindowState := TWindowState.wsNormal;
          FForm.ClientWidth := 1000;
          FForm.ClientHeight := 720;
          B.WinEffect := weBounce;
          FG := 0;
          GoStep(ST_START);
        end;

      ST_START: // switch to the game and deal a hand
        if FSub = 0 then
        begin
          FForm.SwitchGame(FG);
          G := FForm.Game;
          Cls := GAME_CLASSES[FG];
          Check(G.ClassType = Cls, Format('switched to %s', [Cls.Title]));
          FForm.Stats.SetVariant(G.GameId, 0);
          FSeed := FindWinnableSeed(Cls, 0, 1, 400);
          FWinnable := FSeed >= 0;
          if FWinnable then
            Log(Format('%s: the auto-player wins seed %d', [Tag, FSeed]))
          else
          begin
            Log(Format('%s: the auto-player won none of 400 deals; playing seed 1 as far as it gets', [Tag]));
            FSeed := 1;
          end;
          FForm.StartNewGame(FSeed);
          M := FForm.Stats.Get(G.GameId, 0);
          FPlayed0 := M.Played;
          FWon0 := M.Won;
          FStartHash := G.LayoutHash;
          FMovesPlayed := 0;
          FAnimsSeen := 0;
          FDrags := 0;
          FTaps := 0;
          FSawAutoComplete := False;
          FShotMid := False;
          Check(G.CheckIntegrity(Msg), Format('%s: fresh deal is valid %s', [Tag, Msg]));
          Check((G.Moves = 0) and not G.CanUndo and not G.IsWon, Format('%s: fresh game state', [Tag]));
          Check(B.CheckLayout(Msg), Format('%s: deal fits the board %s', [Tag, Msg]));
          Check(Pos(G.Title, FForm.StatusText) > 0, Format('%s: status line names the game', [Tag]));
          FSub := 1;
          FStepWatch := TStopwatch.StartNew;
        end
        else if StepSecs > 0.3 then
        begin
          Shot(Format('%d-%s-1-deal', [FG + 1, G.GameId]));
          GoStep(ST_UNDO);
        end;

      ST_UNDO: // one move through the UI, then undo it
        case FSub of
          0:
            begin
              if FG = 0 then
              begin
                // Klondike: a drop on the stock is illegal and must glide back
                Before := G.Moves;
                I := G.CardCount(G.PileCount - 1) - 1;
                B.SimulateDragTo(G.PileCount - 1, I, B.CardCenter(0, -1));
                Check(G.Moves = Before, 'illegal drop does not change the game');
                Check(B.Animating, 'illegal drop starts the glide-back animation');
              end;
              FSub := 1;
            end;
          1:
            if not B.Animating then
            begin
              H := G.Hint;
              Check(H.Kind <> hkNone, Format('%s: a fresh deal has a hint', [Tag]));
              if H.Kind = hkNone then
              begin
                GoStep(ST_PLAY);
                FPlayer.Free;
                FPlayer := TAutoPlayer.Create(G);
                Exit;
              end;
              DoHintMove(H);
              Check(G.Moves = 1, Format('%s: first move is carried out', [Tag]));
              Check(FForm.Stats.Get(G.GameId, 0).Played = FPlayed0 + 1,
                Format('%s: first move counts the game as played', [Tag]));
              Check(G.CanUndo, Format('%s: undo is available', [Tag]));
              FSub := 2;
            end;
          2:
            if not B.Animating then
            begin
              Check(FForm.DoUndo, Format('%s: undo works', [Tag]));
              Check((G.Moves = 0) and (G.LayoutHash = FStartHash),
                Format('%s: undo restores the deal exactly', [Tag]));
              FPlayer.Free;
              FPlayer := TAutoPlayer.Create(G);
              FFrames0 := B.FrameCount;
              FDrags := 0;
              FTaps := 0;
              GoStep(ST_PLAY);
            end;
        end;

      ST_PLAY: // play the hand through the UI by following the hints
        begin
          if B.AutoCompleting then
            FSawAutoComplete := True;
          if B.WinActive then
            GoStep(ST_RESULT)
          else if not (B.Animating or B.AutoCompleting) then
          begin
            if (FMovesPlayed >= 25) and not FShotMid then
            begin
              FShotMid := True;
              Shot(Format('%d-%s-2-play', [FG + 1, G.GameId]));
            end;
            PlayOne;
          end;
        end;

      ST_RESULT:
        case FSub of
          0:
            if not B.Animating then
            begin
              Log(Format('%s: %d moves through the UI (%d drags, %d taps), %d animations, won=%s',
                [Tag, FMovesPlayed, FDrags, FTaps, FAnimsSeen, BoolToStr(G.IsWon, True)]));
              Check(FMovesPlayed >= 3, Format('%s: several moves were played (%d)', [Tag, FMovesPlayed]));
              Check(FAnimsSeen >= FTaps, Format('%s: moves were animated (%d of %d)', [Tag, FAnimsSeen, FMovesPlayed]));
              Check(B.FrameCount - FFrames0 > 20, Format('%s: animation frames were drawn (%d)', [Tag, B.FrameCount - FFrames0]));
              Check(G.CheckIntegrity(Msg), Format('%s: layout valid after play %s', [Tag, Msg]));
              if FWinnable then
                Check(G.IsWon, Format('%s: the winnable deal was won through the UI', [Tag]));
              FObjects1 := 0;
              if G.IsWon then
                FSub := 1
              else
              begin
                if G.IsStuck then
                  Log(Format('%s: the game reports no more moves', [Tag]));
                Shot(Format('%d-%s-3-end', [FG + 1, G.GameId]));
                GoStep(ST_HINT);
              end;
            end;
          1: // the win screen
            if StepSecs > 1.0 then
            begin
              M := FForm.Stats.Get(G.GameId, 0);
              Check(B.WinActive, Format('%s: win effect is running', [Tag]));
              Check(M.Won = FWon0 + 1, Format('%s: win was added to this game''s statistics', [Tag]));
              Check(M.Streak >= 1, Format('%s: win streak increased', [Tag]));
              Check(M.BestScore >= G.Score, Format('%s: best score recorded', [Tag]));
              Check(B.ActiveEffect = weBounce, Format('%s: bouncing-card effect chosen', [Tag]));
              Check(B.TrailBitmap <> nil, Format('%s: bounce effect has its trail bitmap', [Tag]));
              if FG = 0 then
              begin
                Check(FSawAutoComplete, 'Klondike: auto-complete took over at the end');
                Check((FDrags > 5) and (FTaps > 5), Format('Klondike: both drags (%d) and taps (%d) were used', [FDrags, FTaps]));
              end;
              FObjects1 := Max(1, B.EffectObjectCount);
              FFrames0 := B.FrameCount;
              FSub := 2;
            end;
          2:
            if StepSecs > 5.0 then
            begin
              Check(B.EffectObjectCount > FObjects1, Format('%s: more cards keep bouncing off (%d -> %d)',
                [Tag, FObjects1, B.EffectObjectCount]));
              Check(B.FrameCount - FFrames0 > 80, Format('%s: bounce effect keeps animating', [Tag]));
              Shot(Format('%d-%s-3-win', [FG + 1, G.GameId]));
              B.SimulateTap(0, -1);   // tapping the win screen deals again
              Check(not B.WinActive, Format('%s: tap closes the win effect', [Tag]));
              Check((G.Moves = 0) and not G.IsWon, Format('%s: tap after a win deals a new game', [Tag]));
              GoStep(ST_HINT);
            end;
        end;

      ST_HINT:
        if FSub = 0 then
        begin
          H := G.Hint;
          Check(FForm.DoHint = (H.Kind <> hkNone), Format('%s: Hint button agrees with the game', [Tag]));
          if H.Kind <> hkNone then
            Check(B.HintActive, Format('%s: hint highlight is showing', [Tag]));
          FSub := 1;
          FStepWatch := TStopwatch.StartNew;
        end
        else if StepSecs > 0.35 then
        begin
          Shot(Format('%d-%s-4-hint', [FG + 1, G.GameId]));
          GoStep(ST_HELP);
        end;

      ST_HELP:
        if FSub = 0 then
        begin
          FForm.ShowPanel(pnHelp);
          Check(FForm.Panel = pnHelp, Format('%s: help opens', [Tag]));
          Check(FForm.HelpItemCount > 12, Format('%s: help has rules text (%d blocks)', [Tag, FForm.HelpItemCount]));
          Check(Pos('# Goal', G.Rules) = 1, Format('%s: rules start with the goal', [Tag]));
          FSub := 1;
          FStepWatch := TStopwatch.StartNew;
        end
        else if StepSecs > 0.4 then
        begin
          ShotControl(FForm.PanelControl(pnHelp), Format('%d-%s-5-help', [FG + 1, G.GameId]));
          FForm.ShowPanel(pnNone);
          Check(FForm.Panel = pnNone, Format('%s: help closes', [Tag]));
          GoStep(ST_SIZES);
        end;

      ST_SIZES: // rotation / window shapes
        begin
          I := FSub div 2;
          if I > High(SIZES) then
            GoStep(ST_NEXT)
          else if not Odd(FSub) then
          begin
            FForm.ClientWidth := SIZES[I].W;
            FForm.ClientHeight := SIZES[I].H;
            Inc(FSub);
            FStepWatch := TStopwatch.StartNew;
          end
          else if StepSecs > 0.45 then
          begin
            Msg := '';
            Check(B.CheckLayout(Msg), Format('%s %s: all cards on the board, no piles collide %s',
              [Tag, SIZES[I].Name, Msg]));
            Check(B.CardWidth >= 24, Format('%s %s: cards are a usable size (%.0f)',
              [Tag, SIZES[I].Name, B.CardWidth]));
            Check(FForm.CheckTextFits(Msg), Format('%s %s: no button or label text is cut off %s',
              [Tag, SIZES[I].Name, Msg]));
            if I < 2 then
              Shot(Format('%d-%s-6-%s', [FG + 1, G.GameId, SIZES[I].Name]));
            Inc(FSub);
          end;
        end;

      ST_NEXT:
        begin
          Inc(FG);
          if FG <= High(GAME_CLASSES) then
            GoStep(ST_START)
          else
            GoStep(ST_SWITCH);
        end;

      ST_SWITCH: // each game keeps its own unfinished deal and its own statistics
        case FSub of
          0:
            begin
              H := G.Hint;
              if H.Kind <> hkNone then
                DoHintMove(H);
              FSub := 1;
            end;
          1:
            if not (B.Animating or B.AutoCompleting or B.WinActive) then
            begin
              FKeepMoves := G.Moves;
              FKeepHash := G.LayoutHash;
              I := FForm.GameIndex;
              FForm.SwitchGame(0);
              Check(FForm.Game.GameId = 'klondike', 'switched away to Klondike');
              FForm.SwitchGame(I);
              Check((FForm.Game.Moves = FKeepMoves) and (FForm.Game.LayoutHash = FKeepHash),
                'coming back to a game restores its unfinished deal');
              for I := 0 to High(GAME_CLASSES) do
                Check(FForm.Stats.Get(GAME_CLASSES[I].GameId, 0).Played >= 1,
                  Format('%s has its own statistics', [GAME_CLASSES[I].Title]));
              Check(FForm.Stats.Get('klondike', 1).Played = 0, 'Klondike Draw 3 statistics are separate from Draw 1');
              FForm.SwitchGame(0);
              GoStep(ST_EFFECTS);
            end;
        end;

      ST_EFFECTS: // preview the other win effects
        begin
          I := FSub div 2;
          if I > High(PREVIEW) then
            GoStep(ST_RANDOM)
          else if not Odd(FSub) then
          begin
            E := PREVIEW[I];
            B.WinEffect := E;
            FKeepMoves := G.Moves;
            FFrames0 := B.FrameCount;
            B.PreviewWin;
            Check(B.WinActive and (B.ActiveEffect = E), 'preview starts: ' + WIN_EFFECT_NAMES[E]);
            Inc(FSub);
            FStepWatch := TStopwatch.StartNew;
          end
          else if StepSecs > 2.5 then
          begin
            E := PREVIEW[I];
            Check(B.EffectObjectCount > 3, Format('%s has moving objects (%d)', [WIN_EFFECT_NAMES[E], B.EffectObjectCount]));
            Check(B.FrameCount - FFrames0 > 50, Format('%s is animating (%d frames)', [WIN_EFFECT_NAMES[E], B.FrameCount - FFrames0]));
            Shot(Format('7-effect-%d', [Ord(E)]));
            B.SimulateTap(0, -1);
            Check(not B.WinActive, 'tap closes the preview');
            Check((G.Moves = FKeepMoves) and G.CheckIntegrity(Msg), 'preview leaves the game untouched');
            Inc(FSub);
          end;
        end;

      ST_RANDOM: // "Random" never repeats the same effect twice in a row
        begin
          B.WinEffect := weRandom;
          for I := 0 to 2 do
          begin
            B.PreviewWin;
            Seen[I] := B.ActiveEffect;
            B.Reset;
          end;
          Check((Seen[0] <> Seen[1]) and (Seen[1] <> Seen[2]), 'random win effect changes from win to win');
          Check(not B.WinActive, 'board reset stops the effect');
          // a bounce preview in a game without foundations (cards pour from the top edge)
          FForm.SwitchGame(GameIndexOf('tripeaks'));
          FForm.Board.WinEffect := weBounce;
          FForm.Board.PreviewWin;
          GoStep(ST_PANELS);
        end;

      ST_PANELS:
        case FSub of
          0:
            if StepSecs > 2.5 then
            begin
              Check(B.EffectObjectCount >= 1, 'bounce effect also runs in a game without foundations');
              Shot('7-effect-bounce-tripeaks');
              B.Reset;
              FForm.SwitchGame(GameIndexOf('spider'));   // three statistics columns
              FForm.ShowPanel(pnMenu);
              FSub := 1;
              FStepWatch := TStopwatch.StartNew;
            end;
          1, 2, 3:
            if StepSecs > 0.4 then
            begin
              Check(Ord(FForm.Panel) = FSub, Format('%s panel is showing', [PANEL_NAMES[TPanelKind(FSub)]]));
              ShotControl(FForm.PanelControl(TPanelKind(FSub)), '8-panel-' + PANEL_NAMES[TPanelKind(FSub)]);
              case FSub of
                1: FForm.ShowPanel(pnGames);
                2: FForm.ShowPanel(pnOptions);
                3: FForm.ShowPanel(pnNone);
              end;
              if FSub = 2 then
                FSub := 4   // help was already captured for every game
              else
                Inc(FSub);
              FStepWatch := TStopwatch.StartNew;
            end;
          4:
            if StepSecs > 0.4 then
            begin
              Check(FForm.Panel = pnOptions, 'options panel is showing');
              ShotControl(FForm.PanelControl(pnOptions), '8-panel-options');
              ShotControl(FForm.TopBar, '8-toolbar');
              FForm.ShowPanel(pnNone);
              Check(FForm.Panel = pnNone, 'panels close');
              GoStep(ST_FILES);
            end;
        end;

      ST_FILES:
        begin
          // both card faces, on a game that shows all 52 of them
          FForm.SwitchGame(GameIndexOf('freecell'));
          FForm.StartNewGame(1);
          B.CardStyle := csModern;
          Check(B.CheckLayout(Msg), 'modern card style: layout is valid ' + Msg);
          Shot('9-modern-freecell');
          FForm.SwitchGame(GameIndexOf('freecell'));
          FForm.StartNewGame(1);
          B.CardStyle := csClassic;
          Check(B.CheckLayout(Msg), 'classic card style: layout is valid ' + Msg);
          Shot('9-classic-freecell');
          ShotCourts;
          FForm.SwitchGame(GameIndexOf('spider'));
          Shot('9-classic-spider');
          FForm.ClientWidth := 390;
          FForm.ClientHeight := 800;
          FForm.SwitchGame(GameIndexOf('klondike'));
          Shot('9-classic-portrait');
          FForm.ClientWidth := 1000;
          FForm.ClientHeight := 720;
          FForm.SaveGame;
          for I := 0 to High(GAME_CLASSES) do
            Check(TFile.Exists(TPath.Combine(OutDir, 'game-' + GAME_CLASSES[I].GameId + '.dat')),
              Format('%s deal is saved to disk', [GAME_CLASSES[I].Title]));
          Check(TFile.Exists(TPath.Combine(OutDir, 'solitaire.ini')), 'statistics are saved to disk');
          GoStep(ST_END);
        end;
    else
      Finish;
    end;
  except
    on Ex: Exception do
    begin
      Check(False, Format('exception in step %d.%d: %s: %s', [FStep, FSub, Ex.ClassName, Ex.Message]));
      Finish;
    end;
  end;
end;

procedure TSelfTest.Finish;
begin
  if FDone then
    Exit;
  FDone := True;
  FTimer.Enabled := False;
  Log(Format('%d checks, %d failed', [FChecks, FFails]));
  if FFails = 0 then
    Log('RESULT: PASS')
  else
    Log('RESULT: FAIL');
  try
    FLog.SaveToFile(TPath.Combine(OutDir, 'selftest.log'));
  except
  end;
  if FFails = 0 then
    ExitCode := 0
  else
    ExitCode := 1;
  Application.Terminate;
end;

end.
