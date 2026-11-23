unit uMain;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Math,
  System.IOUtils, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Objects, FMX.StdCtrls,
  FMX.Layouts, FMX.Dialogs, FMX.DialogService, FMX.Controls.Presentation, FMX.TextLayout,
  uCardGame, uGames, uStats, uBoard;

type
  TPanelKind = (pnNone, pnMenu, pnGames, pnHelp, pnOptions);

  TMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormSaveState(Sender: TObject);
  private
    FGame: TCardGame;
    FGameIndex: Integer;
    FStats: TStatsStore;
    FBoard: TSolitaireBoard;
    FTopBar: TRectangle;
    FBtnNew, FBtnUndo, FBtnHint, FBtnMenu: TRectangle;   // own-drawn: same look on every platform
    FStatus: TText;
    FClock: TTimer;
    FNote: string;
    FNoteTicks: Integer;
    // overlay panels
    FOverlay: TRectangle;
    FPanels: array[TPanelKind] of TRectangle;
    FPanel: TPanelKind;
    FGameRows: array of TRectangle;
    FGameTitles: array of TText;
    FHelpTitle: TText;
    FHelpBox: TVertScrollBox;
    FHelpItems: TList<TText>;
    FHelpClose: TButton;
    FOptTitle, FVariantLabel, FVariantNote: TText;
    FBtnVariant, FBtnEffect, FBtnStyle, FBtnSound, FBtnPreview, FBtnReset, FBtnOptClose: TButton;
    FHeads: array[0..2] of TText;
    FCells: array[0..8, 0..2] of TText;
    FSelfTest: TObject;
    FDemo: TObject;

    function MakeButton(AParent: TFmxObject; const ACaption: string; AOnClick: TNotifyEvent): TButton;
    function MakeBarButton(const ACaption: string; AWidth: Single; AOnClick: TNotifyEvent): TRectangle;
    function MakeText(AParent: TFmxObject; X, Y, W, H: Single; const S: string;
      Size: Single; Bold: Boolean; Align: TTextAlign): TText;
    function MakeWrapText(AParent: TFmxObject; X, Y, W: Single; const S: string;
      Size: Single; Bold: Boolean): TText;
    function MakePanel(K: TPanelKind; W, H: Single): TRectangle;
    procedure BuildUI;
    procedure BuildMenuPanel;
    procedure BuildGamesPanel;
    procedure BuildHelpPanel;
    procedure BuildOptionsPanel;
    procedure FillHelp;
    procedure UpdateGamesPanel;
    procedure UpdateOptions;
    procedure LayoutPanels;
    function GameFile(AClass: TCardGameClass): string;
    procedure LoadOrDeal;

    procedure BoardChanged(Sender: TObject);
    procedure BoardNewGame(Sender: TObject);
    procedure ClockTick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure HintClick(Sender: TObject);
    procedure MenuClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure MenuGamesClick(Sender: TObject);
    procedure MenuHelpClick(Sender: TObject);
    procedure MenuOptionsClick(Sender: TObject);
    procedure GameRowClick(Sender: TObject);
    procedure VariantClick(Sender: TObject);
    procedure EffectClick(Sender: TObject);
    procedure StyleClick(Sender: TObject);
    procedure SoundClick(Sender: TObject);
    procedure PreviewClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; var KeyChar: WideChar; Shift: TShiftState);
    procedure SafeAreaChanged(Sender: TObject; const AInsets: TRectF);
  public
    /// Deals a new game, recording an unfinished one as a loss. Seed >= 0 = repeatable deal.
    procedure StartNewGame(ASeed: Integer = -1);
    /// Switches to another game, keeping the current one's deal for later.
    procedure SwitchGame(AIndex: Integer);
    function DoUndo: Boolean;
    function DoHint: Boolean;
    procedure SaveGame;
    procedure ShowPanel(K: TPanelKind);
    procedure UpdateStatus;
    /// Self-test: every button caption and label fits its control, and every panel fits the window.
    function CheckTextFits(out Msg: string): Boolean;
    function PanelControl(K: TPanelKind): TRectangle;
    function StatusText: string;
    function HelpItemCount: Integer;
    property Game: TCardGame read FGame;
    property GameIndex: Integer read FGameIndex;
    property Stats: TStatsStore read FStats;
    property Board: TSolitaireBoard read FBoard;
    property TopBar: TRectangle read FTopBar;
    property Panel: TPanelKind read FPanel;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.fmx}

uses
  uSelfTest, uDemo, uSound;

const
  PANEL_W = 320;
  BTN_FONT = 14;
  COL_FELT = $FF1B6B3A;
  COL_BAR  = $FF124A28;
  COL_TEXT = $FF202020;
  COL_DIM  = $FF707070;
  COL_ROW  = $FFE6E3D6;
  COL_ROW_ON = $FFCFE6D2;
  STAT_LABELS: array[0..8] of string = ('Games played', 'Games won', 'Win rate',
    'Current streak', 'Best streak', 'Best time', 'Average win time', 'Best score',
    'Fewest moves');

{ ---------- text fitting ---------- }

