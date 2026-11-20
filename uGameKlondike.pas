unit uGameKlondike;

interface

uses
  System.SysUtils, System.Math, uCardGame;

const
  KL_STOCK  = 0;
  KL_WASTE  = 1;
  KL_FOUND0 = 2;   // 2..5
  KL_TAB0   = 6;   // 6..12

type
  TKlondikeGame = class(TCardGame)
  protected
    procedure Deal(const Deck: TCards); override;
    procedure DoMove(Src, Index, Dst: Integer); override;
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
    function FanLimit(P: Integer): Integer; override;
    function FoundationsBuildUp: Boolean; override;
    function StockCanRecycle: Boolean; override;
    function StatusExtra: string; override;

    function DrawCount: Integer;
    function CanPickUp(P, Index: Integer): Boolean; override;
    function CanDrop(Src, Index, Dst: Integer): Boolean; override;
    function FindAutoMove(Src, Index: Integer; out Dst: Integer): Boolean; override;
    function FindFoundationMove(out Src, Dst: Integer): Boolean;
    function CanAutoComplete: Boolean; override;
    function AutoStep: Boolean; override;
    function IsWon: Boolean; override;
    function Hint: THint; override;
    function CheckIntegrity(out Msg: string): Boolean; override;
  end;

implementation

class function TKlondikeGame.GameId: string;
begin
  Result := 'klondike';
end;

class function TKlondikeGame.Title: string;
begin
  Result := 'Klondike';
end;

class function TKlondikeGame.Blurb: string;
begin
  Result := 'The classic. Build four suits from Ace to King.';
end;

class function TKlondikeGame.VariantLabel: string;
begin
  Result := 'Cards per draw';
end;

class function TKlondikeGame.VariantCount: Integer;
begin
  Result := 2;
end;

class function TKlondikeGame.VariantName(V: Integer): string;
begin
  if V = 1 then
    Result := 'Draw 3'
  else
    Result := 'Draw 1';
end;

class function TKlondikeGame.Rules: string;
begin
  Result :=
    '# Goal' + sLineBreak +
    'Move all 52 cards onto the four foundations, one suit on each, built upwards from Ace to King.' + sLineBreak +
    '# The table' + sLineBreak +
    '- Seven columns hold 28 cards. Only the last card of each column starts face up.' + sLineBreak +
    '- The rest of the deck is the stock (top left). Tap it to turn cards onto the waste pile beside it.' + sLineBreak +
    '- The four empty spaces marked A are the foundations.' + sLineBreak +
    '# How to play' + sLineBreak +
    '- In the columns, build downwards in alternating colours: a red 7 goes on a black 8, a black Jack on a red Queen.' + sLineBreak +
    '- You can move a whole face-up run at once by dragging its highest card.' + sLineBreak +
    '- When a face-down card is uncovered it turns over automatically.' + sLineBreak +
    '- Only a King (or a run starting with a King) may be placed in an empty column.' + sLineBreak +
    '- The top card of the waste pile can be played to a column or a foundation.' + sLineBreak +
    '- Start each foundation with its Ace, then add the 2, 3 and so on of the same suit.' + sLineBreak +
    '- When the stock runs out, tap the empty space to turn the waste pile over and go through it again.' + sLineBreak +
    '# Controls' + sLineBreak +
    '- Tap a card to send it to the best place automatically, or drag it yourself.' + sLineBreak +
    '- Undo takes back one move at a time. Hint shows a move you can make.' + sLineBreak +
    '# Draw 1 or Draw 3' + sLineBreak +
    'Draw 1 turns one stock card at a time and is easier. Draw 3 turns three, and only the top one can be played, so it takes more planning.' + sLineBreak +
    '# Tips' + sLineBreak +
    '- Turn over face-down cards whenever you can, starting with the longest columns.' + sLineBreak +
    '- Do not empty a column unless you have a King ready to fill it.' + sLineBreak +
    '- Aces and 2s can always go straight to the foundations.' + sLineBreak +
    '# Scoring' + sLineBreak +
    'Card to a foundation +10, waste to a column +5, turning a card over +5, taking a card back off a foundation -15, turning the waste over -100 (Draw 1) or -20 (Draw 3).';
end;

function TKlondikeGame.PileCount: Integer;
begin
  Result := 13;
end;

function TKlondikeGame.PileKind(P: Integer): TPileKind;
begin
  if P = KL_STOCK then
    Result := pkStock
  else if P = KL_WASTE then
    Result := pkWaste
  else if P < KL_TAB0 then
    Result := pkFoundation
  else
    Result := pkTableau;
end;

function TKlondikeGame.DrawCount: Integer;
begin
  if Variant = 1 then
    Result := 3
  else
    Result := 1;
end;

procedure TKlondikeGame.GetLayout(Wide: Boolean; out Cols, Rows: Single);
begin
  if Wide then
  begin
    Cols := 10;
    Rows := 2.6;
  end
  else
  begin
    Cols := 7;
    Rows := 4.0;
  end;
end;

