import Foundation

/// Палитры тем в виде «сырых» hex-констант.
///
/// Живут в Core, а не в UI-слое, чтобы контраст можно было проверять тестом:
/// executable-таргет `MacLimitsTracker` тестам недоступен, а числа — доступны.
/// UI-обёртки (`TerminalPalette` и соседи) строят из этих значений `Color`.
public enum ThemePalette {
    public enum Terminal {
        public static let bg: UInt32 = 0x1A1B26
        public static let fg: UInt32 = 0xC0CAF5
        public static let dim: UInt32 = 0xA9B1D6
        /// Подложка полосы прогресса. Осветлена до 3:1 к фону: по длине полосы
        /// читается доля, а для этого должна быть видна её полная ширина.
        public static let track: UInt32 = 0x5C6497
        public static let cyan: UInt32 = 0x7DCFFF
        public static let warning: UInt32 = 0xE0AF68
        public static let critical: UInt32 = 0xF7768E
    }

    public enum Phosphor {
        public static let bg: UInt32 = 0x050805
        public static let bright: UInt32 = 0x35E06A
        public static let mid: UInt32 = 0x1E9C48
        public static let dim: UInt32 = 0x58C978
        public static let heading: UInt32 = 0x8DFFB0
    }

    public enum Tui {
        public static let bg: UInt32 = 0x101216
        public static let fg: UInt32 = 0xD0D5DD
        /// Рамка панели — основной структурный признак темы, поэтому 3:1 к фону.
        public static let border: UInt32 = 0x566177
        public static let dim: UInt32 = 0xAAB4C5
        public static let normal: UInt32 = 0x9ECE6A
        public static let warning: UInt32 = 0xE0AF68
        public static let critical: UInt32 = 0xF7768E
    }
}

/// Приглушение секции с устаревшими данными.
public enum StaleAppearance {
    /// Прозрачность stale-секции. 0.55 роняла тусклые токены ниже 3:1 к фону
    /// (хуже всех Phosphor mid — 2.39:1), а данные там реальные и их читают.
    /// 0.7 отличимо от свежего состояния и держит контраст.
    public static let opacity: Double = 0.7
}

/// Контраст по WCAG 2.1: относительная яркость и отношение контраста для
/// пары hex-цветов. Нужен тестам-гейтам палитры и ничему больше.
public enum WcagContrast {
    /// Относительная яркость sRGB-цвета (WCAG 2.1, §relative luminance).
    public static func relativeLuminance(_ hex: UInt32) -> Double {
        let channels = [
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255,
        ].map { channel -> Double in
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    /// Отношение контраста двух цветов: от 1 (совпадают) до 21 (чёрный/белый).
    public static func ratio(_ lhs: UInt32, _ rhs: UInt32) -> Double {
        let a = relativeLuminance(lhs)
        let b = relativeLuminance(rhs)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
