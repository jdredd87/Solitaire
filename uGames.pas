unit uGames;

{ The list of solitaire variants. To add a game: write a TCardGame descendant
  and add its class to GAME_CLASSES. }

interface

uses
  System.SysUtils, uCardGame, uGameKlondike, uGameSpider, uGameFreeCell, uGamePyramid,
  uGameTriPeaks;

const
  GAME_CLASSES: array[0..4] of TCardGameClass =
    (TKlondikeGame, TSpiderGame, TFreeCellGame, TPyramidGame, TTriPeaksGame);

/// Index into GAME_CLASSES, or -1.
function GameIndexOf(const AGameId: string): Integer;

implementation

function GameIndexOf(const AGameId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(GAME_CLASSES) do
    if SameText(GAME_CLASSES[I].GameId, AGameId) then
      Exit(I);
  Result := -1;
end;

end.
