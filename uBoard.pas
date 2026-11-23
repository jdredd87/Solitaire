unit uBoard;

{ The playing surface for every game. It asks the game where its piles sit,
  draws the cards with vector graphics (no image assets), turns taps and drags
  into game moves, animates whatever cards a move displaced, and runs the hint
  highlight and the win effects. }

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,
  System.Math.Vectors, System.Diagnostics, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Graphics, uCardGame;

type
  TWinEffect = (weRandom, weBounce, weFireworks, weFountain);
  /// csModern: rank and suit side by side along the top, one large suit below.
  /// csClassic: rank over suit in opposite corners and the traditional pips.
  TCardStyle = (csModern, csClassic);
  /// Moments in a win effect that have a sound of their own.
  TBoardSound = (bsWin, bsBounce, bsBurst, bsLaunch);
  TBoardSoundEvent = procedure(Sender: TObject; Sound: TBoardSound) of object;

const
  WIN_EFFECT_NAMES: array[TWinEffect] of string =
    ('Random', 'Bouncing cards', 'Fireworks', 'Card fountain');
  CARD_STYLE_NAMES: array[TCardStyle] of string = ('Modern', 'Classic');
  MAX_CARDS = 256;

type
  TParticle = record
    Pos, Vel: TPointF;
    Life, MaxLife, Size: Single;
    Color: TAlphaColor;
    Suit: TSuit;
  end;

  TFountainCard = record
    Card: TCard;
    Pos, Vel: TPointF;
    Delay: Single;     // > 0: waiting to launch
    Flying: Boolean;
  end;

  TSolitaireBoard = class(TControl)
  private
    FGame: TCardGame;
    FOnChanged: TNotifyEvent;
    FOnNewGameRequest: TNotifyEvent;
    FOnSound: TBoardSoundEvent;
    // layout
    FCardW, FCardH, FGap, FLeft, FTop: Single;
    FWide: Boolean;
    FSuitPaths: array[TSuit] of TPathData;
    FTmpPath: TPathData;
    // input
    FPressed, FDragging, FCanDrag: Boolean;
    FDragPile, FDragIndex: Integer;
    FDownPos, FDragOffset, FDragPos: TPointF;
    // move animation: cards (by id) gliding from where they were
    FTimer: TTimer;
    FWatch: TStopwatch;
    FAnimActive: Boolean;
    FDealing: Boolean;          // the animation in progress is a fresh deal
    FDealAnimation: Boolean;
    FAnimTime, FAnimDur, FAnimEnd: Single;
    FFlying: array[0..MAX_CARDS - 1] of Boolean;
    FFlyFrom: array[0..MAX_CARDS - 1] of TPointF;
    FFlyDelay: array[0..MAX_CARDS - 1] of Single;
    FAutoCompleting: Boolean;
    FFrameCount: Integer;
    // hint
    FHint: THint;
    FHintTime: Single;
    // win effects
    FWinEffect: TWinEffect;
    FCardStyle: TCardStyle;
    FEffect, FLastEffect: TWinEffect;
    FWinActive, FWinPreview: Boolean;
    FWinTime: Single;
    FTrail: TBitmap;
    FTrailScale: Single;
    FBounceLaunched, FBounceNext: Integer;
    FBounceLive, FBounceDone: Boolean;
    FBounceCard: TCard;
    FBouncePos, FBounceVel: TPointF;
    FBounceList: TArray<TPoint>;                       // (pile, index) in launch order
    FBounceGone: array[0..MAX_CARDS - 1] of Boolean;   // cards that have already left
    FParticles: TList<TParticle>;
    FNextBurst: Single;
    FFly: TArray<TFountainCard>;

    procedure SetGame(const Value: TCardGame);
    procedure BuildSuitPaths;
    procedure UpdateLayout;
    function PilePos(P: Integer): TPointF;
    procedure TableauSteps(P: Integer; BaseY: Single; out DownStep, UpStep: Single);
    function CardPos(P, Index: Integer): TPointF;
    function CardRect(const Pos: TPointF): TRectF;
    function HitCard(const Pt: TPointF; out Pile, Index: Integer): Boolean;
    function FindDropPile: Integer;
    function IsFlying(const C: TCard): Boolean;

    procedure Sound(S: TBoardSound);
    procedure SetDealAnimation(const Value: Boolean);
    procedure DrawSuit(C: TCanvas; Suit: TSuit; const R: TRectF; Color: TAlphaColor; Opacity: Single);
    procedure DrawCard(C: TCanvas; const ACard: TCard; const Pos: TPointF; Strip: Single = 0);
    procedure DrawClassicFace(C: TCanvas; const ACard: TCard; const R: TRectF; Col: TAlphaColor; Strip: Single);
    procedure SetCardStyle(const Value: TCardStyle);
    procedure DrawSlot(C: TCanvas; P: Integer);
    procedure DrawPile(C: TCanvas; P: Integer);
    procedure DrawOutline(C: TCanvas; const R: TRectF; Color: TAlphaColor; Opacity: Single);
    procedure PaintBoard(C: TCanvas);
    procedure PaintHighlights(C: TCanvas);
    procedure PaintBanner(C: TCanvas);
    procedure PaintStuck(C: TCanvas);
    procedure DrawFitted(C: TCanvas; const R: TRectF; const S: string; Size: Single;
      Bold: Boolean; Opacity: Single);

    procedure StartTimer;
    procedure TimerTick(Sender: TObject);
    procedure FinishAnim;
    function Perform(const Action: TFunc<Boolean>; Duration: Single; FromDrag: Boolean): Boolean;
    procedure AfterMove;
    procedure DoChanged;

    function SceneScale: Single;
    procedure StartWin(Preview: Boolean);
    procedure StopWin;
    procedure InitBounce;
    procedure BounceStep(C: TCanvas);
    procedure StepFireworks(Dt: Single);
    procedure LaunchFly(var F: TFountainCard);
    procedure InitFountain;
    procedure StepFountain(Dt: Single);
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Single); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// Cancel drags, animations and effects (after new deal / undo / game switch).
    procedure Reset;
    /// True while input such as Undo should be ignored.
    function Busy: Boolean;
    procedure PreviewWin;
    /// Highlights the game's suggested move for a moment. False = nothing to suggest.
    function ShowHint: Boolean;

    { Hooks used by the automated self-test (uSelfTest); they drive the same
      MouseDown/MouseMove/MouseUp code paths as a real finger or mouse. }
    function CardCenter(P, Index: Integer): TPointF;
    procedure SimulateTap(P, Index: Integer);
    procedure SimulateDrag(Src, Index, Dst: Integer);
    procedure SimulateDragTo(Src, Index: Integer; const Target: TPointF);
    /// Where a card dragged onto pile Dst should be let go.
    function DropCenter(Dst: Integer): TPointF;
    /// One pointer event at a board position: 0 = press, 1 = move, 2 = release.
    procedure SimulatePointer(Phase: Integer; const Pt: TPointF);
    /// Particles / flying cards / bounced cards currently alive in the win effect.
    function EffectObjectCount: Integer;
    /// True when every card is on the board and no two piles collide.
    function CheckLayout(out Msg: string): Boolean;
    property IsWide: Boolean read FWide;
    property CardWidth: Single read FCardW;
    property Animating: Boolean read FAnimActive;
    property AutoCompleting: Boolean read FAutoCompleting;
    property WinActive: Boolean read FWinActive;
    function HintActive: Boolean;
    /// The move currently (or last) highlighted by ShowHint.
    property CurrentHint: THint read FHint;
    property ActiveEffect: TWinEffect read FEffect;
    property FrameCount: Integer read FFrameCount;
    property TrailBitmap: TBitmap read FTrail;

    property Game: TCardGame read FGame write SetGame;
    property WinEffect: TWinEffect read FWinEffect write FWinEffect;
    property CardStyle: TCardStyle read FCardStyle write SetCardStyle;
    /// The given cards side by side, enlarged; for looking closely at the faces.
    function SampleCards(const Cards: array of TCard; Zoom: Single): TBitmap;
    property OnChanged: TNotifyEvent read FOnChanged write FOnChanged;
    property OnNewGameRequest: TNotifyEvent read FOnNewGameRequest write FOnNewGameRequest;
    property OnSound: TBoardSoundEvent read FOnSound write FOnSound;
    /// Lays a fresh deal out card by card. Call right after the game was dealt.
    procedure AnimateDeal;
    /// False makes AnimateDeal do nothing (and ends a deal that is under way).
    property DealAnimation: Boolean read FDealAnimation write SetDealAnimation;
  end;

implementation

const
  COL_FELT   = $FF1B6B3A;
  COL_FACE   = $FFFDFDF8;
  COL_EDGE   = $FF7A7A7A;
  COL_RED    = $FFD12B2B;
  COL_BLACK  = $FF1E1E1E;
  COL_BACK   = $FF1F4E9E;
  COL_BACK2  = $FF2C66C4;
  COL_SELECT = $FFFFD54F;
  COL_HINT   = $FF40C4FF;
  HINT_SECONDS = 2.2;
  SPARK_COLORS: array[0..5] of TAlphaColor =
    ($FFFFD54F, $FFFF5252, $FF40C4FF, $FF69F0AE, $FFFF80AB, $FFFFFFFF);

