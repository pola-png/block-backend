Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $root 'output\playstore-listing'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Get-ChildItem -LiteralPath $outDir -Filter '*.png' -ErrorAction SilentlyContinue | Remove-Item -Force
$sourceShotDir = 'C:\Users\user\Pictures\XapZap logo\screenshot'

$iconPath = Join-Path $root 'assets\icons\xapzap_app_icon.png'
$icon = if (Test-Path $iconPath) { [System.Drawing.Image]::FromFile($iconPath) } else { $null }

$screens = @{
  home = Join-Path $sourceShotDir 'Screenshot_20260420-121111.png'
  feed = Join-Path $sourceShotDir 'Screenshot.jpeg'
  watch = Join-Path $sourceShotDir 'screenshot2.jpeg'
  reels = Join-Path $sourceShotDir 'screenshot3.jpeg'
  profile = Join-Path $sourceShotDir 'screenshot5.jpeg'
  creator = Join-Path $sourceShotDir 'screenshot6.jpeg'
}

function New-Brush([string]$Hex) {
  New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml($Hex))
}

function New-Pen([string]$Hex, [float]$Width) {
  New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml($Hex)), $Width
}

function Fill-RoundedRect {
  param(
    [System.Drawing.Graphics]$G,
    [System.Drawing.Brush]$Brush,
    [float]$X,
    [float]$Y,
    [float]$W,
    [float]$H,
    [float]$R
  )
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $R * 2
  $path.AddArc($X, $Y, $d, $d, 180, 90)
  $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
  $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
  $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  $G.FillPath($Brush, $path)
  $path.Dispose()
}

function Draw-RoundedRect {
  param(
    [System.Drawing.Graphics]$G,
    [System.Drawing.Pen]$Pen,
    [float]$X,
    [float]$Y,
    [float]$W,
    [float]$H,
    [float]$R
  )
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $R * 2
  $path.AddArc($X, $Y, $d, $d, 180, 90)
  $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
  $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
  $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  $G.DrawPath($Pen, $path)
  $path.Dispose()
}

function Draw-Circle {
  param(
    [System.Drawing.Graphics]$G,
    [string]$Hex,
    [float]$X,
    [float]$Y,
    [float]$Size
  )
  $brush = New-Brush $Hex
  $G.FillEllipse($brush, $X, $Y, $Size, $Size)
  $brush.Dispose()
}

function Draw-Label {
  param(
    [System.Drawing.Graphics]$G,
    [string]$Text,
    [System.Drawing.Font]$Font,
    [string]$Hex,
    [float]$X,
    [float]$Y,
    [float]$W,
    [float]$H,
    [string]$Align = 'Near'
  )
  $brush = New-Brush $Hex
  $rect = New-Object System.Drawing.RectangleF($X, $Y, $W, $H)
  $fmt = New-Object System.Drawing.StringFormat
  switch ($Align) {
    'Center' { $fmt.Alignment = [System.Drawing.StringAlignment]::Center }
    'Far' { $fmt.Alignment = [System.Drawing.StringAlignment]::Far }
    default { $fmt.Alignment = [System.Drawing.StringAlignment]::Near }
  }
  $fmt.LineAlignment = [System.Drawing.StringAlignment]::Near
  $G.DrawString($Text, $Font, $brush, $rect, $fmt)
  $fmt.Dispose()
  $brush.Dispose()
}

function Draw-Line {
  param(
    [System.Drawing.Graphics]$G,
    [string]$Hex,
    [float]$X,
    [float]$Y,
    [float]$W,
    [float]$H = 10,
    [float]$R = 5
  )
  $brush = New-Brush $Hex
  Fill-RoundedRect $G $brush $X $Y $W $H $R
  $brush.Dispose()
}

function Draw-GradientRect {
  param(
    [System.Drawing.Graphics]$G,
    [float]$X,
    [float]$Y,
    [float]$W,
    [float]$H,
    [float]$R,
    [string]$HexA,
    [string]$HexB,
    [float]$Angle = 45.0
  )
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $R * 2
  $path.AddArc($X, $Y, $d, $d, 180, 90)
  $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
  $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
  $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  $rect = New-Object System.Drawing.RectangleF($X, $Y, $W, $H)
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect,
    ([System.Drawing.ColorTranslator]::FromHtml($HexA)),
    ([System.Drawing.ColorTranslator]::FromHtml($HexB)),
    $Angle
  )
  $G.FillPath($brush, $path)
  $brush.Dispose()
  $path.Dispose()
}

