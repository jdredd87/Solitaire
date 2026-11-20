unit uCardGame;

{ Shared engine for all the solitaire variants. A game is a set of piles; each
  variant (uGameKlondike, uGameSpider, ...) supplies the deal, the rules, where
  its piles sit on the table, a hint and its rules text. No UI dependencies. }

interface

uses
  System.SysUtils, System.Classes, System.Math, System.Generics.Collections;

type
  TSuit = (suClubs, suDiamonds, suHearts, suSpades);

  TCard = record
    Suit: TSuit;
    Rank: Byte;        // 1 = Ace .. 13 = King
    FaceUp: Boolean;
    Id: Byte;          // unique per physical card in the deal (0..DeckSize-1)
    function IsRed: Boolean;
  end;
  TCards = TArray<TCard>;

  /// pkSpot = one fixed position holding at most one card (Pyramid, TriPeaks)
  TPileKind = (pkStock, pkWaste, pkFoundation, pkTableau, pkCell, pkSpot);
  TFan = (fnNone, fnDown, fnRight);

  /// Where a pile sits: X in card columns, Y in card heights.
  TPileSlot = record
    X, Y: Single;
    Fan: TFan;
  end;

  THintKind = (hkNone, hkMove, hkTap);
  THint = record
    Kind: THintKind;
    Src, Index, Dst: Integer;   // hkMove: drag Src[Index..] to Dst; hkTap: tap Src[Index]
  end;

  TGameState = record
    Piles: TArray<TCards>;
    Score: Integer;
    Moves: Integer;
    Extra: array[0..3] of Integer;   // per-game counters (redeals used, streak, ...)
  end;

  TCardGame = class
  private
    FUndo: TList<TGameState>;
    FVariant: Integer;
    FSeconds: Integer;
    FCounted: Boolean;
    FWinRecorded: Boolean;
    function CloneState(const S: TGameState): TGameState;
  protected
    FState: TGameState;
    procedure PushUndo;
    procedure AddScore(Delta: Integer);
    procedure Push(P: Integer; const C: TCard);
    /// Moves cards Src[Index..] onto Dst without any rule checks.
    procedure Transfer(Src, Index, Dst: Integer);
    /// Turns the top card of P face up. True if it was face down.
    function FlipTop(P: Integer): Boolean;
    function TopCard(P: Integer; out C: TCard): Boolean;

    function BuildDeck: TCards; virtual;
    procedure Deal(const Deck: TCards); virtual; abstract;
    procedure DoMove(Src, Index, Dst: Integer); virtual;
    procedure AfterMove; virtual;
    procedure ClearTransient; virtual;
    function DealStock: Boolean; virtual;
    function MakeHint(AKind: THintKind; ASrc, AIndex, ADst: Integer): THint;
  public
    constructor Create; virtual;
    destructor Destroy; override;

    { --- description --- }
    class function GameId: string; virtual; abstract;       // 'klondike'
    class function Title: string; virtual; abstract;        // 'Klondike'
    class function Blurb: string; virtual; abstract;        // one line for the game picker
    class function VariantLabel: string; virtual;           // 'Cards per draw'; '' = no variants
    class function VariantCount: Integer; virtual;
    class function VariantName(V: Integer): string; virtual;
    /// Rules text. Lines starting with '# ' are headings, '- ' are bullet points.
    class function Rules: string; virtual; abstract;

    { --- lifecycle --- }
    /// Deals a new game. A Seed >= 0 gives a repeatable deal.
    procedure NewGame(AVariant: Integer; ASeed: Integer = -1);
    /// Test support: replace the whole layout (clears undo history).
    procedure SetLayout(const APiles: array of TCards; AVariant: Integer);
    function CanUndo: Boolean;
    function Undo: Boolean;
    procedure SaveToStream(S: TStream);
    function LoadFromStream(S: TStream): Boolean;

    { --- piles --- }
    function PileCount: Integer; virtual; abstract;
    function PileKind(P: Integer): TPileKind; virtual; abstract;
    function CardCount(P: Integer): Integer;
    function CardAt(P, Index: Integer): TCard;
    function DeckSize: Integer;
    function FirstPile(Kind: TPileKind): Integer;
    function CountPiles(Kind: TPileKind): Integer;

    { --- table layout (used by the board) --- }
    function HasWideLayout: Boolean; virtual;
    /// The wide arrangement is used when its cards, times this, beat the other one.
    function WideBias: Single; virtual;
    /// Size of the table: Cols card columns across, Rows card heights down.
    procedure GetLayout(Wide: Boolean; out Cols, Rows: Single); virtual; abstract;
    function PileSlot(P: Integer; Wide: Boolean): TPileSlot; virtual; abstract;
    /// How many of a fanned pile's top cards are spread out; 0 = the whole pile.
    function FanLimit(P: Integer): Integer; virtual;
    function ShowEmptySlot(P: Integer; Wide: Boolean): Boolean; virtual;
    /// True when foundations are built Ace upwards (drawn with an "A" marker).
    function FoundationsBuildUp: Boolean; virtual;
    function StockCanRecycle: Boolean; virtual;
    function IsSelected(P, Index: Integer): Boolean; virtual;
    /// Extra text for the status line, e.g. 'Stock 12'.
    function StatusExtra: string; virtual;

    { --- rules --- }
    function CanPickUp(P, Index: Integer): Boolean; virtual; abstract;
    function CanDrop(Src, Index, Dst: Integer): Boolean; virtual; abstract;
    function MoveCards(Src, Index, Dst: Integer): Boolean;
    /// A tap/click on a pile (Index = -1: its empty slot). True if something changed.
    function Tap(P, Index: Integer): Boolean; virtual;
    function FindAutoMove(Src, Index: Integer; out Dst: Integer): Boolean; virtual;
    function CanAutoComplete: Boolean; virtual;
    /// Plays one automatic finishing move. Only called while CanAutoComplete.
    function AutoStep: Boolean; virtual;
    function IsWon: Boolean; virtual; abstract;
    /// True when the game can prove there is no legal move left.
    function IsStuck: Boolean; virtual;
    /// A suggested next move (hkNone when the game has nothing to suggest).
    function Hint: THint; virtual; abstract;
    /// Verifies the deck and the game's own ordering invariants.
    function CheckIntegrity(out Msg: string): Boolean; virtual;
    /// Fingerprint of the card positions only (not score/moves); for loop detection.
    function LayoutHash: string;

    property Variant: Integer read FVariant;
    property Score: Integer read FState.Score;
    property Moves: Integer read FState.Moves;
    property Seconds: Integer read FSeconds write FSeconds;
    /// True once this deal has been counted as "played" in the statistics.
    property Counted: Boolean read FCounted write FCounted;
    property WinRecorded: Boolean read FWinRecorded write FWinRecorded;
  end;

  TCardGameClass = class of TCardGame;

