<#
  Claude Account Switcher - dark mode window.
  Uses ClaudeSwitcher.ps1 (same folder) for the actual switching.
  Start it with "Claude Account Switcher.cmd".
#>
[CmdletBinding()]
param(
    [string]$SwitchTo,                 # from desktop shortcuts
    [string]$DataRoot = (Join-Path $env:LOCALAPPDATA 'Claude-Data'),
    [switch]$NoLaunch,                 # testing
    [switch]$SkipProcessCheck,         # testing
    [switch]$Yes,                      # testing: skip confirmations
    [string]$Snapshot,                 # testing: save a PNG of the window and exit
    [switch]$InstallShortcuts          # create Start menu + desktop shortcuts and exit
)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -Namespace CAS -Name Dwm -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(System.IntPtr hwnd, int attr, ref int value, int size);
[System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int SetCurrentProcessExplicitAppUserModelID(string appId);
'@ -ErrorAction SilentlyContinue

# One fixed taskbar identity, so the window groups under the pinned icon.
$AppUserModelId = 'ClaudeAccountSwitcher.App'
try { [void][CAS.Dwm]::SetCurrentProcessExplicitAppUserModelID($AppUserModelId) } catch { }
$IcoPath = Join-Path $PSScriptRoot 'ClaudeSwitcher.ico'

# Shortcut writer that can also set the taskbar identity (compiled only when needed).
$LinkCs = @'
using System;
using System.Runtime.InteropServices;
using System.Text;
namespace CAS {
  [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IShellLinkW {
    void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder f, int cch, IntPtr pfd, uint flags);
    void GetIDList(out IntPtr ppidl);
    void SetIDList(IntPtr pidl);
    void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder n, int cch);
    void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string n);
    void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder d, int cch);
    void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string d);
    void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder a, int cch);
    void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string a);
    void GetHotkey(out short h);
    void SetHotkey(short h);
    void GetShowCmd(out int c);
    void SetShowCmd(int c);
    void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder p, int cch, out int i);
    void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string p, int i);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string p, uint r);
    void Resolve(IntPtr hwnd, uint flags);
    void SetPath([MarshalAs(UnmanagedType.LPWStr)] string f);
  }
  [StructLayout(LayoutKind.Sequential, Pack = 4)]
  public struct PropKey { public Guid fmtid; public uint pid; }
  [StructLayout(LayoutKind.Explicit)]
  public struct PropVar { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr p; [FieldOffset(16)] public IntPtr pad; }
  [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyStore {
    void GetCount(out uint c);
    void GetAt(uint i, out PropKey k);
    void GetValue(ref PropKey k, out PropVar v);
    void SetValue(ref PropKey k, ref PropVar v);
    void Commit();
  }
  [ComImport, Guid("0000010b-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPersistFile {
    void GetClassID(out Guid c);
    [PreserveSig] int IsDirty();
    void Load([MarshalAs(UnmanagedType.LPWStr)] string f, uint m);
    void Save([MarshalAs(UnmanagedType.LPWStr)] string f, bool remember);
    void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string f);
    void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string f);
  }
  [ComImport, Guid("00021401-0000-0000-C000-000000000046")] class CShellLink { }
  public static class Link {
    public static void Create(string lnk, string target, string args, string workDir, string icon, string desc, string appId, int showCmd) {
      IShellLinkW sl = (IShellLinkW)new CShellLink();
      sl.SetPath(target); sl.SetArguments(args); sl.SetWorkingDirectory(workDir);
      sl.SetIconLocation(icon, 0); sl.SetDescription(desc); sl.SetShowCmd(showCmd);
      if (!String.IsNullOrEmpty(appId)) {
        IPropertyStore ps = (IPropertyStore)sl;
        PropKey key = new PropKey(); key.fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"); key.pid = 5;
        PropVar v = new PropVar(); v.vt = 31; v.p = Marshal.StringToCoTaskMemUni(appId);
        try { ps.SetValue(ref key, ref v); ps.Commit(); } finally { Marshal.FreeCoTaskMem(v.p); }
      }
      ((IPersistFile)sl).Save(lnk, true);
    }
  }
}
'@