function MeasureText(const S: string; AFont: TFont; Size, MaxWidth: Single; Wrap: Boolean): TSizeF;
var
  L: TTextLayout;
begin
  L := TTextLayoutManager.DefaultTextLayout.Create;
  try
    L.BeginUpdate;
    try
      L.Font.Assign(AFont);
      L.Font.Size := Size;
      L.WordWrap := Wrap;
      L.MaxSize := PointF(MaxWidth, 10000);
      L.Text := S;
    finally
      L.EndUpdate;
    end;
    Result := TSizeF.Create(L.TextRect.Width, L.TextRect.Height);
  finally
    L.Free;
  end;
end;

function TextWidthOf(const S: string; AFont: TFont; Size: Single): Single;
begin
  // phones draw text slightly wider than it measures
  Result := MeasureText(S, AFont, Size, 10000, False).Width * 1.06;
end;

/// Shrinks a button's font until its caption fits inside the button.
procedure FitButton(B: TButton);
var
  Size: Single;
begin
  B.StyledSettings := B.StyledSettings - [TStyledSetting.Size];
  Size := BTN_FONT;
  while (Size > 8) and (TextWidthOf(B.Text, B.TextSettings.Font, Size) > B.Width - 14) do
    Size := Size - 0.5;
  B.TextSettings.Font.Size := Size;
end;

/// Shrinks a one-line text's font (from BaseSize) until it fits its own width.
procedure FitText(T: TText; BaseSize: Single);
var
  Size: Single;
begin
  Size := BaseSize;
  while (Size > 8) and (T.Width > 20) and (TextWidthOf(T.Text, T.TextSettings.Font, Size) > T.Width) do
    Size := Size - 0.5;
  T.TextSettings.Font.Size := Size;
end;

{ ---------- construction ---------- }

function TMainForm.MakeButton(AParent: TFmxObject; const ACaption: string;
  AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Text := ACaption;
  Result.OnClick := AOnClick;
  Result.CanFocus := False;
end;

function TMainForm.MakeBarButton(const ACaption: string; AWidth: Single;
  AOnClick: TNotifyEvent): TRectangle;
var
  T: TText;
begin
  Result := TRectangle.Create(Self);
  Result.Parent := FTopBar;
  Result.Width := AWidth;
  Result.Fill.Color := $38FFFFFF;
  Result.Stroke.Kind := TBrushKind.None;
  Result.XRadius := 7;
  Result.YRadius := 7;
  Result.HitTest := True;
  Result.OnClick := AOnClick;
  T := TText.Create(Self);
  T.Parent := Result;
  T.SetBounds(4, 0, AWidth - 8, 34);
  T.Align := TAlignLayout.Client;
  T.Margins.Rect := RectF(4, 0, 4, 0);
  T.HitTest := False;
  T.WordWrap := False;
  T.Text := ACaption;
  T.TextSettings.Font.Size := 15;
  T.TextSettings.FontColor := TAlphaColors.White;
  T.TextSettings.HorzAlign := TTextAlign.Center;
  T.TextSettings.VertAlign := TTextAlign.Center;
  FitText(T, 15);
end;

function TMainForm.MakeText(AParent: TFmxObject; X, Y, W, H: Single; const S: string;
  Size: Single; Bold: Boolean; Align: TTextAlign): TText;
begin
  Result := TText.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, H);
  Result.HitTest := False;
  Result.WordWrap := False;
  Result.Text := S;
  Result.TextSettings.Font.Size := Size;
  if Bold then
    Result.TextSettings.Font.Style := [TFontStyle.fsBold];
  Result.TextSettings.FontColor := COL_TEXT;
  Result.TextSettings.HorzAlign := Align;
  Result.TextSettings.VertAlign := TTextAlign.Center;
  Result.TagFloat := Size;   // the size to fit down from when the text changes
  FitText(Result, Size);
end;

/// A paragraph: wraps inside W and is exactly as tall as its text.
function TMainForm.MakeWrapText(AParent: TFmxObject; X, Y, W: Single; const S: string;
  Size: Single; Bold: Boolean): TText;
begin
  Result := TText.Create(Self);
  Result.Parent := AParent;
  Result.HitTest := False;
  Result.WordWrap := True;
  Result.Text := S;
  Result.TextSettings.Font.Size := Size;
  if Bold then
    Result.TextSettings.Font.Style := [TFontStyle.fsBold];
  Result.TextSettings.FontColor := COL_TEXT;
  Result.TextSettings.HorzAlign := TTextAlign.Leading;
  Result.TextSettings.VertAlign := TTextAlign.Leading;
  // measured a few pixels narrower than it is drawn, so the last line is never lost
  Result.SetBounds(X, Y, W, Ceil(MeasureText(S, Result.TextSettings.Font, Size, Max(8, W - 8), True).Height) + 4);
end;

