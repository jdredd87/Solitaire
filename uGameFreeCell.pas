unit uGameFreeCell;

interface

uses
  System.SysUtils, System.Math, uCardGame;

const
  FC_CELL0  = 0;   // 0..3
  FC_FOUND0 = 4;   // 4..7
  FC_TAB0   = 8;   // 8..15

type
  TFreeCellGame = class(TCardGame)
  private
    function IsRun(P, Index: Integer): Boolean;
    function MaxMovable(Dst: Integer): Integer;
    function FindFoundationMove(out Src, Dst: Integer): Boolean;
    function SitsOnParent(P, Index: Integer): Boolean;
  protected
    procedure Deal(const Deck: TCards); override;
    procedure DoMove(Src, Index, Dst: Integer); override;
  public
    class function GameId: string; override;
    class function Title: string; override;
    class function Blurb: string; override;
    class function Rules: string; override;

    function PileCount: Integer; override;
    function PileKind(P: Integer): TPileKind; override;
    procedure GetLayout(Wide: Boolean; out Cols, Rows: Single); override;
    function PileSlot(P: Integer; Wide: Boolean): TPileSlot; override;
    function FoundationsBuildUp: Boolean; override;
    function StatusExtra: string; override;

    function CanPickUp(P, Index: Integer): Boolean; override;
    function CanDrop(Src, Index, Dst: Integer): Boolean; override;
    function FindAutoMove(Src, Index: Integer; out Dst: Integer): Boolean; override;
    function CanAutoComplete: Boolean; override;
    function AutoStep: Boolean; override;
    function IsWon: Boolean; override;
    function Hint: THint; override;
    function CheckIntegrity(out Msg: string): Boolean; override;
  end;

implementation

class function TFreeCellGame.GameId: string;
begin
  Result := 'freecell';
end;

class function TFreeCellGame.Title: string;
begin
  Result := 'FreeCell';
end;

class function TFreeCellGame.Blurb: string;
begin
  Result := 'All cards face up. Four free cells. Nearly every deal can be won.';
end;

class function TFreeCellGame.Rules: string;
begin
  Result :=
    '# Goal' + sLineBreak +
    'Move all 52 cards onto the four foundations, one suit on each, built upwards from Ace to King.' + sLineBreak +
    '# The table' + sLineBreak +
    '- All 52 cards are dealt face up into eight columns, so nothing is hidden.' + sLineBreak +
    '- The four empty spaces at the top left are the free cells. Each can hold one card of any kind.' + sLineBreak +
    '- The four spaces marked A are the foundations.' + sLineBreak +
    '# How to play' + sLineBreak +
    '- Only the last card of a column, or a card in a free cell, can be moved.' + sLineBreak +
    '- In the columns, build downwards in alternating colours: a red 6 goes on a black 7.' + sLineBreak +
    '- Any card may be placed in an empty column or in an empty free cell.' + sLineBreak +
    '- Start each foundation with its Ace and add the same suit in order.' + sLineBreak +
    '# Moving several cards' + sLineBreak +
    'Strictly you move one card at a time, but the game lets you drag an ordered run as a shortcut, as long as there are enough empty free cells and empty columns to have done it one card at a time. With no empty columns you can move one more card than you have empty free cells. Each empty column doubles that number.' + sLineBreak +
    '# Controls' + sLineBreak +
    '- Tap a card to send it to the best place, or drag it yourself.' + sLineBreak +
    '- Undo takes back one move at a time. Hint shows a move you can make.' + sLineBreak +
    '# Tips' + sLineBreak +
    '- Free cells are precious. Every card parked in one makes the next move harder, so empty them again as soon as you can.' + sLineBreak +
    '- Look for the Aces and low cards first and plan how to dig them out.' + sLineBreak +
    '- An empty column is worth more than a free cell: it can take a whole run.' + sLineBreak +
    '- Think a few moves ahead before you fill the last free cell.' + sLineBreak +
    '# Scoring' + sLineBreak +
    'Each card moved to a foundation scores 10.';