{ TSolitaireBoard }

constructor TSolitaireBoard.Create(AOwner: TComponent);
begin
  inherited;
  HitTest := True;
  AutoCapture := True;
  ClipChildren := True;
  FTmpPath := TPathData.Create;
  FParticles := TList<TParticle>.Create;
  BuildSuitPaths;
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := 16;
  FTimer.OnTimer := TimerTick;
  FDragPile := -1;
  FLastEffect := weRandom;
  FDealAnimation := True;
  FCardW := 60;
  FCardH := 84;
end;

destructor TSolitaireBoard.Destroy;
var
  S: TSuit;
begin
  FTimer.Enabled := False;
  FTrail.Free;
  FParticles.Free;
  FTmpPath.Free;
  for S := Low(TSuit) to High(TSuit) do
    FSuitPaths[S].Free;
  inherited;
end;

procedure TSolitaireBoard.SetGame(const Value: TCardGame);
begin
  if FGame = Value then
    Exit;
  FGame := nil;      // Reset must not touch the old game
  Reset;
  FGame := Value;
  if FGame <> nil then
    UpdateLayout;
  Repaint;
end;

procedure TSolitaireBoard.BuildSuitPaths;
var
  P: TPathData;
begin
  // All paths live in a 0..1 box and are scaled when drawn.
  P := TPathData.Create;
  P.MoveTo(PointF(0.5, 0.95));
  P.CurveTo(PointF(0.10, 0.65), PointF(0.0, 0.42), PointF(0.0, 0.28));
  P.CurveTo(PointF(0.0, 0.10), PointF(0.13, 0.02), PointF(0.26, 0.02));
  P.CurveTo(PointF(0.38, 0.02), PointF(0.46, 0.10), PointF(0.5, 0.20));
  P.CurveTo(PointF(0.54, 0.10), PointF(0.62, 0.02), PointF(0.74, 0.02));
  P.CurveTo(PointF(0.87, 0.02), PointF(1.0, 0.10), PointF(1.0, 0.28));
  P.CurveTo(PointF(1.0, 0.42), PointF(0.90, 0.65), PointF(0.5, 0.95));
  P.ClosePath;
  FSuitPaths[suHearts] := P;

  P := TPathData.Create;
  P.MoveTo(PointF(0.5, 0.0));
  P.LineTo(PointF(0.90, 0.5));
  P.LineTo(PointF(0.5, 1.0));
  P.LineTo(PointF(0.10, 0.5));
  P.ClosePath;
  FSuitPaths[suDiamonds] := P;

  P := TPathData.Create;
  P.MoveTo(PointF(0.5, 0.02));
  P.CurveTo(PointF(0.90, 0.32), PointF(1.0, 0.50), PointF(1.0, 0.62));
  P.CurveTo(PointF(1.0, 0.76), PointF(0.90, 0.84), PointF(0.78, 0.84));
  P.CurveTo(PointF(0.68, 0.84), PointF(0.60, 0.80), PointF(0.55, 0.72));
  P.CurveTo(PointF(0.56, 0.85), PointF(0.60, 0.93), PointF(0.68, 0.98));
  P.LineTo(PointF(0.32, 0.98));
  P.CurveTo(PointF(0.40, 0.93), PointF(0.44, 0.85), PointF(0.45, 0.72));
  P.CurveTo(PointF(0.40, 0.80), PointF(0.32, 0.84), PointF(0.22, 0.84));
  P.CurveTo(PointF(0.10, 0.84), PointF(0.0, 0.76), PointF(0.0, 0.62));
  P.CurveTo(PointF(0.0, 0.50), PointF(0.10, 0.32), PointF(0.5, 0.02));
  P.ClosePath;
  FSuitPaths[suSpades] := P;

  // Club: only the stem is a path; the three lobes are drawn as ellipses.
  P := TPathData.Create;
  P.MoveTo(PointF(0.46, 0.50));
  P.CurveTo(PointF(0.46, 0.80), PointF(0.40, 0.92), PointF(0.32, 0.98));
  P.LineTo(PointF(0.68, 0.98));
  P.CurveTo(PointF(0.60, 0.92), PointF(0.54, 0.80), PointF(0.54, 0.50));
  P.ClosePath;
  FSuitPaths[suClubs] := P;
end;

{ ---------- layout ---------- }

procedure TSolitaireBoard.UpdateLayout;
var
  Cols, Rows, WCols, WRows, Classic, WideW: Single;
begin
  if FGame = nil then
    Exit;
  // A table of Cols card columns (with gaps of 0.12 card) and Rows card heights.
  FGame.GetLayout(False, Cols, Rows);
  Classic := Min(Width / (Cols + (Cols + 1) * 0.12), (Height / Rows) / 1.4);
  FWide := False;
  FCardW := Classic;
  if FGame.HasWideLayout then
  begin
    // the sideways arrangement is used whenever it gives bigger cards
    FGame.GetLayout(True, WCols, WRows);
    WideW := Min(Width / (WCols + (WCols + 1) * 0.12), (Height / WRows) / 1.4);
    if WideW * FGame.WideBias > Classic then
    begin
      FWide := True;
      FCardW := WideW;
      Cols := WCols;
    end;
  end;
  FCardW := Max(FCardW, 12);
  FCardH := FCardW * 1.4;
  FGap := FCardW * 0.12;
  FTop := FGap;
  FLeft := (Width - (Cols * FCardW + (Cols - 1) * FGap)) / 2;
end;

function TSolitaireBoard.PilePos(P: Integer): TPointF;
var
  S: TPileSlot;
begin
  S := FGame.PileSlot(P, FWide);
  Result.X := FLeft + S.X * (FCardW + FGap);
  Result.Y := FTop + S.Y * FCardH;
end;

procedure TSolitaireBoard.TableauSteps(P: Integer; BaseY: Single; out DownStep, UpStep: Single);
var
  I, N: Integer;
  Total, Avail, K: Single;
begin
  DownStep := FCardH * 0.13;
  UpStep := FCardH * 0.27;
  N := FGame.CardCount(P);
  Total := 0;
  for I := 0 to N - 2 do
    if FGame.CardAt(P, I).FaceUp then
      Total := Total + UpStep
    else
      Total := Total + DownStep;
  Avail := Height - BaseY - FCardH - FGap;
  if (Total > Avail) and (Total > 0) then
  begin
    // squeeze a long column so it still fits on the screen
    K := Max(Avail / Total, 0.25);
    DownStep := DownStep * K;
    UpStep := UpStep * K;
  end;
end;

function TSolitaireBoard.CardPos(P, Index: Integer): TPointF;
var
  S: TPileSlot;
  I, N, Lim, J: Integer;
  DownStep, UpStep: Single;
begin
  S := FGame.PileSlot(P, FWide);
  Result := PilePos(P);
  if S.Fan = fnNone then
    Exit;
  N := FGame.CardCount(P);
  Lim := FGame.FanLimit(P);
  J := Index;
  if Lim > 0 then
    J := Max(0, Index - (N - Min(N, Lim)));   // only the top few are spread out
  if S.Fan = fnRight then
    Result.X := Result.X + J * FCardW * 0.3
  else if Lim > 0 then
    Result.Y := Result.Y + J * FCardH * 0.22
  else
  begin
    TableauSteps(P, Result.Y, DownStep, UpStep);
    for I := 0 to Min(Index, N) - 1 do
      if FGame.CardAt(P, I).FaceUp then
        Result.Y := Result.Y + UpStep
      else
        Result.Y := Result.Y + DownStep;
  end;
end;

function TSolitaireBoard.CardRect(const Pos: TPointF): TRectF;
begin
  Result := RectF(Pos.X, Pos.Y, Pos.X + FCardW, Pos.Y + FCardH);
end;

function TSolitaireBoard.HitCard(const Pt: TPointF; out Pile, Index: Integer): Boolean;
var
  P, I, N, First: Integer;
  S: TPileSlot;
begin
  Result := False;
  Pile := -1;
  Index := -1;
  // later piles are drawn over earlier ones, so look at them first
  for P := FGame.PileCount - 1 downto 0 do
  begin
    N := FGame.CardCount(P);
    if N = 0 then
    begin
      if (FGame.ShowEmptySlot(P, FWide) or (FGame.PileKind(P) = pkStock)) and
        CardRect(PilePos(P)).Contains(Pt) then
      begin
        Pile := P;
        Exit(True);
      end;
      Continue;
    end;
    S := FGame.PileSlot(P, FWide);
    First := N - 1;
    if S.Fan <> fnNone then
    begin
      First := 0;
      if FGame.FanLimit(P) > 0 then
        First := N - 1;   // in a waste fan only the top card counts
    end;
    for I := N - 1 downto First do
      if CardRect(CardPos(P, I)).Contains(Pt) then
      begin
        Pile := P;
        Index := I;
        Exit(True);
      end;
  end;
end;

function TSolitaireBoard.FindDropPile: Integer;
var
  P, N: Integer;
  DragR, R, X: TRectF;
  Area, Best: Single;
