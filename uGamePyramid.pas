unit uGamePyramid;

interface

uses
  System.SysUtils, System.Math, uCardGame;

const
  PY_STOCK   = 0;
  PY_WASTE   = 1;
  PY_DISCARD = 2;    // removed pairs
  PY_SPOT0   = 3;    // 3..30: row r (0..6), position i (0..r) = PY_SPOT0 + r*(r+1)/2 + i
  PY_REDEALS = 2;    // times the waste may be turned over

type
  TPyramidGame = class(TCardGame)
  private
    FSel: Integer;   // pile of the card picked first for a pair, or -1
    class function SpotIndex(Row, Pos: Integer): Integer; static;
    class procedure SpotRowPos(P: Integer; out Row, Pos: Integer); static;
    function Exposed(P: Integer): Boolean;
    function Playable(P: Integer): Boolean;
    function PlayRank(P: Integer): Integer;
  protected
    procedure Deal(const Deck: TCards); override;
    procedure DoMove(Src, Index, Dst: Integer); override;
    procedure ClearTransient; override;
    function DealStock: Boolean; override;
  public
    class function GameId: string; override;
    class function Title: string; override;
    class function Blurb: string; override;
    class function Rules: string; override;

    function PileCount: Integer; override;
    function PileKind(P: Integer): TPileKind; override;
    procedure GetLayout(Wide: Boolean; out Cols, Rows: Single); override;
    function PileSlot(P: Integer; Wide: Boolean): TPileSlot; override;
    function StockCanRecycle: Boolean; override;
    function IsSelected(P, Index: Integer): Boolean; override;
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

class function TPyramidGame.GameId: string;
begin
  Result := 'pyramid';
end;

class function TPyramidGame.Title: string;
begin
  Result := 'Pyramid';
end;

class function TPyramidGame.Blurb: string;
begin
  Result := 'Clear the pyramid by pairing cards that add up to 13.';
end;

class function TPyramidGame.Rules: string;
begin
  Result :=
    '# Goal' + sLineBreak +
    'Remove every card from the pyramid.' + sLineBreak +
    '# The table' + sLineBreak +
    '- 28 cards are laid out as a pyramid of seven overlapping rows, all face up.' + sLineBreak +
    '- The other 24 cards are the stock. Tap it to turn one card at a time onto the waste pile.' + sLineBreak +
    '- Removed cards go to the discard pile.' + sLineBreak +
    '# Card values' + sLineBreak +
    'Ace counts 1, the number cards count their number, Jack is 11, Queen is 12 and King is 13.' + sLineBreak +
    '# How to play' + sLineBreak +
    '- Remove two cards together when they add up to 13: 6 and 7, 5 and 8, 4 and 9, 3 and 10, 2 and Jack, Ace and Queen.' + sLineBreak +
    '- A King is 13 on its own, so it is removed by itself.' + sLineBreak +
    '- A pyramid card can only be used when it is uncovered, meaning both cards overlapping it from the row below are gone.' + sLineBreak +
    '- The top card of the waste pile can always be used, with a pyramid card.' + sLineBreak +
    '- When the stock runs out you may turn the waste pile over and go through it again, twice per game.' + sLineBreak +
    '# Controls' + sLineBreak +
    '- Tap one card, then tap its partner. The first card is outlined until you choose the second.' + sLineBreak +
    '- Or drag one card onto the other.' + sLineBreak +
    '- Tap a King to remove it.' + sLineBreak +
    '- Undo takes back one move at a time. Hint shows a pair you can remove.' + sLineBreak +
    '# Tips' + sLineBreak +
    '- Remove Kings as soon as they are uncovered. It never hurts.' + sLineBreak +
    '- Before pairing a waste card, check whether its partner is buried underneath the card you need it for.' + sLineBreak +
    '- Prefer pairs that use two pyramid cards: they open the pyramid faster.' + sLineBreak +
    '- Many deals cannot be won. If the game says there are no more moves, deal again.' + sLineBreak +
    '# Scoring' + sLineBreak +
    'Each card removed scores 5.';
end;

class function TPyramidGame.SpotIndex(Row, Pos: Integer): Integer;
begin
  Result := PY_SPOT0 + Row * (Row + 1) div 2 + Pos;
end;

class procedure TPyramidGame.SpotRowPos(P: Integer; out Row, Pos: Integer);
var
  K: Integer;
begin
  K := P - PY_SPOT0;
  Row := 0;
  while K > Row do
  begin
    Dec(K, Row + 1);
    Inc(Row);
  end;
  Pos := K;
