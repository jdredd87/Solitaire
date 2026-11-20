unit uGameTriPeaks;

interface

uses
  System.SysUtils, System.Math, uCardGame;

const
  TP_STOCK = 0;
  TP_WASTE = 1;
  TP_ROW0  = 2;    // 3 peak cards
  TP_ROW1  = 5;    // 6 cards
  TP_ROW2  = 11;   // 9 cards
  TP_ROW3  = 20;   // 10 cards, face up from the start
  TP_END   = 30;

type
  TTriPeaksGame = class(TCardGame)
  private
    function Covered(P: Integer): Boolean;
    function Adjacent(A, B: Integer): Boolean;
    procedure TurnUncovered;
  protected
    procedure Deal(const Deck: TCards); override;
    procedure DoMove(Src, Index, Dst: Integer); override;
    procedure AfterMove; override;
    function DealStock: Boolean; override;
  public
    class function GameId: string; override;
    class function Title: string; override;
    class function Blurb: string; override;
    class function Rules: string; override;

    function PileCount: Integer; override;
    function PileKind(P: Integer): TPileKind; override;
    function WideBias: Single; override;
    procedure GetLayout(Wide: Boolean; out Cols, Rows: Single); override;
    function PileSlot(P: Integer; Wide: Boolean): TPileSlot; override;
    function StatusExtra: string; override;

    function CanPickUp(P, Index: Integer): Boolean; override;
    function CanDrop(Src, Index, Dst: Integer): Boolean; override;
    function Tap(P, Index: Integer): Boolean; override;
    function IsWon: Boolean; override;
    function IsStuck: Boolean; override;
    function Hint: THint; override;
    function CheckIntegrity(out Msg: string): Boolean; override;
  end;

implementation

class function TTriPeaksGame.GameId: string;
begin
  Result := 'tripeaks';
end;

class function TTriPeaksGame.Title: string;
begin
  Result := 'TriPeaks';
end;

class function TTriPeaksGame.Blurb: string;
begin
  Result := 'Three peaks. Play cards one higher or lower in long runs.';
end;

class function TTriPeaksGame.Rules: string;
begin
  Result :=
    '# Goal' + sLineBreak +
    'Clear all three peaks by moving every card onto the waste pile.' + sLineBreak +
    '# The table' + sLineBreak +
    '- 28 cards form three overlapping peaks. Only the bottom row starts face up.' + sLineBreak +
    '- One card is turned up to start the waste pile. The rest of the deck is the stock.' + sLineBreak +
    '# How to play' + sLineBreak +
    '- Tap a face-up peak card that is one rank higher or one rank lower than the top card of the waste pile. It moves onto the waste pile and becomes the new card to follow.' + sLineBreak +
    '- Suits and colours do not matter.' + sLineBreak +
    '- The ranks wrap around: an Ace can follow a King and a King can follow an Ace.' + sLineBreak +
    '- A card turns face up as soon as nothing overlaps it.' + sLineBreak +
    '- When nothing fits, tap the stock to turn a new card onto the waste pile.' + sLineBreak +
    '- The game is lost when the stock is empty and no card can be played.' + sLineBreak +
    '# Example' + sLineBreak +
    'With a 7 on the waste pile you may play a 6 or an 8. If you play the 8, the next card must be a 7 or a 9, and so on.' + sLineBreak +
    '# Controls' + sLineBreak +
    '- Tap a card to play it, or drag it to the waste pile.' + sLineBreak +
    '- Undo takes back one move at a time. Hint shows a card you can play.' + sLineBreak +
    '# Tips' + sLineBreak +
    '- Look for the longest chain before you start, for example 7, 8, 9, 8, 7, 6.' + sLineBreak +
    '- When two cards both fit, play the one that uncovers more face-down cards.' + sLineBreak +
    '- Do not turn the stock while a play is still possible. Every stock card you save may be the one you need at the end.' + sLineBreak +
    '# Scoring' + sLineBreak +
    'The first card of a run scores 1, the second 2, the third 3 and so on. Turning a stock card ends the run. Clearing a peak scores 15 and clearing the table 30 more.';
end;

function TTriPeaksGame.PileCount: Integer;
begin
  Result := TP_END;
end;