begin
  Result := -1;
  Best := 0;
  DragR := CardRect(FDragPos);
  for P := 0 to FGame.PileCount - 1 do
  begin
    if (P = FDragPile) or not FGame.CanDrop(FDragPile, FDragIndex, P) then
      Continue;
    N := FGame.CardCount(P);
    if N > 0 then
      R := CardRect(CardPos(P, N - 1))
    else
      R := CardRect(PilePos(P));
    if FGame.PileKind(P) = pkTableau then
    begin
      R.Top := PilePos(P).Y;
      R.Bottom := Height;   // the whole column is a target
    end;
    X := TRectF.Intersect(DragR, R);
    if (X.Width <= 0) or (X.Height <= 0) then
      Continue;
    Area := X.Width * X.Height;
    if Area > Best then
    begin
      Best := Area;
      Result := P;
    end;
  end;
end;

/// The card is not drawn in its pile: it is gliding, or has bounced away.
function TSolitaireBoard.IsFlying(const C: TCard): Boolean;
begin
  Result := (FAnimActive and FFlying[C.Id]) or
    (FWinActive and (FEffect = weBounce) and FBounceGone[C.Id]);
end;

{ ---------- drawing ---------- }

procedure TSolitaireBoard.DrawSuit(C: TCanvas; Suit: TSuit; const R: TRectF;
  Color: TAlphaColor; Opacity: Single);
var
  S: Single;

  procedure Lobe(CX, CY, Rad: Single);
  begin
    C.FillEllipse(RectF(R.Left + (CX - Rad) * S, R.Top + (CY - Rad) * S,
      R.Left + (CX + Rad) * S, R.Top + (CY + Rad) * S), Opacity);
  end;

begin
  S := R.Width;
  C.Fill.Kind := TBrushKind.Solid;
  C.Fill.Color := Color;
  if Suit = suClubs then
  begin
    Lobe(0.50, 0.25, 0.23);
    Lobe(0.24, 0.58, 0.23);
    Lobe(0.76, 0.58, 0.23);
    Lobe(0.50, 0.50, 0.13);
  end;
  FTmpPath.Assign(FSuitPaths[Suit]);
  FTmpPath.Scale(S, S);
  FTmpPath.Translate(R.Left, R.Top);
  C.FillPath(FTmpPath, Opacity);
end;

procedure TSolitaireBoard.SetCardStyle(const Value: TCardStyle);
begin
  if FCardStyle <> Value then
  begin
    FCardStyle := Value;
    Repaint;
  end;
end;

{ The traditional face: rank over suit in the top-left corner, the same again
  upside down in the bottom-right, and one pip per point in between. Strip is
  how much of the card the next one leaves showing (0 = all of it): when a long
  column is squeezed the suit moves up beside the rank so it can still be read. }
procedure TSolitaireBoard.DrawClassicFace(C: TCanvas; const ACard: TCard; const R: TRectF;
  Col: TAlphaColor; Strip: Single);
const
  XL = 0.37;
  XC = 0.50;
  XR = 0.63;
  Y1 = 0.22;     // top row; the bottom row mirrors it
  Y2 = 0.403;    // second of four rows
var
  Saved, Flip: TMatrix;
  Beside: Boolean;
  PipS: Single;
  T: TRectF;

  procedure Corner;
  var
    S: Single;
    B: TRectF;
  begin
    C.Fill.Color := Col;
    C.Font.Size := FCardH * 0.135;
    C.Font.Style := [TFontStyle.fsBold];
    B := RectF(R.Left - FCardW * 0.03, R.Top + FCardH * 0.008, R.Left + FCardW * 0.31, R.Top + FCardH * 0.15);
    C.FillText(B, RankName(ACard.Rank), False, 1, [], TTextAlign.Center, TTextAlign.Center);
    S := FCardW * 0.1275;
    if Beside then
      DrawSuit(C, ACard.Suit, RectF(R.Left + FCardW * 0.31, R.Top + FCardH * 0.08 - S / 2,
        R.Left + FCardW * 0.31 + S, R.Top + FCardH * 0.08 + S / 2), Col, 1)
    else
      DrawSuit(C, ACard.Suit, RectF(R.Left + FCardW * 0.14 - S / 2, R.Top + FCardH * 0.148,
        R.Left + FCardW * 0.14 + S / 2, R.Top + FCardH * 0.148 + S), Col, 1);
  end;

  // X, Y are fractions of the card; pips in the lower half stand on their heads
  procedure Pip(X, Y, Size: Single);
  var
    P: TPointF;
    Turned: Boolean;
  begin
    Turned := Y > 0.5;
    if Turned then
    begin
      C.SetMatrix(Flip);
      X := 1 - X;
      Y := 1 - Y;
    end;
    P := PointF(R.Left + X * FCardW, R.Top + Y * FCardH);
    DrawSuit(C, ACard.Suit, RectF(P.X - Size / 2, P.Y - Size / 2, P.X + Size / 2, P.Y + Size / 2), Col, 1);
    if Turned then
      C.SetMatrix(Saved);
  end;

  procedure Pair(Y: Single);
  begin
    Pip(XL, Y, PipS);
    Pip(XR, Y, PipS);
  end;

  { Court cards: a simple bust in a frame, drawn twice so it reads either way
    up. U runs across the frame, V from its top edge (0) to its middle (1). }
  procedure Court;
  const
    COL_SKIN = $FFF3D3B1;
    COL_GOLD = $FFE0A92E;
    COL_EYE  = $FF2A2320;
    COL_LIP  = $FFB23A3A;
    HAIR: array[11..13] of TAlphaColor = ($FF7A4A22, $FFB5722A, $FF5F5148);
  var
    PW, HH, HR: Single;
    HC: TPointF;

    function P(U, V: Single): TPointF;
    begin
      Result := PointF(T.Left + U * PW, T.Top + V * HH);
    end;

    procedure Poly(const A: array of Single; Color: TAlphaColor);
    var
      I: Integer;
    begin
      FTmpPath.Clear;
      FTmpPath.MoveTo(P(A[0], A[1]));
      I := 2;
      while I < High(A) do
      begin
        FTmpPath.LineTo(P(A[I], A[I + 1]));
        Inc(I, 2);
      end;
      FTmpPath.ClosePath;
      C.Fill.Color := Color;
      C.FillPath(FTmpPath, 1);
    end;

    // an ellipse about the middle of the head; offsets and radii in head radii
    procedure Oval(DX, DY, RX, RY: Single; Color: TAlphaColor);
    begin
      C.Fill.Color := Color;
      C.FillEllipse(RectF(HC.X + (DX - RX) * HR, HC.Y + (DY - RY) * HR,
        HC.X + (DX + RX) * HR, HC.Y + (DY + RY) * HR), 1);
    end;

    procedure Box(U1, V1, U2, V2, Round: Single; Color: TAlphaColor);
    begin
      C.Fill.Color := Color;
      C.FillRect(TRectF.Create(P(U1, V1), P(U2, V2)), Round * PW, Round * PW, AllCorners, 1);
    end;

    procedure Half;
    var
      E: Single;
    begin
      // hair behind the head
      case ACard.Rank of
        11: Box(0.29, 0.30, 0.71, 0.60, 0.08, HAIR[11]);
        12: Box(0.27, 0.30, 0.73, 0.82, 0.10, HAIR[12]);
        13: Oval(0, 0.25, 1.2, 1.35, HAIR[13]);
      end;
      Box(0.43, 0.50, 0.57, 0.72, 0, COL_SKIN);                                // neck
      Poly([0.04, 1, 0.08, 0.80, 0.30, 0.66, 0.70, 0.66, 0.92, 0.80, 0.96, 1], Col);   // robe
      Poly([0.36, 0.66, 0.50, 0.90, 0.64, 0.66, 0.56, 0.66, 0.50, 0.79, 0.44, 0.66], COL_GOLD);
      Box(0.04, 0.94, 0.96, 1, 0, COL_GOLD);                                   // sash
      Oval(0, 0, 1, 1, COL_SKIN);                                              // face
      if ACard.Rank = 13 then
        Oval(0, 0.68, 0.78, 0.46, HAIR[13])                                    // beard
      else
      begin
        Oval(0, -0.62, 1.02, 0.42, HAIR[ACard.Rank]);                          // fringe
        Oval(0, 0.52, 0.26, 0.09, COL_LIP);
      end;
      E := Max(0.11, 0.8 / HR);
      Oval(-0.38, 0.08, E, E, COL_EYE);
      Oval(0.38, 0.08, E, E, COL_EYE);
      case ACard.Rank of
        11:
          begin   // a cap with a feather
            Poly([0.30, 0.34, 0.33, 0.20, 0.67, 0.20, 0.70, 0.34], Col);
            Box(0.30, 0.30, 0.70, 0.35, 0, COL_GOLD);
            C.Stroke.Color := COL_GOLD;
            C.Stroke.Thickness := Max(1, PW * 0.05);
            C.DrawLine(P(0.64, 0.22), P(0.84, 0.05), 1);
            C.Stroke.Thickness := 1;
          end;
        12:
          begin   // a tiara
            Poly([0.36, 0.33, 0.36, 0.20, 0.43, 0.26, 0.50, 0.14, 0.57, 0.26, 0.64, 0.20, 0.64, 0.33], COL_GOLD);
            Oval(0, -1.02, 0.14, 0.14, Col);
          end;
        13:
          begin   // a crown
            Poly([0.31, 0.36, 0.31, 0.12, 0.405, 0.24, 0.50, 0.08, 0.595, 0.24, 0.69, 0.12, 0.69, 0.36], COL_GOLD);
            Oval(0, -0.98, 0.16, 0.16, Col);
            Oval(-0.62, -0.98, 0.11, 0.11, Col);
            Oval(0.62, -0.98, 0.11, 0.11, Col);
          end;
      end;
    end;

  begin
    T := RectF(R.Left + FCardW * 0.27, R.Top + FCardH * 0.13, R.Right - FCardW * 0.27, R.Bottom - FCardH * 0.13);
    PW := T.Width;
    HH := T.Height / 2;
    HR := PW * 0.17;
    HC := P(0.5, 0.46);
    C.Fill.Color := Col;
    C.FillRect(T, FCardW * 0.04, FCardW * 0.04, AllCorners, 0.09);
    Half;
    C.SetMatrix(Flip);
    Half;
    C.SetMatrix(Saved);
    C.Stroke.Color := Col;
    C.Stroke.Thickness := Max(1, FCardW * 0.015);
    C.DrawRect(T, FCardW * 0.04, FCardW * 0.04, AllCorners, 0.8);
    C.Stroke.Thickness := 1;
    Pip(0.345, 0.19, FCardW * 0.11);
    Pip(0.655, 0.81, FCardW * 0.11);
  end;