function TMainForm.MakePanel(K: TPanelKind; W, H: Single): TRectangle;
begin
  Result := TRectangle.Create(Self);
  Result.Parent := FOverlay;
  Result.Align := TAlignLayout.Center;
  Result.Width := W;
  Result.Height := H;
  Result.Fill.Color := $FFF6F5EE;
  Result.Stroke.Kind := TBrushKind.None;
  Result.XRadius := 12;
  Result.YRadius := 12;
  Result.Visible := False;
  FPanels[K] := Result;
end;

procedure TMainForm.BuildUI;
begin
  Fill.Kind := TBrushKind.Solid;
  Fill.Color := COL_FELT;

  FTopBar := TRectangle.Create(Self);
  FTopBar.Parent := Self;
  FTopBar.Align := TAlignLayout.Top;
  FTopBar.Height := 46;
  FTopBar.Fill.Color := COL_BAR;
  FTopBar.Stroke.Kind := TBrushKind.None;
  FTopBar.Padding.Rect := RectF(6, 6, 6, 6);

  // the strip behind the clock/battery icons matches the toolbar (iOS picks
  // light status-bar text for a dark colour)
  SystemStatusBar.BackgroundColor := COL_BAR;

  FBtnNew := MakeBarButton('New', 64, NewClick);
  FBtnNew.Align := TAlignLayout.Left;
  FBtnNew.Margins.Right := 6;

  FBtnUndo := MakeBarButton('Undo', 64, UndoClick);
  FBtnUndo.Align := TAlignLayout.Left;
  FBtnUndo.Margins.Right := 6;
  FBtnUndo.Position.X := 100;   // keeps the left-aligned buttons in creation order

  FBtnHint := MakeBarButton('Hint', 64, HintClick);
  FBtnHint.Align := TAlignLayout.Left;
  FBtnHint.Position.X := 200;

  FBtnMenu := MakeBarButton('Menu', 72, MenuClick);
  FBtnMenu.Align := TAlignLayout.Right;

  FStatus := TText.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := TAlignLayout.Bottom;
  FStatus.Height := 26;
  FStatus.HitTest := False;
  FStatus.WordWrap := False;
  FStatus.TextSettings.Font.Size := 13;
  FStatus.TextSettings.FontColor := TAlphaColors.White;
  FStatus.TextSettings.HorzAlign := TTextAlign.Center;

  FBoard := TSolitaireBoard.Create(Self);
  FBoard.Parent := Self;
  FBoard.Align := TAlignLayout.Client;
  FBoard.WinEffect := TWinEffect(FStats.WinEffect);
  FBoard.CardStyle := TCardStyle(FStats.CardStyle);
  FBoard.OnChanged := BoardChanged;
  FBoard.OnNewGameRequest := BoardNewGame;

  FClock := TTimer.Create(Self);
  FClock.Interval := 1000;
  FClock.OnTimer := ClockTick;
  FClock.Enabled := True;

  FOverlay := TRectangle.Create(Self);
  FOverlay.Parent := Self;
  FOverlay.Align := TAlignLayout.Contents;
  FOverlay.Fill.Color := $B0000000;
  FOverlay.Stroke.Kind := TBrushKind.None;
  FOverlay.OnClick := CloseClick;
  FOverlay.Visible := False;

  FHelpItems := TList<TText>.Create;
  BuildMenuPanel;
  BuildGamesPanel;
  BuildHelpPanel;
  BuildOptionsPanel;
end;

procedure TMainForm.BuildMenuPanel;
var
  P: TRectangle;

  procedure Item(Y: Single; const Caption: string; Click: TNotifyEvent);
  var
    B: TButton;
  begin
    B := MakeButton(P, Caption, Click);
    B.SetBounds(16, Y, PANEL_W - 32, 42);
    FitButton(B);
  end;

begin
  P := MakePanel(pnMenu, PANEL_W, 266);
  MakeText(P, 16, 10, PANEL_W - 32, 28, 'Menu', 17, True, TTextAlign.Center);
  Item(48, 'Choose game', MenuGamesClick);
  Item(98, 'How to play', MenuHelpClick);
  Item(148, 'Options and statistics', MenuOptionsClick);
  Item(208, 'Close', CloseClick);
end;

procedure TMainForm.BuildGamesPanel;
var
  P, Row: TRectangle;
  I: Integer;
  B: TButton;
  Y: Single;
  T: TText;
begin
  P := MakePanel(pnGames, PANEL_W, 52 + Length(GAME_CLASSES) * 72 + 52);
  MakeText(P, 16, 10, PANEL_W - 32, 28, 'Choose a game', 17, True, TTextAlign.Center);
  SetLength(FGameRows, Length(GAME_CLASSES));
  SetLength(FGameTitles, Length(GAME_CLASSES));
  for I := 0 to High(GAME_CLASSES) do
  begin
    Y := 46 + I * 72;
    Row := TRectangle.Create(Self);
    Row.Parent := P;
    Row.SetBounds(16, Y, PANEL_W - 32, 66);
    Row.Fill.Color := COL_ROW;
    Row.Stroke.Kind := TBrushKind.None;
    Row.XRadius := 8;
    Row.YRadius := 8;
    Row.HitTest := True;
    Row.Tag := I;
    Row.OnClick := GameRowClick;
    FGameRows[I] := Row;
    FGameTitles[I] := MakeText(Row, 10, 4, PANEL_W - 52, 22, GAME_CLASSES[I].Title, 15, True, TTextAlign.Leading);
    T := MakeWrapText(Row, 10, 27, PANEL_W - 52, GAME_CLASSES[I].Blurb, 12, False);
    T.TextSettings.FontColor := $FF404040;
  end;
  B := MakeButton(P, 'Close', CloseClick);
  B.SetBounds(16, 46 + Length(GAME_CLASSES) * 72 + 6, PANEL_W - 32, 36);
  FitButton(B);