end;

function TFreeCellGame.PileCount: Integer;
begin
  Result := 16;
end;

function TFreeCellGame.PileKind(P: Integer): TPileKind;
begin
  if P < FC_FOUND0 then
    Result := pkCell
  else if P < FC_TAB0 then
    Result := pkFoundation
  else
    Result := pkTableau;
end;

procedure TFreeCellGame.GetLayout(Wide: Boolean; out Cols, Rows: Single);
begin
  if Wide then
  begin
    Cols := 12;
    Rows := 2.6;
  end
  else
  begin
    Cols := 8;
    Rows := 4.4;
  end;
end;

function TFreeCellGame.PileSlot(P: Integer; Wide: Boolean): TPileSlot;
var
  I: Integer;
begin
  Result.X := 0;
  Result.Y := 0;
  Result.Fan := fnNone;
  if Wide then
    case PileKind(P) of
      pkCell:
        begin
          I := P - FC_CELL0;
          Result.X := I mod 2;
          Result.Y := (I div 2) * 1.09;
        end;
      pkFoundation:
        begin
          I := P - FC_FOUND0;
          Result.X := 10 + (I mod 2);
          Result.Y := (I div 2) * 1.09;
        end;
      pkTableau:
        begin
          Result.X := 2 + (P - FC_TAB0);
          Result.Fan := fnDown;
        end;
    end
  else
    case PileKind(P) of
      pkCell:
        Result.X := P - FC_CELL0;
      pkFoundation:
        Result.X := 4 + (P - FC_FOUND0);
      pkTableau:
        begin
          Result.X := P - FC_TAB0;
          Result.Y := 1.17;
          Result.Fan := fnDown;
        end;
    end;
end;

function TFreeCellGame.FoundationsBuildUp: Boolean;
begin
  Result := True;
end;

function TFreeCellGame.StatusExtra: string;
var
  P, N: Integer;
begin
  N := 0;
  for P := FC_CELL0 to FC_CELL0 + 3 do
    if CardCount(P) = 0 then
      Inc(N);
  Result := Format('Free cells %d', [N]);
end;

procedure TFreeCellGame.Deal(const Deck: TCards);
var
  I: Integer;
  C: TCard;
begin
  for I := 0 to High(Deck) do
  begin
    C := Deck[I];
    C.FaceUp := True;
    Push(FC_TAB0 + (I mod 8), C);
  end;
end;

/// Cards P[Index..] form a descending run of alternating colours.
function TFreeCellGame.IsRun(P, Index: Integer): Boolean;
var
  I: Integer;
begin
  for I := Index + 1 to CardCount(P) - 1 do
    if (FState.Piles[P][I].IsRed = FState.Piles[P][I - 1].IsRed) or
      (FState.Piles[P][I].Rank + 1 <> FState.Piles[P][I - 1].Rank) then
      Exit(False);
  Result := True;
end;

/// Longest run that the empty cells and columns allow to be moved to Dst.
function TFreeCellGame.MaxMovable(Dst: Integer): Integer;
var
  P, Cells, Cols: Integer;
begin
  Cells := 0;
  Cols := 0;
  for P := FC_CELL0 to FC_CELL0 + 3 do
    if CardCount(P) = 0 then
      Inc(Cells);
  for P := FC_TAB0 to FC_TAB0 + 7 do
    if (CardCount(P) = 0) and (P <> Dst) then
      Inc(Cols);
  Result := (Cells + 1) shl Cols;
end;

function TFreeCellGame.CanPickUp(P, Index: Integer): Boolean;
var
  N: Integer;
begin
  Result := False;
  if (P < 0) or (P >= PileCount) then
    Exit;
  N := CardCount(P);
  if (Index < 0) or (Index >= N) then
    Exit;
  case PileKind(P) of
    pkCell, pkFoundation:
      Result := Index = N - 1;
    pkTableau:
      Result := IsRun(P, Index);
  end;
