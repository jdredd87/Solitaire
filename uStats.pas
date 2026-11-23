unit uStats;

{ Persistent statistics and settings (one small ini file per device).
  Statistics are kept per game and per variant, e.g. [klondike.1] = Klondike
  Draw 3, [spider.0] = Spider with one suit. }

interface

uses
  System.SysUtils, System.Classes, System.IOUtils, System.IniFiles, System.Math,
  System.Generics.Collections;

type
  TModeStats = record
    Played: Integer;
    Won: Integer;
    Streak: Integer;
    BestStreak: Integer;
    BestTime: Integer;      // seconds, 0 = none yet
    BestScore: Integer;
    FewestMoves: Integer;   // 0 = none yet
    TotalWinTime: Integer;  // seconds, summed over won games
  end;

  TStatsStore = class
  private
    FFileName: string;
    FStats: TDictionary<string, TModeStats>;
    FVariants: TDictionary<string, Integer>;
    class function Key(const GameId: string; Variant: Integer): string; static;
    procedure Put(const GameId: string; Variant: Integer; const M: TModeStats);
  public
    CurrentGame: string;  // game id shown at start-up
    WinEffect: Integer;   // ordinal of TWinEffect
    CardStyle: Integer;   // ordinal of TCardStyle
    constructor Create;
    destructor Destroy; override;
    procedure Load;
    procedure Save;
    function Get(const GameId: string; Variant: Integer): TModeStats;
    /// The variant the player chose for this game's next deal.
    function GetVariant(const GameId: string): Integer;
    procedure SetVariant(const GameId: string; Variant: Integer);
    procedure RecordStart(const GameId: string; Variant: Integer);
    procedure RecordWin(const GameId: string; Variant, Seconds, Score, Moves: Integer);
    procedure RecordLoss(const GameId: string; Variant: Integer);
    procedure ResetGame(const GameId: string);
    procedure ResetAll;
  end;

/// Writable per-user folder for the saved games and statistics.
function AppDataDir: string;

var
  /// When set (automated tests), data goes here instead of the user's folder.
  DataDirOverride: string = '';

implementation

function AppDataDir: string;
begin
  if DataDirOverride <> '' then
  begin
    ForceDirectories(DataDirOverride);
    Exit(DataDirOverride);
  end;
{$IF Defined(MSWINDOWS)}
  Result := TPath.Combine(TPath.GetHomePath, 'Solitaire');
{$ELSE}
  Result := TPath.GetDocumentsPath;
{$ENDIF}
  try
    ForceDirectories(Result);
  except
  end;
end;

{ TStatsStore }

constructor TStatsStore.Create;
begin
  inherited;
  FStats := TDictionary<string, TModeStats>.Create;
  FVariants := TDictionary<string, Integer>.Create;
  FFileName := TPath.Combine(AppDataDir, 'solitaire.ini');
  CurrentGame := 'klondike';
  WinEffect := 0;
  CardStyle := 1;   // Classic
  Load;
end;

destructor TStatsStore.Destroy;
begin
  FVariants.Free;
  FStats.Free;
  inherited;
end;

class function TStatsStore.Key(const GameId: string; Variant: Integer): string;
begin
  Result := LowerCase(GameId) + '.' + IntToStr(Variant);
end;

function TStatsStore.Get(const GameId: string; Variant: Integer): TModeStats;
begin
  if not FStats.TryGetValue(Key(GameId, Variant), Result) then
    Result := Default(TModeStats);
end;

procedure TStatsStore.Put(const GameId: string; Variant: Integer; const M: TModeStats);
begin
  FStats.AddOrSetValue(Key(GameId, Variant), M);
end;

function TStatsStore.GetVariant(const GameId: string): Integer;
begin
  if not FVariants.TryGetValue(LowerCase(GameId), Result) then
    Result := 0;
end;

procedure TStatsStore.SetVariant(const GameId: string; Variant: Integer);
begin
  FVariants.AddOrSetValue(LowerCase(GameId), Max(0, Variant));
end;

procedure TStatsStore.Load;
var
  Ini: TMemIniFile;
  Sections, Keys: TStringList;
  S, K: string;
  M: TModeStats;

  function ReadStats(const Section: string): TModeStats;
  begin
    Result.Played := Max(0, Ini.ReadInteger(Section, 'Played', 0));
    Result.Won := Max(0, Ini.ReadInteger(Section, 'Won', 0));
    Result.Streak := Max(0, Ini.ReadInteger(Section, 'Streak', 0));
    Result.BestStreak := Max(0, Ini.ReadInteger(Section, 'BestStreak', 0));
    Result.BestTime := Max(0, Ini.ReadInteger(Section, 'BestTime', 0));
    Result.BestScore := Max(0, Ini.ReadInteger(Section, 'BestScore', 0));
    Result.FewestMoves := Max(0, Ini.ReadInteger(Section, 'FewestMoves', 0));
    Result.TotalWinTime := Max(0, Ini.ReadInteger(Section, 'TotalWinTime', 0));
  end;