end;

procedure TMainForm.BuildHelpPanel;
var
  P: TRectangle;
begin
  P := MakePanel(pnHelp, 420, 560);
  FHelpTitle := MakeText(P, 16, 10, 388, 28, 'How to play', 17, True, TTextAlign.Center);
  FHelpBox := TVertScrollBox.Create(Self);
  FHelpBox.Parent := P;
  FHelpBox.SetBounds(16, 44, 388, 460);
  FHelpClose := MakeButton(P, 'Close', CloseClick);
  FHelpClose.SetBounds(16, 512, 388, 36);
  FitButton(FHelpClose);
end;

procedure TMainForm.BuildOptionsPanel;
var
  P: TRectangle;
  I, C: Integer;
  Y: Single;
begin
  P := MakePanel(pnOptions, PANEL_W, 564);
  FOptTitle := MakeText(P, 16, 10, PANEL_W - 32, 28, 'Options and statistics', 17, True, TTextAlign.Center);

  // each setting is a short label plus a button that only shows the value,
  // so no caption has to squeeze a whole sentence into a button
  FVariantLabel := MakeText(P, 16, 46, 130, 34, '', 14, False, TTextAlign.Leading);
  FBtnVariant := MakeButton(P, '', VariantClick);
  FBtnVariant.SetBounds(150, 46, 154, 34);
  FVariantNote := MakeText(P, 16, 80, PANEL_W - 32, 16, 'A change applies from the next deal', 11,
    False, TTextAlign.Trailing);
  FVariantNote.TextSettings.FontColor := COL_DIM;

  MakeText(P, 16, 102, 130, 34, 'Win effect', 14, False, TTextAlign.Leading);
  FBtnEffect := MakeButton(P, '', EffectClick);
  FBtnEffect.SetBounds(150, 102, 154, 34);
  FBtnPreview := MakeButton(P, 'Preview win effect', PreviewClick);
  FBtnPreview.SetBounds(16, 142, PANEL_W - 32, 34);

  MakeText(P, 16, 182, 130, 34, 'Card style', 14, False, TTextAlign.Leading);
  FBtnStyle := MakeButton(P, '', StyleClick);
  FBtnStyle.SetBounds(150, 182, 154, 34);

  MakeText(P, 16, 222, 130, 34, 'Sounds', 14, False, TTextAlign.Leading);
  FBtnSound := MakeButton(P, '', SoundClick);
  FBtnSound.SetBounds(150, 222, 154, 34);

  for C := 0 to 2 do
    FHeads[C] := MakeText(P, 150 + C * 52, 266, 50, 22, '', 13, True, TTextAlign.Trailing);
  for I := 0 to High(STAT_LABELS) do
  begin
    Y := 290 + I * 24;
    MakeText(P, 16, Y, 132, 22, STAT_LABELS[I], 13, False, TTextAlign.Leading);
    for C := 0 to 2 do
      FCells[I, C] := MakeText(P, 150 + C * 52, Y, 50, 22, '', 13, False, TTextAlign.Trailing);
  end;

  FBtnReset := MakeButton(P, 'Reset stats', ResetClick);
  FBtnReset.SetBounds(16, 514, 140, 36);
  FBtnOptClose := MakeButton(P, 'Close', CloseClick);
  FBtnOptClose.SetBounds(164, 514, 140, 36);
  FitButton(FBtnPreview);
  FitButton(FBtnReset);
  FitButton(FBtnOptClose);
end;

