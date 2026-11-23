unit uSound;

{ The game's sounds: cards being dealt when a new game starts, chimes when a
  game is won, and one small sound for each win effect (a card bouncing, a
  firework going off, a card shooting out of the fountain). All are synthesised
  here, so the app ships no audio files. Several can sound at once. Playing
  never raises: a device without sound simply stays quiet. }

interface

type
  TSoundKind = (skShuffle, skWin, skBounce, skBurst, skWhoosh);

procedure PlayGameSound(Kind: TSoundKind);
/// The sound's WAV file, written on first use.
function SoundFile(Kind: TSoundKind): string;

implementation

uses
  System.SysUtils, System.Classes, System.Math, System.IOUtils, System.Diagnostics
  {$IFDEF MSWINDOWS}, Winapi.Windows, Winapi.MMSystem{$ELSE}, FMX.Media{$ENDIF};

const
  RATE = 44100;
  FILE_NAMES: array[TSoundKind] of string = ('solitaire-deal-2.wav', 'solitaire-win-2.wav',
    'solitaire-bounce-1.wav', 'solitaire-burst-1.wav', 'solitaire-whoosh-1.wav');
  // how loud each sound is, the chimes being the loudest
  GAIN: array[TSoundKind] of Single = (0.8, 0.8, 0.45, 0.6, 0.3);
  // the same sound is not started again within this many milliseconds
  MIN_GAP: array[TSoundKind] of Integer = (0, 0, 70, 120, 280);

type
  TSamples = TArray<Single>;

var
  // a private generator: the game's own random numbers must not be disturbed
  NoiseSeed: Cardinal = 12345;
  Clock: TStopwatch;
  LastPlayed: array[TSoundKind] of Int64;

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

{ A card landing on the table: a short, soft knock. }
function MakeBounce: TSamples;
var
  I: Integer;
  T, Phase: Single;
begin
  SetLength(Result, Round(RATE * 0.11));
  Phase := 0;
  for I := 0 to High(Result) do
  begin
    T := I / RATE;
    Phase := Phase + 2 * Pi * (240 + 200 * Exp(-T / 0.012)) / RATE;   // the pitch drops as it rings
    Result[I] := Min(1, T / 0.001) * Exp(-T / 0.022) * Sin(Phase) + 0.35 * Exp(-T / 0.0015) * Noise;
  end;
end;

{ A firework: a dull thump and then a fading crackle of sparks. }
function MakeBurst: TSamples;
var
  I, J, N: Integer;
  T, LP, Phase, A: Single;
begin
  SetLength(Result, Round(RATE * 0.9));
  LP := 0;
  Phase := 0;
  for I := 0 to High(Result) do
  begin
    T := I / RATE;
    LP := LP + 0.06 * (Noise - LP);
    Phase := Phase + 2 * Pi * (55 + 60 * Exp(-T / 0.05)) / RATE;
    Result[I] := Min(1, T / 0.002) * (2.2 * Exp(-T / 0.07) * LP + 0.7 * Exp(-T / 0.09) * Sin(Phase));
  end;
  // sparks: single sharp ticks at random moments, fewer and quieter as it fades
  I := Round(RATE * 0.08);
  while I < Length(Result) - 200 do
  begin
    T := I / RATE;
    A := 0.5 * Exp(-T / 0.3) * (0.4 + Rand01 * 0.6);
    N := Round(RATE * 0.002);
    for J := 0 to N - 1 do
      Result[I + J] := Result[I + J] + A * Exp(-J / (RATE * 0.0005)) * Noise;
    I := I + Round(RATE * (0.004 + Rand01 * 0.03 * (1 + T * 4)));
  end;
end;

{ A card shooting upwards: a quick breath of air that brightens as it goes. }
function MakeWhoosh: TSamples;
var
  I, N: Integer;
  X, U, LP, Soft: Single;
begin
  N := Round(RATE * 0.30);
  SetLength(Result, N);
  LP := 0;
  Soft := 0;
  for I := 0 to N - 1 do
  begin
    U := I / N;
    X := Noise;
    LP := LP + 0.12 * (X - LP);
    X := X - LP;                                    // no rumble
    Soft := Soft + (0.08 + 0.45 * U) * (X - Soft);  // opens up towards the end
    Result[I] := Sqr(Sin(Pi * Power(U, 0.7))) * Soft;
  end;
end;

function Render(Kind: TSoundKind): TSamples;
begin
  case Kind of
    skShuffle: Result := MakeShuffle;
    skWin:     Result := MakeWin;
    skBounce:  Result := MakeBounce;
    skBurst:   Result := MakeBurst;
  else
    Result := MakeWhoosh;
  end;
end;

{ 16-bit mono samples, levelled, with the last few milliseconds faded out. }
function ToPcm(const A: TSamples; Level: Single): TBytes;
var
  I: Integer;
  Peak, Fade: Single;
  V: SmallInt;
begin
  Peak := 0.001;
  for I := 0 to High(A) do
    Peak := Max(Peak, Abs(A[I]));
  SetLength(Result, Length(A) * 2);
  for I := 0 to High(A) do
  begin
    Fade := Min(1, (High(A) - I) / (RATE * 0.01));
    V := Round(A[I] / Peak * Fade * Level * 32767);
    Move(V, Result[I * 2], 2);
  end;
end;