$Core = Join-Path $PSScriptRoot 'ClaudeSwitcher.ps1'
$PsExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Show-Fatal([string]$msg) {
    [void][Windows.MessageBox]::Show($msg, 'Claude Account Switcher', 'OK', 'Error'); exit 1
}
if (-not (Test-Path -LiteralPath $Core)) { Show-Fatal "ClaudeSwitcher.ps1 is missing. Keep both files in the same folder." }
if ($PSCommandPath.StartsWith([IO.Path]::GetFullPath($DataRoot), [StringComparison]::OrdinalIgnoreCase)) {
    Show-Fatal "This tool is inside Claude's own data folder, so it would move with a profile. Move the 'Claude Account Switcher' folder to Documents and run it from there."
}
if (-not (Test-Path -LiteralPath $DataRoot)) { Show-Fatal "Claude's data folder was not found. Is the Claude desktop app installed and opened at least once?" }

$keep = @{ SwitchTo = $SwitchTo; Yes = $Yes; NoLaunch = $NoLaunch; SkipProcessCheck = $SkipProcessCheck }
. $Core -DataRoot $DataRoot          # load the engine's functions only
$SwitchTo = $keep.SwitchTo; $Yes = $keep.Yes; $NoLaunch = $keep.NoLaunch; $SkipProcessCheck = $keep.SkipProcessCheck
$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------- look & feel
$Styles = @'
<Style x:Key="Btn" TargetType="Button">
  <Setter Property="Foreground" Value="#ECECEE"/>
  <Setter Property="Background" Value="#2E2E35"/>
  <Setter Property="BorderThickness" Value="0"/>
  <Setter Property="Padding" Value="14,8"/>
  <Setter Property="FontSize" Value="13"/>
  <Setter Property="Cursor" Value="Hand"/>
  <Setter Property="Template">
    <Setter.Value>
      <ControlTemplate TargetType="Button">
        <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="8" Padding="{TemplateBinding Padding}">
          <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <ControlTemplate.Triggers>
          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.82"/></Trigger>
          <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.35"/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate>
    </Setter.Value>
  </Setter>
</Style>
<Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource Btn}">
  <Setter Property="Background" Value="#D97757"/>
  <Setter Property="Foreground" Value="#FFFFFF"/>
  <Setter Property="FontWeight" Value="SemiBold"/>
</Style>
<Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource Btn}">
  <Setter Property="Background" Value="#3A1D1D"/>
  <Setter Property="Foreground" Value="#FCA5A5"/>
</Style>
<Style x:Key="DangerSolid" TargetType="Button" BasedOn="{StaticResource Btn}">
  <Setter Property="Background" Value="#DC2626"/>
  <Setter Property="Foreground" Value="#FFFFFF"/>
  <Setter Property="FontWeight" Value="SemiBold"/>
</Style>
<Style x:Key="Input" TargetType="TextBox">
  <Setter Property="Background" Value="#2A2A30"/>
  <Setter Property="Foreground" Value="#ECECEE"/>
  <Setter Property="CaretBrush" Value="#ECECEE"/>
  <Setter Property="BorderBrush" Value="#3A3A42"/>
  <Setter Property="BorderThickness" Value="1"/>
  <Setter Property="Padding" Value="8,7"/>
  <Setter Property="FontSize" Value="14"/>
</Style>
'@

$MainXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Account Switcher" Width="480" SizeToContent="Height"
        ResizeMode="CanMinimize" WindowStartupLocation="CenterScreen"
        Background="#17171A" FontFamily="Segoe UI" UseLayoutRounding="True">
  <Window.Resources>$Styles</Window.Resources>
  <StackPanel Margin="26,24,26,26">
    <TextBlock Text="Claude Account Switcher" FontSize="22" FontWeight="SemiBold" Foreground="#ECECEE"/>
    <TextBlock Text="Switch between client accounts in one click." Foreground="#9A9AA3" Margin="0,4,0,22"/>

    <Border Background="#232328" BorderBrush="#D97757" BorderThickness="1" CornerRadius="12" Padding="18,16">
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock Text="SIGNED IN RIGHT NOW" FontSize="11" FontWeight="SemiBold" Foreground="#9A9AA3"/>
          <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
            <Ellipse x:Name="ActiveDot" Width="10" Height="10" Fill="#4ADE80" VerticalAlignment="Center" Margin="0,2,10,0"/>
            <TextBlock x:Name="ActiveName" FontSize="24" FontWeight="SemiBold" Foreground="#ECECEE"/>
          </StackPanel>
          <TextBlock x:Name="ActiveHint" Foreground="#9A9AA3" FontSize="12" Margin="0,4,0,0" TextWrapping="Wrap"/>
        </StackPanel>
        <Button x:Name="RenameBtn" Grid.Column="1" Style="{StaticResource Btn}" Content="Rename" VerticalAlignment="Center"/>
      </Grid>
    </Border>

    <TextBlock Text="SWITCH TO" FontSize="11" FontWeight="SemiBold" Foreground="#9A9AA3" Margin="2,24,0,10"/>
    <StackPanel x:Name="AccountList"/>
    <TextBlock x:Name="EmptyText" Text="No other accounts yet. Add your first client below." Foreground="#9A9AA3" Margin="2,0,0,4" Visibility="Collapsed"/>
    <Button x:Name="AddBtn" Style="{StaticResource Btn}" Content="+   Add a new account" Padding="14,12" Margin="0,6,0,0"/>

    <Border x:Name="BusyPanel" Visibility="Collapsed" Background="#232328" CornerRadius="10" Padding="16,14" Margin="0,18,0,0">
      <StackPanel>
        <TextBlock x:Name="BusyText" Foreground="#ECECEE" TextWrapping="Wrap"/>
        <ProgressBar IsIndeterminate="True" Height="4" Margin="0,12,0,0" Foreground="#D97757" Background="#2E2E35" BorderThickness="0"/>
      </StackPanel>
    </Border>
    <Border x:Name="StatusPanel" Visibility="Collapsed" CornerRadius="10" Padding="16,12" Margin="0,18,0,0">
      <TextBlock x:Name="StatusText" Foreground="#ECECEE" TextWrapping="Wrap"/>
    </Border>

    <Border Background="#1F1F24" CornerRadius="10" Padding="16,14" Margin="0,22,0,0">
      <StackPanel>
        <TextBlock Text="How it works" Foreground="#ECECEE" FontWeight="SemiBold"/>
        <TextBlock Foreground="#9A9AA3" FontSize="12" TextWrapping="Wrap" Margin="0,6,0,0" LineHeight="19">&#x2022;  Click <Run Foreground="#ECECEE">Switch</Run>: Claude closes and reopens in that account.<LineBreak/>&#x2022;  Every account stays signed in. You never have to log out.<LineBreak/>&#x2022;  Finish your work first: switching stops anything running in Claude.<LineBreak/>&#x2022;  <Run Foreground="#ECECEE">Shortcut</Run> puts a one-click icon for that account on your desktop.<LineBreak/>&#x2022;  <Run Foreground="#ECECEE">Delete</Run> removes an account from this PC only (not the Claude account itself).</TextBlock>
      </StackPanel>
    </Border>
    <Button x:Name="AppShortcutBtn" Style="{StaticResource Btn}" Background="Transparent" Foreground="#9A9AA3" FontSize="12"
            Content="Add this app to Start menu, desktop and taskbar" HorizontalAlignment="Center" Margin="0,12,0,0"/>
  </StackPanel>
</Window>
"@

$DialogXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Width="420" SizeToContent="Height" ResizeMode="NoResize" ShowInTaskbar="False"
        WindowStartupLocation="CenterOwner" Background="#1E1E22" FontFamily="Segoe UI">
  <Window.Resources>$Styles</Window.Resources>
  <StackPanel Margin="24,22,24,22">
    <TextBlock x:Name="T" FontSize="18" FontWeight="SemiBold" Foreground="#ECECEE" TextWrapping="Wrap"/>
    <TextBlock x:Name="M" Foreground="#B5B5BD" FontSize="13" TextWrapping="Wrap" Margin="0,10,0,0" LineHeight="20"/>
    <TextBox x:Name="I" Style="{StaticResource Input}" Margin="0,16,0,0" Visibility="Collapsed"/>
    <TextBlock x:Name="E" Foreground="#F87171" FontSize="12" Margin="0,6,0,0" Visibility="Collapsed" TextWrapping="Wrap"/>
    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,22,0,0">
      <Button x:Name="C" Style="{StaticResource Btn}" Content="Cancel" Margin="0,0,8,0" IsCancel="True"/>
      <Button x:Name="O" Style="{StaticResource Primary}" Content="OK" IsDefault="True"/>
    </StackPanel>
  </StackPanel>
</Window>
"@

function Set-DarkTitle($w) {
    try {
        $h = (New-Object Windows.Interop.WindowInteropHelper $w).EnsureHandle()
        $v = 1
        [void][CAS.Dwm]::DwmSetWindowAttribute($h, 20, [ref]$v, 4)
    } catch { }
}

function Get-Brush([string]$hex) { (New-Object Windows.Media.BrushConverter).ConvertFromString($hex) }

# Dark dialog. Returns $true (confirm), the typed text (input), or $null (cancel).
function Show-Dialog {
    param([string]$Title, [string]$Message, [switch]$AskText, [string]$OkText = 'OK',
          [string]$CancelText = 'Cancel', [switch]$NoCancel, [switch]$Danger, [scriptblock]$Validate)
    $d = [Windows.Markup.XamlReader]::Parse($DialogXaml)
    $d.Title = 'Claude Account Switcher'
    if ($script:Window -and $script:Window.IsVisible) { $d.Owner = $script:Window } else { $d.WindowStartupLocation = 'CenterScreen' }
    Set-DarkTitle $d
    $t = $d.FindName('T'); $m = $d.FindName('M'); $i = $d.FindName('I')
    $e = $d.FindName('E'); $o = $d.FindName('O'); $c = $d.FindName('C')
    $t.Text = $Title; $m.Text = $Message; $o.Content = $OkText; $c.Content = $CancelText
    if (-not $Message) { $m.Visibility = 'Collapsed' }
    if ($NoCancel) { $c.Visibility = 'Collapsed' }
    if ($Danger) { $o.Style = $d.FindResource('DangerSolid'); $o.IsDefault = $false; $c.IsDefault = $true }
    if ($AskText) { $i.Visibility = 'Visible'; $d.Add_ContentRendered({ $i.Focus() }) }
    $state = @{ Result = $null }
    $o.Add_Click({
        if ($AskText) {
            $val = $i.Text.Trim()
            if ($Validate) {
                $err = & $Validate $val
                if ($err) { $e.Text = $err; $e.Visibility = 'Visible'; return }
            }
            $state.Result = $val
        } else { $state.Result = $true }
        $d.Close()
    }.GetNewClosure())
    [void]$d.ShowDialog()
    return $state.Result
}

$script:Window = [Windows.Markup.XamlReader]::Parse($MainXaml)
$W = $script:Window
$ui = @{}
foreach ($n in 'ActiveDot','ActiveName','ActiveHint','RenameBtn','AccountList','EmptyText','AddBtn',
               'BusyPanel','BusyText','StatusPanel','StatusText','AppShortcutBtn') { $ui[$n] = $W.FindName($n) }
$W.Add_SourceInitialized({ Set-DarkTitle $this })
if (Test-Path -LiteralPath $IcoPath) { try { $W.Icon = [Windows.Media.Imaging.BitmapFrame]::Create((New-Object Uri $IcoPath)) } catch { } }

function Show-Status([string]$msg, [string]$kind = 'ok') {
    $ui.StatusText.Text = $msg
    switch ($kind) {
        'ok'    { $ui.StatusPanel.Background = Get-Brush '#16301F'; $ui.StatusText.Foreground = Get-Brush '#86EFAC' }
        'info'  { $ui.StatusPanel.Background = Get-Brush '#1E2A3A'; $ui.StatusText.Foreground = Get-Brush '#93C5FD' }
        'error' { $ui.StatusPanel.Background = Get-Brush '#3A1D1D'; $ui.StatusText.Foreground = Get-Brush '#FCA5A5' }
    }
    $ui.StatusPanel.Visibility = 'Visible'
}

