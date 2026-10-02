using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using System.Windows.Threading;
using Microsoft.Win32;
using Tidebar.Modules;

namespace Tidebar {
    public class HudWindow : Window {
        private IntPtr _hwnd = IntPtr.Zero;

        // 模块列表
        private CpuModule _modCpu;
        private MemoryModule _modMemory;
        private GpuModule _modGpu;
        private NetworkModule _modNetwork;
        private LatencyModule _modLatency;
        private SyncthingModule _modSyncthing;
        private ClaudeModule _modClaude;
        private SystemModule _modSystem;
        private List<IHudModule> _modules;

        // 状态变量
        private bool _isMiniMode;
        private bool _autoExpandOnHover = true;
        private bool _userTopmostPreference = true;
        private bool _isCurrentlyFullscreenSunk = false;
        private double _bgAlpha = 0.72;
        private Timer _workerTimer;
        private DispatcherTimer _collapseTimer;
        private DispatcherTimer _posDebounceTimer;
        private static int _isCollecting = 0;
        private int _tickCount = 0;

        // UI 容器
        private Border _rootBorder;
        private Grid _fullContainer;
        private Grid _miniContainer;

        // 卡片引用（用于动态按可用性显示/隐藏）
        private Border _headerCard;
        private Border _netCard;
        private DockPanel _netSpeedRow;
        private DockPanel _netPingRow;
        private DockPanel _netTotalRow;
        private Border _syncCard;
        private Border _claudeCard;
        private Border _cpuCard;
        private Border _ramCard;
        private Border _gpuCard;
        private DockPanel _sysFooter;

        // 全览模式 UI 元素
        private TextBlock _txtClock;
        private TextBlock _txtNetSpeedDown, _txtNetSpeedUp, _txtNetTotal;
        private TextBlock _txtLatency;
        private Ellipse _dotLatency;
        private TextBlock _lblSyncTitle;
        private TextBlock _txtSyncStatus, _txtSyncNodes, _txtSyncSize;
        private Ellipse _dotSync;
        private ProgressBar _progSync;
        private Border _btnManualSync;
        private TextBlock _txtManualSync;

        private TextBlock _txtClaudeWindows, _txtClaudeCost;

        private TextBlock _lblCpuTitle, _txtCpuLoad;
        private ProgressBar _progCpu;
        private TextBlock _txtRamLoad, _txtRamDetail, _txtTopProc;
        private ProgressBar _progRam;
        private TextBlock _txtGpuTitle, _txtGpuLoad, _txtGpuDetail;
        private ProgressBar _progGpu;
        private TextBlock _txtDiskDetail, _txtPowerStatus, _txtUptime;
        private TextBlock _btnPin;

        // 迷你胶囊模式 UI 元素
        private StackPanel _miniPanelLatency;
        private TextBlock _miniTxtLatency;
        private Ellipse _miniDotLatency;
        private TextBlock _miniTxtSpeed;
        private TextBlock _miniTxtClaude;
        private TextBlock _miniTxtCpu;
        private TextBlock _miniTxtRam;
        private TextBlock _miniTxtGpu;
        private StackPanel _miniSyncBtn;
        private TextBlock _miniTxtSync;
        private Ellipse _miniDotSync;

        public HudWindow() {
            InitModules();
            LoadConfig();
            InitializeWindow();
            BuildUi();
            InitTimers();
        }

        protected override void OnSourceInitialized(EventArgs e) {
            base.OnSourceInitialized(e);
            _hwnd = new WindowInteropHelper(this).Handle;
        }

        private void InitModules() {
            _modCpu = new CpuModule();
            _modMemory = new MemoryModule();
            _modGpu = new GpuModule();
            _modNetwork = new NetworkModule();
            _modLatency = new LatencyModule();
            _modSyncthing = new SyncthingModule();
            _modClaude = new ClaudeModule();
            _modSystem = new SystemModule();

            _modules = new List<IHudModule>();
            _modules.Add(_modCpu);
            _modules.Add(_modMemory);
            _modules.Add(_modGpu);
            _modules.Add(_modNetwork);
            _modules.Add(_modLatency);
            _modules.Add(_modSyncthing);
            _modules.Add(_modClaude);
            _modules.Add(_modSystem);
        }

        private bool IsModuleEnabled(string moduleId) {
            string val = Config.Instance.GetString("modules", moduleId, "auto");
            val = val.Trim().ToLowerInvariant();
            if (val == "off" || val == "false" || val == "0") return false;
            return true;
        }

        private void LoadConfig() {
            Config cfg = Config.Instance;
            _bgAlpha = cfg.GetDouble("window", "opacity", 0.72);
            if (_bgAlpha < 0.2) _bgAlpha = 0.2;
            if (_bgAlpha > 0.95) _bgAlpha = 0.95;

            _userTopmostPreference = cfg.GetBool("window", "topmost", true);
            _autoExpandOnHover = cfg.GetBool("window", "hover_expand", true);
        }

        private void InitializeWindow() {
            this.Title = string.Format("{0} - 整机全览", AppInfo.Name);
            this.WindowStyle = WindowStyle.None;
            this.AllowsTransparency = true;
            this.Background = Brushes.Transparent;
            this.Topmost = _userTopmostPreference;
            this.ShowInTaskbar = false;
            this.Width = 316;
            this.SizeToContent = SizeToContent.Height;

            // 修复 bug #7：读取保存的坐标，并检查是否落在已连接的屏幕中
            Config cfg = Config.Instance;
            string leftStr = cfg.GetString("window", "left", "");
            string topStr = cfg.GetString("window", "top", "");
            bool posValid = false;

            double targetLeft = 0;
            double targetTop = 0;

            if (!string.IsNullOrEmpty(leftStr) && !string.IsNullOrEmpty(topStr)) {
                double l, t;
                if (double.TryParse(leftStr, out l) && double.TryParse(topStr, out t)) {
                    // 检查是否在任何已连接屏幕的有效工作区内
                    System.Windows.Forms.Screen[] screens = System.Windows.Forms.Screen.AllScreens;
                    for (int i = 0; i < screens.Length; i++) {
                        if (screens[i].WorkingArea.Contains((int)l, (int)t)) {
                            posValid = true;
                            targetLeft = l;
                            targetTop = t;
                            break;
                        }
                    }
                }
            }

            if (posValid) {
                this.Left = targetLeft;
                this.Top = targetTop;
            } else {
                // 回到主屏幕右上角，算上 WorkArea.Left 和 WorkArea.Top
                ResetToTopRight();
            }

            // 鼠标左键拖拽移动
            this.MouseLeftButtonDown += (s, e) => {
                if (e.ButtonState == MouseButtonState.Pressed) {
                    this.DragMove();
                }
            };

            // 修复 bug #7：防抖保存窗口坐标 (拖拽结束后 1 秒写入 config.ini)
            _posDebounceTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1000) };
            _posDebounceTimer.Tick += (s, e) => {
                _posDebounceTimer.Stop();
                Config.Instance.Set("window", "left", ((int)this.Left).ToString());
                Config.Instance.Set("window", "top", ((int)this.Top).ToString());
                Config.Instance.Save();
            };
            this.LocationChanged += (s, e) => {
                _posDebounceTimer.Stop();
                _posDebounceTimer.Start();
            };

