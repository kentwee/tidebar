using System.Windows.Media;

namespace Tidebar {
    public static class HudBrushes {
        public static readonly SolidColorBrush Green = Create(34, 197, 94);
        public static readonly SolidColorBrush Amber = Create(234, 179, 8);
        public static readonly SolidColorBrush Red = Create(244, 63, 94);
        public static readonly SolidColorBrush Cyan = Create(6, 182, 212);
        public static readonly SolidColorBrush Blue = Create(96, 165, 250);
        public static readonly SolidColorBrush Sky = Create(56, 189, 248);
        public static readonly SolidColorBrush Purple = Create(192, 132, 252);
        public static readonly SolidColorBrush Gray = Create(148, 163, 184);
        public static readonly SolidColorBrush Slate = Create(203, 213, 225);
        public static readonly SolidColorBrush TextWhite = Create(255, 255, 255);
        public static readonly SolidColorBrush TextLight = Create(226, 232, 240);
        public static readonly SolidColorBrush DarkBg = Create(15, 23, 42);
        public static readonly SolidColorBrush BorderBlue = Create(59, 130, 246);
        public static readonly SolidColorBrush ProgressBg = CreateAlpha(60, 30, 41, 59);

        private static SolidColorBrush Create(byte r, byte g, byte b) {
            var brush = new SolidColorBrush(Color.FromRgb(r, g, b));
            brush.Freeze();
            return brush;
        }

        private static SolidColorBrush CreateAlpha(byte a, byte r, byte g, byte b) {
            var brush = new SolidColorBrush(Color.FromArgb(a, r, g, b));
            brush.Freeze();
            return brush;
        }
    }
}
