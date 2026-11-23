unit uSound;

{ The game's two sounds: cards being dealt when a new game starts, and a
  short run of chimes when a game is won. Both are synthesised here and written out
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
  RATE = 44100;
  FILE_NAMES: array[TSoundKind] of string = ('solitaire-deal-2.wav', 'solitaire-win-2.wav');

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

{ Cards being dealt: a handful of quick paper flicks. Each one is a short burst
  of hiss with the low end taken out (low rumble is what makes noise sound
  rude) and a tiny snap as the card lands. }
function MakeShuffle: TSamples;
const
  FLICKS = 7;
var
  K, I, N, At: Integer;
  T, Amp, Env, X, LP, Soft: Single;
begin
  SetLength(Result, Round(RATE * 0.95));
  T := 0.02;
  for K := 0 to FLICKS - 1 do
  begin
    Amp := 0.6 + Rand01 * 0.4;
    At := Round(T * RATE);
    N := Round(RATE * 0.075);
    LP := 0;
    Soft := 0;
    for I := 0 to N - 1 do
    begin
      X := Noise;
      LP := LP + 0.20 * (X - LP);          // what is below about 1.5 kHz ...
      X := X - LP;                         // ... is removed
      Soft := Soft + 0.65 * (X - Soft);    // and the very top is rounded off
      Env := Min(1, I / (RATE * 0.008)) * Exp(-I / (RATE * 0.018));
      if I >= N - Round(RATE * 0.012) then   // the snap
        Env := Env + 1.3 * Exp(-(I - (N - Round(RATE * 0.012))) / (RATE * 0.0012));
      if At + I < Length(Result) then
        Result[At + I] := Result[At + I] + Amp * Env * Soft;
    end;
    T := T + 0.105 + (Rand01 - 0.5) * 0.02;
  end;
end;

{ A rising run of chimes that ends on the full chord. }
function MakeWin: TSamples;
const
  NOTES: array[0..3] of Single = (1046.5, 1318.5, 1568.0, 2093.0);

  procedure Chime(var A: TSamples; Freq, Start, Decay, Amp: Single);
  var
    I, At: Integer;
    T: Single;
  begin
    At := Round(Start * RATE);
    for I := 0 to Length(A) - At - 1 do
    begin
      T := I / RATE;
      A[At + I] := A[At + I] + Amp * Min(1, T / 0.003) *
        (Exp(-T / Decay) * Sin(2 * Pi * Freq * T) +
         0.3 * Exp(-T / 0.05) * Sin(2 * Pi * Freq * 3 * T));   // the bright strike
    end;
  end;

var
  I: Integer;
begin
  SetLength(Result, Round(RATE * 2.0));
  for I := 0 to High(NOTES) do
    Chime(Result, NOTES[I], I * 0.11, 0.30, 0.25);
  for I := 0 to High(NOTES) do
    Chime(Result, NOTES[I], 0.52, 0.55, 0.20);
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