            // 启动时完整展开 3.5 秒后收缩为极简胶囊
            _collapseTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(3500) };
            _collapseTimer.Tick += (s, e) => {
                _collapseTimer.Stop();
                _collapseTimer.Interval = TimeSpan.FromMilliseconds(350);
                if (_autoExpandOnHover) {
                    if (this.ContextMenu != null && this.ContextMenu.IsOpen) return;
                    if (this.IsMouseOver) return;
                    CollapseToMini();
                }
            };
            _collapseTimer.Start();

            this.MouseEnter += (s, e) => {
                if (_autoExpandOnHover) {
                    _collapseTimer.Stop();
                    ExpandToFull();
                }
            };

            this.MouseLeave += (s, e) => {
                if (_autoExpandOnHover) {
                    _collapseTimer.Stop();
                    _collapseTimer.Start();
                }
            };

            this.MouseDoubleClick += (s, e) => {
                ToggleMode();
            };

            BuildContextMenu();
        }

        private void ResetToTopRight() {
            Rect workArea = SystemParameters.WorkArea;
            this.Left = workArea.Left + workArea.Width - this.Width - 24;
            this.Top = workArea.Top + 32;
        }

        private void ResetToTopCenter() {
            Rect workArea = SystemParameters.WorkArea;
            this.Left = workArea.Left + (workArea.Width - this.Width) / 2;
            this.Top = workArea.Top + 32;
        }

        private void BuildContextMenu() {
            ContextMenu menu = new ContextMenu {
                Background = HudBrushes.DarkBg,
                Foreground = HudBrushes.TextWhite,
                BorderBrush = HudBrushes.BorderBlue
            };

            MenuItem itemAutoExpand = new MenuItem {
                Header = _autoExpandOnHover ? "✓ 悬停自动展开 / 移开折叠 (已开启)" : "⚙ 悬停自动展开 / 移开折叠 (已关闭)",
                Foreground = HudBrushes.TextWhite
            };
            itemAutoExpand.Click += (s, e) => {
                _autoExpandOnHover = !_autoExpandOnHover;
                itemAutoExpand.Header = _autoExpandOnHover ? "✓ 悬停自动展开 / 移开折叠 (已开启)" : "⚙ 悬停自动展开 / 移开折叠 (已关闭)";
                Config.Instance.Set("window", "hover_expand", _autoExpandOnHover ? "on" : "off");
                Config.Instance.Save();
                if (!_autoExpandOnHover) {
                    ExpandToFull();
                }
            };
            menu.Items.Add(itemAutoExpand);

            MenuItem itemMode = new MenuItem { Header = "⇄ 手动切换全览 / 极简胶囊条", Foreground = HudBrushes.TextWhite };
            itemMode.Click += (s, e) => ToggleMode();
            menu.Items.Add(itemMode);

            MenuItem itemTop = new MenuItem { Header = _userTopmostPreference ? "📌 窗口置顶 (当前: 开启)" : "📌 窗口置顶 (当前: 关闭)", Foreground = HudBrushes.TextWhite };
            itemTop.Click += (s, e) => {
                _userTopmostPreference = !_userTopmostPreference;
                this.Topmost = _userTopmostPreference;
                itemTop.Header = _userTopmostPreference ? "📌 窗口置顶 (当前: 开启)" : "📌 窗口置顶 (当前: 关闭)";
                Config.Instance.Set("window", "topmost", _userTopmostPreference ? "on" : "off");
                Config.Instance.Save();
                UpdatePinButtonVisual();
            };
            menu.Items.Add(itemTop);

            // 透明度调节
            MenuItem itemAlphaMenu = new MenuItem { Header = "🎨 窗口透明度调节", Foreground = HudBrushes.TextWhite };
            AddOpacityMenuItem(itemAlphaMenu, "52% (高透光轻盈)", 0.52);
            AddOpacityMenuItem(itemAlphaMenu, "72% (高对比深邃 · 默认推荐)", 0.72);
            AddOpacityMenuItem(itemAlphaMenu, "85% (暗色曜石)", 0.85);
            AddOpacityMenuItem(itemAlphaMenu, "95% (高饱和实色)", 0.95);
            menu.Items.Add(itemAlphaMenu);

            MenuItem itemResetPos = new MenuItem { Header = "🎯 归位到屏幕右上角", Foreground = HudBrushes.TextWhite };
            itemResetPos.Click += (s, e) => {
                ResetToTopRight();
                _posDebounceTimer.Stop();
                _posDebounceTimer.Start();
            };
            menu.Items.Add(itemResetPos);

            MenuItem itemCenterPos = new MenuItem { Header = "🎯 停靠在屏幕顶部居中", Foreground = HudBrushes.TextWhite };
            itemCenterPos.Click += (s, e) => {
                ResetToTopCenter();
                _posDebounceTimer.Stop();
                _posDebounceTimer.Start();
            };
            menu.Items.Add(itemCenterPos);

            menu.Items.Add(new Separator());

            // Syncthing 同步相关项
            if (_modSyncthing != null && _modSyncthing.Available) {
                MenuItem itemSyncNow = new MenuItem { Header = "🔄 立即手动同步", Foreground = HudBrushes.Sky };
                itemSyncNow.Click += (s, e) => {
                    _modSyncthing.TriggerManualSync();
                };
                menu.Items.Add(itemSyncNow);

                MenuItem itemSyncWeb = new MenuItem { Header = "☁️ 打开 Syncthing 同步控制台", Foreground = HudBrushes.TextWhite };
                itemSyncWeb.Click += (s, e) => {
                    try { Process.Start(_modSyncthing.GuiUrl); } catch { }
                };
                menu.Items.Add(itemSyncWeb);

                MenuItem itemOpenFolder = new MenuItem { Header = "📁 打开本地同步目录", Foreground = HudBrushes.TextWhite };
                itemOpenFolder.Click += (s, e) => {
                    try {
                        string p = _modSyncthing.FolderPath;
                        if (!string.IsNullOrEmpty(p) && Directory.Exists(p)) {
                            Process.Start("explorer.exe", p);
                        }
                    } catch { }
                };
                menu.Items.Add(itemOpenFolder);

                menu.Items.Add(new Separator());
            }

            // 打开配置文件
            MenuItem itemEditConfig = new MenuItem { Header = "📝 打开配置文件 (config.ini)", Foreground = HudBrushes.TextWhite };
            itemEditConfig.Click += (s, e) => {
                try {
                    Process.Start("notepad.exe", Config.Instance.FilePath);
                } catch (Exception ex) {
                    Logger.Log(ex);
                }
            };
            menu.Items.Add(itemEditConfig);

            // 重新加载配置
            MenuItem itemReloadConfig = new MenuItem { Header = "🔄 重新加载配置", Foreground = HudBrushes.TextWhite };
            itemReloadConfig.Click += (s, e) => {
                try {
                    Config.Instance.Reload();
                    LoadConfig();
                    ApplyWindowOpacity();
                    this.Topmost = _userTopmostPreference;
                    UpdatePinButtonVisual();
                } catch (Exception ex) {
                    Logger.Log(ex);
                }
            };
            menu.Items.Add(itemReloadConfig);

            // 开机自动启动
            bool isAuto = CheckStartupAutoRun();
            MenuItem itemAuto = new MenuItem { Header = isAuto ? "✓ 开机自动启动 (已启用)" : "🚀 开机自动启动 (未启用)", Foreground = HudBrushes.TextWhite };
            itemAuto.Click += (s, e) => {
                bool newState = !CheckStartupAutoRun();
                SetStartupAutoRun(newState);
                itemAuto.Header = newState ? "✓ 开机自动启动 (已启用)" : "🚀 开机自动启动 (未启用)";
            };
            menu.Items.Add(itemAuto);

            // 关于
            MenuItem itemAbout = new MenuItem { Header = string.Format("ℹ 关于 {0}", AppInfo.Name), Foreground = HudBrushes.TextWhite };
            itemAbout.Click += (s, e) => {
                string msg = string.Format("{0} v{1}\n通用桌面 HUD 看板", AppInfo.Name, AppInfo.Version);
                if (!string.IsNullOrEmpty(AppInfo.RepoUrl)) {
                    msg += string.Format("\n开源地址: {0}", AppInfo.RepoUrl);
                }
                MessageBox.Show(msg, string.Format("关于 {0}", AppInfo.Name), MessageBoxButton.OK, MessageBoxImage.Information);
            };
            menu.Items.Add(itemAbout);

            // 退出
            MenuItem itemExit = new MenuItem { Header = string.Format("✕ 退出 {0}", AppInfo.Name), Foreground = HudBrushes.Red };
            itemExit.Click += (s, e) => {
                if (_workerTimer != null) _workerTimer.Dispose();
                Application.Current.Shutdown();
            };
            menu.Items.Add(itemExit);

            menu.Closed += (s, e) => {
                if (_autoExpandOnHover && !this.IsMouseOver) {
                    _collapseTimer.Stop();
                    _collapseTimer.Start();
                }
            };

            this.ContextMenu = menu;
        }

        private void AddOpacityMenuItem(MenuItem parent, string title, double alpha) {
            MenuItem item = new MenuItem { Header = title, Foreground = HudBrushes.TextWhite };
            item.Click += (s, e) => {
                _bgAlpha = alpha;
                ApplyWindowOpacity();
                Config.Instance.Set("window", "opacity", _bgAlpha.ToString("F2"));
                Config.Instance.Save();
            };
            parent.Items.Add(item);
        }

        private void ApplyWindowOpacity() {
            if (_rootBorder != null) {
                byte a = (byte)(_bgAlpha * 255);
                _rootBorder.Background = new SolidColorBrush(Color.FromArgb(a, 10, 16, 30));
            }
        }

        private void BuildUi() {
            byte a = (byte)(_bgAlpha * 255);

            _rootBorder = new Border {
                Background = new SolidColorBrush(Color.FromArgb(a, 10, 16, 30)),
                BorderBrush = new SolidColorBrush(Color.FromArgb(120, 6, 182, 212)),
                BorderThickness = new Thickness(1.2),
                CornerRadius = new CornerRadius(12),
                Padding = _isMiniMode ? new Thickness(10, 6, 10, 6) : new Thickness(12, 9, 12, 10)
            };

            DropShadowEffect shadow = new DropShadowEffect {
                Color = Color.FromRgb(0, 0, 0),
                BlurRadius = 16,
                ShadowDepth = 3,
                Opacity = 0.4
            };
            _rootBorder.Effect = shadow;

            // 1. 全览模式容器
            _fullContainer = new Grid { Visibility = _isMiniMode ? Visibility.Collapsed : Visibility.Visible };
            _fullContainer.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // 0: 标题与时钟
            _fullContainer.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // 1: 网络与延迟
            _fullContainer.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // 2: 双端同步
            _fullContainer.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // 3: Claude Code 用量
            _fullContainer.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // 4: CPU
            _fullContainer.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // 5: 内存
            _fullContainer.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // 6: 显卡
            _fullContainer.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // 7: 底部系统信息

            // [Row 0] 标题栏 + 数字时钟
            Grid headerGrid = new Grid { Margin = new Thickness(0, 0, 0, 7) };
            headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            StackPanel titlePanel = new StackPanel { Orientation = Orientation.Horizontal };
            Ellipse liveDot = new Ellipse {
                Width = 7, Height = 7, Margin = new Thickness(0, 0, 6, 0),
                Fill = HudBrushes.Cyan,
                VerticalAlignment = VerticalAlignment.Center
            };
            TextBlock titleText = new TextBlock {
                Text = AppInfo.Name.ToUpper(),
                FontWeight = FontWeights.Bold,
                FontSize = 11,
                Foreground = HudBrushes.TextWhite,
                VerticalAlignment = VerticalAlignment.Center
            };
            _txtClock = new TextBlock {
                Text = "--:--:--",
                FontSize = 9.5,
                FontWeight = FontWeights.SemiBold,
                Foreground = HudBrushes.Sky,
                Margin = new Thickness(8, 1, 0, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
            titlePanel.Children.Add(liveDot);
            titlePanel.Children.Add(titleText);
            titlePanel.Children.Add(_txtClock);
            Grid.SetColumn(titlePanel, 0);

            StackPanel actionPanel = new StackPanel { Orientation = Orientation.Horizontal };
            _btnPin = new TextBlock {
                Text = "📌",
                FontSize = 11,
                Cursor = Cursors.Hand,
                Margin = new Thickness(4, 0, 6, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Opacity = _userTopmostPreference ? 0.95 : 0.35
            };
            _btnPin.MouseLeftButtonDown += (s, e) => {
                e.Handled = true;
                _userTopmostPreference = !_userTopmostPreference;
                this.Topmost = _userTopmostPreference;
                Config.Instance.Set("window", "topmost", _userTopmostPreference ? "on" : "off");
                Config.Instance.Save();
                UpdatePinButtonVisual();
            };

            TextBlock btnMini = new TextBlock {
                Text = "➖",
                FontSize = 10,
                Cursor = Cursors.Hand,
                Margin = new Thickness(0, 0, 6, 0),
                Foreground = HudBrushes.TextWhite,
                VerticalAlignment = VerticalAlignment.Center
            };
            btnMini.MouseLeftButtonDown += (s, e) => {
                e.Handled = true;
                ToggleMode();
            };

            TextBlock btnClose = new TextBlock {
                Text = "✕",
                FontSize = 11,
                FontWeight = FontWeights.Bold,
                Cursor = Cursors.Hand,
                Foreground = HudBrushes.TextLight,
                VerticalAlignment = VerticalAlignment.Center
            };
            btnClose.MouseEnter += (s, e) => btnClose.Foreground = HudBrushes.Red;
            btnClose.MouseLeave += (s, e) => btnClose.Foreground = HudBrushes.TextLight;
            btnClose.MouseLeftButtonDown += (s, e) => {
                e.Handled = true;
                if (_workerTimer != null) _workerTimer.Dispose();
                Application.Current.Shutdown();
            };

            actionPanel.Children.Add(_btnPin);
            actionPanel.Children.Add(btnMini);
            actionPanel.Children.Add(btnClose);
            Grid.SetColumn(actionPanel, 1);

            headerGrid.Children.Add(titlePanel);
            headerGrid.Children.Add(actionPanel);
            Grid.SetRow(headerGrid, 0);
            _fullContainer.Children.Add(headerGrid);

            // [Row 1] 网络监控卡片
            _netCard = CreateGlassCard();
            Grid netGrid = new Grid();
            netGrid.RowDefinitions.Add(new RowDefinition());
            netGrid.RowDefinitions.Add(new RowDefinition());
            netGrid.RowDefinitions.Add(new RowDefinition());

            _netSpeedRow = new DockPanel { LastChildFill = false };
            TextBlock lblSpeed = new TextBlock { Text = "实时网速", FontSize = 10.5, FontWeight = FontWeights.Medium, Foreground = HudBrushes.TextLight };
            _txtNetSpeedDown = new TextBlock { Text = "↓ 0.0 KB/s", FontSize = 11.5, FontWeight = FontWeights.Bold, Foreground = HudBrushes.Green, Margin = new Thickness(0, 0, 8, 0) };
            _txtNetSpeedUp = new TextBlock { Text = "↑ 0.0 KB/s", FontSize = 11.5, FontWeight = FontWeights.Bold, Foreground = HudBrushes.Sky };
            DockPanel.SetDock(lblSpeed, Dock.Left);
            DockPanel.SetDock(_txtNetSpeedUp, Dock.Right);
            DockPanel.SetDock(_txtNetSpeedDown, Dock.Right);
            _netSpeedRow.Children.Add(lblSpeed);
            _netSpeedRow.Children.Add(_txtNetSpeedUp);
            _netSpeedRow.Children.Add(_txtNetSpeedDown);
            Grid.SetRow(_netSpeedRow, 0);

            _netPingRow = new DockPanel { Margin = new Thickness(0, 3, 0, 0), LastChildFill = false };
            TextBlock lblPing = new TextBlock { Text = "网络延迟", FontSize = 10.5, FontWeight = FontWeights.Medium, Foreground = HudBrushes.TextLight };
            StackPanel latencyPanel = new StackPanel { Orientation = Orientation.Horizontal };
            _dotLatency = new Ellipse { Width = 7, Height = 7, Fill = HudBrushes.Green, Margin = new Thickness(0, 0, 5, 0), VerticalAlignment = VerticalAlignment.Center };
            _txtLatency = new TextBlock { Text = "测速中...", FontSize = 11, FontWeight = FontWeights.Bold, Foreground = HudBrushes.TextWhite };
            latencyPanel.Children.Add(_dotLatency);
            latencyPanel.Children.Add(_txtLatency);
            DockPanel.SetDock(lblPing, Dock.Left);
            DockPanel.SetDock(latencyPanel, Dock.Right);
            _netPingRow.Children.Add(lblPing);
            _netPingRow.Children.Add(latencyPanel);
            Grid.SetRow(_netPingRow, 1);

            _netTotalRow = new DockPanel { Margin = new Thickness(0, 2, 0, 0), LastChildFill = false };
            TextBlock lblTotal = new TextBlock { Text = "本次流量", FontSize = 9.5, Foreground = HudBrushes.Gray };
            _txtNetTotal = new TextBlock { Text = "↓ 0 MB | ↑ 0 MB", FontSize = 9.5, Foreground = HudBrushes.Slate };
            DockPanel.SetDock(lblTotal, Dock.Left);
            DockPanel.SetDock(_txtNetTotal, Dock.Right);
            _netTotalRow.Children.Add(lblTotal);
            _netTotalRow.Children.Add(_txtNetTotal);
            Grid.SetRow(_netTotalRow, 2);

            netGrid.Children.Add(_netSpeedRow);
            netGrid.Children.Add(_netPingRow);
            netGrid.Children.Add(_netTotalRow);
            _netCard.Child = netGrid;
            Grid.SetRow(_netCard, 1);
            _fullContainer.Children.Add(_netCard);

            // [Row 2] 双端同步卡片
            _syncCard = CreateGlassCard();
            Grid syncGrid = new Grid();
            syncGrid.RowDefinitions.Add(new RowDefinition());
            syncGrid.RowDefinitions.Add(new RowDefinition());
            syncGrid.RowDefinitions.Add(new RowDefinition());

            DockPanel syncHeader = new DockPanel { LastChildFill = false };
            StackPanel leftSyncPanel = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            _lblSyncTitle = new TextBlock { Text = "同步", FontSize = 10.5, FontWeight = FontWeights.Medium, Foreground = HudBrushes.TextLight, VerticalAlignment = VerticalAlignment.Center };

            _btnManualSync = new Border {
                Background = new SolidColorBrush(Color.FromArgb(50, 30, 58, 138)),
                BorderBrush = new SolidColorBrush(Color.FromArgb(160, 96, 165, 250)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(3),
                Padding = new Thickness(5, 1, 5, 1),
                Margin = new Thickness(6, 0, 0, 0),
                Cursor = Cursors.Hand,
                VerticalAlignment = VerticalAlignment.Center,
                ToolTip = "立即扫描变动并同步"
            };
            _txtManualSync = new TextBlock {
                Text = "🔄 手动同步",
                FontSize = 9.0,
                FontWeight = FontWeights.SemiBold,
                Foreground = HudBrushes.Sky
            };
            _btnManualSync.Child = _txtManualSync;
            _btnManualSync.MouseLeftButtonDown += (s, e) => {
                e.Handled = true;
                if (_modSyncthing != null) _modSyncthing.TriggerManualSync();
            };

            leftSyncPanel.Children.Add(_lblSyncTitle);
            leftSyncPanel.Children.Add(_btnManualSync);

            StackPanel syncStatusPanel = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            _dotSync = new Ellipse { Width = 7, Height = 7, Fill = HudBrushes.Green, Margin = new Thickness(0, 0, 5, 0), VerticalAlignment = VerticalAlignment.Center };
            _txtSyncStatus = new TextBlock { Text = "已同步", FontSize = 11, FontWeight = FontWeights.Bold, Foreground = HudBrushes.TextWhite };
            syncStatusPanel.Children.Add(_dotSync);
            syncStatusPanel.Children.Add(_txtSyncStatus);

            DockPanel.SetDock(leftSyncPanel, Dock.Left);
            DockPanel.SetDock(syncStatusPanel, Dock.Right);
            syncHeader.Children.Add(leftSyncPanel);
            syncHeader.Children.Add(syncStatusPanel);
            Grid.SetRow(syncHeader, 0);

            _progSync = CreateModernProgressBar(HudBrushes.Green);
            Grid.SetRow(_progSync, 1);

            DockPanel syncNodeRow = new DockPanel { Margin = new Thickness(0, 3, 0, 0), LastChildFill = false };
            _txtSyncNodes = new TextBlock { Text = "检测中...", FontSize = 9.5, Foreground = HudBrushes.Gray };
            _txtSyncSize = new TextBlock { Text = "--", FontSize = 9.5, Foreground = HudBrushes.Slate };
            DockPanel.SetDock(_txtSyncNodes, Dock.Left);
            DockPanel.SetDock(_txtSyncSize, Dock.Right);
            syncNodeRow.Children.Add(_txtSyncNodes);
            syncNodeRow.Children.Add(_txtSyncSize);
            Grid.SetRow(syncNodeRow, 2);

            syncGrid.Children.Add(syncHeader);
            syncGrid.Children.Add(_progSync);
            syncGrid.Children.Add(syncNodeRow);
            _syncCard.Child = syncGrid;
            Grid.SetRow(_syncCard, 2);
            _fullContainer.Children.Add(_syncCard);

            // [Row 3] Claude Code 用量卡片 (新模块)
            _claudeCard = CreateGlassCard();
            Grid claudeGrid = new Grid();
            claudeGrid.RowDefinitions.Add(new RowDefinition());
            claudeGrid.RowDefinitions.Add(new RowDefinition());

            DockPanel claudeHeader = new DockPanel { LastChildFill = false };
            TextBlock lblClaude = new TextBlock { Text = "Claude Code", FontSize = 10.5, FontWeight = FontWeights.Medium, Foreground = HudBrushes.TextLight };
            _txtClaudeWindows = new TextBlock { Text = "活跃窗口 0 个", FontSize = 10.0, FontWeight = FontWeights.SemiBold, Foreground = HudBrushes.Sky };
            DockPanel.SetDock(lblClaude, Dock.Left);
            DockPanel.SetDock(_txtClaudeWindows, Dock.Right);
            claudeHeader.Children.Add(lblClaude);
            claudeHeader.Children.Add(_txtClaudeWindows);
            Grid.SetRow(claudeHeader, 0);

            DockPanel claudeStatsRow = new DockPanel { Margin = new Thickness(0, 3, 0, 0), LastChildFill = false };
            TextBlock lblCostTitle = new TextBlock { Text = "用量折算", FontSize = 9.5, Foreground = HudBrushes.Gray };
            _txtClaudeCost = new TextBlock { Text = "今日 0.0 万 · 5 小时 0.0 万", FontSize = 9.5, FontWeight = FontWeights.SemiBold, Foreground = HudBrushes.Slate };
            DockPanel.SetDock(lblCostTitle, Dock.Left);
            DockPanel.SetDock(_txtClaudeCost, Dock.Right);
            claudeStatsRow.Children.Add(lblCostTitle);
            claudeStatsRow.Children.Add(_txtClaudeCost);
            Grid.SetRow(claudeStatsRow, 1);

            claudeGrid.Children.Add(claudeHeader);
            claudeGrid.Children.Add(claudeStatsRow);
            _claudeCard.Child = claudeGrid;
            Grid.SetRow(_claudeCard, 3);
            _fullContainer.Children.Add(_claudeCard);

            // [Row 4] 处理器板块
            _cpuCard = CreateGlassCard();
            Grid cpuGrid = new Grid();
            cpuGrid.RowDefinitions.Add(new RowDefinition());
            cpuGrid.RowDefinitions.Add(new RowDefinition());

            DockPanel cpuHeader = new DockPanel { LastChildFill = false };
            _lblCpuTitle = new TextBlock { Text = _modCpu.CpuModel, FontSize = 10.5, FontWeight = FontWeights.Medium, Foreground = HudBrushes.TextLight };
            _txtCpuLoad = new TextBlock { Text = "0%", FontSize = 11.5, FontWeight = FontWeights.Bold, Foreground = HudBrushes.Cyan };
            DockPanel.SetDock(_lblCpuTitle, Dock.Left);
            DockPanel.SetDock(_txtCpuLoad, Dock.Right);
            cpuHeader.Children.Add(_lblCpuTitle);
            cpuHeader.Children.Add(_txtCpuLoad);
            Grid.SetRow(cpuHeader, 0);

            _progCpu = CreateModernProgressBar(HudBrushes.Cyan);
            Grid.SetRow(_progCpu, 1);

            cpuGrid.Children.Add(cpuHeader);
            cpuGrid.Children.Add(_progCpu);
            _cpuCard.Child = cpuGrid;
            Grid.SetRow(_cpuCard, 4);
            _fullContainer.Children.Add(_cpuCard);

            // [Row 5] 内存板块
            _ramCard = CreateGlassCard();
            Grid ramGrid = new Grid();
            ramGrid.RowDefinitions.Add(new RowDefinition());
            ramGrid.RowDefinitions.Add(new RowDefinition());
            ramGrid.RowDefinitions.Add(new RowDefinition());

            DockPanel ramHeader = new DockPanel { LastChildFill = false };
            _txtRamDetail = new TextBlock { Text = "内存 0G / 0G", FontSize = 10.5, FontWeight = FontWeights.Medium, Foreground = HudBrushes.TextLight };
            _txtRamLoad = new TextBlock { Text = "0%", FontSize = 11.5, FontWeight = FontWeights.Bold, Foreground = HudBrushes.Blue };
            DockPanel.SetDock(_txtRamDetail, Dock.Left);
            DockPanel.SetDock(_txtRamLoad, Dock.Right);
            ramHeader.Children.Add(_txtRamDetail);
            ramHeader.Children.Add(_txtRamLoad);
            Grid.SetRow(ramHeader, 0);

            _progRam = CreateModernProgressBar(HudBrushes.Blue);
            Grid.SetRow(_progRam, 1);

            DockPanel topProcRow = new DockPanel { Margin = new Thickness(0, 3, 0, 0), LastChildFill = false };
            TextBlock lblTop = new TextBlock { Text = "Top占用", FontSize = 9.5, Foreground = HudBrushes.Gray };
            _txtTopProc = new TextBlock { Text = "--", FontSize = 9.5, FontWeight = FontWeights.SemiBold, Foreground = HudBrushes.TextLight };
            DockPanel.SetDock(lblTop, Dock.Left);
            DockPanel.SetDock(_txtTopProc, Dock.Right);
            topProcRow.Children.Add(lblTop);
            topProcRow.Children.Add(_txtTopProc);
            Grid.SetRow(topProcRow, 2);

            ramGrid.Children.Add(ramHeader);
            ramGrid.Children.Add(_progRam);
            ramGrid.Children.Add(topProcRow);
            _ramCard.Child = ramGrid;
            Grid.SetRow(_ramCard, 5);
            _fullContainer.Children.Add(_ramCard);

            // [Row 6] 显卡板块
            _gpuCard = CreateGlassCard();
            Grid gpuGrid = new Grid();
            gpuGrid.RowDefinitions.Add(new RowDefinition());
            gpuGrid.RowDefinitions.Add(new RowDefinition());

            DockPanel gpuHeader = new DockPanel { LastChildFill = false };
            _txtGpuTitle = new TextBlock { Text = "GPU", FontSize = 10.5, FontWeight = FontWeights.Medium, Foreground = HudBrushes.TextLight };
            _txtGpuLoad = new TextBlock { Text = "0%", FontSize = 11.5, FontWeight = FontWeights.Bold, Foreground = HudBrushes.Purple };
            DockPanel.SetDock(_txtGpuTitle, Dock.Left);
            DockPanel.SetDock(_txtGpuLoad, Dock.Right);
            _txtGpuDetail = new TextBlock { Text = "", FontSize = 9.5, Foreground = HudBrushes.Slate, Margin = new Thickness(0, 1, 8, 0), VerticalAlignment = VerticalAlignment.Center };
            DockPanel.SetDock(_txtGpuDetail, Dock.Right);
            gpuHeader.Children.Add(_txtGpuTitle);
            gpuHeader.Children.Add(_txtGpuLoad);
            gpuHeader.Children.Add(_txtGpuDetail);
            Grid.SetRow(gpuHeader, 0);

            _progGpu = CreateModernProgressBar(HudBrushes.Purple);
            Grid.SetRow(_progGpu, 1);

            gpuGrid.Children.Add(gpuHeader);
            gpuGrid.Children.Add(_progGpu);
            _gpuCard.Child = gpuGrid;
            Grid.SetRow(_gpuCard, 6);
            _fullContainer.Children.Add(_gpuCard);

            // [Row 7] 底部栏
            _sysFooter = new DockPanel { Margin = new Thickness(2, 3, 2, 0), LastChildFill = false };
            _txtDiskDetail = new TextBlock { Text = "系统盘: --", FontSize = 9.5, Foreground = HudBrushes.Slate };
            _txtPowerStatus = new TextBlock { Text = "⚡ 100%", FontSize = 9.5, FontWeight = FontWeights.SemiBold, Foreground = HudBrushes.Sky, Margin = new Thickness(6, 0, 6, 0) };
            _txtUptime = new TextBlock { Text = "开机: --", FontSize = 9.5, Foreground = HudBrushes.Slate };
            DockPanel.SetDock(_txtDiskDetail, Dock.Left);
            DockPanel.SetDock(_txtUptime, Dock.Right);
            DockPanel.SetDock(_txtPowerStatus, Dock.Right);
            _sysFooter.Children.Add(_txtDiskDetail);
            _sysFooter.Children.Add(_txtPowerStatus);
            _sysFooter.Children.Add(_txtUptime);
            Grid.SetRow(_sysFooter, 7);
            _fullContainer.Children.Add(_sysFooter);

            // 2. 迷你胶囊模式容器
            _miniContainer = new Grid { Visibility = _isMiniMode ? Visibility.Visible : Visibility.Collapsed };
            DockPanel miniDock = new DockPanel { LastChildFill = false };
            StackPanel miniPanel = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };

            // 延迟小格
            _miniPanelLatency = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 6, 0) };
            _miniDotLatency = new Ellipse { Width = 7, Height = 7, Fill = HudBrushes.Green, Margin = new Thickness(0, 0, 4, 0), VerticalAlignment = VerticalAlignment.Center };
            _miniTxtLatency = new TextBlock { Text = "260ms", FontSize = 10.5, FontWeight = FontWeights.Bold, Foreground = HudBrushes.Green, VerticalAlignment = VerticalAlignment.Center };
            _miniPanelLatency.Children.Add(_miniDotLatency);
            _miniPanelLatency.Children.Add(_miniTxtLatency);

            // 网速小格
            _miniTxtSpeed = new TextBlock { Text = "↓0K", FontSize = 9.5, FontWeight = FontWeights.SemiBold, Foreground = HudBrushes.Sky, Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };

            // Claude AI 小格 (AI:N)
            _miniTxtClaude = new TextBlock { Text = "AI:0", FontSize = 9.5, FontWeight = FontWeights.Bold, Foreground = HudBrushes.Gray, Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };

            // CPU 小格
            _miniTxtCpu = new TextBlock { Text = "C:0%", FontSize = 9.5, FontWeight = FontWeights.Bold, Foreground = HudBrushes.Cyan, Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };

            // 内存小格
            _miniTxtRam = new TextBlock { Text = "M:0%", FontSize = 9.5, FontWeight = FontWeights.Bold, Foreground = HudBrushes.Blue, Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };

            // 显卡小格
            _miniTxtGpu = new TextBlock { Text = "G:--", FontSize = 9.5, FontWeight = FontWeights.Bold, Foreground = HudBrushes.Purple, Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };

            // 同步小格
            _miniDotSync = new Ellipse { Width = 6, Height = 6, Fill = HudBrushes.Green, Margin = new Thickness(2, 0, 3, 0), VerticalAlignment = VerticalAlignment.Center };
            _miniTxtSync = new TextBlock { Text = "已同步", FontSize = 9.5, FontWeight = FontWeights.Bold, Foreground = HudBrushes.Green, VerticalAlignment = VerticalAlignment.Center };
            _miniSyncBtn = new StackPanel {
                Orientation = Orientation.Horizontal,
                VerticalAlignment = VerticalAlignment.Center,
                Cursor = Cursors.Hand,
                ToolTip = "点击立即手动同步"
            };
            _miniSyncBtn.Children.Add(_miniDotSync);
            _miniSyncBtn.Children.Add(_miniTxtSync);
            _miniSyncBtn.MouseLeftButtonDown += (s, e) => {
                e.Handled = true;
                if (_modSyncthing != null) _modSyncthing.TriggerManualSync();
            };

            miniPanel.Children.Add(_miniPanelLatency);
            miniPanel.Children.Add(_miniTxtSpeed);
            miniPanel.Children.Add(_miniTxtClaude);
            miniPanel.Children.Add(_miniTxtCpu);
            miniPanel.Children.Add(_miniTxtRam);
            miniPanel.Children.Add(_miniTxtGpu);
            miniPanel.Children.Add(_miniSyncBtn);

            TextBlock hintExpand = new TextBlock {
                Text = "▾",
                FontSize = 9.5,
                Foreground = new SolidColorBrush(Color.FromArgb(160, 203, 213, 225)),
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 2, 0),
                ToolTip = "悬停展开完整全览"
            };

            DockPanel.SetDock(miniPanel, Dock.Left);
            DockPanel.SetDock(hintExpand, Dock.Right);
            miniDock.Children.Add(miniPanel);
            miniDock.Children.Add(hintExpand);
            _miniContainer.Children.Add(miniDock);

            // 整合
            StackPanel mainStack = new StackPanel();
            mainStack.Children.Add(_fullContainer);
            mainStack.Children.Add(_miniContainer);
            _rootBorder.Child = mainStack;
            this.Content = _rootBorder;
        }

        private Border CreateGlassCard() {
            return new Border {
                Background = new SolidColorBrush(Color.FromArgb(130, 15, 23, 42)),
                BorderBrush = new SolidColorBrush(Color.FromArgb(85, 56, 189, 248)),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(8, 5, 8, 5),
                Margin = new Thickness(0, 0, 0, 5)
            };
        }

        private ProgressBar CreateModernProgressBar(SolidColorBrush foregroundBrush) {
            return new ProgressBar {
                Height = 4,
                Minimum = 0,
                Maximum = 100,
                Value = 0,
                Margin = new Thickness(0, 3, 0, 0),
                Background = HudBrushes.ProgressBg,
                Foreground = foregroundBrush,
                BorderThickness = new Thickness(0)
            };
        }

        private void ExpandToFull() {
            _isMiniMode = false;
            _miniContainer.Visibility = Visibility.Collapsed;
            _fullContainer.Visibility = Visibility.Visible;
            _rootBorder.Padding = new Thickness(12, 9, 12, 10);
            this.Width = 316;
        }

        private void CollapseToMini() {
            _isMiniMode = true;
            _fullContainer.Visibility = Visibility.Collapsed;
            _miniContainer.Visibility = Visibility.Visible;
            _rootBorder.Padding = new Thickness(10, 6, 10, 6);
            this.Width = 316;
        }

        private void ToggleMode() {
            if (_isMiniMode) {
                ExpandToFull();
            } else {
                CollapseToMini();
            }
        }

        private void UpdatePinButtonVisual() {
            if (_btnPin != null) {
                _btnPin.Opacity = _userTopmostPreference ? 0.95 : 0.35;
            }
        }

        // 修复 bug #9：全屏窗口避让侦测（基于 HUD 所在屏幕与物理像素矩形对比）
        private bool IsForegroundFullscreen() {
            try {
                IntPtr fg = Native.GetForegroundWindow();
                if (fg == IntPtr.Zero || fg == _hwnd) return false;
                if (fg == Native.GetShellWindow() || fg == Native.GetDesktopWindow()) return false;

                // 排除带有普通标题栏的应用窗口（即便常规最大化也不算真全屏）
                int style = Native.GetWindowLong(fg, Native.GWL_STYLE);
                if ((style & Native.WS_CAPTION) == Native.WS_CAPTION) {
                    return false;
                }

                Native.RECT rect;
                if (Native.GetWindowRect(fg, out rect)) {
                    // 获取当前 HUD 所在屏幕的物理像素 Bounds
                    System.Windows.Forms.Screen screen = System.Windows.Forms.Screen.FromHandle(_hwnd);
                    if (screen != null) {
                        System.Drawing.Rectangle bounds = screen.Bounds;
                        // 覆盖该屏幕物理区域即判定为真全屏避让
                        if (rect.Left <= bounds.Left && rect.Top <= bounds.Top &&
                            rect.Right >= bounds.Right && rect.Bottom >= bounds.Bottom) {
                            return true;
                        }
                    }
                }
            } catch { }
            return false;
        }

        private void InitTimers() {
            _workerTimer = new Timer(WorkerCallback, null, 100, 1000);
        }

        // 修复 bug #2：重入闸与按各模块 IntervalSeconds 独立调度
        private void WorkerCallback(object state) {
            if (Interlocked.CompareExchange(ref _isCollecting, 1, 0) != 0) {
                // 上一拍尚未执行完成，立即跳过，避免后台线程堆积
                return;
            }

            try {
                for (int i = 0; i < _modules.Count; i++) {
                    IHudModule mod = _modules[i];
                    if (mod.Available && IsModuleEnabled(mod.Id)) {
                        if (_tickCount % mod.IntervalSeconds == 0) {
                            try {
                                mod.Collect();
                            } catch (Exception ex) {
                                Logger.Log(ex);
                            }
                        }
                    }
                }
                _tickCount++;

                bool isFs = IsForegroundFullscreen();

                this.Dispatcher.BeginInvoke(DispatcherPriority.Normal, new Action(() => {
                    RenderUi(isFs);
                }));
            } catch (Exception ex) {
                Logger.Log(ex);
            } finally {
                Interlocked.Exchange(ref _isCollecting, 0);
            }
        }

        private void RenderUi(bool isFs) {
            try {
                // 全屏避让
                if (isFs && !_isCurrentlyFullscreenSunk) {
                    _isCurrentlyFullscreenSunk = true;
                    this.Topmost = false;
                    if (_hwnd != IntPtr.Zero) {
                        Native.SetWindowPos(_hwnd, Native.HWND_NOTOPMOST, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
                        Native.SetWindowPos(_hwnd, Native.HWND_BOTTOM, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
                    }
                } else if (!isFs && _isCurrentlyFullscreenSunk) {
                    _isCurrentlyFullscreenSunk = false;
                    this.Topmost = _userTopmostPreference;
                    if (_hwnd != IntPtr.Zero && _userTopmostPreference) {
                        Native.SetWindowPos(_hwnd, Native.HWND_TOPMOST, 0, 0, 0, 0, Native.SWP_NOMOVE | Native.SWP_NOSIZE | Native.SWP_NOACTIVATE);
                    }
                }

                _txtClock.Text = DateTime.Now.ToString("HH:mm:ss");

                // 1. 网络与延迟模块
                bool netEnabled = _modNetwork.Available && IsModuleEnabled(_modNetwork.Id);
                bool latencyEnabled = _modLatency.Available && IsModuleEnabled(_modLatency.Id);

                _netSpeedRow.Visibility = netEnabled ? Visibility.Visible : Visibility.Collapsed;
                _netTotalRow.Visibility = netEnabled ? Visibility.Visible : Visibility.Collapsed;
                _netPingRow.Visibility = latencyEnabled ? Visibility.Visible : Visibility.Collapsed;
                _netCard.Visibility = (netEnabled || latencyEnabled) ? Visibility.Visible : Visibility.Collapsed;

                if (netEnabled) {
                    _txtNetSpeedDown.Text = _modNetwork.DownSpeedText;
                    _txtNetSpeedUp.Text = _modNetwork.UpSpeedText;
                    _txtNetTotal.Text = _modNetwork.TotalTrafficText;
                    _miniTxtSpeed.Text = _modNetwork.MiniSpeedText;
                    _miniTxtSpeed.Visibility = Visibility.Visible;
                } else {
                    _miniTxtSpeed.Visibility = Visibility.Collapsed;
                }

                if (latencyEnabled) {
                    long lat = _modLatency.LatencyMs;
                    _txtLatency.Text = _modLatency.StatusText;
                    SolidColorBrush latBrush = (lat >= 0 && lat < 350) ? HudBrushes.Green :
                                               (lat >= 0 && lat < 800) ? HudBrushes.Amber : HudBrushes.Red;
                    _dotLatency.Fill = latBrush;
                    _miniTxtLatency.Text = _modLatency.MiniText;
                    _miniTxtLatency.Foreground = latBrush;
                    _miniDotLatency.Fill = latBrush;
                    _miniPanelLatency.Visibility = Visibility.Visible;
                } else {
                    _miniPanelLatency.Visibility = Visibility.Collapsed;
                }

                // 2. Syncthing 双端同步
                bool syncEnabled = _modSyncthing.Available && IsModuleEnabled(_modSyncthing.Id);
                _syncCard.Visibility = syncEnabled ? Visibility.Visible : Visibility.Collapsed;
                _miniSyncBtn.Visibility = syncEnabled ? Visibility.Visible : Visibility.Collapsed;

                if (syncEnabled) {
                    _lblSyncTitle.Text = string.Format("同步 · {0}", _modSyncthing.FolderLabel);
                    _txtSyncStatus.Text = _modSyncthing.StatusDisplay;
                    _progSync.Value = _modSyncthing.CompletionPct;

                    SolidColorBrush syncBrush = HudBrushes.Green;
                    if (_modSyncthing.StatusColor == "amber") syncBrush = HudBrushes.Amber;
                    else if (_modSyncthing.StatusColor == "cyan") syncBrush = HudBrushes.Cyan;
                    else if (_modSyncthing.StatusColor == "red") syncBrush = HudBrushes.Red;
                    else if (_modSyncthing.StatusColor == "gray") syncBrush = HudBrushes.Gray;

                    _dotSync.Fill = syncBrush;
                    _progSync.Foreground = syncBrush;
                    _txtSyncNodes.Text = _modSyncthing.NodeStatusSummary;
                    _txtSyncSize.Text = _modSyncthing.InSyncGb > 0 ? string.Format("{0:F2} GB", _modSyncthing.InSyncGb) : "--";

                    _miniDotSync.Fill = syncBrush;
                    _miniTxtSync.Text = _modSyncthing.MiniDisplay;
                    _miniTxtSync.Foreground = syncBrush;

                    if (_modSyncthing.IsManualSyncing) {
                        _txtManualSync.Text = "⏳ 扫描中...";
                        _txtManualSync.Foreground = HudBrushes.Amber;
                    } else {
                        _txtManualSync.Text = "🔄 手动同步";
                        _txtManualSync.Foreground = HudBrushes.Sky;
                    }
                }

                // 3. Claude Code 用量
                bool claudeEnabled = _modClaude.Available && IsModuleEnabled(_modClaude.Id);
                _claudeCard.Visibility = claudeEnabled ? Visibility.Visible : Visibility.Collapsed;
                _miniTxtClaude.Visibility = claudeEnabled ? Visibility.Visible : Visibility.Collapsed;

                if (claudeEnabled) {
                    _txtClaudeWindows.Text = string.Format("活跃窗口 {0} 个", _modClaude.ActiveWindows);
                    _txtClaudeCost.Text = string.Format("今日 {0:F1} 万 · 5 小时 {1:F1} 万", _modClaude.TodayWan, _modClaude.FiveHourWan);

                    _miniTxtClaude.Text = string.Format("AI:{0}", _modClaude.ActiveWindows);
                    _miniTxtClaude.Foreground = (_modClaude.ActiveWindows > 0) ? HudBrushes.Sky : HudBrushes.Gray;
                }

                // 4. CPU
                bool cpuEnabled = _modCpu.Available && IsModuleEnabled(_modCpu.Id);
                _cpuCard.Visibility = cpuEnabled ? Visibility.Visible : Visibility.Collapsed;
                _miniTxtCpu.Visibility = cpuEnabled ? Visibility.Visible : Visibility.Collapsed;

                if (cpuEnabled) {
                    _lblCpuTitle.Text = _modCpu.CpuModel;
                    int cpu = _modCpu.LoadPct;
                    _txtCpuLoad.Text = cpu + "%";
                    _progCpu.Value = cpu;
                    _progCpu.Foreground = (cpu > 80) ? HudBrushes.Red : HudBrushes.Cyan;
                    _miniTxtCpu.Text = "C:" + cpu + "%";
                }

                // 5. 内存
                bool ramEnabled = _modMemory.Available && IsModuleEnabled(_modMemory.Id);
                _ramCard.Visibility = ramEnabled ? Visibility.Visible : Visibility.Collapsed;
                _miniTxtRam.Visibility = ramEnabled ? Visibility.Visible : Visibility.Collapsed;

                if (ramEnabled) {
                    int ram = _modMemory.LoadPct;
                    _txtRamLoad.Text = ram + "%";
                    _txtRamDetail.Text = string.Format("内存 {0:F1}G / {1:F1}G", _modMemory.UsedPhysGb, _modMemory.TotalPhysGb);
                    _txtTopProc.Text = _modMemory.TopProcDesc;
                    _progRam.Value = ram;
                    _progRam.Foreground = (ram > 85) ? HudBrushes.Red : HudBrushes.Blue;
                    _miniTxtRam.Text = "M:" + ram + "%";
                }

                // 6. 显卡
                bool gpuEnabled = _modGpu.Available && IsModuleEnabled(_modGpu.Id);
                _gpuCard.Visibility = gpuEnabled ? Visibility.Visible : Visibility.Collapsed;
                _miniTxtGpu.Visibility = gpuEnabled ? Visibility.Visible : Visibility.Collapsed;

                if (gpuEnabled) {
                    int gpu = _modGpu.LoadPct;
                    _txtGpuTitle.Text = _modGpu.GpuName;
                    if (gpu >= 0) {
                        _txtGpuLoad.Text = gpu + "%";
                        _progGpu.Value = gpu;
                        _txtGpuDetail.Text = string.Format("{0}°C ({1}M)", _modGpu.Temperature, _modGpu.MemUsedMb);
                        _miniTxtGpu.Text = "G:" + gpu + "%";
                    } else {
                        _txtGpuLoad.Text = "--";
                        _progGpu.Value = 0;
                        _txtGpuDetail.Text = "待机";
                        _miniTxtGpu.Text = "G:--";
                    }
                }

                // 7. 系统信息
                bool sysEnabled = _modSystem.Available && IsModuleEnabled(_modSystem.Id);
                _sysFooter.Visibility = sysEnabled ? Visibility.Visible : Visibility.Collapsed;

                if (sysEnabled) {
                    _txtDiskDetail.Text = _modSystem.SysDiskDesc;
                    _txtPowerStatus.Text = _modSystem.PowerDesc;
                    _txtUptime.Text = _modSystem.UptimeDesc;
                }
            } catch (Exception ex) {
                Logger.Log(ex);
            }
        }

        private static bool CheckStartupAutoRun() {
            try {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", false)) {
                    if (key != null) {
                        return key.GetValue(AppInfo.Name) != null;
                    }
                }
            } catch { }
            return false;
        }

        private static void SetStartupAutoRun(bool enable) {
            try {
                using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true)) {
                    if (key != null) {
                        if (enable) {
                            string exePath = Process.GetCurrentProcess().MainModule.FileName;
                            key.SetValue(AppInfo.Name, "\"" + exePath + "\"");
                        } else {
                            key.DeleteValue(AppInfo.Name, false);
                        }
                    }
                }
            } catch (Exception ex) {
                Logger.Log(ex);
            }
        }
    }
}