function Draw-ImageCover {
  param(
    [System.Drawing.Graphics]$G,
    [System.Drawing.Image]$Image,
    [float]$X,
    [float]$Y,
    [float]$W,
    [float]$H,
    [float]$R
  )
  if ($Image -eq $null) { return }
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = $R * 2
  $path.AddArc($X, $Y, $d, $d, 180, 90)
  $path.AddArc($X + $W - $d, $Y, $d, $d, 270, 90)
  $path.AddArc($X + $W - $d, $Y + $H - $d, $d, $d, 0, 90)
  $path.AddArc($X, $Y + $H - $d, $d, $d, 90, 90)
  $path.CloseFigure()

  $state = $G.Save()
  $G.SetClip($path)

  $srcAspect = $Image.Width / $Image.Height
  $dstAspect = $W / $H
  if ($srcAspect -gt $dstAspect) {
    $scale = $H / $Image.Height
    $drawW = $Image.Width * $scale
    $drawH = $H
    $drawX = $X - (($drawW - $W) / 2)
    $drawY = $Y
  } else {
    $scale = $W / $Image.Width
    $drawW = $W
    $drawH = $Image.Height * $scale
    $drawX = $X
    $drawY = $Y - (($drawH - $H) / 2)
  }

  $G.DrawImage($Image, [float]$drawX, [float]$drawY, [float]$drawW, [float]$drawH)
  $G.Restore($state)
  $path.Dispose()
}

function Get-SourceImage {
  param([string]$Key)
  $path = $screens[$Key]
  if (-not $path) { return $null }
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  return [System.Drawing.Image]::FromFile($path)
}

function Draw-ScreenshotCard {
  param(
    [System.Drawing.Graphics]$G,
    [float]$X,
    [float]$Y,
    [float]$W,
    [float]$H,
    [System.Drawing.Image]$Image,
    [string]$Accent
  )
  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(44, 7, 11, 22))
  Fill-RoundedRect $G $shadow ($X + 12) ($Y + 14) $W $H 30
  $shadow.Dispose()

  Draw-GradientRect $G $X $Y $W $H 30 '#111827' '#1E293B' 90
  $framePen = New-Pen '#334155' 2
  Draw-RoundedRect $G $framePen $X $Y $W $H 30
  $framePen.Dispose()

  Draw-ImageCover $G $Image ($X + 16) ($Y + 16) ($W - 32) ($H - 32) 22
  $badge = New-Brush '#FFFFFF'
  Fill-RoundedRect $G $badge ($X + 28) ($Y + 28) 110 30 15
  $badge.Dispose()
  Draw-Label $G 'XapZap' (New-Object System.Drawing.Font('Segoe UI Semibold', 11, [System.Drawing.FontStyle]::Bold)) $Accent ($X + 48) ($Y + 36) 60 16
}

function Draw-SectionCard {
  param(
    [System.Drawing.Graphics]$G,
    [float]$X,
    [float]$Y,
    [float]$W,
    [float]$H,
    [string]$Fill = '#FFFFFF',
    [string]$Stroke = '#E7EEF7'
  )
  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(26, 16, 24, 40))
  Fill-RoundedRect $G $shadow ($X + 8) ($Y + 10) $W $H 26
  $shadow.Dispose()
  $brush = New-Brush $Fill
  Fill-RoundedRect $G $brush $X $Y $W $H 26
  $brush.Dispose()
  $pen = New-Pen $Stroke 2
  Draw-RoundedRect $G $pen $X $Y $W $H 26
  $pen.Dispose()
}

function Draw-GradientBackground {
  param(
    [System.Drawing.Graphics]$G,
    [int]$W,
    [int]$H,
    [string]$TopHex,
    [string]$BottomHex,
    [string]$GlowHex
  )
  $rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
  $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    $rect,
    ([System.Drawing.ColorTranslator]::FromHtml($TopHex)),
    ([System.Drawing.ColorTranslator]::FromHtml($BottomHex)),
    90.0
  )
  $G.FillRectangle($brush, $rect)
  $brush.Dispose()

  $glow = [System.Drawing.ColorTranslator]::FromHtml($GlowHex)
  $g1 = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(70, $glow))
  $g2 = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(46, $glow))
  $g3 = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(30, 255, 255, 255))
  $G.FillEllipse($g1, -160, -100, 560, 560)
  $G.FillEllipse($g2, $W - 460, $H - 740, 640, 640)
  $G.FillEllipse($g3, $W - 340, 80, 260, 260)
  $g1.Dispose()
  $g2.Dispose()
  $g3.Dispose()
}

function Draw-HeaderBlock {
  param(
    [System.Drawing.Graphics]$G,
    [string]$Headline,
    [string]$Subline,
    [System.Drawing.Image]$Icon
  )
  if ($Icon -ne $null) {
    Draw-Circle $G '#FFFFFF' 86 86 112
    $G.DrawImage($Icon, 102, 102, 80, 80)
  }
  $brandFont = New-Object System.Drawing.Font('Segoe UI Semibold', 38, [System.Drawing.FontStyle]::Bold)
  $headlineFont = New-Object System.Drawing.Font('Segoe UI Semibold', 52, [System.Drawing.FontStyle]::Bold)
  $subFont = New-Object System.Drawing.Font('Segoe UI', 17, [System.Drawing.FontStyle]::Regular)
  Draw-Label $G 'XapZap' $brandFont '#FFFFFF' 214 94 320 64
  Draw-Label $G $Headline $headlineFont '#FFFFFF' 86 238 900 180
  Draw-Label $G $Subline $subFont '#E9F0FF' 86 420 840 80
  $brandFont.Dispose()
  $headlineFont.Dispose()
  $subFont.Dispose()
}

