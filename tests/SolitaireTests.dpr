program SolitaireTests;

{ Console tests for the rules engines, hints/auto-player and statistics of
  every game. Build + run with tests\run-tests.bat. Exit code 0 = all passed. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.IniFiles,
  uCardGame in '..\uCardGame.pas',
  uGameKlondike in '..\uGameKlondike.pas',
  uGameSpider in '..\uGameSpider.pas',
  uGameFreeCell in '..\uGameFreeCell.pas',
  uGamePyramid in '..\uGamePyramid.pas',
  uGameTriPeaks in '..\uGameTriPeaks.pas',
  uGames in '..\uGames.pas',
  uAutoPlay in '..\uAutoPlay.pas',
  uStats in '..\uStats.pas';

var
  Checks, Fails: Integer;

procedure Check(Cond: Boolean; const Msg: string);
begin
  Inc(Checks);
  if not Cond then
  begin
    Inc(Fails);
    Writeln('  FAIL  ', Msg);
  end;
end;

procedure Section(const Name: string);
begin
  Writeln(Name);
end;

function C(Suit: TSuit; Rank: Integer; FaceUp: Boolean = True): TCard;
begin
  Result.Suit := Suit;
  Result.Rank := Rank;
  Result.FaceUp := FaceUp;
  Result.Id := 0;
end;

function Snapshot(G: TCardGame): TBytes;
var
  M: TBytesStream;
begin
  M := TBytesStream.Create;
  try
    G.SaveToStream(M);
    Result := Copy(M.Bytes, 0, M.Size);
  finally
    M.Free;
  end;
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

function LoadBytes(G: TCardGame; const B: TBytes): Boolean;
var
  M: TBytesStream;
begin
  M := TBytesStream.Create(B);
  try
    Result := G.LoadFromStream(M);
  finally
    M.Free;
  end;
end;

function Empty(G: TCardGame): TArray<TCards>;
begin
  Result := nil;   // a function result can alias the caller's old array
  SetLength(Result, G.PileCount);
end;

/// K..A (Desc) or A..K of one suit
function SuitRun(S: TSuit; FromRank, ToRank: Integer): TCards;
var
  R, N, Step: Integer;
begin
  Result := nil;
  N := Abs(ToRank - FromRank) + 1;
  SetLength(Result, N);
  if ToRank >= FromRank then
    Step := 1
  else
    Step := -1;
  R := FromRank;
  for N := 0 to High(Result) do
  begin
    Result[N] := C(S, R);
    Inc(R, Step);
  end;
end;

/// Every card of a standard deck that is not in Used.
function Rest(const Used: array of TCard; FaceUp: Boolean): TCards;
var
  S: TSuit;
  R, I, N: Integer;
  Found: Boolean;
begin
  Result := nil;
  SetLength(Result, 52);
  N := 0;
  for S := Low(TSuit) to High(TSuit) do
    for R := 1 to 13 do
    begin
      Found := False;
      for I := 0 to High(Used) do
        if (Used[I].Suit = S) and (Used[I].Rank = R) then
          Found := True;
      if not Found then
      begin
        Result[N] := C(S, R, FaceUp);
        Inc(N);
      end;
    end;
  SetLength(Result, N);
end;

{ ---------- tests that apply to every game ---------- }

procedure TestRegistry;
var
  I, J: Integer;
  G: TCardGame;
  R: string;
begin
  Section('Game list');
  Check(Length(GAME_CLASSES) = 5, 'five games are registered');
  for I := 0 to High(GAME_CLASSES) do
  begin
    for J := I + 1 to High(GAME_CLASSES) do
      Check(GAME_CLASSES[I].GameId <> GAME_CLASSES[J].GameId, 'game ids are unique');
    Check(GameIndexOf(GAME_CLASSES[I].GameId) = I, 'game can be found by id');
    Check((GAME_CLASSES[I].Title <> '') and (GAME_CLASSES[I].Blurb <> ''), 'game has a title and description');
    R := GAME_CLASSES[I].Rules;
    Check(Pos('# Goal', R) = 1, GAME_CLASSES[I].Title + ': rules start with the goal');
    Check((Pos('# How to play', R) > 0) and (Pos('# Controls', R) > 0) and (Pos('# Tips', R) > 0),
      GAME_CLASSES[I].Title + ': rules cover play, controls and tips');
    Check(Length(R) > 600, GAME_CLASSES[I].Title + ': rules are more than a stub');
    G := GAME_CLASSES[I].Create;
    try
      for J := 0 to G.VariantCount - 1 do
        Check(G.VariantName(J) <> '', 'variant has a name');
      Check((G.VariantCount = 1) or (G.VariantLabel <> ''), 'games with variants label the choice');
    finally
      G.Free;
    end;
  end;
  Check(GameIndexOf('nonsense') = -1, 'unknown game id is not found');
end;

procedure TestGameGeneric(AClass: TCardGameClass; Seeds: Integer);
var
  G, H: TCardGame;
  P: TAutoPlayer;
  V, Seed, Steps, Wins, Total, PrevMoves, Undone, I, PileIdx, N: Integer;
  Msg: string;
  A, B, Start: TBytes;
  Cols, Rows: Single;
  Slot: TPileSlot;
  Hint: THint;
  Wide: Boolean;
begin
  for V := 0 to AClass.VariantCount - 1 do
  begin
    G := AClass.Create;
    H := AClass.Create;
    try
      Section(Format('%s (%s): %d deals', [G.Title, G.VariantName(V), Seeds]));

      // deals
      G.NewGame(V, 42);
      A := Snapshot(G);
      G.NewGame(V, 42);
      Check(SameBytes(A, Snapshot(G)), 'same seed gives the same deal');
      G.NewGame(V, 43);
      Check(not SameBytes(A, Snapshot(G)), 'different seed gives a different deal');
      Check(G.Variant = V, 'variant is stored');
      N := 0;
      for PileIdx := 0 to G.PileCount - 1 do
        Inc(N, G.CardCount(PileIdx));
      Check(N = G.DeckSize, 'every card is dealt');

      // layout description is sane in both arrangements
      for Wide := False to G.HasWideLayout do
      begin
        G.GetLayout(Wide, Cols, Rows);
        Check((Cols >= 6) and (Rows >= 2), 'layout has a size');
        for PileIdx := 0 to G.PileCount - 1 do
        begin
          Slot := G.PileSlot(PileIdx, Wide);
          Check((Slot.X >= 0) and (Slot.X <= Cols - 1 + 0.001) and (Slot.Y >= 0) and (Slot.Y <= Rows - 1 + 0.001),
            Format('pile %d sits inside the %s table', [PileIdx, BoolToStr(Wide, True)]));
        end;
      end;

      Wins := 0;
      Total := 0;
      for Seed := 1 to Seeds do
      begin
        G.NewGame(V, Seed);
        Start := Snapshot(G);
        if not G.CheckIntegrity(Msg) then
          Check(False, Format('seed %d: bad deal: %s', [Seed, Msg]));
        Check((G.Moves = 0) and not G.CanUndo and not G.IsWon, 'fresh game state');
        Hint := G.Hint;
        Check(Hint.Kind <> hkNone, Format('seed %d: a fresh deal has a hint', [Seed]));

        P := TAutoPlayer.Create(G);
        try
          Steps := 0;
          repeat
            PrevMoves := G.Moves;
            if not P.Step then
              Break;
            Inc(Steps);
            if G.Moves <> PrevMoves + 1 then
              Check(False, Format('seed %d step %d: move counter did not advance', [Seed, Steps]));
            if not G.CheckIntegrity(Msg) then
            begin
              Check(False, Format('seed %d step %d: %s', [Seed, Steps, Msg]));
              Break;
            end;
          until Steps > 5000;
          Check(Steps <= 5000, Format('seed %d: auto-player terminates', [Seed]));
          Inc(Total, Steps);

          // save / load round trip in the middle of a game
          if Seed mod 7 = 0 then
          begin
            G.Seconds := 77;
            G.Counted := True;
            B := Snapshot(G);
            H.NewGame(0, 5);
            Check(LoadBytes(H, B), Format('seed %d: saved game loads', [Seed]));
            Check(SameBytes(B, Snapshot(H)), Format('seed %d: loaded game is identical', [Seed]));
            Check((H.Seconds = 77) and H.Counted and (H.Variant = V) and (H.Moves = G.Moves)
              and (H.Score = G.Score), 'time, variant, moves and score survive');
            Check(not H.CanUndo, 'undo history starts fresh after loading');
            G.Seconds := 0;
            G.Counted := False;
          end;

          if G.IsWon then
          begin
            Inc(Wins);
            Check(G.Score > 0, 'a won game has a score');
            Check(not G.CanUndo, 'no undo after a win');
            Check(G.Hint.Kind = hkNone, 'no hint after a win');
          end
          else if Seed mod 5 = 0 then
          begin
            // unwind an unfinished game completely: must land on the original deal
            Undone := 0;
            while G.Undo do
              Inc(Undone);
            Check(Undone = Steps, Format('seed %d: every step can be undone (%d of %d)', [Seed, Undone, Steps]));
            Check(SameBytes(Start, Snapshot(G)), Format('seed %d: full undo restores the deal', [Seed]));
          end;
        finally
          P.Free;
        end;
      end;
      Writeln(Format('  auto-player won %d of %d deals (%d moves, integrity checked after each)',
        [Wins, Seeds, Total]));

      // damaged save files must be rejected and leave the game untouched
      G.NewGame(V, 9);
      A := Snapshot(G);
      Check(not LoadBytes(G, TBytes.Create(1, 2, 3, 4, 5, 6)), 'garbage is rejected');
      Check(not LoadBytes(G, Copy(A, 0, Length(A) div 2)), 'truncated file is rejected');
      Check(not LoadBytes(G, nil), 'empty file is rejected');
      B := Copy(A);
      B[Length(B) - 2] := 99;   // impossible rank on the last card
      Check(not LoadBytes(G, B), 'corrupted card data is rejected');
      B := Copy(A);
      B[Length(B) - 4] := (B[Length(B) - 4] + 1) mod G.DeckSize;   // two cards with the same id
      Check(not LoadBytes(G, B), 'duplicate card is rejected');
      Check(SameBytes(A, Snapshot(G)), 'rejected loads leave the current game untouched');
      // another game's save must not load here
      for I := 0 to High(GAME_CLASSES) do
        if GAME_CLASSES[I] <> AClass then
        begin
          H.Free;
          H := GAME_CLASSES[I].Create;
          Check(not LoadBytes(G, Snapshot(H)), 'a different game''s save is rejected');
          Break;
        end;
    finally
      H.Free;
      G.Free;
    end;
  end;
end;

{ ---------- Klondike ---------- }

procedure TestKlondike;
var
  G: TKlondikeGame;
  L: TArray<TCards>;
  Dst, I, N: Integer;
  S: TSuit;
  Top: TCard;
begin
  Section('Klondike rules');
  G := TKlondikeGame.Create;
  try
    G.NewGame(0, 7);
    Check(G.CardCount(KL_STOCK) = 24, 'stock has 24 cards');
    for I := 0 to 6 do
    begin
      Check(G.CardCount(KL_TAB0 + I) = I + 1, 'column sizes 1..7');
      Check(G.CardAt(KL_TAB0 + I, I).FaceUp and ((I = 0) or not G.CardAt(KL_TAB0 + I, 0).FaceUp),
        'only the top card is face up');
    end;

    L := Empty(G);
    L[KL_WASTE] := [C(suHearts, 1)];
    L[KL_FOUND0] := [C(suSpades, 1)];
    L[KL_TAB0] := [C(suClubs, 9, False), C(suSpades, 8), C(suHearts, 7)];
    L[KL_TAB0 + 1] := [C(suClubs, 8)];
    L[KL_TAB0 + 2] := [C(suDiamonds, 9)];
    L[KL_TAB0 + 3] := [C(suSpades, 13), C(suHearts, 12)];
    L[KL_TAB0 + 4] := [C(suSpades, 2)];
    L[KL_TAB0 + 5] := [C(suDiamonds, 2)];
    G.SetLayout(L, 0);
    Check(not G.CanPickUp(KL_TAB0, 0), 'face-down card cannot be picked up');
    Check(G.CanPickUp(KL_TAB0, 1), 'face-up run can be picked up');
    Check(not G.CanPickUp(KL_STOCK, 0), 'stock cards cannot be picked up');
    Check(G.CanDrop(KL_TAB0, 2, KL_TAB0 + 1), 'red 7 goes on black 8');
    Check(G.CanDrop(KL_TAB0, 1, KL_TAB0 + 2), 'run 8-7 goes on red 9');
    Check(not G.CanDrop(KL_TAB0 + 4, 0, KL_TAB0 + 1), '2 does not go on 8');
    Check(not G.CanDrop(KL_TAB0, 2, KL_TAB0 + 6), 'only a king goes on an empty column');
    Check(G.CanDrop(KL_TAB0 + 3, 0, KL_TAB0 + 6), 'king run goes on an empty column');
    Check(G.CanDrop(KL_WASTE, 0, KL_FOUND0 + 1), 'ace goes on an empty foundation');
    Check(not G.CanDrop(KL_WASTE, 0, KL_FOUND0), 'ace does not go on another ace');
    Check(G.CanDrop(KL_TAB0 + 4, 0, KL_FOUND0), '2 of spades goes on ace of spades');
    Check(not G.CanDrop(KL_TAB0 + 5, 0, KL_FOUND0), '2 of diamonds does not go on ace of spades');
    Check(not G.CanDrop(KL_TAB0, 1, KL_FOUND0), 'a run cannot go to a foundation');
    Check(G.FindAutoMove(KL_TAB0 + 4, 0, Dst) and (Dst = KL_FOUND0), 'tap sends the 2 to its foundation');
    Check(G.FindAutoMove(KL_TAB0, 2, Dst) and (Dst = KL_TAB0 + 1), 'tap sends the red 7 to the black 8');
    Check(not G.FindAutoMove(KL_TAB0 + 3, 0, Dst), 'a king at the bottom of a column stays put');
    Check(G.Tap(KL_TAB0 + 4, 0) and (G.CardCount(KL_FOUND0) = 2), 'Tap plays the auto-move');

    L := Empty(G);
    L[KL_TAB0] := [C(suSpades, 8)];
    L[KL_TAB0 + 1] := [C(suClubs, 7)];
    L[KL_TAB0 + 2] := [C(suHearts, 7)];
    G.SetLayout(L, 0);
    Check(not G.CanDrop(KL_TAB0 + 1, 0, KL_TAB0), 'black 7 does not go on black 8');
    Check(G.CanDrop(KL_TAB0 + 2, 0, KL_TAB0), 'red 7 goes on black 8');

    // scoring and the automatic flip
    L := Empty(G);
    L[KL_WASTE] := [C(suHearts, 1)];
    L[KL_TAB0] := [C(suClubs, 9, False), C(suSpades, 8), C(suHearts, 7)];
    L[KL_TAB0 + 2] := [C(suDiamonds, 9)];
    L[KL_TAB0 + 4] := [C(suSpades, 2)];
    G.SetLayout(L, 0);
    Check(G.MoveCards(KL_TAB0, 1, KL_TAB0 + 2) and G.CardAt(KL_TAB0, 0).FaceUp and (G.Score = 5),
      'moving a run turns the card underneath (+5)');
    Check(G.MoveCards(KL_WASTE, 0, KL_FOUND0) and (G.Score = 15), 'card to foundation scores 10');
    Check(G.MoveCards(KL_FOUND0, 0, KL_TAB0 + 4) and (G.Score = 0), 'taking a card back costs 15 (never below 0)');
    Check((not G.MoveCards(KL_TAB0 + 4, 0, KL_STOCK)) and (G.Moves = 3), 'illegal move is refused and not counted');

    // stock: draw 1, recycle, draw 3
    G.NewGame(0, 7);
    Top := G.CardAt(KL_STOCK, 23);
    Check(G.Tap(KL_STOCK, 23) and (G.CardCount(KL_WASTE) = 1) and (G.CardAt(KL_WASTE, 0).Rank = Top.Rank)
      and (G.CardAt(KL_WASTE, 0).Suit = Top.Suit) and G.CardAt(KL_WASTE, 0).FaceUp, 'draw 1 turns the stock top');
    for I := 1 to 23 do
      G.Tap(KL_STOCK, 0);
    Check((G.CardCount(KL_STOCK) = 0) and G.StockCanRecycle, 'stock exhausted, waste can be turned');
    Check(G.Tap(KL_STOCK, -1) and (G.CardCount(KL_STOCK) = 24) and (G.CardAt(KL_STOCK, 23).Rank = Top.Rank),
      'recycling keeps the order');
    G.NewGame(1, 7);
    Check((G.DrawCount = 3) and G.Tap(KL_STOCK, 0) and (G.CardCount(KL_WASTE) = 3), 'draw 3 turns three cards');
    Check(G.CanPickUp(KL_WASTE, 2) and not G.CanPickUp(KL_WASTE, 1), 'only the top waste card is playable');
    Check(G.FanLimit(KL_WASTE) = 3, 'draw 3 fans three waste cards');

    // win through auto-complete
    L := Empty(G);
    for S := Low(TSuit) to High(TSuit) do
    begin
      L[KL_FOUND0 + Ord(S)] := SuitRun(S, 1, 12);
      L[KL_TAB0 + Ord(S)] := [C(S, 13)];
    end;
    G.SetLayout(L, 0);
    Check(G.CanAutoComplete and not G.IsWon, 'auto-complete is offered when everything is face up');
    N := 0;
    while G.CanAutoComplete and G.AutoStep do
      Inc(N);
    Check((N = 4) and G.IsWon and (G.Score = 40), 'auto-complete wins the game');
    L := Empty(G);
    L[KL_TAB0] := [C(suClubs, 5, False), C(suHearts, 4)];
    G.SetLayout(L, 0);
    Check(not G.CanAutoComplete, 'a face-down card blocks auto-complete');
  finally
    G.Free;
  end;
end;

{ ---------- FreeCell ---------- }

procedure TestFreeCell;
var
  G: TFreeCellGame;
  L: TArray<TCards>;
  S: TSuit;
  I, N, Dst: Integer;
begin
  Section('FreeCell rules');
  G := TFreeCellGame.Create;
  try
    G.NewGame(0, 3);
    N := 0;
    for I := 0 to 7 do
    begin
      Inc(N, G.CardCount(FC_TAB0 + I));
      Check(G.CardCount(FC_TAB0 + I) in [6, 7], 'columns hold 6 or 7 cards');
    end;
    Check(N = 52, 'all 52 cards are in the columns');
    Check(G.CardAt(FC_TAB0, 0).FaceUp, 'every card is face up');

    L := Empty(G);
    L[FC_TAB0] := [C(suSpades, 9), C(suHearts, 8), C(suClubs, 7), C(suDiamonds, 6)];
    L[FC_TAB0 + 1] := [C(suClubs, 9)];
    L[FC_TAB0 + 2] := [C(suClubs, 3), C(suDiamonds, 9)];
    L[FC_TAB0 + 3] := [C(suHearts, 1)];
    L[FC_TAB0 + 4] := [C(suSpades, 4)];
    L[FC_TAB0 + 5] := [C(suSpades, 5)];
    L[FC_TAB0 + 6] := [C(suSpades, 6)];
    L[FC_TAB0 + 7] := [C(suSpades, 10)];
    G.SetLayout(L, 0);
    Check(G.CanPickUp(FC_TAB0, 1), 'an ordered alternating run can be picked up');
    Check(not G.CanPickUp(FC_TAB0 + 2, 0), 'cards out of order cannot be picked up together');
    // 4 free cells, no empty column: up to 5 cards
    Check(G.CanDrop(FC_TAB0, 1, FC_TAB0 + 1), 'run of three goes on a black 9 with four free cells');
    Check(not G.CanDrop(FC_TAB0, 1, FC_TAB0 + 7), 'run starting with 8 does not go on a 10');
    Check(G.CanDrop(FC_TAB0, 3, FC_CELL0), 'a single card goes to a free cell');
    Check(not G.CanDrop(FC_TAB0, 2, FC_CELL0), 'two cards do not go to a free cell');
    Check(G.CanDrop(FC_TAB0 + 3, 0, FC_FOUND0), 'ace goes to a foundation');
    Check(not G.CanDrop(FC_TAB0 + 4, 0, FC_FOUND0), 'a 4 does not start a foundation');
    Check(G.FindAutoMove(FC_TAB0 + 3, 0, Dst) and (Dst = FC_FOUND0), 'tap sends the ace up');

    // fill the cells: the allowed run length shrinks
    Check(G.MoveCards(FC_TAB0 + 4, 0, FC_CELL0) and G.MoveCards(FC_TAB0 + 5, 0, FC_CELL0 + 1)
      and G.MoveCards(FC_TAB0 + 6, 0, FC_CELL0 + 2), 'three cards parked');
    Check(not G.CanDrop(FC_TAB0 + 7, 0, FC_CELL0), 'an occupied cell is refused');
    // 1 free cell, 3 empty columns: onto the black 9 that is (1+1) * 2^3 = 16
    Check(G.CanDrop(FC_TAB0, 1, FC_TAB0 + 1), 'empty columns allow the run to move');
    Check(G.MoveCards(FC_TAB0 + 7, 0, FC_CELL0 + 3), 'last cell filled');
    // 0 free cells, 4 empty columns but the target is one of them: 1 * 2^3 = 8
    Check(G.CanDrop(FC_TAB0, 1, FC_TAB0 + 7), 'a run may move into an empty column');
    L := Empty(G);
    L[FC_CELL0] := [C(suClubs, 2)];
    L[FC_CELL0 + 1] := [C(suClubs, 4)];
    L[FC_CELL0 + 2] := [C(suClubs, 5)];
    L[FC_CELL0 + 3] := [C(suClubs, 10)];
    L[FC_TAB0] := [C(suSpades, 9), C(suHearts, 8), C(suClubs, 7)];
    L[FC_TAB0 + 1] := [C(suDiamonds, 9)];
    for I := 2 to 7 do
      L[FC_TAB0 + I] := [C(suSpades, 13 - I)];
    G.SetLayout(L, 0);
    Check(not G.CanDrop(FC_TAB0, 1, FC_TAB0 + 1), 'no free cell and no empty column: only one card moves');
    Check(G.CanDrop(FC_TAB0, 2, FC_TAB0 + 1) = False, 'a black 7 does not go on a red 9');

    // win
    L := Empty(G);
    for S := Low(TSuit) to High(TSuit) do
    begin
      L[FC_FOUND0 + Ord(S)] := SuitRun(S, 1, 12);
      L[FC_CELL0 + Ord(S)] := [C(S, 13)];
    end;
    G.SetLayout(L, 0);
    Check(G.CanAutoComplete and not G.IsWon, 'auto-complete is offered once nothing is trapped');
    N := 0;
    while G.CanAutoComplete and G.AutoStep do
      Inc(N);
    Check((N = 4) and G.IsWon, 'auto-complete wins the game');
    L := Empty(G);
    L[FC_TAB0] := [C(suClubs, 3), C(suHearts, 9)];
    G.SetLayout(L, 0);
    Check(not G.CanAutoComplete, 'a higher card on top of a lower one blocks auto-complete');
  finally
    G.Free;
  end;
end;

{ ---------- Spider ---------- }

procedure TestSpider;
var
  G: TSpiderGame;
  L: TArray<TCards>;
  I, N, Dst: Integer;
begin
  Section('Spider rules');
  G := TSpiderGame.Create;
  try
    G.NewGame(2, 5);
    Check(G.DeckSize = 104, 'two decks');
    N := 0;
    for I := 0 to 9 do
      Inc(N, G.CardCount(SP_TAB0 + I));
    Check((N = 54) and (G.CardCount(SP_STOCK) = 50), '54 cards dealt, 50 in the stock');
    Check((G.CardCount(SP_TAB0) = 6) and (G.CardCount(SP_TAB0 + 9) = 5), 'columns of 6 and 5');
    Check(G.Score = 500, 'starts with 500 points');
    Check(G.Tap(SP_STOCK, 0) and (G.CardCount(SP_STOCK) = 40) and (G.CardCount(SP_TAB0) = 7)
      and G.CardAt(SP_TAB0, 6).FaceUp, 'a deal puts one face-up card on every column');

    L := Empty(G);
    L[SP_TAB0] := [C(suSpades, 9, False), C(suSpades, 8), C(suSpades, 7), C(suHearts, 6)];
    L[SP_TAB0 + 1] := [C(suHearts, 9)];
    L[SP_TAB0 + 2] := [C(suSpades, 7)];
    L[SP_TAB0 + 3] := [C(suHearts, 7)];
    for I := 4 to 9 do
      L[SP_TAB0 + I] := [C(suClubs, 13)];
    G.SetLayout(L, 2);
    Check(G.CanPickUp(SP_TAB0, 3), 'the top card can be picked up');
    Check(not G.CanPickUp(SP_TAB0, 1), 'a run with mixed suits cannot be moved together');
    Check(G.CanDrop(SP_TAB0, 3, SP_TAB0 + 2), 'a 6 goes on a 7 of another suit');
    Check(not G.CanDrop(SP_TAB0, 3, SP_TAB0 + 1), 'a 6 does not go on a 9');
    Check(G.FindAutoMove(SP_TAB0, 3, Dst) and (Dst = SP_TAB0 + 3), 'tap prefers the same suit');
    Check(G.MoveCards(SP_TAB0, 3, SP_TAB0 + 3) and (G.Moves = 1), 'move the 6 away');
    Check(G.CanPickUp(SP_TAB0, 1), 'now the same-suit 8-7 run moves together');
    Check(G.MoveCards(SP_TAB0, 1, SP_TAB0 + 1) and G.CardAt(SP_TAB0, 0).FaceUp, 'moving the run turns the card underneath');

    // dealing is blocked while a column is empty
    L := Empty(G);
    for I := 0 to 8 do
      L[SP_TAB0 + I] := [C(suSpades, 5), C(suSpades, 3)];
    L[SP_STOCK] := SuitRun(suHearts, 1, 10);
    for I := 0 to 9 do
      L[SP_STOCK][I].FaceUp := False;
    G.SetLayout(L, 2);
    Check(not G.Tap(SP_STOCK, 0), 'no deal while a column is empty');
    Check(G.Hint.Kind = hkMove, 'the hint suggests filling the empty column');
    Check(G.MoveCards(SP_TAB0, 1, SP_TAB0 + 9) and G.Tap(SP_STOCK, 0), 'deal allowed once every column has a card');

    // a completed King-to-Ace run leaves the table
    L := Empty(G);
    for I := 0 to 6 do
      L[SP_FOUND0 + I] := SuitRun(suSpades, 13, 1);
    L[SP_TAB0] := SuitRun(suSpades, 13, 2);
    L[SP_TAB0 + 1] := [C(suSpades, 1)];
    G.SetLayout(L, 0);
    Check(not G.IsWon, 'one run still to finish');
    Check(G.Hint.Kind = hkMove, 'hint finds the finishing move');
    I := G.Score;
    Check(G.MoveCards(SP_TAB0 + 1, 0, SP_TAB0), 'ace completes the run');
    Check((G.CardCount(SP_TAB0) = 0) and (G.CardCount(SP_FOUND0 + 7) = 13), 'the finished run is taken off');
    // this hand-built position starts at 0 and the score never drops below 0
    Check((I = 0) and (G.Score = 100), 'a finished run scores 100');
    Check(G.IsWon, 'eight finished runs win the game');
  finally
    G.Free;
  end;
end;

{ ---------- Pyramid ---------- }

function Spot(Row, Pos: Integer): Integer;
begin
  Result := PY_SPOT0 + Row * (Row + 1) div 2 + Pos;
end;

procedure TestPyramid;
var
  G: TPyramidGame;
  L: TArray<TCards>;
  I: Integer;
  Msg: string;
begin
  Section('Pyramid rules');
  G := TPyramidGame.Create;
  try
    G.NewGame(0, 4);
    Check((G.CardCount(PY_STOCK) = 24) and (G.CardCount(PY_WASTE) = 0), '24 cards in the stock');
    for I := PY_SPOT0 to G.PileCount - 1 do
      Check((G.CardCount(I) = 1) and G.CardAt(I, 0).FaceUp, 'pyramid cards are face up');
    Check(not G.CanPickUp(Spot(0, 0), 0), 'the top of the pyramid is covered');
    Check(G.CanPickUp(Spot(6, 3), 0), 'the bottom row is uncovered');

    L := Empty(G);
    L[Spot(5, 0)] := [C(suSpades, 13)];
    L[Spot(6, 0)] := [C(suSpades, 6)];
    L[Spot(6, 1)] := [C(suHearts, 7)];
    L[Spot(6, 2)] := [C(suHearts, 9)];
    L[Spot(6, 6)] := [C(suClubs, 13)];
    L[PY_WASTE] := [C(suClubs, 2), C(suDiamonds, 4)];
    L[PY_STOCK] := [C(suClubs, 11, False)];
    G.SetLayout(L, 0);
    Check(not G.CanPickUp(Spot(5, 0), 0), 'a card is covered while the two below it remain');
    Check(G.CanDrop(Spot(6, 0), 0, Spot(6, 1)), '6 and 7 make 13');
    Check(not G.CanDrop(Spot(6, 0), 0, Spot(6, 2)), '6 and 9 do not make 13');
    Check(G.CanDrop(PY_WASTE, 1, Spot(6, 2)), 'waste 4 pairs with a pyramid 9');
    Check(not G.CanDrop(PY_WASTE, 0, Spot(6, 2)), 'only the top waste card is playable');
    Check(G.CanDrop(Spot(6, 6), 0, PY_DISCARD), 'a king can be dragged to the discard pile');
    Check(not G.CanDrop(Spot(6, 0), 0, PY_DISCARD), 'other cards cannot go alone');

    // tap to select, tap the partner
    Check((not G.Tap(Spot(6, 0), 0)) and G.IsSelected(Spot(6, 0), 0), 'first tap selects a card');
    Check((not G.Tap(Spot(6, 2), 0)) and G.IsSelected(Spot(6, 2), 0) and not G.IsSelected(Spot(6, 0), 0),
      'tapping a card that does not fit selects that one instead');
    Check((not G.Tap(Spot(6, 2), 0)) and not G.IsSelected(Spot(6, 2), 0), 'tapping it again deselects');
    G.Tap(Spot(6, 0), 0);
    Check(G.Tap(Spot(6, 1), 0) and (G.CardCount(Spot(6, 0)) = 0) and (G.CardCount(Spot(6, 1)) = 0)
      and (G.CardCount(PY_DISCARD) = 2) and (G.Score = 10), 'second tap removes the pair (+10)');
    Check(G.CanPickUp(Spot(5, 0), 0), 'removing both cards below uncovers the one above');
    Check(G.Tap(Spot(5, 0), 0) and (G.CardCount(PY_DISCARD) = 3), 'tapping a king removes it');
    Check(G.Hint.Kind <> hkNone, 'hint finds a move');
    Check(G.Undo and (G.CardCount(Spot(5, 0)) = 1), 'undo brings the king back');

    // stock, waste and the two redeals
    L := Empty(G);
    L[Spot(6, 0)] := [C(suSpades, 5)];
    L[PY_STOCK] := [C(suClubs, 2, False), C(suClubs, 3, False)];
    G.SetLayout(L, 0);
    Check(G.Tap(PY_STOCK, 1) and (G.CardCount(PY_WASTE) = 1) and (G.CardAt(PY_WASTE, 0).Rank = 3)
      and G.CardAt(PY_WASTE, 0).FaceUp, 'stock turns one card');
    G.Tap(PY_STOCK, 0);
    Check((G.CardCount(PY_STOCK) = 0) and G.StockCanRecycle, 'first redeal available');
    Check(G.Tap(PY_STOCK, -1) and (G.CardCount(PY_STOCK) = 2) and (G.CardAt(PY_STOCK, 1).Rank = 3),
      'redeal keeps the order');
    G.Tap(PY_STOCK, 0);
    G.Tap(PY_STOCK, 0);
    Check(G.Tap(PY_STOCK, -1), 'second redeal');
    G.Tap(PY_STOCK, 0);
    G.Tap(PY_STOCK, 0);
    Check((not G.StockCanRecycle) and not G.Tap(PY_STOCK, -1), 'no third redeal');
    Check(G.IsStuck and (G.Hint.Kind = hkNone), 'out of moves is detected');

    // win
    L := Empty(G);
    L[Spot(6, 0)] := [C(suSpades, 6)];
    L[Spot(6, 1)] := [C(suHearts, 7)];
    L[PY_DISCARD] := Rest([C(suSpades, 6), C(suHearts, 7)], True);
    G.SetLayout(L, 0);
    Check(G.CheckIntegrity(Msg), 'hand-built position is valid ' + Msg);
    Check(not G.IsWon and not G.IsStuck, 'one pair left');
    Check(G.Hint.Kind = hkMove, 'hint shows the last pair');
    Check(G.MoveCards(Spot(6, 0), 0, Spot(6, 1)) and G.IsWon, 'clearing the pyramid wins');
  finally
    G.Free;
  end;
end;

{ ---------- TriPeaks ---------- }

procedure TestTriPeaks;
var
  G: TTriPeaksGame;
  L: TArray<TCards>;
  I: Integer;
  Msg: string;
begin
  Section('TriPeaks rules');
  G := TTriPeaksGame.Create;
  try
    G.NewGame(0, 6);
    Check((G.CardCount(TP_STOCK) = 23) and (G.CardCount(TP_WASTE) = 1), '23 in the stock, one on the waste');
    for I := TP_ROW0 to TP_END - 1 do
      Check((G.CardCount(I) = 1) and (G.CardAt(I, 0).FaceUp = (I >= TP_ROW3)), 'only the bottom row is face up');
    Check(not G.CanPickUp(TP_ROW0, 0), 'a face-down card cannot be played');

    L := Empty(G);
    L[TP_ROW2] := [C(suSpades, 5, False)];        // covered by ROW3 + 0 and + 1
    L[TP_ROW3] := [C(suHearts, 8)];
    L[TP_ROW3 + 1] := [C(suClubs, 13)];
    L[TP_ROW3 + 5] := [C(suClubs, 3)];
    L[TP_WASTE] := [C(suDiamonds, 7)];
    L[TP_STOCK] := [C(suDiamonds, 1, False)];
    G.SetLayout(L, 0);
    Check(G.CanDrop(TP_ROW3, 0, TP_WASTE), '8 follows 7');
    Check(not G.CanDrop(TP_ROW3 + 1, 0, TP_WASTE), 'king does not follow 7');
    Check(not G.CanDrop(TP_ROW3 + 5, 0, TP_WASTE), '3 does not follow 7');
    Check(not G.Tap(TP_ROW3 + 5, 0), 'tapping a card that does not fit does nothing');
    Check(G.Hint.Kind = hkTap, 'hint finds the playable card');
    Check(G.Tap(TP_ROW3, 0) and (G.CardAt(TP_WASTE, 1).Rank = 8) and (G.Score = 1), 'tap plays the 8 (+1)');
    Check(not G.CardAt(TP_ROW2, 0).FaceUp, 'still covered by the king');
    Check(G.Tap(TP_STOCK, 0) and (G.CardAt(TP_WASTE, 2).Rank = 1), 'stock turns an ace');
    Check(G.Tap(TP_ROW3 + 1, 0), 'king follows ace (wraps round)');
    Check(G.CardAt(TP_ROW2, 0).FaceUp, 'a card turns over when nothing covers it');
    Check(G.Undo and not G.CardAt(TP_ROW2, 0).FaceUp and (G.CardCount(TP_ROW3 + 1) = 1), 'undo puts the king back');
    Check(G.Tap(TP_ROW3 + 1, 0) and not G.IsWon and G.IsStuck, 'stock empty and nothing fits: no more moves');

    // run scoring: 1, 2, 3 ... and the stock ends the run
    L := Empty(G);
    L[TP_ROW3] := [C(suHearts, 8)];
    L[TP_ROW3 + 2] := [C(suHearts, 9)];
    L[TP_ROW3 + 4] := [C(suHearts, 10)];
    L[TP_ROW3 + 6] := [C(suHearts, 4)];
    L[TP_WASTE] := [C(suDiamonds, 7)];
    L[TP_STOCK] := [C(suDiamonds, 5, False)];
    G.SetLayout(L, 0);
    G.Tap(TP_ROW3, 0);
    G.Tap(TP_ROW3 + 2, 0);
    G.Tap(TP_ROW3 + 4, 0);
    Check(G.Score = 6, 'a run of three scores 1 + 2 + 3');
    G.Tap(TP_STOCK, 0);
    Check(G.Tap(TP_ROW3 + 6, 0) and (G.Score = 7), 'after the stock the run starts again at 1');
    Check(G.IsWon, 'clearing every peak card wins');

    // win from a full hand-built position
    L := Empty(G);
    L[TP_ROW3] := [C(suSpades, 5)];
    L[TP_WASTE] := Rest([C(suSpades, 5), C(suHearts, 6)], True) + [C(suHearts, 6)];
    G.SetLayout(L, 0);
    Check(G.CheckIntegrity(Msg), 'hand-built position is valid ' + Msg);
    Check(G.Tap(TP_ROW3, 0) and G.IsWon and (G.Hint.Kind = hkNone), 'last card wins');
  finally
    G.Free;
  end;
end;

{ ---------- statistics ---------- }

procedure TestStats;
var
  S: TStatsStore;
  Dir: string;
  Ini: TMemIniFile;
begin
  Section('Statistics');
  Dir := TPath.Combine(TPath.GetTempPath, 'SolitaireTests-' + IntToStr(Random(MaxInt)));
  DataDirOverride := Dir;
  try
    S := TStatsStore.Create;
    try
      Check((S.Get('klondike', 0).Played = 0) and (S.CurrentGame = 'klondike'), 'new store starts empty');
      S.RecordStart('klondike', 0);
      S.RecordWin('klondike', 0, 200, 500, 120);
      S.RecordStart('klondike', 0);
      S.RecordWin('klondike', 0, 150, 450, 130);
      S.RecordStart('klondike', 0);
      S.RecordLoss('klondike', 0);
      S.RecordStart('klondike', 1);
      S.RecordWin('klondike', 1, 300, 700, 140);
      S.RecordStart('spider', 2);
      S.RecordStart('pyramid', 0);
      S.RecordWin('pyramid', 0, 90, 140, 40);
      S.SetVariant('spider', 2);
      S.CurrentGame := 'spider';
      S.WinEffect := 2;
      S.Save;
    finally
      S.Free;
    end;

    S := TStatsStore.Create;   // re-read from disk
    try
      Check((S.Get('klondike', 0).Played = 3) and (S.Get('klondike', 0).Won = 2), 'played / won persist');
      Check((S.Get('klondike', 0).Streak = 0) and (S.Get('klondike', 0).BestStreak = 2),
        'a loss ends the streak, best streak is kept');
      Check(S.Get('klondike', 0).BestTime = 150, 'best time is the fastest win');
      Check(S.Get('klondike', 0).BestScore = 500, 'best score is the highest');
      Check(S.Get('klondike', 0).FewestMoves = 120, 'fewest moves is the lowest');
      Check(S.Get('klondike', 0).TotalWinTime = 350, 'total win time adds up');
      Check((S.Get('klondike', 1).Played = 1) and (S.Get('klondike', 1).Won = 1), 'variants are tracked separately');
      Check((S.Get('spider', 2).Played = 1) and (S.Get('spider', 0).Played = 0), 'Spider suit counts are separate');
      Check((S.Get('pyramid', 0).Won = 1) and (S.Get('tripeaks', 0).Played = 0), 'each game has its own statistics');
      Check((S.GetVariant('spider') = 2) and (S.GetVariant('klondike') = 0), 'chosen variants persist per game');
      Check((S.CurrentGame = 'spider') and (S.WinEffect = 2), 'settings persist');
      S.ResetGame('klondike');
    finally
      S.Free;
    end;

    S := TStatsStore.Create;
    try
      Check((S.Get('klondike', 0).Played = 0) and (S.Get('klondike', 1).Won = 0), 'reset clears that game');
      Check(S.Get('pyramid', 0).Won = 1, 'reset leaves the other games alone');
      Check(S.GetVariant('spider') = 2, 'reset keeps the settings');
    finally
      S.Free;
    end;

    // a statistics file written before the other games existed
    Ini := TMemIniFile.Create(TPath.Combine(Dir, 'solitaire.ini'));
    try
      Ini.Clear;
      Ini.WriteInteger('Settings', 'DrawCount', 3);
      Ini.WriteInteger('Settings', 'WinEffect', 1);
      Ini.WriteInteger('Draw1', 'Played', 12);
      Ini.WriteInteger('Draw1', 'Won', 5);
      Ini.WriteInteger('Draw3', 'Played', 4);
      Ini.WriteInteger('Draw3', 'BestTime', 222);
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
    S := TStatsStore.Create;
    try
      Check((S.Get('klondike', 0).Played = 12) and (S.Get('klondike', 0).Won = 5), 'old Draw 1 statistics carry over');
      Check((S.Get('klondike', 1).Played = 4) and (S.Get('klondike', 1).BestTime = 222), 'old Draw 3 statistics carry over');
      Check((S.GetVariant('klondike') = 1) and (S.WinEffect = 1), 'old settings carry over');
      S.Save;
    finally
      S.Free;
    end;
    S := TStatsStore.Create;
    try
      Check(S.Get('klondike', 0).Played = 12, 'carried-over statistics survive the next save');
    finally
      S.Free;
    end;
  finally
    DataDirOverride := '';
    try
      TDirectory.Delete(Dir, True);
    except
    end;
  end;
end;

var
  I: Integer;
begin
  try
    Randomize;
    TestRegistry;
    TestKlondike;
    TestFreeCell;
    TestSpider;
    TestPyramid;
    TestTriPeaks;
    for I := 0 to High(GAME_CLASSES) do
      TestGameGeneric(GAME_CLASSES[I], 150);
    TestStats;
  except
    on E: Exception do
    begin
      Inc(Fails);
      Writeln('EXCEPTION ', E.ClassName, ': ', E.Message);
    end;
  end;
  Writeln;
  Writeln(Format('%d checks, %d failed', [Checks, Fails]));
  if Fails = 0 then
    Writeln('RESULT: PASS')
  else
  begin
    Writeln('RESULT: FAIL');
    ExitCode := 1;
  end;
end.