function FormatGameTime(Seconds: Integer): string;
function RankName(Rank: Integer): string;

implementation

const
  SAVE_MAGIC = $324C4F53; // 'SOL2'

function FormatGameTime(Seconds: Integer): string;
begin
  if Seconds < 0 then
    Seconds := 0;
  if Seconds >= 3600 then
    Result := Format('%d:%.2d:%.2d', [Seconds div 3600, (Seconds div 60) mod 60, Seconds mod 60])
  else
    Result := Format('%d:%.2d', [Seconds div 60, Seconds mod 60]);
end;

function RankName(Rank: Integer): string;
const
  N: array[1..13] of string = ('A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K');
begin
  if (Rank >= 1) and (Rank <= 13) then
    Result := N[Rank]
  else
    Result := '?';
end;

{ TCard }

function TCard.IsRed: Boolean;
begin
  Result := Suit in [suDiamonds, suHearts];
end;

{ TCardGame }

constructor TCardGame.Create;
begin
  inherited Create;
  FUndo := TList<TGameState>.Create;
  NewGame(0);
end;

destructor TCardGame.Destroy;
begin
  FUndo.Free;
  inherited;
end;

class function TCardGame.VariantLabel: string;
begin
  Result := '';
end;

class function TCardGame.VariantCount: Integer;
begin
  Result := 1;
end;

class function TCardGame.VariantName(V: Integer): string;
begin
  Result := Title;
end;

function TCardGame.CloneState(const S: TGameState): TGameState;
var
  I: Integer;
begin
  SetLength(Result.Piles, Length(S.Piles));
  for I := 0 to High(S.Piles) do
    Result.Piles[I] := Copy(S.Piles[I]);
  Result.Score := S.Score;
  Result.Moves := S.Moves;
  Result.Extra := S.Extra;
end;