function Draw-PhoneShell {
  param(
    [System.Drawing.Graphics]$G,
    [float]$X,
    [float]$Y,
    [float]$W,
    [float]$H
  )
  $shadow = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(76, 4, 8, 18))
  Fill-RoundedRect $G $shadow ($X + 24) ($Y + 28) $W $H 64
  $shadow.Dispose()

  $bodyBrush = New-Brush '#0C1221'
  Fill-RoundedRect $G $bodyBrush $X $Y $W $H 64
  $bodyBrush.Dispose()

  $stroke = New-Pen '#27344E' 4
  Draw-RoundedRect $G $stroke $X $Y $W $H 64
  $stroke.Dispose()

  $screenBrush = New-Brush '#F8FBFF'
  Fill-RoundedRect $G $screenBrush ($X + 24) ($Y + 24) ($W - 48) ($H - 48) 48
  $screenBrush.Dispose()

  $notch = New-Brush '#0C1221'
  Fill-RoundedRect $G $notch ($X + $W / 2 - 82) ($Y + 26) 164 28 14
  $notch.Dispose()
}

function Draw-AppTopBar {
  param(
    [System.Drawing.Graphics]$G,
    [float]$X,
    [float]$Y,
    [float]$W,
    [System.Drawing.Image]$Icon,
    [string]$Title = 'XapZap'
  )
  $bar = New-Brush '#FFFFFF'
  Fill-RoundedRect $G $bar $X $Y $W 88 24
  $bar.Dispose()
  if ($Icon -ne $null) {
    $G.DrawImage($Icon, $X + 24, $Y + 18, 50, 50)
  }
  $titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 22, [System.Drawing.FontStyle]::Bold)
  Draw-Label $G $Title $titleFont '#111827' ($X + 90) ($Y + 21) 220 40
  $titleFont.Dispose()
  Draw-Circle $G '#E2E8F0' ($X + $W - 118) ($Y + 23) 42
  Draw-Circle $G '#E2E8F0' ($X + $W - 64) ($Y + 23) 42
}

function Draw-StoryRow {
  param([System.Drawing.Graphics]$G, [float]$X, [float]$Y)
  $names = @('You', 'Ava', 'Tobi', 'Mia', 'Jay')
  $font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Regular)
  $colors = @('#60A5FA', '#A78BFA', '#F472B6', '#34D399', '#F59E0B')
  for ($i = 0; $i -lt 5; $i++) {
    $cx = $X + ($i * 122)
    Draw-Circle $G $colors[$i] $cx $Y 72
    Draw-Circle $G '#FFFFFF' ($cx + 7) ($Y + 7) 58
    Draw-Circle $G $colors[$i] ($cx + 22) ($Y + 22) 28
    Draw-Label $G $names[$i] $font '#475569' ($cx - 4) ($Y + 82) 80 18 'Center'
  }
  $font.Dispose()
}

function Draw-ReactionRow {
  param([System.Drawing.Graphics]$G, [float]$X, [float]$Y, [string]$Likes, [string]$Comments, [string]$Shares)
  $font = New-Object System.Drawing.Font('Segoe UI Semibold', 11, [System.Drawing.FontStyle]::Bold)
  Draw-Circle $G '#F43F5E' $X $Y 18
  Draw-Label $G $Likes $font '#64748B' ($X + 24) ($Y - 1) 50 20
  Draw-Circle $G '#38BDF8' ($X + 92) $Y 18
  Draw-Label $G $Comments $font '#64748B' ($X + 116) ($Y - 1) 60 20
  Draw-Circle $G '#10B981' ($X + 208) $Y 18
  Draw-Label $G $Shares $font '#64748B' ($X + 232) ($Y - 1) 60 20
  $font.Dispose()
}

