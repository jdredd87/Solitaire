unit uGameSpider;

interface

uses
  System.SysUtils, System.Math, uCardGame;

const
  SP_STOCK  = 0;
  SP_FOUND0 = 1;    // 1..8, one finished King-to-Ace run each
  SP_TAB0   = 9;    // 9..18

type
  TSpiderGame = class(TCardGame)
  private
    function IsSuitRun(P, Index: Integer): Boolean;
    function RunStart(P: Integer): Integer;
    function CanDeal: Boolean;
  protected
    function BuildDeck: TCards; override;
    procedure Deal(const Deck: TCards); override;
    procedure DoMove(Src, Index, Dst: Integer); override;
    procedure AfterMove; override;
    function DealStock: Boolean; override;
  public
    class function GameId: string; override;
    class function Title: string; override;
    class function Blurb: string; override;
    class function VariantLabel: string; override;
    class function VariantCount: Integer; override;
    class function VariantName(V: Integer): string; override;
    class function Rules: string; override;

    function PileCount: Integer; override;
    function PileKind(P: Integer): TPileKind; override;
    procedure GetLayout(Wide: Boolean; out Cols, Rows: Single); override;
    function PileSlot(P: Integer; Wide: Boolean): TPileSlot; override;
    function ShowEmptySlot(P: Integer; Wide: Boolean): Boolean; override;
    function StatusExtra: string; override;

    function CanPickUp(P, Index: Integer): Boolean; override;
    function CanDrop(Src, Index, Dst: Integer): Boolean; override;
    function FindAutoMove(Src, Index: Integer; out Dst: Integer): Boolean; override;
    function IsWon: Boolean; override;
    function Hint: THint; override;
    function CheckIntegrity(out Msg: string): Boolean; override;
  end;

implementation

class function TSpiderGame.GameId: string;
begin
  Result := 'spider';
end;

class function TSpiderGame.Title: string;
begin
  Result := 'Spider';
end;

class function TSpiderGame.Blurb: string;
begin
  Result := 'Two decks, ten columns. Build King-to-Ace runs in one suit.';
end;

class function TSpiderGame.VariantLabel: string;
begin
  Result := 'Suits';
end;

class function TSpiderGame.VariantCount: Integer;
begin
  Result := 3;
end;

class function TSpiderGame.VariantName(V: Integer): string;
begin
  case V of
    1: Result := '2 suits';
    2: Result := '4 suits';
  else
    Result := '1 suit';
  end;
end;

class function TSpiderGame.Rules: string;
begin
  Result :=
    '# Goal' + sLineBreak +
    'Build eight complete runs from King down to Ace, each in a single suit. A finished run is taken off the table automatically. Clear all 104 cards to win.' + sLineBreak +
    '# The table' + sLineBreak +
    '- Two decks are used. 54 cards are dealt into ten columns, with only the last card of each column face up.' + sLineBreak +
    '- The other 50 cards wait in the stock, enough for five more deals.' + sLineBreak +
    '- The eight spaces show the runs you have completed.' + sLineBreak +
    '# How to play' + sLineBreak +
    '- A card can be placed on any card that is one rank higher, whatever the suit: a 5 on any 6.' + sLineBreak +
    '- You can only move several cards together if they are in order and all the same suit.' + sLineBreak +
    '- So mixing suits is allowed, but it locks the cards underneath until you move the odd card away again.' + sLineBreak +
    '- Any card or same-suit run may be placed in an empty column.' + sLineBreak +
    '- When a face-down card is uncovered it turns over automatically.' + sLineBreak +
    '# Dealing from the stock' + sLineBreak +
    'Tap the stock to deal one new card onto every column. You may not deal while a column is empty, so fill empty columns first.' + sLineBreak +
    '# Controls' + sLineBreak +
    '- Tap a card to send it (and the same-suit cards on top of it) to the best place, or drag it yourself.' + sLineBreak +
    '- Undo takes back one move at a time. Hint shows a move you can make.' + sLineBreak +
    '# 1, 2 or 4 suits' + sLineBreak +
    'With 1 suit every card matches, so it is the place to learn. 2 suits is a fair challenge. 4 suits is very hard.' + sLineBreak +
    '# Tips' + sLineBreak +
    '- Prefer same-suit builds: they stay movable.' + sLineBreak +
    '- Empty columns are your working space. Try to empty one early and keep it free as long as you can.' + sLineBreak +
    '- Turn over face-down cards before you deal again, because a deal buries every column.' + sLineBreak +
    '# Scoring' + sLineBreak +
    'You start with 500 points. Every move costs 1 and every completed run earns 100.';