function Test-NewName([string]$v) {
    if (-not (Test-Name $v)) { return 'Use 1-40 letters, numbers, spaces, - or _.' }
    if (@(Get-SavedProfiles) | Where-Object { $_ -ieq $v }) { return "There is already an account called '$v'." }
    $cur = Get-ActiveName
    if ($cur -and ($cur -ieq $v)) { return "'$v' is the account you are signed in to right now." }
    return $null
}

function Set-Busy([bool]$busy, [string]$text = '') {
    $ui.BusyText.Text = $text
    $ui.BusyPanel.Visibility = $(if ($busy) { 'Visible' } else { 'Collapsed' })
    if ($busy) { $ui.StatusPanel.Visibility = 'Collapsed' }
    foreach ($b in @($ui.RenameBtn, $ui.AddBtn, $ui.AppShortcutBtn)) { $b.IsEnabled = -not $busy }
    foreach ($card in $ui.AccountList.Children) { $card.IsEnabled = -not $busy }
}

function New-AccountCard([string]$name) {
    $card = New-Object Windows.Controls.Border
    $card.Background = Get-Brush '#232328'
    $card.CornerRadius = New-Object Windows.CornerRadius 10
    $card.Padding = New-Object Windows.Thickness 16, 10, 10, 10
    $card.Margin = New-Object Windows.Thickness 0, 0, 0, 8

    $g = New-Object Windows.Controls.Grid
    foreach ($colWidth in '*', 'Auto', 'Auto', 'Auto') {
        $cd = New-Object Windows.Controls.ColumnDefinition
        $cd.Width = (New-Object Windows.GridLengthConverter).ConvertFromString($colWidth)
        $g.ColumnDefinitions.Add($cd)
    }
    $tb = New-Object Windows.Controls.TextBlock
    $tb.Text = $name; $tb.FontSize = 16; $tb.FontWeight = 'SemiBold'
    $tb.Foreground = Get-Brush '#ECECEE'; $tb.VerticalAlignment = 'Center'
    $g.Children.Add($tb) | Out-Null

    $del = New-Object Windows.Controls.Button
    $del.Content = 'Delete'; $del.Style = $W.FindResource('Danger'); $del.Margin = New-Object Windows.Thickness 0, 0, 8, 0
    $del.ToolTip = "Remove $name from this PC"
    $del.Tag = $name
    $del.Add_Click({ Start-Delete $this.Tag })
    [Windows.Controls.Grid]::SetColumn($del, 1); $g.Children.Add($del) | Out-Null

    $sc = New-Object Windows.Controls.Button
    $sc.Content = 'Shortcut'; $sc.Style = $W.FindResource('Btn'); $sc.Margin = New-Object Windows.Thickness 0, 0, 8, 0
    $sc.ToolTip = "Put a 'Claude - $name' icon on your desktop"
    $sc.Tag = $name
    $sc.Add_Click({ Invoke-Shortcut $this.Tag })
    [Windows.Controls.Grid]::SetColumn($sc, 2); $g.Children.Add($sc) | Out-Null

    $sw = New-Object Windows.Controls.Button
    $sw.Content = 'Switch'; $sw.Style = $W.FindResource('Primary'); $sw.MinWidth = 92
    $sw.Tag = $name
    $sw.Add_Click({ Start-Switch $this.Tag $false })
    [Windows.Controls.Grid]::SetColumn($sw, 3); $g.Children.Add($sw) | Out-Null

    $card.Child = $g
    return $card
}