begin
  FStats.Clear;
  FVariants.Clear;
  try
    Ini := TMemIniFile.Create(FFileName);
    Sections := TStringList.Create;
    Keys := TStringList.Create;
    try
      CurrentGame := LowerCase(Ini.ReadString('Settings', 'Game', 'klondike'));
      WinEffect := EnsureRange(Ini.ReadInteger('Settings', 'WinEffect', 0), 0, 3);
      CardStyle := EnsureRange(Ini.ReadInteger('Settings', 'CardStyle', 1), 0, 1);

      Ini.ReadSection('Variants', Keys);
      for K in Keys do
        FVariants.AddOrSetValue(LowerCase(K), Max(0, Ini.ReadInteger('Variants', K, 0)));

      Ini.ReadSections(Sections);
      for S in Sections do
        if S.Contains('.') then
          FStats.AddOrSetValue(LowerCase(S), ReadStats(S));

      // statistics written before the other games existed were Klondike only
      if Ini.SectionExists('Draw1') and not FStats.ContainsKey('klondike.0') then
      begin
        M := ReadStats('Draw1');
        FStats.AddOrSetValue('klondike.0', M);
      end;
      if Ini.SectionExists('Draw3') and not FStats.ContainsKey('klondike.1') then
      begin
        M := ReadStats('Draw3');
        FStats.AddOrSetValue('klondike.1', M);
      end;
      if (not FVariants.ContainsKey('klondike')) and (Ini.ReadInteger('Settings', 'DrawCount', 1) = 3) then
        FVariants.AddOrSetValue('klondike', 1);
    finally
      Keys.Free;
      Sections.Free;
      Ini.Free;
    end;
  except
    // unreadable file: keep defaults
  end;
end;

procedure TStatsStore.Save;
var
  Ini: TMemIniFile;
  Pair: TPair<string, TModeStats>;
  V: TPair<string, Integer>;
begin
  try
    Ini := TMemIniFile.Create(FFileName);
    try
      Ini.Clear;
      Ini.WriteString('Settings', 'Game', CurrentGame);
      Ini.WriteInteger('Settings', 'WinEffect', WinEffect);
      Ini.WriteInteger('Settings', 'CardStyle', CardStyle);
      for V in FVariants do
        Ini.WriteInteger('Variants', V.Key, V.Value);
      for Pair in FStats do
      begin
        Ini.WriteInteger(Pair.Key, 'Played', Pair.Value.Played);
        Ini.WriteInteger(Pair.Key, 'Won', Pair.Value.Won);
        Ini.WriteInteger(Pair.Key, 'Streak', Pair.Value.Streak);
        Ini.WriteInteger(Pair.Key, 'BestStreak', Pair.Value.BestStreak);
        Ini.WriteInteger(Pair.Key, 'BestTime', Pair.Value.BestTime);
        Ini.WriteInteger(Pair.Key, 'BestScore', Pair.Value.BestScore);
        Ini.WriteInteger(Pair.Key, 'FewestMoves', Pair.Value.FewestMoves);
        Ini.WriteInteger(Pair.Key, 'TotalWinTime', Pair.Value.TotalWinTime);
      end;
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  except
    // statistics are best-effort; never take the game down over them
  end;
end;

procedure TStatsStore.RecordStart(const GameId: string; Variant: Integer);
var
  M: TModeStats;
begin
  M := Get(GameId, Variant);
  Inc(M.Played);
  Put(GameId, Variant, M);
  Save;
end;

procedure TStatsStore.RecordWin(const GameId: string; Variant, Seconds, Score, Moves: Integer);
var
  M: TModeStats;
begin
  M := Get(GameId, Variant);
  Inc(M.Won);
  Inc(M.Streak);
  M.BestStreak := Max(M.BestStreak, M.Streak);
  if (M.BestTime = 0) or (Seconds < M.BestTime) then
    M.BestTime := Max(1, Seconds);
  M.BestScore := Max(M.BestScore, Score);
  if (M.FewestMoves = 0) or (Moves < M.FewestMoves) then
    M.FewestMoves := Moves;
  Inc(M.TotalWinTime, Max(0, Seconds));
  Put(GameId, Variant, M);
  Save;
end;

procedure TStatsStore.RecordLoss(const GameId: string; Variant: Integer);
var
  M: TModeStats;
begin
  M := Get(GameId, Variant);
  M.Streak := 0;
  Put(GameId, Variant, M);
  Save;
end;

procedure TStatsStore.ResetGame(const GameId: string);
var
  K: string;
  Doomed: TList<string>;
begin
  Doomed := TList<string>.Create;
  try
    for K in FStats.Keys do
      if K.StartsWith(LowerCase(GameId) + '.') then
        Doomed.Add(K);
    for K in Doomed do
      FStats.Remove(K);
  finally
    Doomed.Free;
  end;
  Save;
end;

procedure TStatsStore.ResetAll;
begin
  FStats.Clear;
  Save;
end;

end.