end;

function TSpiderGame.PileCount: Integer;
begin
  Result := 19;
end;

function TSpiderGame.PileKind(P: Integer): TPileKind;
begin
  if P = SP_STOCK then
    Result := pkStock
  else if P < SP_TAB0 then
    Result := pkFoundation
  else
    Result := pkTableau;
end;

function TSpiderGame.BuildDeck: TCards;
const
  // which suits make up the 104 cards in each variant
  SUITS: array[0..2, 0..7] of TSuit = (
    (suSpades, suSpades, suSpades, suSpades, suSpades, suSpades, suSpades, suSpades),
    (suSpades, suHearts, suSpades, suHearts, suSpades, suHearts, suSpades, suHearts),
    (suClubs, suDiamonds, suHearts, suSpades, suClubs, suDiamonds, suHearts, suSpades));
var
  D, R, K: Integer;
begin
  SetLength(Result, 104);
  K := 0;
  for D := 0 to 7 do
    for R := 1 to 13 do
    begin
      Result[K].Suit := SUITS[EnsureRange(Variant, 0, 2), D];
      Result[K].Rank := R;
      Result[K].FaceUp := False;
      Inc(K);
    end;
end;

procedure TSpiderGame.GetLayout(Wide: Boolean; out Cols, Rows: Single);
begin
  if Wide then
  begin
    Cols := 12;
    Rows := 2.7;
  end
  else
  begin
    Cols := 10;
    Rows := 4.4;
  end;
end;

function TSpiderGame.PileSlot(P: Integer; Wide: Boolean): TPileSlot;
begin
  Result.X := 0;
  Result.Y := 0;
  Result.Fan := fnNone;
  case PileKind(P) of
    pkFoundation:
      if Wide then
      begin
        // finished runs stack up down the right-hand edge
        Result.X := 11;
        Result.Y := (P - SP_FOUND0) * 0.2;
      end
      else
        Result.X := 2 + (P - SP_FOUND0);
    pkTableau:
      begin
        Result.Fan := fnDown;
        if Wide then
          Result.X := 1 + (P - SP_TAB0)
        else
        begin
          Result.X := P - SP_TAB0;
          Result.Y := 1.17;
        end;
      end;
  end;
end;

function TSpiderGame.ShowEmptySlot(P: Integer; Wide: Boolean): Boolean;
begin
  // the overlapping finished-run places would only draw a ladder of outlines
  Result := not (Wide and (PileKind(P) = pkFoundation) and (P <> SP_FOUND0));
end;

function TSpiderGame.StatusExtra: string;
var
  P, Done: Integer;
begin
  Done := 0;
  for P := SP_FOUND0 to SP_FOUND0 + 7 do
    if CardCount(P) > 0 then
      Inc(Done);
  Result := Format('Runs %d/8     Deals left %d', [Done, CardCount(SP_STOCK) div 10]);
end;

procedure TSpiderGame.Deal(const Deck: TCards);
var
  I, K, Col, N: Integer;
  C: TCard;
begin
  K := 0;
  for Col := 0 to 9 do
  begin
    if Col < 4 then
      N := 6
    else
      N := 5;
    for I := 1 to N do
    begin
      C := Deck[K];
      Inc(K);
      C.FaceUp := (I = N);
      Push(SP_TAB0 + Col, C);
    end;
  end;
  while K < Length(Deck) do
  begin
    Push(SP_STOCK, Deck[K]);
    Inc(K);
  end;
  FState.Score := 500;
end;

/// Cards P[Index..] are face up, descending and all of one suit.
function TSpiderGame.IsSuitRun(P, Index: Integer): Boolean;
var
  I: Integer;
begin
  if not FState.Piles[P][Index].FaceUp then
    Exit(False);
  for I := Index + 1 to CardCount(P) - 1 do
    if (FState.Piles[P][I].Suit <> FState.Piles[P][I - 1].Suit) or
      (FState.Piles[P][I].Rank + 1 <> FState.Piles[P][I - 1].Rank) then
      Exit(False);
  Result := True;
end;

