unit uAutoPlay;

{ Plays any game by following its own hints. Used by the automated tests.
  It stops when the game is won, when there is no hint, or when a card layout
  comes round a second time (so it can never loop). }

interface

uses
  System.SysUtils, System.Generics.Collections, uCardGame;

type
  TAutoPlayer = class
  private
    FGame: TCardGame;
    FSeen: TDictionary<string, Boolean>;
  public
    constructor Create(AGame: TCardGame);
    destructor Destroy; override;
    /// The next move to make, or hkNone when the player gives up / has won.
    function Choose: THint;
    /// Chooses and plays one move directly on the model. False = finished.
    function Step: Boolean;
  end;

/// Plays the deal to the end on a scratch game. True if the player wins it.
function AutoPlayerWins(AClass: TCardGameClass; AVariant, ASeed: Integer): Boolean;
/// First seed >= StartSeed the auto-player can win, or -1.
function FindWinnableSeed(AClass: TCardGameClass; AVariant, StartSeed, MaxTries: Integer): Integer;
/// Carries out a hint on the model. True if it changed the game.
function PlayHint(AGame: TCardGame; const H: THint): Boolean;

implementation

function PlayHint(AGame: TCardGame; const H: THint): Boolean;
begin
  case H.Kind of
    hkMove:
      Result := AGame.MoveCards(H.Src, H.Index, H.Dst);
    hkTap:
      Result := AGame.Tap(H.Src, H.Index);
  else
    Result := False;
  end;
end;

{ TAutoPlayer }

constructor TAutoPlayer.Create(AGame: TCardGame);
begin
  inherited Create;
  FGame := AGame;
  FSeen := TDictionary<string, Boolean>.Create;
end;

destructor TAutoPlayer.Destroy;
begin
  FSeen.Free;
  inherited;
end;

function TAutoPlayer.Choose: THint;
var
  Key: string;
begin
  Result.Kind := hkNone;
  Result.Src := -1;
  Result.Index := -1;
  Result.Dst := -1;
  if FGame.IsWon then
    Exit;
  Key := FGame.LayoutHash;
  if FSeen.ContainsKey(Key) then
    Exit;               // been here before: going round in circles
  FSeen.Add(Key, True);
  Result := FGame.Hint;
end;

function TAutoPlayer.Step: Boolean;
var
  H: THint;
begin
  H := Choose;
  Result := H.Kind <> hkNone;
  if Result and not PlayHint(FGame, H) then
    raise Exception.CreateFmt('%s: hint %d[%d] -> %d could not be played',
      [FGame.Title, H.Src, H.Index, H.Dst]);
end;

function AutoPlayerWins(AClass: TCardGameClass; AVariant, ASeed: Integer): Boolean;
var
  G: TCardGame;
  P: TAutoPlayer;
  Guard: Integer;
begin
  G := AClass.Create;
  P := TAutoPlayer.Create(G);
  try
    G.NewGame(AVariant, ASeed);
    Guard := 0;
    while P.Step and (Guard < 20000) do
      Inc(Guard);
    Result := G.IsWon;
  finally
    P.Free;
    G.Free;
  end;
end;

function FindWinnableSeed(AClass: TCardGameClass; AVariant, StartSeed, MaxTries: Integer): Integer;
var
  I: Integer;
begin
  for I := StartSeed to StartSeed + MaxTries - 1 do
    if AutoPlayerWins(AClass, AVariant, I) then
      Exit(I);
  Result := -1;
end;

end.
