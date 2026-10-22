import AppKit

/// Finder 一致的条目图标:按真实路径向 NSWorkspace 取系统图标——桌面/文稿/下载/
/// 应用/卷等特殊目录各有与 Finder 完全相同的图标,普通目录是通用文件夹图标。
/// 抽屉树与锚点菜单共用本处,保证两处图标口径一致(「与 Finder 一致」的唯一落点)。
/// NSWorkspace 可能返回共享实例,复制后再改尺寸,避免影响他人正在使用的图标。
enum FinderIcon {
    static func folder(at url: URL, size: CGFloat) -> NSImage {
        let base = NSWorkspace.shared.icon(forFile: url.path)
        let icon = (base.copy() as? NSImage) ?? base
        icon.size = NSSize(width: size, height: size)
        return icon
    }
}