begin
  Saved := C.Matrix;
  // a half turn about the middle of the card
  Flip := TMatrix.CreateScaling(-1, -1) * TMatrix.CreateTranslation(R.Left + R.Right, R.Top + R.Bottom) * Saved;
  Beside := (Strip > 0) and (Strip < FCardH * 0.25);
  PipS := FCardW * 0.18;

  Corner;
  C.SetMatrix(Flip);
  Corner;
  C.SetMatrix(Saved);

  case ACard.Rank of
    1:
      Pip(XC, 0.5, FCardW * 0.42);
    2, 3:
      begin
        Pip(XC, Y1, PipS);
        Pip(XC, 1 - Y1, PipS);
        if ACard.Rank = 3 then
          Pip(XC, 0.5, PipS);
      end;
    4, 5:
      begin
        Pair(Y1);
        Pair(1 - Y1);
        if ACard.Rank = 5 then
          Pip(XC, 0.5, PipS);
      end;
    6, 7, 8:
      begin
        Pair(Y1);
        Pair(0.5);
        Pair(1 - Y1);
        if ACard.Rank >= 7 then
          Pip(XC, 0.355, PipS);
        if ACard.Rank = 8 then
          Pip(XC, 0.645, PipS);
      end;
    9, 10:
      begin
        Pair(Y1);
        Pair(Y2);
        Pair(1 - Y2);
        Pair(1 - Y1);
        if ACard.Rank = 9 then
          Pip(XC, 0.5, PipS)
        else
        begin
          Pip(XC, 0.305, PipS);
          Pip(XC, 0.695, PipS);
        end;
      end;
  else
    Court;
  end;
end;

function TSolitaireBoard.SampleCards(const Cards: array of TCard; Zoom: Single): TBitmap;
var
  I: Integer;
  Gap: Single;
begin
  Gap := FCardW * 0.12;
  Result := TBitmap.Create(Ceil((Length(Cards) * (FCardW + Gap) + Gap) * Zoom), Ceil((FCardH + 2 * Gap) * Zoom));
  if Result.Canvas.BeginScene then
    try
      Result.Canvas.Clear(COL_FELT);
      Result.Canvas.SetMatrix(TMatrix.CreateScaling(Zoom, Zoom));
      for I := 0 to High(Cards) do
        DrawCard(Result.Canvas, Cards[I], PointF(Gap + I * (FCardW + Gap), Gap));
    finally
      Result.Canvas.EndScene;
    end;
end;

procedure TSolitaireBoard.DrawCard(C: TCanvas; const ACard: TCard; const Pos: TPointF; Strip: Single);
var
  R, T: TRectF;
  Rad, S: Single;
  Col: TAlphaColor;
begin
  R := CardRect(Pos);
  Rad := FCardW * 0.08;
  C.Stroke.Kind := TBrushKind.Solid;
  C.Stroke.Thickness := 1;
  C.Fill.Kind := TBrushKind.Solid;
  if not ACard.FaceUp then
  begin
    C.Fill.Color := COL_FACE;
    C.FillRect(R, Rad, Rad, AllCorners, 1);
    T := R;
    T.Inflate(-FCardW * 0.06, -FCardW * 0.06);
    C.Fill.Color := COL_BACK;
    C.FillRect(T, Rad * 0.6, Rad * 0.6, AllCorners, 1);
    T.Inflate(-FCardW * 0.08, -FCardW * 0.08);
    C.Stroke.Color := COL_BACK2;
    C.Stroke.Thickness := Max(1, FCardW * 0.035);
    C.DrawRect(T, Rad * 0.4, Rad * 0.4, AllCorners, 1);
    S := FCardW * 0.34;
    DrawSuit(C, suSpades, RectF(R.CenterPoint.X - S / 2, R.CenterPoint.Y - S / 2,
      R.CenterPoint.X + S / 2, R.CenterPoint.Y + S / 2), COL_BACK2, 1);
    C.Stroke.Thickness := 1;
    C.Stroke.Color := COL_EDGE;
    C.DrawRect(R, Rad, Rad, AllCorners, 1);
    Exit;
  end;

  C.Fill.Color := COL_FACE;
  C.FillRect(R, Rad, Rad, AllCorners, 1);
  C.Stroke.Color := COL_EDGE;
  C.DrawRect(R, Rad, Rad, AllCorners, 1);

  if ACard.IsRed then
    Col := COL_RED
  else
    Col := COL_BLACK;

  if FCardStyle = csClassic then
  begin
    DrawClassicFace(C, ACard, R, Col, Strip);
    Exit;
  end;

  // rank, top-left
  C.Fill.Color := Col;
  C.Font.Size := FCardH * 0.19;
  C.Font.Style := [TFontStyle.fsBold];
  T := RectF(R.Left + FCardW * 0.07, R.Top + FCardH * 0.015,
    R.Left + FCardW * 0.66, R.Top + FCardH * 0.25);
  C.FillText(T, RankName(ACard.Rank), False, 1, [], TTextAlign.Leading, TTextAlign.Center);

  // small suit, top-right
  S := FCardW * 0.27;
  DrawSuit(C, ACard.Suit, RectF(R.Right - FCardW * 0.07 - S, R.Top + FCardH * 0.035,
    R.Right - FCardW * 0.07, R.Top + FCardH * 0.035 + S), Col, 1);

  // big suit, centre
  S := FCardW * 0.56;
  DrawSuit(C, ACard.Suit, RectF(R.CenterPoint.X - S / 2, R.Top + FCardH * 0.62 - S / 2,
    R.CenterPoint.X + S / 2, R.Top + FCardH * 0.62 + S / 2), Col, 1);
end;

procedure TSolitaireBoard.DrawSlot(C: TCanvas; P: Integer);
var
  R, T: TRectF;
  Rad, S: Single;
begin
  R := CardRect(PilePos(P));
  Rad := FCardW * 0.08;
  C.Fill.Kind := TBrushKind.Solid;
  C.Fill.Color := TAlphaColors.Black;
  C.FillRect(R, Rad, Rad, AllCorners, 0.18);
  C.Stroke.Kind := TBrushKind.Solid;
  C.Stroke.Color := TAlphaColors.White;
  C.Stroke.Thickness := 1;
  C.DrawRect(R, Rad, Rad, AllCorners, 0.25);
  case FGame.PileKind(P) of
    pkFoundation:
      if FGame.FoundationsBuildUp then
      begin
        C.Fill.Color := TAlphaColors.White;
        C.Font.Size := FCardH * 0.36;
        C.Font.Style := [TFontStyle.fsBold];
        C.FillText(R, 'A', False, 0.3, [], TTextAlign.Center, TTextAlign.Center);
      end;
    pkStock:
      begin
        // a ring: bright while the waste can still be turned over
        S := FCardW * 0.42;
        T := RectF(R.CenterPoint.X - S / 2, R.CenterPoint.Y - S / 2,
          R.CenterPoint.X + S / 2, R.CenterPoint.Y + S / 2);
        C.Stroke.Thickness := Max(1.5, FCardW * 0.05);
        if FGame.StockCanRecycle then
          C.DrawEllipse(T, 0.55)
        else
          C.DrawEllipse(T, 0.15);
        C.Stroke.Thickness := 1;
      end;
  end;
end;

procedure TSolitaireBoard.DrawPile(C: TCanvas; P: Integer);
var
  N, Limit, I, First, Lim: Integer;
  Strip: Single;
  S: TPileSlot;
  Card: TCard;
  Drawn: Boolean;