end;

function TFreeCellGame.CanDrop(Src, Index, Dst: Integer): Boolean;
var
  C, T: TCard;
  N, DN: Integer;
begin
  Result := False;
  if (Src = Dst) or (Dst < 0) or (Dst >= PileCount) or not CanPickUp(Src, Index) then
    Exit;
  C := FState.Piles[Src][Index];
  N := CardCount(Src) - Index;
  DN := CardCount(Dst);
  case PileKind(Dst) of
    pkCell:
      Result := (N = 1) and (DN = 0);
    pkFoundation:
      begin
        if N <> 1 then
          Exit;
        if DN = 0 then
          Result := C.Rank = 1
        else
        begin
          T := FState.Piles[Dst][DN - 1];
          Result := (T.Suit = C.Suit) and (T.Rank + 1 = C.Rank);
        end;
      end;
    pkTableau:
      begin
        if N > MaxMovable(Dst) then
          Exit;
        if DN = 0 then
          Result := True
        else
        begin
          T := FState.Piles[Dst][DN - 1];
          Result := (T.IsRed <> C.IsRed) and (T.Rank = C.Rank + 1);
        end;
      end;
  end;
end;

procedure TFreeCellGame.DoMove(Src, Index, Dst: Integer);
begin
  Transfer(Src, Index, Dst);
  if PileKind(Dst) = pkFoundation then
    AddScore(10)
  else if PileKind(Src) = pkFoundation then
    AddScore(-10);
end;

function TFreeCellGame.FindFoundationMove(out Src, Dst: Integer): Boolean;
var
  S, P, N: Integer;
begin
  Result := False;
  Src := -1;
  Dst := -1;
  for S := 0 to PileCount - 1 do
  begin
    if PileKind(S) = pkFoundation then
      Continue;
    N := CardCount(S);
    if N = 0 then
      Continue;
    for P := FC_FOUND0 to FC_FOUND0 + 3 do
      if CanDrop(S, N - 1, P) then
      begin
        Src := S;
        Dst := P;
        Exit(True);
      end;
  end;
end;

/// The card already rests on a card it could legally be built on.
function TFreeCellGame.SitsOnParent(P, Index: Integer): Boolean;
begin
  Result := (PileKind(P) = pkTableau) and (Index > 0) and
    (FState.Piles[P][Index - 1].IsRed <> FState.Piles[P][Index].IsRed) and
    (FState.Piles[P][Index - 1].Rank = FState.Piles[P][Index].Rank + 1);
end;

function TFreeCellGame.FindAutoMove(Src, Index: Integer; out Dst: Integer): Boolean;
var
  P: Integer;
begin
  Result := False;
  Dst := -1;
  if not CanPickUp(Src, Index) then
    Exit;
  if PileKind(Src) <> pkFoundation then
    for P := FC_FOUND0 to FC_FOUND0 + 3 do
      if CanDrop(Src, Index, P) then
      begin
        Dst := P;
        Exit(True);
      end;
  for P := FC_TAB0 to FC_TAB0 + 7 do
    if (CardCount(P) > 0) and CanDrop(Src, Index, P) then
    begin
      Dst := P;
      Exit(True);
    end;
  // an empty column, unless the cards already fill a column on their own
  if not ((PileKind(Src) = pkTableau) and (Index = 0)) then
    for P := FC_TAB0 to FC_TAB0 + 7 do
      if (CardCount(P) = 0) and CanDrop(Src, Index, P) then
      begin
        Dst := P;
        Exit(True);
      end;
  if PileKind(Src) = pkTableau then
    for P := FC_CELL0 to FC_CELL0 + 3 do
      if CanDrop(Src, Index, P) then
      begin
        Dst := P;
        Exit(True);
      end;
end;

{ Once every column is in descending order nothing can be trapped any more:
  the lowest card still in play is always on top of a column or in a cell. }