function Draw-PostCard {
  param(
    [System.Drawing.Graphics]$G,
    [float]$X,
    [float]$Y,
    [float]$W,
    [float]$H,
    [string]$AccentA,
    [string]$AccentB,
    [string]$UserName,
    [string]$Handle,
    [string]$Caption,
    [string]$Likes,
    [string]$Comments,
    [string]$Shares
  )
  Draw-SectionCard $G $X $Y $W $H
  Draw-Circle $G $AccentA ($X + 24) ($Y + 20) 46
  Draw-Circle $G '#FFFFFF' ($X + 34) ($Y + 30) 26

  $nameFont = New-Object System.Drawing.Font('Segoe UI Semibold', 16, [System.Drawing.FontStyle]::Bold)
  $metaFont = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
  $bodyFont = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Regular)
  Draw-Label $G $UserName $nameFont '#111827' ($X + 84) ($Y + 18) 240 24
  Draw-Label $G $Handle $metaFont '#6B7280' ($X + 84) ($Y + 42) 220 18
  Draw-Label $G '2m' $metaFont '#94A3B8' ($X + $W - 52) ($Y + 22) 30 18
  Draw-Label $G $Caption $bodyFont '#334155' ($X + 24) ($Y + 82) ($W - 48) 54

  Draw-GradientRect $G ($X + 24) ($Y + 146) ($W - 48) 250 30 $AccentA $AccentB 35
  Draw-Circle $G '#FFFFFF' ($X + 44) ($Y + 168) 20
  Draw-Circle $G '#FFFFFF' ($X + 76) ($Y + 200) 14
  Draw-Circle $G '#FFFFFF' ($X + $W - 94) ($Y + 176) 36
  $overlay = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(44, 255, 255, 255))
  Fill-RoundedRect $G $overlay ($X + 42) ($Y + 330) 170 34 18
  $overlay.Dispose()
  Draw-Label $G 'Trending now' $metaFont '#F8FAFC' ($X + 56) ($Y + 338) 120 18
  Draw-ReactionRow $G ($X + 26) ($Y + $H - 44) $Likes $Comments $Shares
  Draw-Line $G '#E2E8F0' ($X + 24) ($Y + $H - 88) ($W - 48) 2 1

  $nameFont.Dispose()
  $metaFont.Dispose()
  $bodyFont.Dispose()
}

function Draw-ReelUi {
  param([System.Drawing.Graphics]$G, [float]$X, [float]$Y, [float]$W, [float]$H)
  Draw-GradientRect $G $X $Y $W $H 42 '#0F172A' '#7C2D5A' 90
  $overlay1 = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(80, 255, 255, 255))
  $overlay2 = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(34, 255, 255, 255))
  $G.FillEllipse($overlay1, $X + 40, $Y + 130, $W - 140, $H - 440)
  $G.FillEllipse($overlay2, $X + 120, $Y + 220, $W - 240, $H - 620)
  $overlay1.Dispose()
  $overlay2.Dispose()

  $titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 18, [System.Drawing.FontStyle]::Bold)
  $metaFont = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Regular)
  $bodyFont = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Regular)
  Fill-RoundedRect $G (New-Brush '#FFFFFF') ($X + 28) ($Y + 26) 92 30 15
  Draw-Label $G 'Reels' $titleFont '#111827' ($X + 42) ($Y + 29) 60 20
  Draw-Label $G 'For you' $titleFont '#FFFFFF' ($X + 28) ($Y + 84) 90 24
  Draw-Label $G 'Following' $metaFont '#CBD5E1' ($X + 134) ($Y + 89) 90 18

  Draw-Circle $G '#FFFFFF' ($X + $W - 90) ($Y + 198) 48
  Draw-Circle $G '#FFFFFF' ($X + $W - 90) ($Y + 322) 48
  Draw-Circle $G '#FFFFFF' ($X + $W - 90) ($Y + 446) 48
  Draw-Circle $G '#FFFFFF' ($X + $W - 90) ($Y + 570) 48

  Draw-Circle $G '#FBBF24' ($X + 32) ($Y + $H - 178) 44
  Draw-Label $G 'AyoCreative' $titleFont '#FFFFFF' ($X + 88) ($Y + $H - 178) 200 26
  Draw-Label $G '@ayocreative' $metaFont '#E2E8F0' ($X + 88) ($Y + $H - 148) 160 18
  Draw-Label $G 'Behind the scenes from tonight''s creator meetup. Fresh clips, clean edits, and real energy.' $bodyFont '#F8FAFC' ($X + 32) ($Y + $H - 110) ($W - 120) 60

  Fill-RoundedRect $G (New-Brush '#FFFFFF') ($X + 30) ($Y + $H - 42) ($W - 60) 8 4
  $titleFont.Dispose()
  $metaFont.Dispose()
  $bodyFont.Dispose()
}

function Draw-ChatPreviewCard {
  param(
    [System.Drawing.Graphics]$G,
    [float]$X,
    [float]$Y,
    [float]$W,
    [string]$Accent,
    [string]$Name,
    [string]$Message,
    [string]$Time,
    [bool]$Unread = $false
  )
  Draw-SectionCard $G $X $Y $W 96 '#FFFFFF' '#E8EEF6'
  Draw-Circle $G $Accent ($X + 18) ($Y + 18) 58
  Draw-Circle $G '#FFFFFF' ($X + 31) ($Y + 31) 32
  $nameFont = New-Object System.Drawing.Font('Segoe UI Semibold', 14, [System.Drawing.FontStyle]::Bold)
  $bodyFont = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Regular)
  Draw-Label $G $Name $nameFont '#111827' ($X + 92) ($Y + 18) 240 22
  Draw-Label $G $Message $bodyFont '#64748B' ($X + 92) ($Y + 44) ($W - 170) 20
  Draw-Label $G $Time $bodyFont '#94A3B8' ($X + $W - 60) ($Y + 20) 40 18 'Far'
  if ($Unread) {
    Draw-Circle $G '#1D9BF0' ($X + $W - 48) ($Y + 56) 16
  }
  $nameFont.Dispose()
  $bodyFont.Dispose()
}