begin
  N := FGame.CardCount(P);
  Limit := N;
  if FDragging and (P = FDragPile) then
    Limit := Min(Limit, FDragIndex);
  S := FGame.PileSlot(P, FWide);
  Drawn := False;

  if S.Fan = fnNone then
  begin
    // a squared-up pile only shows its top card that is not in flight
    for I := Limit - 1 downto 0 do
    begin
      Card := FGame.CardAt(P, I);
      if not IsFlying(Card) then
      begin
        DrawCard(C, Card, PilePos(P));
        Drawn := True;
        Break;
      end;
    end;
  end
  else
  begin
    First := 0;
    Lim := FGame.FanLimit(P);
    if Lim > 0 then
      First := Max(0, N - Lim - 1);
    for I := First to Limit - 1 do
    begin
      Card := FGame.CardAt(P, I);
      if not IsFlying(Card) then
      begin
        // how much of this card the next one in a downward fan leaves showing
        Strip := 0;
        if (S.Fan = fnDown) and (I < Limit - 1) then
          Strip := CardPos(P, I + 1).Y - CardPos(P, I).Y;
        DrawCard(C, Card, CardPos(P, I), Strip);
        Drawn := True;
      end;
    end;
  end;

  if not Drawn and FGame.ShowEmptySlot(P, FWide) then
    DrawSlot(C, P);
end;

procedure TSolitaireBoard.DrawOutline(C: TCanvas; const R: TRectF; Color: TAlphaColor; Opacity: Single);
var
  T: TRectF;
  Rad: Single;
begin
  T := R;
  T.Inflate(1, 1);
  Rad := FCardW * 0.08;
  C.Stroke.Kind := TBrushKind.Solid;
  C.Stroke.Color := Color;
  C.Stroke.Thickness := Max(2.5, FCardW * 0.06);
  C.DrawRect(T, Rad, Rad, AllCorners, Opacity);
  C.Fill.Kind := TBrushKind.Solid;
  C.Fill.Color := Color;
  C.FillRect(T, Rad, Rad, AllCorners, Opacity * 0.18);
  C.Stroke.Thickness := 1;
end;

procedure TSolitaireBoard.PaintBoard(C: TCanvas);
var
  P, I, N: Integer;
  T, E: Single;
  Base, Target: TPointF;
  Card: TCard;
begin
  C.Fill.Kind := TBrushKind.Solid;
  C.Fill.Color := COL_FELT;
  C.FillRect(RectF(0, 0, Width, Height), 0, 0, AllCorners, 1);
  if FGame = nil then
    Exit;

  for P := 0 to FGame.PileCount - 1 do
    DrawPile(C, P);

  // cards in flight, on top of everything, in pile order
  if FAnimActive then
    for P := 0 to FGame.PileCount - 1 do
      for I := 0 to FGame.CardCount(P) - 1 do
      begin
        Card := FGame.CardAt(P, I);
        if not FFlying[Card.Id] then
          Continue;
        if FDealing and (FAnimTime < FFlyDelay[Card.Id]) then
          Continue;   // still in the dealer's hand
        T := EnsureRange((FAnimTime - FFlyDelay[Card.Id]) / FAnimDur, 0, 1);
        if FDealing and (T < 0.5) then
          Card.FaceUp := False;   // dealt face down, turned over on the way
        E := 1 - Sqr(1 - T);
        Target := CardPos(P, I);
        DrawCard(C, Card, PointF(FFlyFrom[Card.Id].X + (Target.X - FFlyFrom[Card.Id].X) * E,
          FFlyFrom[Card.Id].Y + (Target.Y - FFlyFrom[Card.Id].Y) * E));
      end;

  if FDragging then
  begin
    N := FGame.CardCount(FDragPile);
    Base := CardPos(FDragPile, FDragIndex);
    for I := FDragIndex to N - 1 do
      DrawCard(C, FGame.CardAt(FDragPile, I), FDragPos + (CardPos(FDragPile, I) - Base));
  end;
end;

procedure TSolitaireBoard.PaintHighlights(C: TCanvas);
var
  P, N: Integer;
  R: TRectF;
  A: Single;
begin
  if (FGame = nil) or FWinActive then
    Exit;
  // the card picked as the first half of a pair
  for P := 0 to FGame.PileCount - 1 do
  begin
    N := FGame.CardCount(P);
    if (N > 0) and FGame.IsSelected(P, N - 1) then
      DrawOutline(C, CardRect(CardPos(P, N - 1)), COL_SELECT, 1);
  end;

  if (FHintTime <= 0) or (FHint.Kind = hkNone) or (FHint.Src < 0) or (FHint.Src >= FGame.PileCount) then
    Exit;
  A := 0.55 + 0.45 * Abs(Sin(FHintTime * 5));   // gentle pulse
  N := FGame.CardCount(FHint.Src);
  if (N = 0) or (FHint.Index < 0) or (FHint.Index >= N) then
    R := CardRect(PilePos(FHint.Src))
  else
    R := TRectF.Union(CardRect(CardPos(FHint.Src, FHint.Index)), CardRect(CardPos(FHint.Src, N - 1)));
  DrawOutline(C, R, COL_HINT, A);
  if (FHint.Kind = hkMove) and (FHint.Dst >= 0) and (FHint.Dst < FGame.PileCount) then
  begin
    N := FGame.CardCount(FHint.Dst);
    if N > 0 then
      R := CardRect(CardPos(FHint.Dst, N - 1))
    else
      R := CardRect(PilePos(FHint.Dst));
    DrawOutline(C, R, COL_SELECT, A);
  end;
end;

{ Draws one centred line, shrinking the font until it fits the rectangle. }
procedure TSolitaireBoard.DrawFitted(C: TCanvas; const R: TRectF; const S: string;
  Size: Single; Bold: Boolean; Opacity: Single);
begin
  if S = '' then
    Exit;
  if Bold then
    C.Font.Style := [TFontStyle.fsBold]
  else
    C.Font.Style := [];
  Size := Min(Size, R.Height * 0.8);
  C.Font.Size := Size;
  // phones draw text a little wider than they measure it, hence the margin
  while (Size > 7) and (C.TextWidth(S) * 1.06 > R.Width) do
  begin
    Size := Size - 0.5;
    C.Font.Size := Size;
  end;
  C.FillText(R, S, False, Opacity, [], TTextAlign.Center, TTextAlign.Center);
end;

procedure TSolitaireBoard.PaintBanner(C: TCanvas);
var
  R, T: TRectF;
  W, H, Delay: Single;
  Title, Sub, Hint: string;
begin
  if FEffect = weBounce then
    Delay := 2.5
  else
    Delay := 0.8;
  if FWinTime < Delay then
    Exit;
  if FWinPreview then
  begin
    Title := 'Preview';
    Sub := WIN_EFFECT_NAMES[FEffect];
    Hint := 'Tap to close';
  end
  else
  begin
    Title := 'You win!';
    Sub := Format('Score %d   |   %s   |   %d moves',
      [FGame.Score, FormatGameTime(FGame.Seconds), FGame.Moves]);
    Hint := 'Tap to deal again';
  end;
  W := Min(Width - 24, 340);
  H := Min(Height - 12, 118);
  R := RectF((Width - W) / 2, Height * 0.45 - H / 2, (Width + W) / 2, Height * 0.45 + H / 2);
  C.Fill.Kind := TBrushKind.Solid;
  C.Fill.Color := TAlphaColors.Black;
  C.FillRect(R, 14, 14, AllCorners, 0.72);
  C.Fill.Color := TAlphaColors.White;
  T := RectF(R.Left + 10, R.Top + H * 0.06, R.Right - 10, R.Top + H * 0.46);
  DrawFitted(C, T, Title, 28, True, 1);
  T := RectF(R.Left + 10, R.Top + H * 0.46, R.Right - 10, R.Top + H * 0.70);
  DrawFitted(C, T, Sub, 14, False, 0.95);
  T := RectF(R.Left + 10, R.Top + H * 0.70, R.Right - 10, R.Top + H * 0.94);
  DrawFitted(C, T, Hint, 13, False, 0.8);
end;

procedure TSolitaireBoard.PaintStuck(C: TCanvas);
var
  R: TRectF;
  W: Single;
begin
  W := Min(Width - 16, 380);
  R := RectF((Width - W) / 2, Height - 44, (Width + W) / 2, Height - 6);
  C.Fill.Kind := TBrushKind.Solid;
  C.Fill.Color := TAlphaColors.Black;
  C.FillRect(R, 10, 10, AllCorners, 0.7);
  C.Fill.Color := TAlphaColors.White;
  R.Inflate(-8, -2);
  DrawFitted(C, R, 'No more moves. Tap New to deal again, or Undo.', 14, False, 1);
end;

procedure TSolitaireBoard.Paint;
var
  I: Integer;
  Pt: TParticle;