procedure TCardGame.PushUndo;
begin
  FUndo.Add(CloneState(FState));
end;

procedure TCardGame.AddScore(Delta: Integer);
begin
  FState.Score := Max(0, FState.Score + Delta);
end;

procedure TCardGame.Push(P: Integer; const C: TCard);
var
  N: Integer;
begin
  N := Length(FState.Piles[P]);
  SetLength(FState.Piles[P], N + 1);
  FState.Piles[P][N] := C;
end;

procedure TCardGame.Transfer(Src, Index, Dst: Integer);
var
  I, N: Integer;
begin
  N := CardCount(Src);
  for I := Index to N - 1 do
    Push(Dst, FState.Piles[Src][I]);
  SetLength(FState.Piles[Src], Index);
end;

function TCardGame.FlipTop(P: Integer): Boolean;
var
  N: Integer;
begin
  N := CardCount(P);
  Result := (N > 0) and not FState.Piles[P][N - 1].FaceUp;
  if Result then
    FState.Piles[P][N - 1].FaceUp := True;
end;

function TCardGame.TopCard(P: Integer; out C: TCard): Boolean;
var
  N: Integer;
begin
  N := CardCount(P);
  Result := N > 0;
  if Result then
    C := FState.Piles[P][N - 1];
end;

function TCardGame.MakeHint(AKind: THintKind; ASrc, AIndex, ADst: Integer): THint;
begin
  Result.Kind := AKind;
  Result.Src := ASrc;
  Result.Index := AIndex;
  Result.Dst := ADst;
end;

function TCardGame.BuildDeck: TCards;
var
  S: TSuit;
  R, K: Integer;
begin
  SetLength(Result, 52);
  K := 0;
  for S := Low(TSuit) to High(TSuit) do
    for R := 1 to 13 do
    begin
      Result[K].Suit := S;
      Result[K].Rank := R;
      Result[K].FaceUp := False;
      Inc(K);
    end;
end;

function TCardGame.DeckSize: Integer;
begin
  Result := Length(BuildDeck);
end;

procedure TCardGame.ClearTransient;
begin
end;

procedure TCardGame.NewGame(AVariant: Integer; ASeed: Integer);
var
  Deck: TCards;
  I, J: Integer;
  T: TCard;
begin
  if ASeed >= 0 then
    RandSeed := ASeed;
  FVariant := EnsureRange(AVariant, 0, VariantCount - 1);
  FUndo.Clear;
  FSeconds := 0;
  FCounted := False;
  FWinRecorded := False;
  FState := Default(TGameState);
  SetLength(FState.Piles, PileCount);
  ClearTransient;

  Deck := BuildDeck;
  for I := High(Deck) downto 1 do
  begin
    J := Random(I + 1);
    T := Deck[I];
    Deck[I] := Deck[J];
    Deck[J] := T;
  end;
  for I := 0 to High(Deck) do
    Deck[I].Id := I;
  Deal(Deck);
end;

procedure TCardGame.SetLayout(const APiles: array of TCards; AVariant: Integer);
var
  I, J, K: Integer;
begin
  FVariant := EnsureRange(AVariant, 0, VariantCount - 1);
  FUndo.Clear;
  FSeconds := 0;
  FCounted := False;
  FWinRecorded := False;
  FState := Default(TGameState);
  SetLength(FState.Piles, PileCount);
  ClearTransient;
  K := 0;
  for I := 0 to PileCount - 1 do
    if I <= High(APiles) then
    begin
      FState.Piles[I] := Copy(APiles[I]);
      for J := 0 to High(FState.Piles[I]) do
      begin
        FState.Piles[I][J].Id := K;   // ids only have to be unique
        Inc(K);
      end;
    end;
end;

function TCardGame.CardCount(P: Integer): Integer;
begin
  Result := Length(FState.Piles[P]);
end;

function TCardGame.CardAt(P, Index: Integer): TCard;
begin
  Result := FState.Piles[P][Index];
end;

function TCardGame.FirstPile(Kind: TPileKind): Integer;
var
  P: Integer;
begin
  for P := 0 to PileCount - 1 do
    if PileKind(P) = Kind then
      Exit(P);
  Result := -1;
end;

function TCardGame.CountPiles(Kind: TPileKind): Integer;
var
  P: Integer;
begin
  Result := 0;
  for P := 0 to PileCount - 1 do
    if PileKind(P) = Kind then
      Inc(Result);