function Draw-ChatBubble {
  param(
    [System.Drawing.Graphics]$G,
    [float]$X,
    [float]$Y,
    [float]$W,
    [float]$H,
    [string]$Fill,
    [string]$Stroke,
    [string]$Text,
    [string]$Hex
  )
  $brush = New-Brush $Fill
  Fill-RoundedRect $G $brush $X $Y $W $H 22
  $brush.Dispose()
  $pen = New-Pen $Stroke 1.5
  Draw-RoundedRect $G $pen $X $Y $W $H 22
  $pen.Dispose()
  $font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Regular)
  Draw-Label $G $Text $font $Hex ($X + 14) ($Y + 12) ($W - 28) ($H - 20)
  $font.Dispose()
}

function Draw-ChatUi {
  param([System.Drawing.Graphics]$G, [float]$X, [float]$Y, [float]$W, [float]$H)
  Draw-SectionCard $G $X $Y $W 118 '#F7FAFF' '#E7EEF7'
  Draw-Label $G 'Messages' (New-Object System.Drawing.Font('Segoe UI Semibold', 20, [System.Drawing.FontStyle]::Bold)) '#111827' ($X + 24) ($Y + 22) 160 28
  Fill-RoundedRect $G (New-Brush '#FFFFFF') ($X + 22) ($Y + 62) ($W - 44) 34 17
  Draw-Line $G '#CBD5E1' ($X + 40) ($Y + 74) 220 10 5

  Draw-ChatPreviewCard $G ($X + 6) ($Y + 136) ($W - 12) '#A78BFA' 'Ava Johnson' 'Can we go live after the post drops?' '2m' $true
  Draw-ChatPreviewCard $G ($X + 6) ($Y + 244) ($W - 12) '#22C55E' 'Tobi N.' 'Sent a photo' '9m'

  Draw-SectionCard $G ($X + 6) ($Y + 362) ($W - 12) ($H - 490) '#FFFFFF' '#E8EEF6'
  Draw-Label $G 'Now chatting with Ava' (New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.FontStyle]::Bold)) '#111827' ($X + 26) ($Y + 384) 220 22
  Draw-ChatBubble $G ($X + 24) ($Y + 432) 312 66 '#F8FAFC' '#E2E8F0' 'The reel cover looks clean. Want me to push it to stories too?' '#334155'
  Draw-ChatBubble $G ($X + 184) ($Y + 520) 324 62 '#1D9BF0' '#1D9BF0' 'Yes. Add the teaser and pin the top comment after upload.' '#FFFFFF'
  Draw-ChatBubble $G ($X + 24) ($Y + 606) 268 58 '#F8FAFC' '#E2E8F0' 'Done. Sending preview now.' '#334155'
  Fill-RoundedRect $G (New-Brush '#D9F0FF') ($X + 24) ($Y + 690) 226 154 22
  Draw-ChatBubble $G ($X + 210) ($Y + 864) 298 58 '#1D9BF0' '#1D9BF0' 'Perfect. Let''s publish.' '#FFFFFF'

  Fill-RoundedRect $G (New-Brush '#F1F5F9') ($X + 20) ($Y + $H - 108) ($W - 40) 68 26
  Draw-Line $G '#94A3B8' ($X + 46) ($Y + $H - 82) 260 10 5
  Draw-Circle $G '#1D9BF0' ($X + $W - 74) ($Y + $H - 92) 44
}

function Draw-ProfileStatCard {
  param([System.Drawing.Graphics]$G, [float]$X, [float]$Y, [string]$Value, [string]$Label)
  Draw-SectionCard $G $X $Y 132 82 '#FFFFFF' '#E8EEF6'
  $valueFont = New-Object System.Drawing.Font('Segoe UI Semibold', 17, [System.Drawing.FontStyle]::Bold)
  $labelFont = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)
  Draw-Label $G $Value $valueFont '#111827' ($X + 16) ($Y + 16) 100 22
  Draw-Label $G $Label $labelFont '#64748B' ($X + 16) ($Y + 44) 90 18
  $valueFont.Dispose()
  $labelFont.Dispose()
}

