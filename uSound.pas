unit uSound;

{ The game's two sounds: cards being shuffled when a new game is dealt, and a
  short fanfare when a game is won. Both are synthesised here and written out
  as small WAV files the first time they are needed, so the app ships no audio
  files. Playing never raises: a device without sound simply stays quiet. }

interface

type
  TSoundKind = (skShuffle, skWin);

procedure PlayGameSound(Kind: TSoundKind);
/// The sound's WAV file, written on first use.
function SoundFile(Kind: TSoundKind): string;

implementation

uses
  System.SysUtils, System.Classes, System.Math, System.IOUtils
  {$IFDEF MSWINDOWS}, Winapi.Windows, Winapi.MMSystem{$ELSE}, FMX.Media{$ENDIF};

const
  RATE = 22050;
  FILE_NAMES: array[TSoundKind] of string = ('solitaire-shuffle-1.wav', 'solitaire-win-1.wav');

type
  TSamples = TArray<Single>;

var
  // a private generator: the game's own random numbers must not be disturbed
  NoiseSeed: Cardinal = 12345;
  {$IFNDEF MSWINDOWS}
  Players: array[TSoundKind] of TMediaPlayer;
  {$ENDIF}

function Noise: Single;   // -1 .. 1
begin
  NoiseSeed := NoiseSeed * 1664525 + 1013904223;
  Result := ((NoiseSeed shr 8) and $FFFF) / 32767.5 - 1;
end;

function Rand01: Single;
begin
  Result := (Noise + 1) / 2;
end;

{ Two riffles (a run of quick card flicks that gets faster) and a soft swish
  as the pack is squared up. }
function MakeShuffle: TSamples;
var
  R, I, N, At: Integer;
  T, T0, Amp, Y: Single;
begin
  SetLength(Result, Round(RATE * 1.5));
  for R := 0 to 1 do
  begin
    T0 := 0.03 + R * 0.55;
    T := T0;
    while T < T0 + 0.42 do
    begin
      Amp := 0.35 + Rand01 * 0.45;
      At := Round(T * RATE);
      N := Round(RATE * 0.012);
      for I := 0 to N - 1 do
        if At + I < Length(Result) then
          Result[At + I] := Result[At + I] + Amp * Exp(-I / (RATE * 0.0025)) * Noise;
      T := T + 0.020 - 0.012 * ((T - T0) / 0.42) + Rand01 * 0.004;
    end;
  end;
  At := Round(1.12 * RATE);
  N := Round(0.32 * RATE);
  for I := 0 to N - 1 do
    if At + I < Length(Result) then
      Result[At + I] := Result[At + I] + 0.28 * Sin(Pi * I / N) * Noise;
  // take the hiss off
  Y := 0;
  for I := 0 to High(Result) do
  begin
    Y := Y + 0.5 * (Result[I] - Y);
    Result[I] := Y;
  end;
end;

{ A rising major arpeggio that ends on the full chord. }
function MakeWin: TSamples;
const
  NOTES: array[0..3] of Single = (523.25, 659.25, 783.99, 1046.5);

  procedure Tone(var A: TSamples; Freq, Start, Decay, Amp: Single);
  var
    I, At: Integer;
    T, Env: Single;
  begin
    At := Round(Start * RATE);
    for I := 0 to Length(A) - At - 1 do
    begin
      T := I / RATE;
      Env := Min(1, T / 0.005) * Exp(-T / Decay);
      A[At + I] := A[At + I] + Amp * Env *
        (Sin(2 * Pi * Freq * T) + 0.3 * Sin(4 * Pi * Freq * T) + 0.15 * Sin(6 * Pi * Freq * T));
    end;
  end;

var
  I: Integer;
begin
  SetLength(Result, Round(RATE * 1.9));
  for I := 0 to High(NOTES) do
    Tone(Result, NOTES[I], I * 0.13, 0.25, 0.22);
  for I := 0 to High(NOTES) do
    Tone(Result, NOTES[I], 0.56, 0.42, 0.20);
end;

procedure SaveWav(const A: TSamples; const FileName: string);
var
  S: TMemoryStream;
  I, Bytes: Integer;
  Peak, Fade: Single;
  V: SmallInt;

  procedure W32(X: Cardinal);
  begin
    S.WriteBuffer(X, 4);
  end;

  procedure W16(X: Word);
  begin
    S.WriteBuffer(X, 2);
  end;

  procedure Tag(const T: AnsiString);
  begin
    S.WriteBuffer(T[1], 4);
  end;

begin
  Peak := 0.001;
  for I := 0 to High(A) do
    Peak := Max(Peak, Abs(A[I]));
  Bytes := Length(A) * 2;
  S := TMemoryStream.Create;
  try
    Tag('RIFF');
    W32(36 + Bytes);
    Tag('WAVE');
    Tag('fmt ');
    W32(16);
    W16(1);            // PCM
    W16(1);            // mono
    W32(RATE);
    W32(RATE * 2);
    W16(2);
    W16(16);
    Tag('data');
    W32(Bytes);
    for I := 0 to High(A) do
    begin
      Fade := Min(1, (High(A) - I) / (RATE * 0.03));   // no click at the end
      V := Round(A[I] / Peak * Fade * 0.8 * 32767);
      S.WriteBuffer(V, 2);
    end;
    S.SaveToFile(FileName);
  finally
    S.Free;
  end;
end;

function SoundFile(Kind: TSoundKind): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, FILE_NAMES[Kind]);
  if not TFile.Exists(Result) then
    if Kind = skShuffle then
      SaveWav(MakeShuffle, Result)
    else
      SaveWav(MakeWin, Result);
end;

procedure PlayGameSound(Kind: TSoundKind);
var
  F: string;
begin
  try
    F := SoundFile(Kind);
    {$IFDEF MSWINDOWS}
    Winapi.MMSystem.PlaySound(PChar(F), 0, SND_FILENAME or SND_ASYNC or SND_NODEFAULT);
    {$ELSE}
    if Players[Kind] = nil then
    begin
      Players[Kind] := TMediaPlayer.Create(nil);
      Players[Kind].FileName := F;
    end
    else
    begin
      Players[Kind].Stop;
      Players[Kind].CurrentTime := 0;
    end;
    Players[Kind].Play;
    {$ENDIF}
  except
    // sound is a nicety; never let it get in the way of the game
  end;
end;

{$IFNDEF MSWINDOWS}
procedure FreePlayers;
var
  K: TSoundKind;
begin
  for K := Low(TSoundKind) to High(TSoundKind) do
    FreeAndNil(Players[K]);
end;

initialization

finalization
  FreePlayers;
{$ENDIF}

end.