begin
  UpdateLayout;
  begin
    // the table (without any cards that have bounced away) is always the bottom layer
    PaintBoard(Canvas);
    PaintHighlights(Canvas);
    if FWinActive then
      case FEffect of
        weBounce:
          // the trails are a separate transparent layer on top, so a card
          // leaving its pile never cuts a hole through them
          if FTrail <> nil then
            Canvas.DrawBitmap(FTrail, RectF(0, 0, FTrail.Width, FTrail.Height),
              RectF(0, 0, Width, Height), 1, False);
        weFireworks:
          begin
            Canvas.Fill.Kind := TBrushKind.Solid;
            Canvas.Fill.Color := TAlphaColors.Black;
            Canvas.FillRect(RectF(0, 0, Width, Height), 0, 0, AllCorners,
              0.5 * Min(1, FWinTime * 2));
            for I := 0 to FParticles.Count - 1 do
            begin
              Pt := FParticles[I];
              DrawSuit(Canvas, Pt.Suit, RectF(Pt.Pos.X - Pt.Size / 2, Pt.Pos.Y - Pt.Size / 2,
                Pt.Pos.X + Pt.Size / 2, Pt.Pos.Y + Pt.Size / 2), Pt.Color,
                EnsureRange(Pt.Life / Pt.MaxLife * 1.6, 0, 1));
            end;
          end;
        weFountain:
          for I := 0 to High(FFly) do
            if FFly[I].Flying then
              DrawCard(Canvas, FFly[I].Card, FFly[I].Pos);
      end
    else if (FGame <> nil) and not (FAnimActive or FDragging) and FGame.IsStuck then
      PaintStuck(Canvas);
  end;
  if FWinActive then
    PaintBanner(Canvas);
end;

procedure TSolitaireBoard.Resize;
begin
  inherited;
  UpdateLayout;
  if FWinActive and (FEffect = weBounce) then
    InitBounce;   // the trail bitmap is tied to the control size
end;

{ ---------- animation ---------- }

procedure TSolitaireBoard.StartTimer;
begin
  if not FTimer.Enabled then
  begin
    FWatch := TStopwatch.StartNew;
    FTimer.Enabled := True;
  end;
end;

procedure TSolitaireBoard.DoChanged;
begin
  if Assigned(FOnChanged) then
    FOnChanged(Self);
end;

procedure TSolitaireBoard.FinishAnim;
begin
  FAnimActive := False;
  FDealing := False;
  FillChar(FFlying, SizeOf(FFlying), 0);
end;

procedure TSolitaireBoard.SetDealAnimation(const Value: Boolean);
begin
  FDealAnimation := Value;
  if not Value and FDealing then
  begin
    FinishAnim;
    Repaint;
  end;
end;

{ A new game: the cards fly out one after another, a row at a time as a dealer
  would, from the stock - or from below the table in a game that has none. }
procedure TSolitaireBoard.AnimateDeal;
var
  P, Depth, MaxDepth, N, Seq: Integer;
  From: TPointF;
  Step: Single;
  Card: TCard;
begin
  if (FGame = nil) or not FDealAnimation or (Width < 10) or (Height < 10) then
    Exit;
  FinishAnim;
  UpdateLayout;
  From := PointF(Width / 2 - FCardW / 2, Height + 4);
  for P := 0 to FGame.PileCount - 1 do
    if FGame.PileKind(P) = pkStock then
    begin
      From := PilePos(P);
      Break;
    end;
  N := 0;
  MaxDepth := 0;
  for P := 0 to FGame.PileCount - 1 do
    if FGame.PileKind(P) <> pkStock then
    begin
      Inc(N, FGame.CardCount(P));
      MaxDepth := Max(MaxDepth, FGame.CardCount(P));
    end;
  if N = 0 then
    Exit;
  Step := Min(0.03, 1.0 / N);   // however many cards, the deal takes about a second
  Seq := 0;
  for Depth := 0 to MaxDepth - 1 do
    for P := 0 to FGame.PileCount - 1 do
      if (FGame.PileKind(P) <> pkStock) and (FGame.CardCount(P) > Depth) then
      begin
        Card := FGame.CardAt(P, Depth);
        FFlying[Card.Id] := True;
        FFlyFrom[Card.Id] := From;
        FFlyDelay[Card.Id] := Seq * Step;
        Inc(Seq);
      end;
  FAnimTime := 0;
  FAnimDur := 0.24;
  FAnimEnd := FAnimDur + (Seq - 1) * Step;
  FAnimActive := True;
  FDealing := True;
  StartTimer;
  Repaint;
end;

{ Runs a game action and animates every card that ended up somewhere else,
  gliding it from where it was (or from the finger, after a drag). }
function TSolitaireBoard.Perform(const Action: TFunc<Boolean>; Duration: Single;
  FromDrag: Boolean): Boolean;
var
  OldPos: array[0..MAX_CARDS - 1] of TPointF;
  OldPile, OldIdx: array[0..MAX_CARDS - 1] of SmallInt;
  P, I, N, Moved, Dealt: Integer;
  Card: TCard;
  Base, NewPos: TPointF;
begin
  FinishAnim;
  UpdateLayout;
  for I := 0 to MAX_CARDS - 1 do
    OldPile[I] := -1;
  for P := 0 to FGame.PileCount - 1 do
    for I := 0 to FGame.CardCount(P) - 1 do
    begin
      Card := FGame.CardAt(P, I);
      OldPos[Card.Id] := CardPos(P, I);
      OldPile[Card.Id] := P;
      OldIdx[Card.Id] := I;
    end;
  if FromDrag then
  begin
    N := FGame.CardCount(FDragPile);
    Base := CardPos(FDragPile, FDragIndex);
    for I := FDragIndex to N - 1 do
      OldPos[FGame.CardAt(FDragPile, I).Id] := FDragPos + (CardPos(FDragPile, I) - Base);
  end;

  Result := Action();
  if not Result then
    Exit;

  FHintTime := 0;
  Moved := 0;
  Dealt := 0;
  FAnimEnd := Duration;
  for P := 0 to FGame.PileCount - 1 do
    for I := 0 to FGame.CardCount(P) - 1 do
    begin
      Card := FGame.CardAt(P, I);
      if (OldPile[Card.Id] < 0) or ((OldPile[Card.Id] = P) and (OldIdx[Card.Id] = I)) then
        Continue;
      NewPos := CardPos(P, I);
      if NewPos.Distance(OldPos[Card.Id]) < 1 then
        Continue;
      FFlying[Card.Id] := True;
      FFlyFrom[Card.Id] := OldPos[Card.Id];
      FFlyDelay[Card.Id] := 0;
      // cards dealt from the stock leave one after another
      if FGame.PileKind(OldPile[Card.Id]) = pkStock then
      begin
        FFlyDelay[Card.Id] := Min(Dealt, 12) * 0.03;
        Inc(Dealt);
      end;
      FAnimEnd := Max(FAnimEnd, Duration + FFlyDelay[Card.Id]);
      Inc(Moved);
    end;

  DoChanged;
  if Moved > 0 then
  begin
    FAnimTime := 0;
    FAnimDur := Max(Duration, 0.01);
    FAnimActive := True;
    StartTimer;
  end
  else
    AfterMove;
  Repaint;
end;

procedure TSolitaireBoard.AfterMove;
begin
  if FGame.IsWon then
  begin
    FAutoCompleting := False;
    StartWin(False);
  end
  else if FGame.CanAutoComplete then
  begin
    FAutoCompleting := True;
    if not Perform(
      function: Boolean
      begin
        Result := FGame.AutoStep;
      end, 0.09, False) then
      FAutoCompleting := False;
  end
  else
    FAutoCompleting := False;
end;

procedure TSolitaireBoard.TimerTick(Sender: TObject);
var
  Dt: Single;
  I: Integer;
begin
  Dt := FWatch.Elapsed.TotalSeconds;
  FWatch := TStopwatch.StartNew;
  Dt := EnsureRange(Dt, 0.001, 0.05);
  Inc(FFrameCount);

  if FAnimActive then
  begin
    FAnimTime := FAnimTime + Dt;
    if FAnimTime >= FAnimEnd then
    begin
      FinishAnim;
      AfterMove;
    end;
  end;

  if FHintTime > 0 then
    FHintTime := Max(0, FHintTime - Dt);

  if FWinActive then
  begin
    FWinTime := FWinTime + Dt;
    case FEffect of
      weBounce:
        if (FTrail <> nil) and not FBounceDone and FTrail.Canvas.BeginScene then
        try
          FTrail.Canvas.SetMatrix(TMatrix.CreateScaling(FTrailScale, FTrailScale));
          // fixed-size physics steps, so the speed does not depend on frame rate
          for I := 1 to EnsureRange(Round(Dt * 190), 1, 10) do
            BounceStep(FTrail.Canvas);
        finally
          FTrail.Canvas.EndScene;
        end;
      weFireworks:
        StepFireworks(Dt);
      weFountain:
        StepFountain(Dt);
    end;
  end;

  if not (FAnimActive or FWinActive or (FHintTime > 0)) then
    FTimer.Enabled := False;
  Repaint;
end;

function TSolitaireBoard.HintActive: Boolean;
begin
  Result := FHintTime > 0;
end;