{ Lays the current game's rules out as headings, paragraphs and bullet points. }
procedure TMainForm.FillHelp;
var
  T: TText;
  Line, S: string;
  W, Y: Single;
begin
  for T in FHelpItems do
    T.Free;
  FHelpItems.Clear;
  FHelpTitle.Text := FGame.Title + ' - how to play';
  FitText(FHelpTitle, 17);

  W := FHelpBox.Width - 24;   // room for the scroll bar
  Y := 0;
  for Line in FGame.Rules.Split([sLineBreak]) do
  begin
    S := Line.Trim;
    if S = '' then
      Continue;
    if S.StartsWith('# ') then
    begin
      if Y > 0 then
        Y := Y + 10;
      T := MakeWrapText(FHelpBox, 2, Y, W, S.Substring(2), 15.5, True);
      T.TextSettings.FontColor := $FF14532D;
      FHelpItems.Add(T);
      Y := Y + T.Height + 2;
    end
    else if S.StartsWith('- ') then
    begin
      T := MakeWrapText(FHelpBox, 6, Y, 12, Char($2022), 13.5, False);
      FHelpItems.Add(T);
      T := MakeWrapText(FHelpBox, 20, Y, W - 20, S.Substring(2), 13.5, False);
      FHelpItems.Add(T);
      Y := Y + T.Height + 3;
    end
    else
    begin
      T := MakeWrapText(FHelpBox, 2, Y, W, S, 13.5, False);
      FHelpItems.Add(T);
      Y := Y + T.Height + 4;
    end;
  end;
  // a little space after the last line
  T := MakeWrapText(FHelpBox, 2, Y, W, ' ', 8, False);
  FHelpItems.Add(T);
  FHelpBox.ViewportPosition := PointF(0, 0);
end;

procedure TMainForm.UpdateGamesPanel;
var
  I: Integer;
begin
  for I := 0 to High(FGameRows) do
  begin
    if I = FGameIndex then
    begin
      FGameRows[I].Fill.Color := COL_ROW_ON;
      FGameTitles[I].Text := GAME_CLASSES[I].Title + '  (playing now)';
    end
    else
    begin
      FGameRows[I].Fill.Color := COL_ROW;
      FGameTitles[I].Text := GAME_CLASSES[I].Title;
    end;
    FitText(FGameTitles[I], 15);
  end;
end;

procedure TMainForm.UpdateOptions;
var
  C, VC, I: Integer;
  M: TModeStats;
  HasVariants: Boolean;

  function TimeOrDash(V: Integer): string;
  begin
    if V > 0 then
      Result := FormatGameTime(V)
    else
      Result := '-';
  end;

  function NumOrDash(V: Integer): string;
  begin
    if V > 0 then
      Result := IntToStr(V)
    else
      Result := '-';
  end;

  procedure Cell(Row, Col: Integer; const S: string);
  begin
    FCells[Row, Col].Text := S;
    FitText(FCells[Row, Col], 13);
  end;

begin
  FOptTitle.Text := FGame.Title + ' - options';
  FitText(FOptTitle, 17);
  VC := FGame.VariantCount;
  HasVariants := VC > 1;
  FVariantLabel.Visible := HasVariants;
  FBtnVariant.Visible := HasVariants;
  FVariantNote.Visible := HasVariants;
  if HasVariants then
  begin
    FVariantLabel.Text := FGame.VariantLabel;
    FitText(FVariantLabel, 14);
    FBtnVariant.Text := FGame.VariantName(FStats.GetVariant(FGame.GameId));
    FitButton(FBtnVariant);
  end;
  FBtnEffect.Text := WIN_EFFECT_NAMES[TWinEffect(FStats.WinEffect)];
  FitButton(FBtnEffect);
  FBtnStyle.Text := CARD_STYLE_NAMES[TCardStyle(FStats.CardStyle)];
  FitButton(FBtnStyle);
  if FStats.Sounds then
    FBtnSound.Text := 'On'
  else
    FBtnSound.Text := 'Off';
  FitButton(FBtnSound);

  // one statistics column per variant, right-aligned against the panel edge
  for C := 0 to 2 do
  begin
    FHeads[C].Visible := C < VC;
    FHeads[C].Position.X := PANEL_W - 16 - (VC - C) * 52 + 2;
    for I := 0 to High(STAT_LABELS) do
    begin
      FCells[I, C].Visible := C < VC;
      FCells[I, C].Position.X := FHeads[C].Position.X;
    end;
    if C >= VC then
      Continue;
    if HasVariants then
      FHeads[C].Text := FGame.VariantName(C)
    else
      FHeads[C].Text := 'All';
    FitText(FHeads[C], 13);
    M := FStats.Get(FGame.GameId, C);
    Cell(0, C, IntToStr(M.Played));
    Cell(1, C, IntToStr(M.Won));
    if M.Played > 0 then
      Cell(2, C, Format('%d%%', [Round(100 * M.Won / M.Played)]))
    else
      Cell(2, C, '-');
    Cell(3, C, IntToStr(M.Streak));
    Cell(4, C, IntToStr(M.BestStreak));
    Cell(5, C, TimeOrDash(M.BestTime));
    if M.Won > 0 then
      Cell(6, C, TimeOrDash(Max(1, M.TotalWinTime div M.Won)))
    else
      Cell(6, C, '-');
    Cell(7, C, NumOrDash(M.BestScore));
    Cell(8, C, NumOrDash(M.FewestMoves));
  end;
end;

{ Fits the panels to the window: fixed-size panels are scaled down on small or
  sideways screens; the help panel is resized instead, so its text stays readable. }
procedure TMainForm.LayoutPanels;
var
  K: TPanelKind;
  P: TRectangle;
  S, W, H: Single;
begin
  if FOverlay = nil then
    Exit;
  for K := Succ(pnNone) to High(TPanelKind) do
  begin
    P := FPanels[K];
    if P = nil then
      Continue;
    if K = pnHelp then
    begin
      W := EnsureRange(ClientWidth - 16, 200, 460);
      H := EnsureRange(ClientHeight - 16, 160, 680);
      if (Abs(P.Width - W) > 0.5) or (Abs(P.Height - H) > 0.5) then
      begin
        P.Width := W;
        P.Height := H;
        FHelpTitle.Width := W - 32;
        FHelpBox.SetBounds(16, 44, W - 32, H - 44 - 52);
        FHelpClose.SetBounds(16, H - 46, W - 32, 36);
        if (FPanel = pnHelp) and (FGame <> nil) then
          FillHelp;
      end;
      Continue;
    end;
    S := Min(1, Min((ClientWidth - 16) / P.Width, (ClientHeight - 16) / P.Height));
    S := Max(S, 0.3);
    P.Scale.Point := PointF(S, S);
  end;
end;

function TMainForm.CheckTextFits(out Msg: string): Boolean;

  function Scan(AParent: TFmxObject; var M: string): Boolean;
  var
    I: Integer;
    C: TFmxObject;
    W: Single;
  begin
    Result := True;
    for I := 0 to AParent.ChildrenCount - 1 do
    begin
      C := AParent.Children[I];
      if C is TButton then
      begin
        if not TButton(C).Visible then
          Continue;
        W := TextWidthOf(TButton(C).Text, TButton(C).TextSettings.Font, TButton(C).TextSettings.Font.Size);
        if W > TButton(C).Width - 8 then
        begin
          M := Format('button "%s" needs %.0f but is %.0f wide', [TButton(C).Text, W, TButton(C).Width]);
          Exit(False);
        end;
      end
      else if C is TText then
      begin
        if (not TText(C).Visible) or TText(C).WordWrap then
          Continue;   // wrapped paragraphs are sized to their text when built
        W := TextWidthOf(TText(C).Text, TText(C).TextSettings.Font, TText(C).TextSettings.Font.Size);
        if W > TText(C).Width + 0.5 then
        begin
          M := Format('text "%s" needs %.0f but is %.0f wide', [TText(C).Text, W, TText(C).Width]);
          Exit(False);
        end;
      end
      else if (C is TRectangle) or (C is TVertScrollBox) or (C.ClassName = 'TScrollContent') then
        if not Scan(C, M) then
          Exit(False);
    end;
  end;

var
  K: TPanelKind;
  P: TRectangle;
begin
  Msg := '';
  UpdateOptions;
  UpdateGamesPanel;
  LayoutPanels;
  UpdateStatus;
  Result := Scan(FTopBar, Msg) and Scan(FOverlay, Msg);
  if Result and (TextWidthOf(FStatus.Text, FStatus.TextSettings.Font, FStatus.TextSettings.Font.Size) > FStatus.Width + 0.5) then
  begin
    Msg := 'status line "' + FStatus.Text + '" is cut off';
    Result := False;
  end;
  if Result then
    for K := Succ(pnNone) to High(TPanelKind) do
    begin
      P := FPanels[K];
      if (P.Width * P.Scale.X > ClientWidth + 0.5) or (P.Height * P.Scale.Y > ClientHeight + 0.5) then
      begin
        Msg := Format('panel %d (%.0fx%.0f) does not fit the %dx%d window',
          [Ord(K), P.Width * P.Scale.X, P.Height * P.Scale.Y, ClientWidth, ClientHeight]);
        Exit(False);
      end;
    end;
end;

function TMainForm.PanelControl(K: TPanelKind): TRectangle;
begin
  Result := FPanels[K];
end;

function TMainForm.StatusText: string;
begin
  Result := FStatus.Text;
end;

function TMainForm.HelpItemCount: Integer;
begin
  Result := FHelpItems.Count;
end;

{ ---------- form events ---------- }

procedure TMainForm.FormCreate(Sender: TObject);
var
  SelfTesting, Demo: Boolean;
begin
  Randomize;
  SelfTesting := FindCmdLineSwitch('selftest');
  Demo := not SelfTesting and DemoRequested;
  if SelfTesting then
    PrepareSelfTestData    // isolated folder: never touches the real statistics
  else if Demo then
    PrepareDemoData;
{$IFDEF MSWINDOWS}
  // on the desktop the game opens filling the screen (the self-test sizes its own
  // window; the demo uses a 16:9 window that suits a video)
  if Demo then
  begin
    ClientWidth := 1280;
    ClientHeight := 720;
  end
  else if not SelfTesting then
    WindowState := TWindowState.wsMaximized;
{$ENDIF}

  FStats := TStatsStore.Create;
  BuildUI;
  OnKeyDown := FormKey;
  OnSafeAreaChanged := SafeAreaChanged;

  FGameIndex := Max(0, GameIndexOf(FStats.CurrentGame));
  FGame := GAME_CLASSES[FGameIndex].Create;
  LoadOrDeal;
  FBoard.Game := FGame;
  UpdateStatus;

  if SelfTesting then
    FSelfTest := TSelfTest.Create(Self)
  else if Demo then
    FDemo := TDemo.Create(Self);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  SaveGame;
  FreeAndNil(FSelfTest);
  FreeAndNil(FDemo);
  FBoard.Game := nil;
  FreeAndNil(FHelpItems);
  FreeAndNil(FGame);
  FreeAndNil(FStats);
end;

procedure TMainForm.FormResize(Sender: TObject);
begin
  LayoutPanels;
  if FStatus <> nil then
    UpdateStatus;
end;

procedure TMainForm.FormSaveState(Sender: TObject);
begin
  // fires when a mobile app goes to the background and when the form closes
  SaveGame;
end;

procedure TMainForm.SafeAreaChanged(Sender: TObject; const AInsets: TRectF);
begin
  // keep clear of notches, rounded corners and the home indicator
  Padding.Rect := AInsets;
end;

procedure TMainForm.FormKey(Sender: TObject; var Key: Word; var KeyChar: WideChar;
  Shift: TShiftState);
begin
  if (FPanel <> pnNone) and ((Key = vkEscape) or (Key = vkHardwareBack)) then
  begin
    ShowPanel(pnNone);
    Key := 0;
  end
  else if FPanel <> pnNone then
    Exit
  else if Key = vkF1 then
    ShowPanel(pnHelp)
  else if Key = vkF2 then
    NewClick(nil)
  else if (ssCtrl in Shift) and ((KeyChar = 'z') or (KeyChar = 'Z') or (Key = vkZ)) then
    DoUndo
  else if (KeyChar = 'h') or (KeyChar = 'H') then
    DoHint;
end;

{ ---------- persistence ---------- }

function TMainForm.GameFile(AClass: TCardGameClass): string;
begin
  // every game keeps its own unfinished deal
  Result := System.IOUtils.TPath.Combine(AppDataDir, 'game-' + AClass.GameId + '.dat');
end;

procedure TMainForm.SaveGame;
var
  FS: TFileStream;
begin
  if FGame = nil then
    Exit;
  try
    FS := TFileStream.Create(GameFile(TCardGameClass(FGame.ClassType)), fmCreate);
    try
      FGame.SaveToStream(FS);
    finally
      FS.Free;
    end;
  except
    // a failed save must never crash the game
  end;
end;

procedure TMainForm.LoadOrDeal;
var
  FS: TFileStream;
  Ok: Boolean;
  FN: string;
begin
  Ok := False;
  FN := GameFile(TCardGameClass(FGame.ClassType));
  try
    if TFile.Exists(FN) then
    begin
      FS := TFileStream.Create(FN, fmOpenRead or fmShareDenyWrite);
      try
        Ok := FGame.LoadFromStream(FS);
      finally
        FS.Free;
      end;
    end;
  except
    Ok := False;
  end;
  if (not Ok) or FGame.IsWon then
    FGame.NewGame(FStats.GetVariant(FGame.GameId));
end;

{ ---------- game flow ---------- }

procedure TMainForm.StartNewGame(ASeed: Integer);
begin
  if FGame.Counted and not FGame.IsWon then
    FStats.RecordLoss(FGame.GameId, FGame.Variant);
  FGame.NewGame(FStats.GetVariant(FGame.GameId), ASeed);
  FBoard.Reset;
  if FStats.Sounds then
    PlayGameSound(skShuffle);
  UpdateStatus;
  SaveGame;
end;

procedure TMainForm.SwitchGame(AIndex: Integer);
var
  Old: TCardGame;
begin
  if (AIndex < 0) or (AIndex > High(GAME_CLASSES)) or (AIndex = FGameIndex) then
    Exit;
  SaveGame;   // the deal being left is kept for when the player comes back
  Old := FGame;
  FGameIndex := AIndex;
  FGame := GAME_CLASSES[AIndex].Create;
  LoadOrDeal;
  FBoard.Game := FGame;
  Old.Free;
  FStats.CurrentGame := FGame.GameId;
  FStats.Save;
  FNote := '';
  UpdateStatus;
end;

function TMainForm.DoUndo: Boolean;
begin
  Result := False;
  if FBoard.Busy then
    Exit;
  Result := FGame.Undo;
  if Result then
  begin
    FBoard.Reset;
    UpdateStatus;
  end;
end;

function TMainForm.DoHint: Boolean;
begin
  Result := FBoard.ShowHint;
  if not Result and not FBoard.Busy then
  begin
    if FGame.IsStuck then
      FNote := 'No more moves - tap New to deal again'
    else
      FNote := 'No suggestion for this position';
    FNoteTicks := 3;
    UpdateStatus;
  end;
end;

procedure TMainForm.BoardChanged(Sender: TObject);
begin
  if (not FGame.Counted) and (FGame.Moves > 0) then
  begin
    FGame.Counted := True;
    FStats.RecordStart(FGame.GameId, FGame.Variant);
  end;
  if FGame.IsWon and not FGame.WinRecorded then
  begin
    FGame.WinRecorded := True;
    FStats.RecordWin(FGame.GameId, FGame.Variant, FGame.Seconds, FGame.Score, FGame.Moves);
    if FStats.Sounds then
      PlayGameSound(skWin);
    SaveGame;
  end;
  FNote := '';
  UpdateStatus;
end;

procedure TMainForm.BoardNewGame(Sender: TObject);
begin
  StartNewGame;
end;

procedure TMainForm.ClockTick(Sender: TObject);
begin
  if FNoteTicks > 0 then
  begin
    Dec(FNoteTicks);
    if FNoteTicks = 0 then
      FNote := '';
  end;
  if (FGame.Moves > 0) and not FGame.IsWon and (FPanel = pnNone) then
    FGame.Seconds := FGame.Seconds + 1;
  UpdateStatus;
end;

procedure TMainForm.UpdateStatus;
var
  S, Extra: string;
begin
  if FGame = nil then
    Exit;
  if FNote <> '' then
    S := FNote
  else
  begin
    S := FGame.Title;
    if FGame.VariantCount > 1 then
      S := S + ' ' + FGame.VariantName(FGame.Variant);
    S := S + Format('     Score %d     Moves %d     Time %s',
      [FGame.Score, FGame.Moves, FormatGameTime(FGame.Seconds)]);
    Extra := FGame.StatusExtra;
    if Extra <> '' then
      S := S + '     ' + Extra;
  end;
  FStatus.Text := S;
  FitText(FStatus, 13);
  FBtnUndo.HitTest := FGame.CanUndo;
  if FGame.CanUndo then
    FBtnUndo.Opacity := 1
  else
    FBtnUndo.Opacity := 0.4;
end;

procedure TMainForm.NewClick(Sender: TObject);
begin
  if FGame.Counted and not FGame.IsWon then
    TDialogService.MessageDialog('Abandon this game? It will count as a loss.',
      TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], TMsgDlgBtn.mbNo, 0,
      procedure(const AResult: TModalResult)
      begin
        if AResult = mrYes then
          StartNewGame;
      end)
  else
    StartNewGame;