function Update-View {
    $cur = Get-ActiveName
    if ($null -eq $cur) {
        $pending = if (Test-Path -LiteralPath $PendingFile) { (Get-Content -LiteralPath $PendingFile -Raw).Trim() } else { '' }
        $ui.ActiveName.Text = $(if ($pending) { $pending } else { 'New account' })
        $ui.ActiveDot.Fill = Get-Brush '#FBBF24'
        $ui.ActiveHint.Text = 'Open Claude and sign in to finish setting up this account.'
        $ui.RenameBtn.Visibility = 'Collapsed'
    } elseif ($cur -eq '') {
        $ui.ActiveName.Text = 'Not named yet'
        $ui.ActiveDot.Fill = Get-Brush '#FBBF24'
        $ui.ActiveHint.Text = 'Give this account a name (for example Work) so you can switch back to it.'
        $ui.RenameBtn.Content = 'Name it'; $ui.RenameBtn.Visibility = 'Visible'
    } else {
        $ui.ActiveName.Text = $cur
        $ui.ActiveDot.Fill = Get-Brush '#4ADE80'
        $ui.ActiveHint.Text = 'This is the account Claude opens with.'
        $ui.RenameBtn.Content = 'Rename'; $ui.RenameBtn.Visibility = 'Visible'
    }
    if ($null -eq $cur) { $script:Refresh.Start() } else { $script:Refresh.Stop() }
    $ui.AccountList.Children.Clear()
    $saved = @(Get-SavedProfiles)
    foreach ($n in $saved) { [void]$ui.AccountList.Children.Add((New-AccountCard $n)) }
    $ui.EmptyText.Visibility = $(if ($saved.Count -eq 0) { 'Visible' } else { 'Collapsed' })
}

function Request-ActiveName([string]$why) {
    $n = Show-Dialog -Title 'Name the account you are signed in to' -Message $why -AskText -OkText 'Save name' -Validate { param($v) Test-NewName $v }
    if ($n) { Set-Marker $n; Update-View; return $true }
    return $false
}

function New-AppLink([string]$lnkPath, [string]$extraArgs, [string]$desc, [string]$appId) {
    if (-not ('CAS.Link' -as [type])) { Add-Type -TypeDefinition $LinkCs }
    $a = ("-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File `"$PSCommandPath`" " + $extraArgs).Trim()
    [CAS.Link]::Create($lnkPath, $PsExe, $a, $PSScriptRoot, $IcoPath, $desc, $appId, 7)
}

# Start menu + desktop shortcut for the app, and refresh any per-account desktop shortcuts.
function Install-AppShortcuts {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Claude Account Switcher.lnk'
    New-AppLink $startMenu '' 'Switch between Claude accounts' $AppUserModelId
    New-AppLink (Join-Path $desktop 'Claude Account Switcher.lnk') '' 'Switch between Claude accounts' $AppUserModelId
    $known = @(Get-SavedProfiles) + @(Get-ActiveName) | Where-Object { $_ }
    foreach ($lnk in Get-ChildItem -LiteralPath $desktop -Filter 'Claude - *.lnk' -ErrorAction SilentlyContinue) {
        $n = $lnk.BaseName.Substring(9)
        if ($known -contains $n) { New-AppLink $lnk.FullName "-SwitchTo `"$n`"" "Switch Claude to $n" '' }
    }
    # If it is already pinned to the taskbar, update the pin too (e.g. after moving the folder).
    $pinned = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\Claude Account Switcher.lnk'
    if (Test-Path -LiteralPath $pinned) { New-AppLink $pinned '' 'Switch between Claude accounts' $AppUserModelId }
}