function Draw-ProfileUi {
  param([System.Drawing.Graphics]$G, [float]$X, [float]$Y, [float]$W, [float]$H)
  Draw-GradientRect $G $X $Y $W 208 30 '#0F172A' '#2563EB' 20
  Draw-Circle $G '#FFFFFF' ($X + 28) ($Y + 118) 128
  Draw-Circle $G '#60A5FA' ($X + 44) ($Y + 134) 96
  Draw-Label $G '@xapzapcreator' (New-Object System.Drawing.Font('Segoe UI Semibold', 20, [System.Drawing.FontStyle]::Bold)) '#FFFFFF' ($X + 184) ($Y + 90) 260 28
  Draw-Label $G 'Creator, storyteller, and community builder' (New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Regular)) '#DBEAFE' ($X + 184) ($Y + 122) 340 20
  Fill-RoundedRect $G (New-Brush '#FFFFFF') ($X + $W - 168) ($Y + 92) 128 42 20
  Draw-Label $G 'Follow' (New-Object System.Drawing.Font('Segoe UI Semibold', 14, [System.Drawing.FontStyle]::Bold)) '#111827' ($X + $W - 132) ($Y + 104) 60 20 'Center'

  Draw-ProfileStatCard $G ($X + 20) ($Y + 238) '128K' 'Followers'
  Draw-ProfileStatCard $G ($X + 160) ($Y + 238) '4.8M' 'Views'
  Draw-ProfileStatCard $G ($X + 300) ($Y + 238) '328' 'Posts'
  Draw-ProfileStatCard $G ($X + 440) ($Y + 238) '89%' 'Growth'

  Draw-SectionCard $G ($X + 18) ($Y + 338) ($W - 36) 92 '#FFFFFF' '#E7EEF7'
  Draw-Line $G '#111827' ($X + 34) ($Y + 366) 74 4 2
  Draw-Label $G 'Posts' (New-Object System.Drawing.Font('Segoe UI Semibold', 12, [System.Drawing.FontStyle]::Bold)) '#111827' ($X + 34) ($Y + 374) 60 18
  Draw-Label $G 'Reels' (New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Regular)) '#94A3B8' ($X + 146) ($Y + 374) 60 18
  Draw-Label $G 'Media' (New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Regular)) '#94A3B8' ($X + 258) ($Y + 374) 60 18
  Draw-Label $G 'Saved' (New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Regular)) '#94A3B8' ($X + 370) ($Y + 374) 60 18

  $tileW = 198
  $tileH = 182
  $startX = $X + 20
  $startY = $Y + 454
  $colors = @(
    @('#7C3AED', '#38BDF8'),
    @('#0F766E', '#5EEAD4'),
    @('#C026D3', '#FB7185'),
    @('#EA580C', '#FBBF24'),
    @('#1D4ED8', '#A5B4FC'),
    @('#BE123C', '#FDA4AF')
  )
  $index = 0
  for ($r = 0; $r -lt 2; $r++) {
    for ($c = 0; $c -lt 3; $c++) {
      $tx = $startX + ($c * ($tileW + 16))
      $ty = $startY + ($r * ($tileH + 18))
      Draw-GradientRect $G $tx $ty $tileW $tileH 22 $colors[$index][0] $colors[$index][1] 40
      $shade = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(40, 255, 255, 255))
      Fill-RoundedRect $G $shade ($tx + 16) ($ty + 128) 84 28 14
      $shade.Dispose()
      $index++
    }
  }
}

function Draw-CreateUi {
  param([System.Drawing.Graphics]$G, [float]$X, [float]$Y, [float]$W, [float]$H)
  Draw-SectionCard $G $X $Y $W 130 '#FFFFFF' '#E7EEF7'
  Draw-Label $G 'Create a post' (New-Object System.Drawing.Font('Segoe UI Semibold', 19, [System.Drawing.FontStyle]::Bold)) '#111827' ($X + 24) ($Y + 20) 180 24
  Draw-Circle $G '#E2E8F0' ($X + $W - 72) ($Y + 24) 40
  Fill-RoundedRect $G (New-Brush '#F8FAFC') ($X + 22) ($Y + 62) ($W - 44) 40 18
  Draw-Line $G '#94A3B8' ($X + 46) ($Y + 76) 280 10 5

  Draw-SectionCard $G $X ($Y + 150) $W 238 '#FFFFFF' '#E7EEF7'
  Draw-Label $G 'Caption' (New-Object System.Drawing.Font('Segoe UI Semibold', 14, [System.Drawing.FontStyle]::Bold)) '#111827' ($X + 24) ($Y + 172) 90 20
  Draw-Line $G '#334155' ($X + 24) ($Y + 210) 380 8 4
  Draw-Line $G '#64748B' ($X + 24) ($Y + 234) 520 8 4
  Draw-Line $G '#64748B' ($X + 24) ($Y + 258) 460 8 4
  Draw-Line $G '#CBD5E1' ($X + 24) ($Y + 282) 220 8 4

  Draw-SectionCard $G $X ($Y + 404) $W 360 '#FFFFFF' '#E7EEF7'
  Draw-Label $G 'Media preview' (New-Object System.Drawing.Font('Segoe UI Semibold', 14, [System.Drawing.FontStyle]::Bold)) '#111827' ($X + 24) ($Y + 426) 120 20
  Draw-GradientRect $G ($X + 24) ($Y + 462) 308 232 24 '#1D4ED8' '#22D3EE' 40
  Draw-GradientRect $G ($X + 348) ($Y + 462) 308 112 22 '#EC4899' '#F59E0B' 35
  Draw-GradientRect $G ($X + 348) ($Y + 582) 308 112 22 '#0F766E' '#34D399' 35
  Fill-RoundedRect $G (New-Brush '#FFFFFF') ($X + 24) ($Y + 710) 92 28 14
  Fill-RoundedRect $G (New-Brush '#FFFFFF') ($X + 126) ($Y + 710) 112 28 14

  Draw-SectionCard $G $X ($Y + 782) $W 196 '#FFFFFF' '#E7EEF7'
  Draw-Label $G 'Tools' (New-Object System.Drawing.Font('Segoe UI Semibold', 14, [System.Drawing.FontStyle]::Bold)) '#111827' ($X + 24) ($Y + 804) 60 20
  $toolLabels = @('Photo', 'Text', 'Poll', 'Tag', 'Music')
  for ($i = 0; $i -lt 5; $i++) {
    $tx = $X + 24 + ($i * 126)
    Draw-Circle $G '#F1F5F9' $tx ($Y + 840) 58
    Draw-Label $G $toolLabels[$i] (New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)) '#475569' ($tx - 4) ($Y + 906) 68 16 'Center'
  }

  Fill-RoundedRect $G (New-Brush '#111827') ($X + 24) ($Y + $H - 88) ($W - 48) 64 24
  Draw-Label $G 'Publish now' (New-Object System.Drawing.Font('Segoe UI Semibold', 16, [System.Drawing.FontStyle]::Bold)) '#FFFFFF' ($X + 220) ($Y + $H - 69) 180 22 'Center'
}