end;

function TPyramidGame.PileCount: Integer;
begin
  Result := PY_SPOT0 + 28;
end;

function TPyramidGame.PileKind(P: Integer): TPileKind;
begin
  case P of
    PY_STOCK:   Result := pkStock;
    PY_WASTE:   Result := pkWaste;
    PY_DISCARD: Result := pkFoundation;
  else
    Result := pkSpot;
  end;
end;

procedure TPyramidGame.GetLayout(Wide: Boolean; out Cols, Rows: Single);
begin
  if Wide then
  begin
    Cols := 9;
    Rows := 4.2;
  end
  else
  begin
    Cols := 7;
    Rows := 5.5;
  end;
end;

function TPyramidGame.PileSlot(P: Integer; Wide: Boolean): TPileSlot;
var
  Row, Pos: Integer;
begin
  Result.X := 0;
  Result.Y := 0;
  Result.Fan := fnNone;
  if PileKind(P) = pkSpot then
  begin
    SpotRowPos(P, Row, Pos);
    Result.X := 3 - Row * 0.5 + Pos;
    Result.Y := Row * 0.5;
    if Wide then
      Result.X := Result.X + 1;
  end
  else if Wide then
    case P of
      PY_WASTE:   Result.Y := 1.09;
      PY_DISCARD: Result.X := 8;
    end
  else
  begin
    Result.Y := 4.3;
    case P of
      PY_STOCK:   Result.X := 1.5;
      PY_WASTE:   Result.X := 2.5;
      PY_DISCARD: Result.X := 4.5;
    end;
  end;
end;

function TPyramidGame.StockCanRecycle: Boolean;
begin
  Result := (CardCount(PY_WASTE) > 0) and (FState.Extra[0] < PY_REDEALS);
end;

function TPyramidGame.IsSelected(P, Index: Integer): Boolean;
begin
  Result := (P = FSel) and (Index = CardCount(P) - 1);
end;

function TPyramidGame.StatusExtra: string;
begin
  Result := Format('Stock %d     Redeals left %d', [CardCount(PY_STOCK), PY_REDEALS - FState.Extra[0]]);
end;

procedure TPyramidGame.ClearTransient;
begin
  FSel := -1;
end;

procedure TPyramidGame.Deal(const Deck: TCards);
var
  I: Integer;
  C: TCard;
begin
  for I := 0 to 27 do
  begin
    C := Deck[I];
    C.FaceUp := True;
    Push(PY_SPOT0 + I, C);
  end;
  for I := 28 to High(Deck) do
    Push(PY_STOCK, Deck[I]);
end;

/// A pyramid card is uncovered when both cards overlapping it are gone.
function TPyramidGame.Exposed(P: Integer): Boolean;
var
  Row, Pos: Integer;
begin
  if (PileKind(P) <> pkSpot) or (CardCount(P) = 0) then
    Exit(False);
  SpotRowPos(P, Row, Pos);
  Result := (Row = 6) or
    ((CardCount(SpotIndex(Row + 1, Pos)) = 0) and (CardCount(SpotIndex(Row + 1, Pos + 1)) = 0));
end;

/// The card on P may be used in a pair right now.
function TPyramidGame.Playable(P: Integer): Boolean;
begin
  if (P < 0) or (P >= PileCount) then
    Exit(False);
  if P = PY_WASTE then
    Result := CardCount(P) > 0
  else
    Result := Exposed(P);
end;

function TPyramidGame.PlayRank(P: Integer): Integer;
begin
  Result := FState.Piles[P][CardCount(P) - 1].Rank;
end;

function TPyramidGame.CanPickUp(P, Index: Integer): Boolean;
begin
  Result := Playable(P) and (Index = CardCount(P) - 1);
end;

function TPyramidGame.CanDrop(Src, Index, Dst: Integer): Boolean;
begin
  Result := False;
  if (Src = Dst) or not CanPickUp(Src, Index) then
    Exit;
  if Dst = PY_DISCARD then
    Result := PlayRank(Src) = 13          // a King goes on its own
  else if Playable(Dst) then
    // two waste cards cannot pair: only the top one is available
    Result := (PlayRank(Src) + PlayRank(Dst) = 13) and not ((Src = PY_WASTE) and (Dst = PY_WASTE));
end;