function Invoke-Shortcut([string]$name) {
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        New-AppLink (Join-Path $desktop "Claude - $name.lnk") "-SwitchTo `"$name`"" "Switch Claude to $name" ''
        Show-Status "Done. 'Claude - $name' is now on your desktop. Double-click it any time to switch to $name." 'ok'
    } catch { Show-Status "Could not create the shortcut: $($_.Exception.Message)" 'error' }
}

$script:Refresh = New-Object Windows.Threading.DispatcherTimer
$script:Refresh.Interval = [TimeSpan]::FromSeconds(2)
$script:Refresh.Add_Tick({ if (-not $script:Timer.IsEnabled -and (Test-Path -LiteralPath $Active)) { Update-View } })

$script:Proc = $null
$script:Timer = New-Object Windows.Threading.DispatcherTimer
$script:Timer.Interval = [TimeSpan]::FromMilliseconds(400)
$script:Timer.Add_Tick({
    if (-not $script:Proc.HasExited) { return }
    $script:Timer.Stop()
    $out = ($script:OutTask.Result + "`n" + $script:ErrTask.Result).Trim()
    $code = $script:Proc.ExitCode
    $target = $script:Target
    Set-Busy $false
    Update-View
    if ($script:Job -eq 'delete') {
        if ($code -eq 0) { Show-Status "$target was deleted from this PC. If that was a mistake, restore it from the Recycle Bin." 'ok' }
        else {
            $lines = ($out -split "`r?`n" | Where-Object { $_ }) -join "`n"
            Show-Status "$target was not deleted.`n`n$lines" 'error'
        }
    } elseif ($code -eq 0) {
        if ($script:TargetIsNew) {
            Show-Status "Switched to $target. Claude is opening signed out: sign in with the $target account. You only do this once." 'info'
        } else {
            Show-Status "Switched to $target. Claude is opening, already signed in." 'ok'
        }
    } else {
        $lines = ($out -split "`r?`n" | Where-Object { $_ -and $_ -notmatch '^\(not starting' }) -join "`n"
        Show-Status "The switch did not happen, and nothing was changed.`n`n$lines" 'error'
    }
    if ($Snapshot) { $W.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action]{ Save-Snapshot }) | Out-Null }
})

function Start-Switch([string]$target, [bool]$isNew) {
    $cur = Get-ActiveName
    if ($cur -eq '') {
        if (-not (Request-ActiveName 'Before switching, give the account you are using now a name (for example Work), so you can come back to it later.')) { return }
        $cur = Get-ActiveName
    }
    if ($cur -and ($cur -ieq $target)) { Show-Status "You are already using $target." 'info'; return }

    if (-not $Yes) {
        if ($isNew) {
            $msg = "Claude will close and reopen signed out, so you can sign in with the $target account.`n`n" +
                   $(if ($cur) { "$cur stays signed in and saved. " } else { '' }) +
                   "Anything running in Claude right now will stop."
            $ok = Show-Dialog -Title "Add $target?" -Message $msg -OkText 'Close Claude and add'
        } else {
            $msg = "Claude will close and reopen signed in to $target.`n`n" +
                   $(if ($cur) { "$cur stays signed in and saved. " } else { '' }) +
                   "Anything running in Claude right now will stop."
            $ok = Show-Dialog -Title "Switch to $target?" -Message $msg -OkText 'Switch now'
        }
        if (-not $ok) { return }
    }

    $script:TargetIsNew = $isNew
    Start-Engine 'switch' $target @('-SwitchTo', "`"$target`"") $(if ($isNew) { "Closing Claude and preparing $target... Claude will open for you to sign in." }
                                                                 else { "Closing Claude and switching to $target... just a few seconds." })
}

function Start-Delete([string]$name) {
    $msg = "This removes $name's saved sign-in, chats and Claude Code sessions from this computer.`n`n" +
           "It does NOT delete $name's Claude account. You can add it again any time and sign in.`n`n" +
           "The folder goes to the Recycle Bin, so you can restore it from there if this was a mistake."
    if (-not $Yes) {
        $ok = Show-Dialog -Title "Delete $name from this PC?" -Message $msg -OkText "Yes, delete $name" -CancelText 'Keep it' -Danger
        if (-not $ok) { return }
    }
    Start-Engine 'delete' $name @('-Delete', "`"$name`"") "Deleting $name..."
}

function Start-Engine([string]$job, [string]$target, [string[]]$jobArgs, [string]$busyText) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Core`"") + $jobArgs + @('-Yes', '-DataRoot', "`"$DataRoot`"")
    if ($NoLaunch) { $argList += '-NoLaunch' }
    if ($SkipProcessCheck) { $argList += '-SkipProcessCheck' }

    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $PsExe
    $psi.Arguments = $argList -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $script:Target = $target
    $script:Job = $job
    Set-Busy $true $busyText
    try {
        $script:Proc = [Diagnostics.Process]::Start($psi)
        $script:OutTask = $script:Proc.StandardOutput.ReadToEndAsync()
        $script:ErrTask = $script:Proc.StandardError.ReadToEndAsync()
        $script:Timer.Start()
    } catch {
        Set-Busy $false
        Show-Status "Could not start: $($_.Exception.Message)" 'error'
    }
}