function TTriPeaksGame.PileKind(P: Integer): TPileKind;
begin
  if P = TP_STOCK then
    Result := pkStock
  else if P = TP_WASTE then
    Result := pkWaste
  else
    Result := pkSpot;
end;

const
  // On a narrow screen the cards overlap sideways. Only the rank matters in
  // this game and it sits in the top-left corner, which stays visible.
  TP_COMPACT = 0.62;

function TTriPeaksGame.WideBias: Single;
begin
  Result := 1.35;   // prefer the tidy full-width peaks unless overlapping is far bigger
end;

procedure TTriPeaksGame.GetLayout(Wide: Boolean; out Cols, Rows: Single);
begin
  if Wide then
    Cols := 10
  else
    Cols := 1 + 9 * TP_COMPACT;
  Rows := 4.0;
end;

function TTriPeaksGame.PileSlot(P: Integer; Wide: Boolean): TPileSlot;
var
  J: Integer;
begin
  Result.X := 0;
  Result.Y := 0;
  Result.Fan := fnNone;
  if P = TP_STOCK then
  begin
    Result.X := 3.4;
    Result.Y := 2.75;
  end
  else if P = TP_WASTE then
  begin
    Result.X := 5.6;
    Result.Y := 2.75;
  end
  else if P >= TP_ROW3 then
  begin
    Result.X := P - TP_ROW3;
    Result.Y := 1.5;
  end
  else if P >= TP_ROW2 then
  begin
    Result.X := 0.5 + (P - TP_ROW2);
    Result.Y := 1.0;
  end
  else if P >= TP_ROW1 then
  begin
    J := P - TP_ROW1;
    Result.X := 1 + (J div 2) * 3 + (J mod 2);
    Result.Y := 0.5;
  end
  else
  begin
    Result.X := 1.5 + (P - TP_ROW0) * 3;
    Result.Y := 0;
  end;
  if not Wide then
    Result.X := Result.X * TP_COMPACT;
end;

function TTriPeaksGame.StatusExtra: string;
begin
  Result := Format('Stock %d     Run %d', [CardCount(TP_STOCK), FState.Extra[0]]);
end;

procedure TTriPeaksGame.Deal(const Deck: TCards);
var
  I: Integer;
  C: TCard;
begin
  for I := 0 to 27 do
  begin
    C := Deck[I];
    C.FaceUp := (TP_ROW0 + I) >= TP_ROW3;
    Push(TP_ROW0 + I, C);
  end;
  C := Deck[28];
  C.FaceUp := True;
  Push(TP_WASTE, C);
  for I := 29 to High(Deck) do
    Push(TP_STOCK, Deck[I]);
end;

/// A peak card is covered while either card overlapping it is still there.
function TTriPeaksGame.Covered(P: Integer): Boolean;
var
  J, A: Integer;
begin
  if P >= TP_ROW3 then
    Exit(False);
  if P >= TP_ROW2 then
    A := TP_ROW3 + (P - TP_ROW2)
  else if P >= TP_ROW1 then
  begin
    J := P - TP_ROW1;
    A := TP_ROW2 + (J div 2) * 3 + (J mod 2);
  end
  else
    A := TP_ROW1 + (P - TP_ROW0) * 2;
  Result := (CardCount(A) > 0) or (CardCount(A + 1) > 0);
end;

/// Ranks one apart, wrapping between King and Ace.
function TTriPeaksGame.Adjacent(A, B: Integer): Boolean;
var
  D: Integer;
begin
  D := Abs(A - B);
  Result := (D = 1) or (D = 12);
end;

function TTriPeaksGame.CanPickUp(P, Index: Integer): Boolean;
begin
  Result := (P >= TP_ROW0) and (P < TP_END) and (Index = 0) and (CardCount(P) = 1)
    and FState.Piles[P][0].FaceUp and not Covered(P);
end;

function TTriPeaksGame.CanDrop(Src, Index, Dst: Integer): Boolean;
var
  N: Integer;
begin
  N := CardCount(TP_WASTE);
  Result := (Dst = TP_WASTE) and (N > 0) and CanPickUp(Src, Index) and
    Adjacent(FState.Piles[Src][0].Rank, FState.Piles[TP_WASTE][N - 1].Rank);
end;

procedure TTriPeaksGame.DoMove(Src, Index, Dst: Integer);
var
  Peak, P: Integer;
