import CoreGraphics

/// Политика геометрии desktop-дашборда (bd mac-limits-tracker-gld.3):
/// одна читабельная колонка контента вместо растяжения на всю ширину окна.
/// Это чистые layout-константы — без бизнес-правил и без привязки к теме:
/// system/terminal/phosphor/tui разделяют одни и те же границы.
public enum DesktopDashboardLayout {
    /// Максимальная ширина колонки контента. На широком окне дальше
    /// остаются спокойные пустые поля, а графики не расползаются в длинные
    /// почти плоские линии.
    public static let maxContentWidth: CGFloat = 840

    /// Минимальная ширина колонки: на минимальном размере окна главные
    /// значения остаются доступны без горизонтального скролла.
    public static let minContentWidth: CGFloat = 380

    /// Горизонтальный отступ колонки от краёв окна.
    public static let horizontalPadding: CGFloat = 20

    /// Минимальная ширина окна: колонка минимальной ширины плюс поля.
    public static let minWindowWidth: CGFloat =
        minContentWidth + 2 * horizontalPadding
}