/// Index where the movable same-suit run on top of column P starts.
function TSpiderGame.RunStart(P: Integer): Integer;
begin
  Result := CardCount(P) - 1;
  while (Result > 0) and IsSuitRun(P, Result - 1) do
    Dec(Result);
end;

function TSpiderGame.CanPickUp(P, Index: Integer): Boolean;
begin
  Result := (P >= SP_TAB0) and (P < PileCount) and (Index >= 0) and (Index < CardCount(P))
    and IsSuitRun(P, Index);
end;

function TSpiderGame.CanDrop(Src, Index, Dst: Integer): Boolean;
var
  DN: Integer;
begin
  Result := False;
  if (Src = Dst) or (Dst < SP_TAB0) or (Dst >= PileCount) or not CanPickUp(Src, Index) then
    Exit;
  DN := CardCount(Dst);
  if DN = 0 then
    Result := True
  else
    Result := FState.Piles[Dst][DN - 1].FaceUp and
      (FState.Piles[Dst][DN - 1].Rank = FState.Piles[Src][Index].Rank + 1);
end;

procedure TSpiderGame.DoMove(Src, Index, Dst: Integer);
begin
  Transfer(Src, Index, Dst);
  FlipTop(Src);
  AddScore(-1);
end;

{ A complete King..Ace run of one suit on top of a column leaves the table. }
procedure TSpiderGame.AfterMove;
var
  P, N, F, I: Integer;
  Complete: Boolean;
begin
  for P := SP_TAB0 to SP_TAB0 + 9 do
  begin
    N := CardCount(P);
    if (N < 13) or (FState.Piles[P][N - 1].Rank <> 1) or (FState.Piles[P][N - 13].Rank <> 13) then
      Continue;
    Complete := IsSuitRun(P, N - 13);
    if not Complete then
      Continue;
    F := -1;
    for I := SP_FOUND0 to SP_FOUND0 + 7 do
      if CardCount(I) = 0 then
      begin
        F := I;
        Break;
      end;
    if F < 0 then
      Continue;
    Transfer(P, N - 13, F);
    FlipTop(P);
    AddScore(100);
  end;
end;

function TSpiderGame.CanDeal: Boolean;
var
  P, Total: Integer;
  AnyEmpty: Boolean;
begin
  Result := False;
  if CardCount(SP_STOCK) < 10 then
    Exit;
  Total := 0;
  AnyEmpty := False;
  for P := SP_TAB0 to SP_TAB0 + 9 do
  begin
    Inc(Total, CardCount(P));
    if CardCount(P) = 0 then
      AnyEmpty := True;
  end;
  // every column needs a card first, unless there are not enough cards to do that
  Result := (not AnyEmpty) or (Total < 10);
end;

function TSpiderGame.DealStock: Boolean;
var
  P, N: Integer;
  C: TCard;
begin
  Result := CanDeal;
  if not Result then
    Exit;
  PushUndo;
  for P := SP_TAB0 to SP_TAB0 + 9 do
  begin
    N := CardCount(SP_STOCK);
    C := FState.Piles[SP_STOCK][N - 1];
    SetLength(FState.Piles[SP_STOCK], N - 1);
    C.FaceUp := True;
    Push(P, C);
  end;
  Inc(FState.Moves);
  AddScore(-1);
  AfterMove;
end;

function TSpiderGame.FindAutoMove(Src, Index: Integer; out Dst: Integer): Boolean;
var
  P, DN: Integer;
  C: TCard;
begin
  Result := False;
  Dst := -1;
  if not CanPickUp(Src, Index) then
    Exit;
  C := FState.Piles[Src][Index];
  // best: continue a run of the same suit
  for P := SP_TAB0 to SP_TAB0 + 9 do
  begin
    DN := CardCount(P);
    if (DN > 0) and CanDrop(Src, Index, P) and (FState.Piles[P][DN - 1].Suit = C.Suit) then
    begin
      Dst := P;
      Exit(True);
    end;
  end;
  for P := SP_TAB0 to SP_TAB0 + 9 do
    if (CardCount(P) > 0) and CanDrop(Src, Index, P) then
    begin
      Dst := P;
      Exit(True);
    end;
  if Index > 0 then
    for P := SP_TAB0 to SP_TAB0 + 9 do
      if (CardCount(P) = 0) and CanDrop(Src, Index, P) then
      begin
        Dst := P;
        Exit(True);
      end;
end;

function TSpiderGame.IsWon: Boolean;
var
  P: Integer;