function TSolitaireBoard.ShowHint: Boolean;
begin
  Result := False;
  if (FGame = nil) or Busy then
    Exit;
  FHint := FGame.Hint;
  Result := FHint.Kind <> hkNone;
  if Result then
  begin
    FHintTime := HINT_SECONDS;
    StartTimer;
  end
  else
    FHintTime := 0;
  Repaint;
end;

{ ---------- win effects ---------- }

function TSolitaireBoard.SceneScale: Single;
begin
  if Scene <> nil then
    Result := Scene.GetSceneScale
  else
    Result := 1;
  if Result <= 0 then
    Result := 1;
end;

procedure TSolitaireBoard.Sound(S: TBoardSound);
begin
  if Assigned(FOnSound) then
    FOnSound(Self, S);
end;

procedure TSolitaireBoard.StartWin(Preview: Boolean);
var
  E: TWinEffect;
begin
  FPressed := False;
  FDragging := False;
  FinishAnim;
  FHintTime := 0;
  FWinPreview := Preview;
  FWinTime := 0;
  E := FWinEffect;
  if E = weRandom then
    repeat
      E := TWinEffect(1 + Random(3));
    until E <> FLastEffect;   // never the same surprise twice in a row
  FLastEffect := E;
  FEffect := E;
  FWinActive := True;
  UpdateLayout;
  case E of
    weBounce:
      InitBounce;
    weFireworks:
      begin
        FParticles.Clear;
        FNextBurst := 0;
      end;
    weFountain:
      InitFountain;
  end;
  StartTimer;
  Repaint;
  Sound(bsWin);
end;

procedure TSolitaireBoard.StopWin;
begin
  FWinActive := False;
  FWinPreview := False;
  FreeAndNil(FTrail);
  FParticles.Clear;
  FFly := nil;
  Repaint;
end;

procedure TSolitaireBoard.PreviewWin;
begin
  if FGame = nil then
    Exit;
  Reset;
  StartWin(True);
end;

{ Classic cascade: each card leaves its place, bounces along the bottom edge
  and leaves a trail, because the off-screen bitmap is never cleared. }
procedure TSolitaireBoard.InitBounce;
const
  // the piles the game was won onto go first, the stock last
  ORDER: array[0..5] of TPileKind = (pkFoundation, pkWaste, pkCell, pkTableau, pkSpot, pkStock);
var
  K, P, Depth, N, MaxDepth: Integer;
begin
  // Every card on the table leaves from where it lies, the top of each pile
  // first and the piles of one kind taking turns (so four foundations give
  // the familiar King, King, King, King, Queen ...).
  FillChar(FBounceGone, SizeOf(FBounceGone), 0);
  FBounceList := nil;
  N := 0;
  SetLength(FBounceList, FGame.DeckSize);
  for K := 0 to High(ORDER) do
  begin
    MaxDepth := 0;
    for P := 0 to FGame.PileCount - 1 do
      if FGame.PileKind(P) = ORDER[K] then
        MaxDepth := Max(MaxDepth, FGame.CardCount(P));
    for Depth := 1 to MaxDepth do
      for P := 0 to FGame.PileCount - 1 do
        if (FGame.PileKind(P) = ORDER[K]) and (FGame.CardCount(P) >= Depth) and (N < Length(FBounceList)) then
        begin
          FBounceList[N] := Point(P, FGame.CardCount(P) - Depth);
          Inc(N);
        end;
  end;
  SetLength(FBounceList, N);
  FBounceNext := 0;

  FreeAndNil(FTrail);
  FTrailScale := SceneScale;
  FTrail := TBitmap.Create(Max(1, Round(Width * FTrailScale)), Max(1, Round(Height * FTrailScale)));
  FTrail.Clear(TAlphaColorRec.Null);   // an empty, see-through layer for the trails

  FBounceLive := False;
  FBounceDone := False;
  FBounceLaunched := 0;
end;

procedure TSolitaireBoard.BounceStep(C: TCanvas);
var
  U: Single;
  P, Index: Integer;
begin
  if FBounceDone then
    Exit;
  U := FCardW / 80;
  if not FBounceLive then
  begin
    if FBounceNext > High(FBounceList) then
    begin
      FBounceDone := True;
      Exit;
    end;
    P := FBounceList[FBounceNext].X;
    Index := FBounceList[FBounceNext].Y;
    Inc(FBounceNext);
    FBounceCard := FGame.CardAt(P, Index);
    FBouncePos := CardPos(P, Index);
    FBounceGone[FBounceCard.Id] := True;
    // From now on the table underneath is painted without this card (see
    // IsFlying), which uncovers whatever it was lying on.
    FBounceCard.FaceUp := True;   // face-down cards turn over as they go

    FBounceVel.X := (2 + Random * 5) * U;
    if Random(2) = 0 then
      FBounceVel.X := -FBounceVel.X;
    FBounceVel.Y := -(Random * 9) * U;
    // A card that starts low on the table (TriPeaks' waste pile, Pyramid's
    // discard pile in portrait) is thrown upwards, high enough to arc towards
    // the top; otherwise it would only make small hops along the bottom.
    // (Gravity is 0.5 * U per step, so v = sqrt(2 * g * rise).)
    if FBouncePos.Y > Height * 0.3 then
      FBounceVel.Y := -Sqrt(Max(0, U * (FBouncePos.Y - FTop))) * (0.55 + Random * 0.45);
    FBounceLive := True;
    Inc(FBounceLaunched);
  end;

  FBounceVel.Y := FBounceVel.Y + 0.5 * U;
  FBouncePos := FBouncePos + FBounceVel;
  if FBouncePos.Y + FCardH > Height then
  begin
    FBouncePos.Y := Height - FCardH;
    if FBounceVel.Y > 2.5 * U then   // the last little hops are silent
      Sound(bsBounce);
    FBounceVel.Y := -FBounceVel.Y * 0.83;
  end;
  DrawCard(C, FBounceCard, FBouncePos);
  if (FBouncePos.X > Width) or (FBouncePos.X + FCardW < 0) then
    FBounceLive := False;
end;

procedure TSolitaireBoard.StepFireworks(Dt: Single);
var
  I, N: Integer;
  Pt: TParticle;
  Center: TPointF;
  Angle, Speed, G: Single;
  Col: TAlphaColor;
  Suit: TSuit;
begin
  G := Height * 0.35;
  for I := FParticles.Count - 1 downto 0 do
  begin
    Pt := FParticles[I];
    Pt.Life := Pt.Life - Dt;
    if Pt.Life <= 0 then
    begin
      FParticles.Delete(I);
      Continue;
    end;
    Pt.Vel.Y := Pt.Vel.Y + G * Dt;
    Pt.Vel := Pt.Vel * (1 - 1.3 * Dt);
    Pt.Pos := Pt.Pos + Pt.Vel * Dt;
    FParticles[I] := Pt;
  end;

  FNextBurst := FNextBurst - Dt;
  if (FNextBurst <= 0) and (FParticles.Count < 220) then
  begin
    FNextBurst := 0.25 + Random * 0.5;
    Sound(bsBurst);
    Center := PointF(Width * (0.12 + Random * 0.76), Height * (0.12 + Random * 0.5));
    Col := SPARK_COLORS[Random(Length(SPARK_COLORS))];
    Suit := TSuit(Random(4));
    N := 26;
    Speed := Max(FCardW, Min(Width, Height) / 9);
    for I := 0 to N - 1 do
    begin
      Angle := 2 * Pi * I / N + Random * 0.2;
      Pt.Pos := Center;
      Pt.Vel := PointF(Cos(Angle), Sin(Angle)) * (Speed * (2.2 + Random * 2.6));
      Pt.MaxLife := 1.1 + Random * 0.7;
      Pt.Life := Pt.MaxLife;
      Pt.Size := Max(FCardW, 40) * (0.17 + Random * 0.1);
      Pt.Color := Col;
      Pt.Suit := Suit;
      FParticles.Add(Pt);
    end;
  end;
end;

procedure TSolitaireBoard.LaunchFly(var F: TFountainCard);
var
  G, Peak: Single;
begin
  G := Height * 1.5;
  Peak := Height * (0.55 + Random * 0.4) + FCardH;
  F.Pos := PointF(Width / 2 - FCardW / 2, Height);
  F.Vel := PointF((Random - 0.5) * Width * 0.75, -Sqrt(2 * G * Peak));
  F.Flying := True;
end;

procedure TSolitaireBoard.InitFountain;
var
  I: Integer;
begin
  SetLength(FFly, 52);
  for I := 0 to 51 do
  begin
    FFly[I].Card.Suit := TSuit(I mod 4);
    FFly[I].Card.Rank := 13 - (I div 4);
    FFly[I].Card.FaceUp := True;
    FFly[I].Delay := 0.01 + I * 0.09;
    FFly[I].Flying := False;
  end;
end;

procedure TSolitaireBoard.StepFountain(Dt: Single);
var
  I: Integer;
  G: Single;