procedure TPyramidGame.DoMove(Src, Index, Dst: Integer);
begin
  if Dst = PY_DISCARD then
  begin
    Transfer(Src, CardCount(Src) - 1, PY_DISCARD);
    AddScore(5);
  end
  else
  begin
    Transfer(Dst, CardCount(Dst) - 1, PY_DISCARD);
    Transfer(Src, CardCount(Src) - 1, PY_DISCARD);
    AddScore(10);
  end;
end;

function TPyramidGame.DealStock: Boolean;
var
  I, N: Integer;
  C: TCard;
begin
  Result := False;
  N := CardCount(PY_STOCK);
  if N > 0 then
  begin
    PushUndo;
    ClearTransient;
    C := FState.Piles[PY_STOCK][N - 1];
    SetLength(FState.Piles[PY_STOCK], N - 1);
    C.FaceUp := True;
    Push(PY_WASTE, C);
    Inc(FState.Moves);
    Result := True;
  end
  else if StockCanRecycle then
  begin
    PushUndo;
    ClearTransient;
    for I := CardCount(PY_WASTE) - 1 downto 0 do
    begin
      C := FState.Piles[PY_WASTE][I];
      C.FaceUp := False;
      Push(PY_STOCK, C);
    end;
    FState.Piles[PY_WASTE] := nil;
    Inc(FState.Extra[0]);
    Inc(FState.Moves);
    Result := True;
  end;
end;

function TPyramidGame.Tap(P, Index: Integer): Boolean;
var
  First: Integer;
begin
  Result := False;
  if (P < 0) or (P >= PileCount) then
    Exit;
  if P = PY_STOCK then
    Exit(DealStock);
  if not Playable(P) then
  begin
    FSel := -1;
    Exit(False);
  end;
  if PlayRank(P) = 13 then
    Exit(MoveCards(P, CardCount(P) - 1, PY_DISCARD));
  First := FSel;
  if (First >= 0) and (First <> P) and Playable(First) and CanDrop(First, CardCount(First) - 1, P) then
    Exit(MoveCards(First, CardCount(First) - 1, P));
  // otherwise this card becomes (or stops being) the first half of a pair
  if First = P then
    FSel := -1
  else
    FSel := P;
end;

function TPyramidGame.IsWon: Boolean;
var
  P: Integer;
begin
  for P := PY_SPOT0 to PileCount - 1 do
    if CardCount(P) > 0 then
      Exit(False);
  Result := True;
end;

function TPyramidGame.IsStuck: Boolean;
begin
  Result := (not IsWon) and (Hint.Kind = hkNone);
end;

function TPyramidGame.Hint: THint;
var
  A, B: Integer;
begin
  Result := MakeHint(hkNone, -1, -1, -1);
  if IsWon then
    Exit;
  // a King
  for A := PY_SPOT0 to PileCount - 1 do
    if Exposed(A) and (PlayRank(A) = 13) then
      Exit(MakeHint(hkTap, A, 0, -1));
  if (CardCount(PY_WASTE) > 0) and (PlayRank(PY_WASTE) = 13) then
    Exit(MakeHint(hkTap, PY_WASTE, CardCount(PY_WASTE) - 1, -1));
  // two pyramid cards
  for A := PY_SPOT0 to PileCount - 1 do
    if Exposed(A) then
      for B := A + 1 to PileCount - 1 do
        if Exposed(B) and (PlayRank(A) + PlayRank(B) = 13) then
          Exit(MakeHint(hkMove, A, 0, B));
  // the waste card with a pyramid card
  if CardCount(PY_WASTE) > 0 then
    for B := PY_SPOT0 to PileCount - 1 do
      if Exposed(B) and (PlayRank(PY_WASTE) + PlayRank(B) = 13) then
        Exit(MakeHint(hkMove, PY_WASTE, CardCount(PY_WASTE) - 1, B));
  if (CardCount(PY_STOCK) > 0) or StockCanRecycle then
    Result := MakeHint(hkTap, PY_STOCK, CardCount(PY_STOCK) - 1, -1);
end;

function TPyramidGame.CheckIntegrity(out Msg: string): Boolean;
var
  I: Integer;
begin
  Result := inherited CheckIntegrity(Msg);
  if not Result then
    Exit;
  Result := False;
  for I := 0 to CardCount(PY_STOCK) - 1 do
    if FState.Piles[PY_STOCK][I].FaceUp then
    begin
      Msg := 'face-up card in the stock';
      Exit;
    end;
  if (FState.Extra[0] < 0) or (FState.Extra[0] > PY_REDEALS) then
  begin
    Msg := 'impossible redeal count';
    Exit;
  end;
  Msg := '';
  Result := True;
end;

end.