end;

procedure TMainForm.UndoClick(Sender: TObject);
begin
  DoUndo;
end;

procedure TMainForm.HintClick(Sender: TObject);
begin
  DoHint;
end;

{ ---------- panels ---------- }

procedure TMainForm.ShowPanel(K: TPanelKind);
var
  I: TPanelKind;
begin
  FPanel := K;
  if K <> pnNone then
  begin
    case K of
      pnGames:   UpdateGamesPanel;
      pnOptions: UpdateOptions;
    end;
    LayoutPanels;
    if K = pnHelp then
      FillHelp;
    FOverlay.BringToFront;
  end;
  for I := Succ(pnNone) to High(TPanelKind) do
    FPanels[I].Visible := I = K;
  FOverlay.Visible := K <> pnNone;
end;

procedure TMainForm.MenuClick(Sender: TObject);
begin
  ShowPanel(pnMenu);
end;

procedure TMainForm.CloseClick(Sender: TObject);
begin
  ShowPanel(pnNone);
end;

procedure TMainForm.MenuGamesClick(Sender: TObject);
begin
  ShowPanel(pnGames);
end;

procedure TMainForm.MenuHelpClick(Sender: TObject);
begin
  ShowPanel(pnHelp);
end;

procedure TMainForm.MenuOptionsClick(Sender: TObject);
begin
  ShowPanel(pnOptions);