begin
  Transfer(Src, 0, TP_WASTE);
  Inc(FState.Extra[0]);
  AddScore(FState.Extra[0]);
  if Src < TP_ROW1 then
  begin
    AddScore(15);            // a peak is cleared
    Peak := 0;
    for P := TP_ROW0 to TP_ROW0 + 2 do
      if CardCount(P) = 0 then
        Inc(Peak);
    if Peak = 3 then
      AddScore(30);
  end;
end;

procedure TTriPeaksGame.TurnUncovered;
var
  P: Integer;
begin
  for P := TP_ROW0 to TP_END - 1 do
    if (CardCount(P) = 1) and (not FState.Piles[P][0].FaceUp) and not Covered(P) then
      FState.Piles[P][0].FaceUp := True;
end;

procedure TTriPeaksGame.AfterMove;
begin
  TurnUncovered;
end;

function TTriPeaksGame.DealStock: Boolean;
var
  N: Integer;
  C: TCard;
begin
  N := CardCount(TP_STOCK);
  Result := N > 0;
  if not Result then
    Exit;
  PushUndo;
  C := FState.Piles[TP_STOCK][N - 1];
  SetLength(FState.Piles[TP_STOCK], N - 1);
  C.FaceUp := True;
  Push(TP_WASTE, C);
  FState.Extra[0] := 0;   // the run is over
  Inc(FState.Moves);
end;

function TTriPeaksGame.Tap(P, Index: Integer): Boolean;
begin
  if P = TP_STOCK then
    Result := DealStock
  else
    Result := (P >= TP_ROW0) and (P < TP_END) and MoveCards(P, 0, TP_WASTE);
end;

function TTriPeaksGame.IsWon: Boolean;
var
  P: Integer;
begin
  for P := TP_ROW0 to TP_END - 1 do
    if CardCount(P) > 0 then
      Exit(False);
  Result := True;
end;

function TTriPeaksGame.IsStuck: Boolean;
begin
  Result := (not IsWon) and (Hint.Kind = hkNone);
end;

function TTriPeaksGame.Hint: THint;
var
  P, Best, BestGain, Gain, Q: Integer;
begin
  Result := MakeHint(hkNone, -1, -1, -1);
  if IsWon then
    Exit;
  // prefer the playable card whose removal uncovers the most cards
  Best := -1;
  BestGain := -1;
  for P := TP_ROW0 to TP_END - 1 do
    if CanDrop(P, 0, TP_WASTE) then
    begin
      Gain := 0;
      for Q := TP_ROW0 to TP_ROW3 - 1 do
        if (CardCount(Q) = 1) and Covered(Q) then
        begin
          // would Q be free once P is gone?
          if P >= TP_ROW3 then
          begin
            if (Q >= TP_ROW2) and ((TP_ROW3 + (Q - TP_ROW2) = P) or (TP_ROW3 + (Q - TP_ROW2) + 1 = P)) then
              if CardCount(2 * TP_ROW3 + 2 * (Q - TP_ROW2) + 1 - P) = 0 then
                Inc(Gain);
          end;
        end;
      if Gain > BestGain then
      begin
        BestGain := Gain;
        Best := P;
      end;
    end;
  if Best >= 0 then
    Exit(MakeHint(hkTap, Best, 0, TP_WASTE));
  if CardCount(TP_STOCK) > 0 then
    Result := MakeHint(hkTap, TP_STOCK, CardCount(TP_STOCK) - 1, -1);
end;

function TTriPeaksGame.CheckIntegrity(out Msg: string): Boolean;
var
  P, I: Integer;
begin
  Result := inherited CheckIntegrity(Msg);
  if not Result then
    Exit;
  Result := False;
  for I := 0 to CardCount(TP_STOCK) - 1 do
    if FState.Piles[TP_STOCK][I].FaceUp then
    begin
      Msg := 'face-up card in the stock';
      Exit;
    end;
  for P := TP_ROW0 to TP_END - 1 do
    if (CardCount(P) = 1) and (FState.Piles[P][0].FaceUp = Covered(P)) then
    begin
      Msg := Format('peak card %d is %s but should not be', [P, 'face ' + BoolToStr(FState.Piles[P][0].FaceUp, True)]);
      Exit;
    end;
  Msg := '';
  Result := True;
end;

end.