end;

function TCardGame.HasWideLayout: Boolean;
begin
  Result := True;
end;

function TCardGame.WideBias: Single;
begin
  Result := 0.97;   // by default: whichever gives clearly bigger cards
end;

function TCardGame.FanLimit(P: Integer): Integer;
begin
  Result := 0;
end;

function TCardGame.ShowEmptySlot(P: Integer; Wide: Boolean): Boolean;
begin
  Result := PileKind(P) <> pkSpot;
end;

function TCardGame.FoundationsBuildUp: Boolean;
begin
  Result := False;
end;

function TCardGame.StockCanRecycle: Boolean;
begin
  Result := False;
end;

function TCardGame.IsSelected(P, Index: Integer): Boolean;
begin
  Result := False;
end;

function TCardGame.StatusExtra: string;
begin
  Result := '';
end;

procedure TCardGame.DoMove(Src, Index, Dst: Integer);
begin
  Transfer(Src, Index, Dst);
end;

procedure TCardGame.AfterMove;
begin
end;

function TCardGame.DealStock: Boolean;
begin
  Result := False;
end;

function TCardGame.MoveCards(Src, Index, Dst: Integer): Boolean;
begin
  Result := CanDrop(Src, Index, Dst);
  if not Result then
    Exit;
  PushUndo;
  ClearTransient;
  DoMove(Src, Index, Dst);
  Inc(FState.Moves);
  AfterMove;
end;

function TCardGame.Tap(P, Index: Integer): Boolean;
var
  Dst: Integer;
begin
  if (P < 0) or (P >= PileCount) then
    Exit(False);
  if PileKind(P) = pkStock then
    Exit(DealStock);
  Result := (Index >= 0) and FindAutoMove(P, Index, Dst) and MoveCards(P, Index, Dst);
end;

function TCardGame.FindAutoMove(Src, Index: Integer; out Dst: Integer): Boolean;
begin
  Dst := -1;
  Result := False;
end;

function TCardGame.CanAutoComplete: Boolean;
begin
  Result := False;
end;

function TCardGame.AutoStep: Boolean;
begin
  Result := False;
end;

function TCardGame.IsStuck: Boolean;
begin
  Result := False;
end;

function TCardGame.CanUndo: Boolean;
begin
  Result := (FUndo.Count > 0) and not IsWon;
end;

function TCardGame.Undo: Boolean;
begin
  Result := CanUndo;
  if Result then
  begin
    FState := FUndo.Last;
    FUndo.Delete(FUndo.Count - 1);
    ClearTransient;
  end;
end;

function TCardGame.CheckIntegrity(out Msg: string): Boolean;
var
  Want, Have: array[TSuit, 1..13] of Integer;
  Seen: array[Byte] of Boolean;
  Deck: TCards;
  P, I, Total: Integer;
  C: TCard;
  S: TSuit;
begin
  Result := False;
  FillChar(Want, SizeOf(Want), 0);
  FillChar(Have, SizeOf(Have), 0);
  FillChar(Seen, SizeOf(Seen), 0);
  Deck := BuildDeck;
  for I := 0 to High(Deck) do
    Inc(Want[Deck[I].Suit, Deck[I].Rank]);
  if Length(FState.Piles) <> PileCount then
  begin
    Msg := 'wrong number of piles';
    Exit;
  end;
  Total := 0;
  for P := 0 to PileCount - 1 do
  begin
    if (PileKind(P) in [pkSpot, pkCell]) and (CardCount(P) > 1) then
    begin
      Msg := Format('pile %d holds more than one card', [P]);
      Exit;
    end;
    for I := 0 to CardCount(P) - 1 do
    begin
      C := FState.Piles[P][I];
      if (C.Rank < 1) or (C.Rank > 13) or (Ord(C.Suit) > 3) then
      begin
        Msg := Format('pile %d: impossible card', [P]);
        Exit;
      end;
      if Seen[C.Id] or (C.Id >= Length(Deck)) then
      begin
        Msg := Format('pile %d: duplicate or unknown card id %d', [P, C.Id]);
        Exit;
      end;
      Seen[C.Id] := True;
      Inc(Have[C.Suit, C.Rank]);
      Inc(Total);
    end;
  end;
  if Total <> Length(Deck) then
  begin
    Msg := Format('%d cards on the table, expected %d', [Total, Length(Deck)]);
    Exit;
  end;
  for S := Low(TSuit) to High(TSuit) do
    for I := 1 to 13 do
      if Have[S, I] <> Want[S, I] then
      begin
        Msg := Format('wrong number of %s of suit %d', [RankName(I), Ord(S)]);
        Exit;
      end;
  Msg := '';
  Result := True;