procedure SaveWav(const Pcm: TBytes; const FileName: string);
var
  S: TMemoryStream;

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
  S := TMemoryStream.Create;
  try
    Tag('RIFF');
    W32(36 + Length(Pcm));
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
    W32(Length(Pcm));
    S.WriteBuffer(Pcm[0], Length(Pcm));
    S.SaveToFile(FileName);
  finally
    S.Free;
  end;
end;

function SoundFile(Kind: TSoundKind): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, FILE_NAMES[Kind]);
  if not TFile.Exists(Result) then
    SaveWav(ToPcm(Render(Kind), GAIN[Kind]), Result);
end;

{$IFDEF MSWINDOWS}

{ Windows: every voice is its own wave-out device, which the system mixes, so
  a chime keeps ringing while the effect sounds play over it. }
const
  VOICES = 8;   // voice 0 is kept for the deal and the chimes

type
  TVoice = record
    Handle: HWAVEOUT;
    Header: TWaveHdr;
    Open, Loaded: Boolean;
  end;

var
  Pcm: array[TSoundKind] of TBytes;
  Voice: array[0..VOICES - 1] of TVoice;
  NextVoice: Integer = 1;

procedure Start(Kind: TSoundKind);
var
  Fmt: TWaveFormatEx;
  N: Integer;
begin
  if Pcm[Kind] = nil then
    Pcm[Kind] := ToPcm(Render(Kind), GAIN[Kind]);
  if Kind in [skShuffle, skWin] then
    N := 0
  else
  begin
    N := NextVoice;
    Inc(NextVoice);
    if NextVoice >= VOICES then
      NextVoice := 1;
  end;
  if not Voice[N].Open then
  begin
    FillChar(Fmt, SizeOf(Fmt), 0);
    Fmt.wFormatTag := WAVE_FORMAT_PCM;
    Fmt.nChannels := 1;
    Fmt.nSamplesPerSec := RATE;
    Fmt.wBitsPerSample := 16;
    Fmt.nBlockAlign := 2;
    Fmt.nAvgBytesPerSec := RATE * 2;
    if waveOutOpen(@Voice[N].Handle, WAVE_MAPPER, @Fmt, 0, 0, CALLBACK_NULL) <> MMSYSERR_NOERROR then
      Exit;
    Voice[N].Open := True;
  end;
  if Voice[N].Loaded then
  begin
    waveOutReset(Voice[N].Handle);
    waveOutUnprepareHeader(Voice[N].Handle, @Voice[N].Header, SizeOf(TWaveHdr));
    Voice[N].Loaded := False;
  end;
  FillChar(Voice[N].Header, SizeOf(TWaveHdr), 0);
  Voice[N].Header.lpData := PAnsiChar(@Pcm[Kind][0]);
  Voice[N].Header.dwBufferLength := Length(Pcm[Kind]);
  if waveOutPrepareHeader(Voice[N].Handle, @Voice[N].Header, SizeOf(TWaveHdr)) = MMSYSERR_NOERROR then
  begin
    Voice[N].Loaded := True;
    waveOutWrite(Voice[N].Handle, @Voice[N].Header, SizeOf(TWaveHdr));
  end;
end;

procedure Shutdown;
var
  N: Integer;
begin
  for N := 0 to VOICES - 1 do
    if Voice[N].Open then
    begin
      waveOutReset(Voice[N].Handle);
      if Voice[N].Loaded then
        waveOutUnprepareHeader(Voice[N].Handle, @Voice[N].Header, SizeOf(TWaveHdr));
      waveOutClose(Voice[N].Handle);
      Voice[N].Open := False;
    end;
end;

{$ELSE}

{ Phones: a few players per sound, used in turn, so a sound can start again
  before its last playing has finished. }
const
  COPIES = 3;

var
  Players: array[TSoundKind, 0..COPIES - 1] of TMediaPlayer;
  NextCopy: array[TSoundKind] of Integer;

procedure Start(Kind: TSoundKind);
var
  N: Integer;
begin
  N := 0;
  if not (Kind in [skShuffle, skWin]) then
  begin
    N := NextCopy[Kind];
    NextCopy[Kind] := (N + 1) mod COPIES;
  end;
  if Players[Kind, N] = nil then
  begin
    Players[Kind, N] := TMediaPlayer.Create(nil);
    Players[Kind, N].FileName := SoundFile(Kind);
  end
  else
    Players[Kind, N].CurrentTime := 0;
  Players[Kind, N].Play;
end;

procedure Shutdown;
var
  K: TSoundKind;
  N: Integer;
begin
  for K := Low(TSoundKind) to High(TSoundKind) do
    for N := 0 to COPIES - 1 do
      FreeAndNil(Players[K, N]);
end;

{$ENDIF}

procedure PlayGameSound(Kind: TSoundKind);
var
  Now: Int64;
begin
  try
    Now := Clock.ElapsedMilliseconds;
    if (MIN_GAP[Kind] > 0) and (LastPlayed[Kind] > 0) and (Now - LastPlayed[Kind] < MIN_GAP[Kind]) then
      Exit;
    LastPlayed[Kind] := Max(1, Now);
    Start(Kind);
  except
    // sound is a nicety; never let it get in the way of the game
  end;
end;

initialization
  Clock := TStopwatch.StartNew;

finalization
  try
    Shutdown;
  except
  end;

end.