function Draw-DatingUi {
  param([System.Drawing.Graphics]$G, [float]$X, [float]$Y, [float]$W, [float]$H)
  Draw-SectionCard $G $X $Y $W 92 '#FFF8FB' '#F5DCE7'
  Draw-Label $G 'Dating' (New-Object System.Drawing.Font('Segoe UI Semibold', 20, [System.Drawing.FontStyle]::Bold)) '#111827' ($X + 24) ($Y + 22) 100 24
  Fill-RoundedRect $G (New-Brush '#FFFFFF') ($X + $W - 148) ($Y + 22) 122 36 18
  Draw-Label $G 'Nearby' (New-Object System.Drawing.Font('Segoe UI Semibold', 12, [System.Drawing.FontStyle]::Bold)) '#BE185D' ($X + $W - 120) ($Y + 32) 70 18

  Draw-SectionCard $G $X ($Y + 112) $W 1018 '#FFF7FB' '#F4D9E6'
  Draw-GradientRect $G ($X + 24) ($Y + 136) ($W - 48) 520 28 '#FB7185' '#C026D3' 55
  $fade = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(50, 255, 255, 255))
  $G.FillEllipse($fade, $X + 72, $Y + 176, 420, 320)
  $G.FillEllipse($fade, $X + 228, $Y + 252, 210, 210)
  $fade.Dispose()
  Fill-RoundedRect $G (New-Brush '#FFFFFF') ($X + 42) ($Y + 588) 138 34 17
  Draw-Label $G '98% match' (New-Object System.Drawing.Font('Segoe UI Semibold', 12, [System.Drawing.FontStyle]::Bold)) '#BE185D' ($X + 66) ($Y + 598) 90 18

  Draw-Label $G 'Amara, 24' (New-Object System.Drawing.Font('Segoe UI Semibold', 24, [System.Drawing.FontStyle]::Bold)) '#111827' ($X + 32) ($Y + 678) 180 28
  Draw-Label $G 'Lagos' (New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Regular)) '#64748B' ($X + 34) ($Y + 714) 80 18
  Draw-Label $G 'Designer, live music lover, and always down for good conversation.' (New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Regular)) '#475569' ($X + 32) ($Y + 744) ($W - 64) 44

  $chips = @('Music', 'Travel', 'Coffee', 'Movies')
  for ($i = 0; $i -lt 4; $i++) {
    $chipX = $X + 32 + ($i * 120)
    Fill-RoundedRect $G (New-Brush '#FFFFFF') $chipX ($Y + 814) 100 34 16
    Draw-Label $G $chips[$i] (New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Regular)) '#BE185D' ($chipX + 18) ($Y + 823) 60 16
  }

  Draw-SectionCard $G ($X + 32) ($Y + 874) ($W - 64) 92 '#FFFFFF' '#F0D9E4'
  Draw-Label $G 'Looking for' (New-Object System.Drawing.Font('Segoe UI Semibold', 12, [System.Drawing.FontStyle]::Bold)) '#111827' ($X + 54) ($Y + 896) 100 18
  Draw-Label $G 'Meaningful connection, laughs, and someone consistent.' (New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Regular)) '#475569' ($X + 54) ($Y + 922) ($W - 140) 20

  Draw-Circle $G '#FFFFFF' ($X + 96) ($Y + $H - 116) 84
  Draw-Circle $G '#FFFFFF' ($X + 238) ($Y + $H - 132) 116
  Draw-Circle $G '#FFFFFF' ($X + 408) ($Y + $H - 116) 84
  Draw-Circle $G '#FB7185' ($X + 128) ($Y + $H - 148) 22
  Draw-Circle $G '#22C55E' ($X + 284) ($Y + $H - 170) 28
  Draw-Circle $G '#A855F7' ($X + 440) ($Y + $H - 148) 22
}