end;

function TCardGame.LayoutHash: string;
var
  SB: TStringBuilder;
  P, I: Integer;
  C: TCard;
begin
  SB := TStringBuilder.Create;
  try
    for P := 0 to PileCount - 1 do
    begin
      for I := 0 to CardCount(P) - 1 do
      begin
        C := FState.Piles[P][I];
        SB.Append(Char(Ord('A') + Ord(C.Suit) * 13 + C.Rank + Ord(C.FaceUp) * 60));
      end;
      SB.Append('|');
    end;
    SB.Append(FState.Extra[0]);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TCardGame.SaveToStream(S: TStream);
var
  W: TBinaryWriter;
  P, I: Integer;
  C: TCard;
begin
  W := TBinaryWriter.Create(S);
  try
    W.Write(Integer(SAVE_MAGIC));
    W.Write(GameId);
    W.Write(Integer(FVariant));
    W.Write(Integer(FState.Score));
    W.Write(Integer(FState.Moves));
    W.Write(Integer(FSeconds));
    W.Write(Byte(Ord(FCounted)));
    W.Write(Byte(Ord(FWinRecorded)));
    for I := 0 to High(FState.Extra) do
      W.Write(Integer(FState.Extra[I]));
    W.Write(Integer(PileCount));
    for P := 0 to PileCount - 1 do
    begin
      W.Write(Byte(CardCount(P)));
      for I := 0 to CardCount(P) - 1 do
      begin
        C := FState.Piles[P][I];
        W.Write(Byte(C.Id));
        W.Write(Byte(Ord(C.Suit)));
        W.Write(Byte(C.Rank));
        W.Write(Byte(Ord(C.FaceUp)));
      end;
    end;
  finally
    W.Free;
  end;
end;

function TCardGame.LoadFromStream(S: TStream): Boolean;
var
  R: TBinaryReader;
  St, Old: TGameState;
  P, I, N, AVariant, ASeconds, OldVariant: Integer;
  ACounted, AWinRec: Boolean;
  C: TCard;
  B: Byte;
  Msg: string;
begin
  Result := False;
  St := Default(TGameState);
  try
    R := TBinaryReader.Create(S);
    try
      if R.ReadInteger <> SAVE_MAGIC then
        Exit;
      if R.ReadString <> GameId then
        Exit;
      AVariant := R.ReadInteger;
      St.Score := R.ReadInteger;
      St.Moves := R.ReadInteger;
      ASeconds := R.ReadInteger;
      ACounted := R.ReadByte <> 0;
      AWinRec := R.ReadByte <> 0;
      for I := 0 to High(St.Extra) do
        St.Extra[I] := R.ReadInteger;
      if (AVariant < 0) or (AVariant >= VariantCount) or (St.Score < 0) or (St.Moves < 0)
        or (ASeconds < 0) then
        Exit;
      if R.ReadInteger <> PileCount then
        Exit;
      SetLength(St.Piles, PileCount);
      for P := 0 to PileCount - 1 do
      begin
        N := R.ReadByte;
        SetLength(St.Piles[P], N);
        for I := 0 to N - 1 do
        begin
          C.Id := R.ReadByte;
          B := R.ReadByte;
          if B > 3 then
            Exit;
          C.Suit := TSuit(B);
          C.Rank := R.ReadByte;
          C.FaceUp := R.ReadByte <> 0;
          St.Piles[P][I] := C;
        end;
      end;
    finally
      R.Free;
    end;
  except
    Exit(False);
  end;

  // adopt the loaded position only if it is a legal one for this game
  Old := FState;
  OldVariant := FVariant;
  FState := St;
  FVariant := AVariant;
  if not CheckIntegrity(Msg) then
  begin
    FState := Old;
    FVariant := OldVariant;
    Exit(False);
  end;
  FSeconds := ASeconds;
  FCounted := ACounted;
  FWinRecorded := AWinRec;
  FUndo.Clear;
  ClearTransient;
  Result := True;
end;

end.