begin
  for P := SP_FOUND0 to SP_FOUND0 + 7 do
    if CardCount(P) <> 13 then
      Exit(False);
  Result := True;
end;

function TSpiderGame.Hint: THint;
var
  S, D, DN, First, Pass: Integer;
  C, Under: TCard;
  SameSuit, OnSameSuitParent, OnParent: Boolean;
begin
  Result := MakeHint(hkNone, -1, -1, -1);
  if IsWon then
    Exit;

  // Pass 0: a same-suit join. Pass 1: any move that turns a card over or
  // empties nothing useful away. Each pass skips moves that gain nothing.
  for Pass := 0 to 1 do
    for S := SP_TAB0 to SP_TAB0 + 9 do
    begin
      if CardCount(S) = 0 then
        Continue;
      First := RunStart(S);
      C := FState.Piles[S][First];
      OnParent := False;
      OnSameSuitParent := False;
      if First > 0 then
      begin
        Under := FState.Piles[S][First - 1];
        OnParent := Under.FaceUp and (Under.Rank = C.Rank + 1);
        OnSameSuitParent := OnParent and (Under.Suit = C.Suit);
      end;
      if OnSameSuitParent then
        Continue;
      for D := SP_TAB0 to SP_TAB0 + 9 do
      begin
        DN := CardCount(D);
        if (D = S) or (DN = 0) or not CanDrop(S, First, D) then
          Continue;
        SameSuit := FState.Piles[D][DN - 1].Suit = C.Suit;
        if (Pass = 0) and SameSuit then
          Exit(MakeHint(hkMove, S, First, D));
        // a mixed-suit move is only worth it if the run is not already resting on a parent
        if (Pass = 1) and not SameSuit and not OnParent then
          Exit(MakeHint(hkMove, S, First, D));
      end;
    end;

  // a run into an empty column, when that uncovers something
  for D := SP_TAB0 to SP_TAB0 + 9 do
    if CardCount(D) = 0 then
      for S := SP_TAB0 to SP_TAB0 + 9 do
      begin
        if CardCount(S) = 0 then
          Continue;
        First := RunStart(S);
        if (First > 0) and not FState.Piles[S][First - 1].FaceUp then
          Exit(MakeHint(hkMove, S, First, D));
      end;
  for D := SP_TAB0 to SP_TAB0 + 9 do
    if CardCount(D) = 0 then
      for S := SP_TAB0 to SP_TAB0 + 9 do
        if (CardCount(S) > 1) and (RunStart(S) > 0) then
          Exit(MakeHint(hkMove, S, RunStart(S), D));

  if CanDeal then
    Result := MakeHint(hkTap, SP_STOCK, CardCount(SP_STOCK) - 1, -1);
end;

function TSpiderGame.CheckIntegrity(out Msg: string): Boolean;
var
  P, I: Integer;
  SeenUp: Boolean;
begin
  Result := inherited CheckIntegrity(Msg);
  if not Result then
    Exit;
  Result := False;
  if CardCount(SP_STOCK) mod 10 <> 0 then
  begin
    Msg := 'stock is not a whole number of deals';
    Exit;
  end;
  for P := SP_FOUND0 to SP_FOUND0 + 7 do
  begin
    if not (CardCount(P) in [0, 13]) then
    begin
      Msg := Format('finished-run pile %d has %d cards', [P, CardCount(P)]);
      Exit;
    end;
    for I := 0 to CardCount(P) - 1 do
      if (FState.Piles[P][I].Rank <> 13 - I) or (FState.Piles[P][I].Suit <> FState.Piles[P][0].Suit) then
      begin
        Msg := Format('finished-run pile %d is not King to Ace in one suit', [P]);
        Exit;
      end;
  end;
  for P := SP_TAB0 to SP_TAB0 + 9 do
  begin
    SeenUp := False;
    for I := 0 to CardCount(P) - 1 do
    begin
      if SeenUp and not FState.Piles[P][I].FaceUp then
      begin
        Msg := Format('column %d: face-down card above a face-up card', [P]);
        Exit;
      end;
      if FState.Piles[P][I].FaceUp then
        SeenUp := True;
    end;
    if (CardCount(P) > 0) and not SeenUp then
    begin
      Msg := Format('column %d: top card is face down', [P]);
      Exit;
    end;
  end;
  Msg := '';
  Result := True;
end;

end.