function TKlondikeGame.PileSlot(P: Integer; Wide: Boolean): TPileSlot;
var
  F: Integer;
begin
  Result.X := 0;
  Result.Y := 0;
  Result.Fan := fnNone;
  if Wide then
  begin
    // stock + waste down the left, columns in the middle, foundations 2 x 2 right
    case PileKind(P) of
      pkWaste:
        begin
          Result.Y := 1.09;
          Result.Fan := fnDown;
        end;
      pkFoundation:
        begin
          F := P - KL_FOUND0;
          Result.X := 8 + (F mod 2);
          Result.Y := (F div 2) * 1.09;
        end;
      pkTableau:
        begin
          Result.X := 1 + (P - KL_TAB0);
          Result.Fan := fnDown;
        end;
    end;
  end
  else
    case PileKind(P) of
      pkWaste:
        begin
          Result.X := 1;
          Result.Fan := fnRight;
        end;
      pkFoundation:
        Result.X := 3 + (P - KL_FOUND0);
      pkTableau:
        begin
          Result.X := P - KL_TAB0;
          Result.Y := 1.17;
          Result.Fan := fnDown;
        end;
    end;
end;

function TKlondikeGame.FanLimit(P: Integer): Integer;
begin
  if P = KL_WASTE then
    Result := DrawCount
  else
    Result := 0;
end;

function TKlondikeGame.FoundationsBuildUp: Boolean;
begin
  Result := True;
end;

function TKlondikeGame.StockCanRecycle: Boolean;
begin
  Result := CardCount(KL_WASTE) > 0;
end;

function TKlondikeGame.StatusExtra: string;
begin
  Result := '';
end;

procedure TKlondikeGame.Deal(const Deck: TCards);
var
  I, J, K: Integer;
  C: TCard;
begin
  K := 0;
  for I := 0 to 6 do
    for J := 0 to I do
    begin
      C := Deck[K];
      Inc(K);
      C.FaceUp := (J = I);
      Push(KL_TAB0 + I, C);
    end;
  while K < Length(Deck) do
  begin
    Push(KL_STOCK, Deck[K]);
    Inc(K);
  end;
end;

function TKlondikeGame.CanPickUp(P, Index: Integer): Boolean;
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
    pkWaste, pkFoundation:
      Result := Index = N - 1;
    pkTableau:
      Result := FState.Piles[P][Index].FaceUp;
  end;
end;

function TKlondikeGame.CanDrop(Src, Index, Dst: Integer): Boolean;
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
      if DN = 0 then
        Result := C.Rank = 13
      else
      begin
        T := FState.Piles[Dst][DN - 1];
        Result := T.FaceUp and (T.IsRed <> C.IsRed) and (T.Rank = C.Rank + 1);
      end;
  end;
end;

procedure TKlondikeGame.DoMove(Src, Index, Dst: Integer);
begin
  Transfer(Src, Index, Dst);
  if PileKind(Dst) = pkFoundation then
    AddScore(10)
  else if PileKind(Src) = pkFoundation then
    AddScore(-15)
  else if Src = KL_WASTE then
    AddScore(5);
  if (PileKind(Src) = pkTableau) and FlipTop(Src) then
    AddScore(5);
end;

function TKlondikeGame.DealStock: Boolean;
var
  I, N, K: Integer;
  C: TCard;
begin
  Result := False;
  N := CardCount(KL_STOCK);
  if N > 0 then
  begin
    PushUndo;
    K := Min(DrawCount, N);
    for I := 1 to K do
    begin
      C := FState.Piles[KL_STOCK][N - I];
      C.FaceUp := True;
      Push(KL_WASTE, C);
    end;
    SetLength(FState.Piles[KL_STOCK], N - K);
    Inc(FState.Moves);
    Result := True;
  end
  else if CardCount(KL_WASTE) > 0 then
  begin
    PushUndo;
    for I := CardCount(KL_WASTE) - 1 downto 0 do
    begin
      C := FState.Piles[KL_WASTE][I];
      C.FaceUp := False;
      Push(KL_STOCK, C);
    end;
    FState.Piles[KL_WASTE] := nil;
    if DrawCount = 1 then
      AddScore(-100)
    else
      AddScore(-20);
    Inc(FState.Moves);
    Result := True;
  end;
end;

function TKlondikeGame.FindAutoMove(Src, Index: Integer; out Dst: Integer): Boolean;
var
  P: Integer;
begin
  Result := False;
  Dst := -1;
  if not CanPickUp(Src, Index) then
    Exit;
  if PileKind(Src) <> pkFoundation then
    for P := KL_FOUND0 to KL_FOUND0 + 3 do
      if CanDrop(Src, Index, P) then
      begin
        Dst := P;
        Exit(True);
      end;
  for P := KL_TAB0 to KL_TAB0 + 6 do
    if (CardCount(P) > 0) and CanDrop(Src, Index, P) then
    begin
      Dst := P;
      Exit(True);
    end;
  // a King already at the bottom of a column gains nothing by moving
  if not ((PileKind(Src) = pkTableau) and (Index = 0)) then
    for P := KL_TAB0 to KL_TAB0 + 6 do
      if (CardCount(P) = 0) and CanDrop(Src, Index, P) then
      begin
        Dst := P;
        Exit(True);
      end;