begin
  G := Height * 1.5;
  for I := 0 to High(FFly) do
    if FFly[I].Flying then
    begin
      FFly[I].Vel.Y := FFly[I].Vel.Y + G * Dt;
      FFly[I].Pos := FFly[I].Pos + FFly[I].Vel * Dt;
      if (FFly[I].Pos.Y > Height + 2) and (FFly[I].Vel.Y > 0) then
      begin
        FFly[I].Flying := False;
        FFly[I].Delay := 0.05 + Random * 0.8;
      end;
    end
    else
    begin
      FFly[I].Delay := FFly[I].Delay - Dt;
      if FFly[I].Delay <= 0 then
      begin
        LaunchFly(FFly[I]);
        Sound(bsLaunch);
      end;
    end;
end;

{ ---------- self-test hooks ---------- }

function TSolitaireBoard.CardCenter(P, Index: Integer): TPointF;
var
  Pos: TPointF;
  N: Integer;
  S: TPileSlot;
  DownStep, UpStep: Single;
begin
  UpdateLayout;
  N := FGame.CardCount(P);
  if (Index < 0) or (N = 0) then
    Exit(CardRect(PilePos(P)).CenterPoint);
  Pos := CardPos(P, Index);
  S := FGame.PileSlot(P, FWide);
  if FGame.PileKind(P) = pkSpot then
    // the next row overlaps the lower half, so aim near the top
    Result := PointF(Pos.X + FCardW / 2, Pos.Y + FCardH * 0.18)
  else if (S.Fan = fnDown) and (FGame.FanLimit(P) = 0) and (Index < N - 1) then
  begin
    // only the strip above the next card is visible
    TableauSteps(P, PilePos(P).Y, DownStep, UpStep);
    if not FGame.CardAt(P, Index).FaceUp then
      UpStep := DownStep;
    Result := PointF(Pos.X + FCardW / 2, Pos.Y + UpStep / 2);
  end
  else
    Result := CardRect(Pos).CenterPoint;
end;

procedure TSolitaireBoard.SimulateTap(P, Index: Integer);
var
  Pt: TPointF;
begin
  Pt := CardCenter(P, Index);
  MouseDown(TMouseButton.mbLeft, [ssLeft], Pt.X, Pt.Y);
  MouseUp(TMouseButton.mbLeft, [], Pt.X, Pt.Y);
end;

procedure TSolitaireBoard.SimulateDragTo(Src, Index: Integer; const Target: TPointF);
var
  A, Pt: TPointF;
  I: Integer;
begin
  A := CardCenter(Src, Index);
  MouseDown(TMouseButton.mbLeft, [ssLeft], A.X, A.Y);
  for I := 1 to 5 do
  begin
    Pt := A + (Target - A) * (I / 5);
    MouseMove([ssLeft], Pt.X, Pt.Y);
  end;
  MouseUp(TMouseButton.mbLeft, [], Target.X, Target.Y);
end;

function TSolitaireBoard.DropCenter(Dst: Integer): TPointF;
var
  N: Integer;
begin
  UpdateLayout;
  N := FGame.CardCount(Dst);
  if N > 0 then
    Result := CardCenter(Dst, N - 1)
  else
    Result := CardRect(PilePos(Dst)).CenterPoint;
end;

procedure TSolitaireBoard.SimulatePointer(Phase: Integer; const Pt: TPointF);
begin
  case Phase of
    0: MouseDown(TMouseButton.mbLeft, [ssLeft], Pt.X, Pt.Y);
    1: MouseMove([ssLeft], Pt.X, Pt.Y);
    2: MouseUp(TMouseButton.mbLeft, [], Pt.X, Pt.Y);
  end;
end;

procedure TSolitaireBoard.SimulateDrag(Src, Index, Dst: Integer);
begin
  SimulateDragTo(Src, Index, DropCenter(Dst));
end;

function TSolitaireBoard.CheckLayout(out Msg: string): Boolean;
var
  P, Q, I: Integer;
  R, X: TRectF;
  Bounds: TArray<TRectF>;
  KP, KQ: TPileKind;
begin
  Result := False;
  UpdateLayout;
  SetLength(Bounds, FGame.PileCount);
  for P := 0 to FGame.PileCount - 1 do
  begin
    Bounds[P] := CardRect(PilePos(P));
    for I := 0 to FGame.CardCount(P) - 1 do
      Bounds[P] := TRectF.Union(Bounds[P], CardRect(CardPos(P, I)));
    R := Bounds[P];
    if (R.Left < -0.5) or (R.Top < -0.5) or (R.Right > Width + 0.5) or (R.Bottom > Height + 0.5) then
    begin
      Msg := Format('pile %d (%.0f,%.0f)-(%.0f,%.0f) leaves the %.0fx%.0f board',
        [P, R.Left, R.Top, R.Right, R.Bottom, Width, Height]);
      Exit;
    end;
  end;
  for P := 0 to FGame.PileCount - 1 do
    for Q := P + 1 to FGame.PileCount - 1 do
    begin
      KP := FGame.PileKind(P);
      KQ := FGame.PileKind(Q);
      // pyramid/peak rows and stacked finished runs overlap on purpose
      if (KP = KQ) and (KP in [pkSpot, pkFoundation]) then
        Continue;
      X := TRectF.Intersect(Bounds[P], Bounds[Q]);
      if (X.Width > 0.5) and (X.Height > 0.5) then
      begin
        Msg := Format('piles %d and %d overlap', [P, Q]);
        Exit;
      end;
    end;
  Msg := '';
  Result := True;
end;

function TSolitaireBoard.EffectObjectCount: Integer;
var
  I: Integer;
begin
  Result := 0;
  if not FWinActive then
    Exit;
  case FEffect of
    weBounce:
      Result := FBounceLaunched;
    weFireworks:
      Result := FParticles.Count;
    weFountain:
      for I := 0 to High(FFly) do
        if FFly[I].Flying then
          Inc(Result);
  end;
end;

{ ---------- input ---------- }

procedure TSolitaireBoard.Reset;
begin
  FPressed := False;
  FDragging := False;
  FinishAnim;
  FAutoCompleting := False;
  FHintTime := 0;
  if FWinActive then
    StopWin;
  Repaint;
end;

function TSolitaireBoard.Busy: Boolean;
begin
  Result := FAutoCompleting or FWinActive or FDragging;
end;

procedure TSolitaireBoard.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  P, Index: Integer;
  Pt: TPointF;
  WasPreview: Boolean;
begin
  inherited;
  if (Button <> TMouseButton.mbLeft) or (FGame = nil) then
    Exit;
  UpdateLayout;

  if FWinActive then
  begin
    if FWinTime < 0.4 then
      Exit;   // ignore the tap that is still finishing the last move
    WasPreview := FWinPreview;
    StopWin;
    if not WasPreview and Assigned(FOnNewGameRequest) then
      FOnNewGameRequest(Self);
    Exit;
  end;

  if FAnimActive then
  begin
    FinishAnim;   // finish the running animation right away
    AfterMove;
  end;
  if FAutoCompleting or FWinActive then
    Exit;

  Pt := PointF(X, Y);
  if not HitCard(Pt, P, Index) then
    Exit;
  FPressed := True;
  FDragging := False;
  FDragPile := P;
  FDragIndex := Index;
  FDownPos := Pt;
  FCanDrag := (Index >= 0) and FGame.CanPickUp(P, Index);
  if FCanDrag then
  begin
    FDragPos := CardPos(P, Index);
    FDragOffset := Pt - FDragPos;
  end;
end;

procedure TSolitaireBoard.MouseMove(Shift: TShiftState; X, Y: Single);
var
  Pt: TPointF;
begin
  inherited;
  if not (FPressed and FCanDrag) then
    Exit;
  Pt := PointF(X, Y);
  if not FDragging and (Pt.Distance(FDownPos) > 6) then
  begin
    FDragging := True;
    FHintTime := 0;
  end;
  if FDragging then
  begin
    FDragPos := Pt - FDragOffset;
    Repaint;
  end;
end;

procedure TSolitaireBoard.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Single);
var
  Dst, Src, Index, I, N: Integer;
  Base: TPointF;
  Done: Boolean;
begin
  inherited;
  if not FPressed then
    Exit;
  FPressed := False;
  Src := FDragPile;
  Index := FDragIndex;

  if FDragging then
  begin
    Dst := FindDropPile;
    Done := False;
    if Dst >= 0 then
      Done := Perform(
        function: Boolean
        begin
          Result := FGame.MoveCards(Src, Index, Dst);
        end, 0.10, True);
    if not Done then
    begin
      // not a legal place: glide back home
      FinishAnim;
      N := FGame.CardCount(Src);
      Base := CardPos(Src, Index);
      for I := Index to N - 1 do
      begin
        FFlying[FGame.CardAt(Src, I).Id] := True;
        FFlyFrom[FGame.CardAt(Src, I).Id] := FDragPos + (CardPos(Src, I) - Base);
        FFlyDelay[FGame.CardAt(Src, I).Id] := 0;
      end;
      FAnimTime := 0;
      FAnimDur := 0.16;
      FAnimEnd := 0.16;
      FAnimActive := True;
      StartTimer;
    end;
    FDragging := False;
  end
  else
    // a tap: the game decides what it means (deal, auto-move, pick a pair...)
    Perform(
      function: Boolean
      begin
        Result := FGame.Tap(Src, Index);
      end, 0.17, False);
  Repaint;
end;

end.