function Save-Snapshot {
    $W.UpdateLayout()
    $dpi = [Windows.Media.VisualTreeHelper]::GetDpi($W)
    $content = $W.Content
    $cw = $content.ActualWidth + $content.Margin.Left + $content.Margin.Right
    $ch = $content.ActualHeight + $content.Margin.Top + $content.Margin.Bottom
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]($cw * $dpi.DpiScaleX)), ([int]($ch * $dpi.DpiScaleY)), (96 * $dpi.DpiScaleX), (96 * $dpi.DpiScaleY), ([Windows.Media.PixelFormats]::Pbgra32)
    $bg = New-Object Windows.Media.DrawingVisual
    $dc = $bg.RenderOpen(); $dc.DrawRectangle($W.Background, $null, (New-Object Windows.Rect 0, 0, $cw, $ch)); $dc.Close()
    $bmp.Render($bg); $bmp.Render($content)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $fs = [IO.File]::Create($Snapshot); $enc.Save($fs); $fs.Close()
    $W.Close()
}

# ---------------------------------------------------------------- events
$ui.RenameBtn.Add_Click({
    $cur = Get-ActiveName
    if ($cur -eq '') { [void](Request-ActiveName 'For example Work. You will see this name in the switcher.') ; return }
    $n = Show-Dialog -Title "Rename $cur" -Message 'Type the new name for this account.' -AskText -OkText 'Rename' -Validate { param($v) Test-NewName $v }
    if ($n) { Set-Marker $n; Update-View; Show-Status "Renamed to $n." 'ok' }
})

$ui.AddBtn.Add_Click({
    $n = Show-Dialog -Title 'Add a new account' -Message 'Type a name for the client account, for example Client A. Claude will then open signed out so you can sign in with that account.' -AskText -OkText 'Next' -Validate { param($v) Test-NewName $v }
    if ($n) { Start-Switch $n $true }
})

$ui.AppShortcutBtn.Add_Click({
    try {
        Install-AppShortcuts
        [void](Show-Dialog -Title 'Ready to pin to your taskbar' -NoCancel -OkText 'Got it' -Message ("'Claude Account Switcher' is now in your Start menu and on your desktop.`n`n" +
            "To pin it to the taskbar:`n  1.  Open Start and type  Claude Account Switcher`n  2.  Right-click it and choose  Pin to taskbar`n`n" +
            "Windows only lets you do the pinning yourself. It takes one click."))
    } catch { Show-Status "Could not create the shortcuts: $($_.Exception.Message)" 'error' }
})

$W.Add_ContentRendered({
    if ($SwitchTo) {
        $match = @(Get-SavedProfiles) | Where-Object { $_ -ieq $SwitchTo } | Select-Object -First 1
        $cur = Get-ActiveName
        if ($match) { Start-Switch $match $false }
        elseif ($cur -and ($cur -ieq $SwitchTo)) { Show-Status "You are already using $cur." 'info' }
        else { Show-Status "There is no saved account called '$SwitchTo'. Use 'Add a new account' to create it." 'error' }
        if ($Snapshot -and -not $script:Timer.IsEnabled) { Save-Snapshot }
    } elseif ($Snapshot) {
        Save-Snapshot
    } elseif ((Get-ActiveName) -eq '') {
        [void](Request-ActiveName 'Welcome! First, give a name to the Claude account you are signed in to right now (for example Work).')
    }
})

if ($InstallShortcuts) {
    try { Install-AppShortcuts; 'Shortcuts created.' } catch { "Failed: $($_.Exception.Message)"; exit 1 }
    exit 0
}
if ($Snapshot) { $W.Left = -4000; $W.Top = 0; $W.WindowStartupLocation = 'Manual'; $W.ShowInTaskbar = $false }
Update-View
[void]$W.ShowDialog()