end;

function TKlondikeGame.FindFoundationMove(out Src, Dst: Integer): Boolean;
var
  S, P, N: Integer;
begin
  Result := False;
  Src := -1;
  Dst := -1;
  for S := KL_WASTE to PileCount - 1 do
  begin
    if PileKind(S) = pkFoundation then
      Continue;
    N := CardCount(S);
    if N = 0 then
      Continue;
    for P := KL_FOUND0 to KL_FOUND0 + 3 do
      if CanDrop(S, N - 1, P) then
      begin
        Src := S;
        Dst := P;
        Exit(True);
      end;
  end;
end;

function TKlondikeGame.CanAutoComplete: Boolean;
var
  P, I: Integer;
begin
  Result := False;
  if IsWon or (CardCount(KL_STOCK) > 0) or (CardCount(KL_WASTE) > 0) then
    Exit;
  for P := KL_TAB0 to KL_TAB0 + 6 do
    for I := 0 to CardCount(P) - 1 do
      if not FState.Piles[P][I].FaceUp then
        Exit;
  Result := True;
end;

function TKlondikeGame.AutoStep: Boolean;
var
  S, D: Integer;
begin
  Result := FindFoundationMove(S, D) and MoveCards(S, CardCount(S) - 1, D);
end;

function TKlondikeGame.IsWon: Boolean;
var
  P: Integer;
begin
  for P := KL_FOUND0 to KL_FOUND0 + 3 do
    if CardCount(P) <> 13 then
      Exit(False);
  Result := True;
end;

function TKlondikeGame.Hint: THint;
var
  S, D, N, I, First: Integer;
begin
  Result := MakeHint(hkNone, -1, -1, -1);
  if IsWon then
    Exit;

  // 1. anything that can go to a foundation
  if FindFoundationMove(S, D) then
    Exit(MakeHint(hkMove, S, CardCount(S) - 1, D));

  // 2. move a whole face-up run if that turns a card over or merges two columns
  for S := KL_TAB0 to KL_TAB0 + 6 do
  begin
    N := CardCount(S);
    if N = 0 then
      Continue;
    First := N - 1;
    for I := 0 to N - 1 do
      if FState.Piles[S][I].FaceUp then
      begin
        First := I;
        Break;
      end;
    for D := KL_TAB0 to KL_TAB0 + 6 do
    begin
      if (D = S) or not CanDrop(S, First, D) then
        Continue;
      if (First = 0) and (CardCount(D) = 0) then
        Continue;   // a run already at the bottom only moves onto another run
      Exit(MakeHint(hkMove, S, First, D));
    end;
  end;

  // 3. waste card onto a column
  N := CardCount(KL_WASTE);
  if N > 0 then
    for D := KL_TAB0 to KL_TAB0 + 6 do
      if CanDrop(KL_WASTE, N - 1, D) then
        Exit(MakeHint(hkMove, KL_WASTE, N - 1, D));

  // 4. turn the stock
  if (CardCount(KL_STOCK) > 0) or (CardCount(KL_WASTE) > 0) then
    Result := MakeHint(hkTap, KL_STOCK, CardCount(KL_STOCK) - 1, -1);
end;

function TKlondikeGame.CheckIntegrity(out Msg: string): Boolean;
var
  P, I: Integer;
  C: TCard;
  SeenUp: Boolean;
begin
  Result := inherited CheckIntegrity(Msg);
  if not Result then
    Exit;
  Result := False;
  for P := 0 to PileCount - 1 do
  begin
    SeenUp := False;
    for I := 0 to CardCount(P) - 1 do
    begin
      C := FState.Piles[P][I];
      case PileKind(P) of
        pkStock:
          if C.FaceUp then
          begin
            Msg := 'face-up card in the stock';
            Exit;
          end;
        pkWaste:
          if not C.FaceUp then
          begin
            Msg := 'face-down card in the waste';
            Exit;
          end;
        pkFoundation:
          if (not C.FaceUp) or (C.Rank <> I + 1) or (C.Suit <> FState.Piles[P][0].Suit) then
          begin
            Msg := Format('foundation %d out of order', [P]);
            Exit;
          end;
        pkTableau:
          begin
            if SeenUp and not C.FaceUp then
            begin
              Msg := Format('column %d: face-down card above a face-up card', [P]);
              Exit;
            end;
            if SeenUp and ((FState.Piles[P][I - 1].IsRed = C.IsRed) or
              (FState.Piles[P][I - 1].Rank <> C.Rank + 1)) then
            begin
              Msg := Format('column %d: broken run', [P]);
              Exit;
            end;
            if C.FaceUp then
              SeenUp := True;
            if (I = CardCount(P) - 1) and not C.FaceUp then
            begin
              Msg := Format('column %d: top card is face down', [P]);
              Exit;
            end;
          end;
      end;
    end;
  end;
  Msg := '';
  Result := True;
end;

end.