end;

procedure TMainForm.GameRowClick(Sender: TObject);
begin
  ShowPanel(pnNone);
  SwitchGame(TFmxObject(Sender).Tag);
end;

procedure TMainForm.VariantClick(Sender: TObject);
begin
  FStats.SetVariant(FGame.GameId, (FStats.GetVariant(FGame.GameId) + 1) mod FGame.VariantCount);
  FStats.Save;
  // an untouched deal can simply be dealt again in the new variant
  if not FGame.Counted then
    StartNewGame;
  UpdateOptions;
end;

procedure TMainForm.EffectClick(Sender: TObject);
begin
  FStats.WinEffect := (FStats.WinEffect + 1) mod (Ord(High(TWinEffect)) + 1);
  FStats.Save;
  FBoard.WinEffect := TWinEffect(FStats.WinEffect);
  UpdateOptions;
end;

procedure TMainForm.StyleClick(Sender: TObject);
begin
  FStats.CardStyle := (FStats.CardStyle + 1) mod (Ord(High(TCardStyle)) + 1);
  FStats.Save;
  FBoard.CardStyle := TCardStyle(FStats.CardStyle);
  UpdateOptions;
end;

procedure TMainForm.SoundClick(Sender: TObject);
begin
  FStats.Sounds := not FStats.Sounds;
  FStats.Save;
  if FStats.Sounds then
    PlayGameSound(skShuffle);   // so the player hears what was switched on
  UpdateOptions;
end;

procedure TMainForm.PreviewClick(Sender: TObject);
begin
  ShowPanel(pnNone);
  FBoard.PreviewWin;
end;

procedure TMainForm.ResetClick(Sender: TObject);
begin
  TDialogService.MessageDialog('Reset the ' + FGame.Title + ' statistics?',
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], TMsgDlgBtn.mbNo, 0,
    procedure(const AResult: TModalResult)
    begin
      if AResult = mrYes then
      begin
        FStats.ResetGame(FGame.GameId);
        UpdateOptions;
      end;
    end);
end;

end.