function TFreeCellGame.CanAutoComplete: Boolean;
var
  P, I: Integer;
begin
  Result := False;
  if IsWon then
    Exit;
  for P := FC_TAB0 to FC_TAB0 + 7 do
    for I := 1 to CardCount(P) - 1 do
      if FState.Piles[P][I].Rank > FState.Piles[P][I - 1].Rank then
        Exit;
  Result := True;
end;

function TFreeCellGame.AutoStep: Boolean;
var
  S, D: Integer;
begin
  Result := FindFoundationMove(S, D) and MoveCards(S, CardCount(S) - 1, D);
end;

function TFreeCellGame.IsWon: Boolean;
var
  P: Integer;
begin
  for P := FC_FOUND0 to FC_FOUND0 + 3 do
    if CardCount(P) <> 13 then
      Exit(False);
  Result := True;
end;

function TFreeCellGame.Hint: THint;
var
  S, D, N, I, First: Integer;
begin
  Result := MakeHint(hkNone, -1, -1, -1);
  if IsWon then
    Exit;

  // 1. a card to a foundation
  if FindFoundationMove(S, D) then
    Exit(MakeHint(hkMove, S, CardCount(S) - 1, D));

  // 2. a free-cell card back onto a column
  for S := FC_CELL0 to FC_CELL0 + 3 do
    if CardCount(S) = 1 then
      for D := FC_TAB0 to FC_TAB0 + 7 do
        if (CardCount(D) > 0) and CanDrop(S, 0, D) then
          Exit(MakeHint(hkMove, S, 0, D));

  // 3. the longest run of a column onto another column, if it is not built there already
  for S := FC_TAB0 to FC_TAB0 + 7 do
  begin
    N := CardCount(S);
    if N = 0 then
      Continue;
    First := N - 1;
    while (First > 0) and IsRun(S, First - 1) do
      Dec(First);
    if SitsOnParent(S, First) then
      Continue;
    for I := First to N - 1 do
      for D := FC_TAB0 to FC_TAB0 + 7 do
        if (D <> S) and (CardCount(D) > 0) and CanDrop(S, I, D) and not SitsOnParent(S, I) then
          Exit(MakeHint(hkMove, S, I, D));
  end;

  // 4. a free-cell card into an empty column
  for S := FC_CELL0 to FC_CELL0 + 3 do
    if CardCount(S) = 1 then
      for D := FC_TAB0 to FC_TAB0 + 7 do
        if (CardCount(D) = 0) and CanDrop(S, 0, D) then
          Exit(MakeHint(hkMove, S, 0, D));

  // 5. park the top card of the shortest column in a free cell
  D := -1;
  for I := FC_CELL0 to FC_CELL0 + 3 do
    if CardCount(I) = 0 then
    begin
      D := I;
      Break;
    end;
  if D >= 0 then
  begin
    First := -1;
    for S := FC_TAB0 to FC_TAB0 + 7 do
      if (CardCount(S) > 0) and ((First < 0) or (CardCount(S) < CardCount(First))) then
        First := S;
    if First >= 0 then
      Result := MakeHint(hkMove, First, CardCount(First) - 1, D);
  end;
end;

function TFreeCellGame.CheckIntegrity(out Msg: string): Boolean;
var
  P, I: Integer;
  C: TCard;
begin
  Result := inherited CheckIntegrity(Msg);
  if not Result then
    Exit;
  Result := False;
  for P := 0 to PileCount - 1 do
    for I := 0 to CardCount(P) - 1 do
    begin
      C := FState.Piles[P][I];
      if not C.FaceUp then
      begin
        Msg := Format('pile %d: face-down card', [P]);
        Exit;
      end;
      if (PileKind(P) = pkFoundation) and ((C.Rank <> I + 1) or (C.Suit <> FState.Piles[P][0].Suit)) then
      begin
        Msg := Format('foundation %d out of order', [P]);
        Exit;
      end;
    end;
  Msg := '';
  Result := True;
end;

end.