function Save-Screenshot {
  param(
    [string]$FileName,
    [string]$Headline,
    [string]$Subline,
    [string]$TopHex,
    [string]$BottomHex,
    [string]$GlowHex,
    [scriptblock]$PhoneRenderer
  )
  $w = 1080
  $h = 2400
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

  Draw-GradientBackground $g $w $h $TopHex $BottomHex $GlowHex
  Draw-HeaderBlock $g $Headline $Subline $icon

  $phoneX = 140
  $phoneY = 620
  $phoneW = 800
  $phoneH = 1540
  Draw-PhoneShell $g $phoneX $phoneY $phoneW $phoneH

  $screenX = $phoneX + 24
  $screenY = $phoneY + 24
  $screenW = $phoneW - 48
  $screenH = $phoneH - 48

  & $PhoneRenderer $g $screenX $screenY $screenW $screenH

  $target = Join-Path $outDir $FileName
  $bmp.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose()
  $bmp.Dispose()
}

function Save-RealScreenshot {
  param(
    [string]$FileName,
    [string]$Headline,
    [string]$Subline,
    [string]$TopHex,
    [string]$BottomHex,
    [string]$GlowHex,
    [string]$SourceKey,
    [string]$Accent = '#38BDF8'
  )
  $w = 1080
  $h = 2400
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

  Draw-GradientBackground $g $w $h $TopHex $BottomHex $GlowHex
  Draw-HeaderBlock $g $Headline $Subline $icon

  $shot = Get-SourceImage $SourceKey
  if ($shot -ne $null) {
    Draw-ScreenshotCard $g 126 610 828 1620 $shot $Accent
    $shot.Dispose()
  }

  $target = Join-Path $outDir $FileName
  $bmp.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose()
  $bmp.Dispose()
}

function Save-FeatureGraphic {
  $w = 1024
  $h = 500
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

  Draw-GradientBackground $g $w $h '#07101E' '#214177' '#60A5FA'
  if ($icon -ne $null) {
    Draw-Circle $g '#FFFFFF' 52 54 76
    $g.DrawImage($icon, 68, 70, 44, 44)
  }

  $titleFont = New-Object System.Drawing.Font('Segoe UI Semibold', 36, [System.Drawing.FontStyle]::Bold)
  $heroFont = New-Object System.Drawing.Font('Segoe UI Semibold', 26, [System.Drawing.FontStyle]::Bold)
  $bodyFont = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Regular)
  Draw-Label $g 'XapZap' $titleFont '#FFFFFF' 140 56 240 46
  Draw-Label $g 'Share posts, watch reels, chat, create, and connect.' $heroFont '#FFFFFF' 54 138 430 74
  Draw-Label $g 'Premium social app listing graphics with richer in-app content.' $bodyFont '#D7E6FF' 54 226 390 44

  $items = @(
    @{X = 530; Y = 44; Key = 'home'; Accent = '#38BDF8'},
    @{X = 662; Y = 16; Key = 'reels'; Accent = '#FB7185'},
    @{X = 794; Y = 44; Key = 'creator'; Accent = '#A78BFA'}
  )

  foreach ($item in $items) {
    $img = Get-SourceImage $item.Key
    if ($img -ne $null) {
      Draw-ScreenshotCard $g ([float]$item.X) ([float]$item.Y) 176 372 $img $item.Accent
      $img.Dispose()
    }
  }

  $target = Join-Path $outDir 'feature-graphic-1024x500.png'
  $bmp.Save($target, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose()
  $bmp.Dispose()
}

Save-RealScreenshot '01-home-feed-1080x2400.png' 'See What''s Happening Instantly' 'Real home feed with stories, posts, and social engagement.' '#08101F' '#165D8C' '#38BDF8' 'home' '#38BDF8'
Save-RealScreenshot '02-watch-feed-1080x2400.png' 'Watch Videos Inside The Feed' 'Scroll rich posts, video cards, and news in one place.' '#0A1423' '#1D4ED8' '#60A5FA' 'watch' '#60A5FA'
Save-RealScreenshot '03-reels-1080x2400.png' 'Watch Reels That Keep You Hooked' 'Immersive short video with live engagement controls.' '#180C1B' '#8A1F52' '#FB7185' 'reels' '#FB7185'
Save-RealScreenshot '04-profile-1080x2400.png' 'Build Your Profile And Grow' 'Creator tools, tabs, metrics, and a polished profile view.' '#0B1220' '#455A8B' '#A5B4FC' 'profile' '#A5B4FC'
Save-RealScreenshot '05-creator-profile-1080x2400.png' 'Follow Creators And Start Conversations' 'Profiles are built for discovery, follows, and direct connection.' '#0F172A' '#155E75' '#2DD4BF' 'creator' '#2DD4BF'
Save-RealScreenshot '06-dating-1080x2400.png' 'Meet New People Your Way' 'Dating lives inside the app with a clear entry point on the feed.' '#1A1020' '#B8376D' '#FDA4AF' 'home' '#FDA4AF'

Save-FeatureGraphic

if ($icon -ne $null) {
  $icon.Dispose()
}

Write-Output "Generated Play Store assets in $outDir"
