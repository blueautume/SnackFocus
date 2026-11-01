import SwiftUI
import UIKit

func labText(_ chinese: String, _ english: String) -> String {
    Locale.current.language.languageCode?.identifier == "zh" ? chinese : english
}

enum LabSnakeForm: String, CaseIterable, Identifiable {
    case pixel, ribbon, ink, neon, origami, clay, chrome, glass, pearl, hologram
    var id: String { rawValue }
    var number: Int { Self.allCases.firstIndex(of: self)! + 1 }
    var code: String { String(format: "S%02d", number) }
    var is3D: Bool { [.clay, .chrome, .glass, .pearl, .hologram].contains(self) }
    var title: String {
        switch self {
        case .pixel: return labText("像素生物", "Pixel creature")
        case .ribbon: return labText("流动丝带", "Silk ribbon")
        case .ink: return labText("水墨游龙", "Ink brush")
        case .neon: return labText("霓虹光管", "Neon light")
        case .origami: return labText("折纸鳞片", "Folded paper")
        case .clay: return labText("软糖黏土", "Soft clay")
        case .chrome: return labText("液态金属", "Liquid chrome")
        case .glass: return labText("冰透玻璃", "Frosted glass")
        case .pearl: return labText("珍珠陶瓷", "Pearl ceramic")
        case .hologram: return labText("全息晶体", "Hologram")
        }
    }
    var detail: String {
        switch self {
        case .pixel: return labText("颗粒像素、鳞纹与细尾", "Pixel scales and a tapered tail")
        case .ribbon: return labText("连续曲线、绸缎高光与渐变", "Flowing curves with satin highlights")
        case .ink: return labText("干笔飞白、墨色与纸张颗粒", "Dry-brush grain and ink texture")
        case .neon: return labText("发光轮廓、亮芯与柔和光晕", "Luminous core and a soft halo")
        case .origami: return labText("棱角折面、明暗交替的纸鳞", "Angular folds and paper facets")
        case .clay: return labText("真实三维、哑光软材质与阴影", "True 3D with soft matte shading")
        case .chrome: return labText("真实三维、金属反射与高光", "True 3D with metallic reflections")
        case .glass: return labText("真实三维、透明管身与亮边", "True 3D with translucent edges")
        case .pearl: return labText("真实三维、串珠轮廓与釉面", "True 3D glazed pearl segments")
        case .hologram: return labText("真实三维、虹彩晶体与自发光", "True 3D emissive crystal facets")
        }
    }
    var symbol: String {
        switch self {
        case .pixel: return "square.grid.3x3.fill"
        case .ribbon: return "wind"
        case .ink: return "paintbrush.pointed.fill"
        case .neon: return "bolt.fill"
        case .origami: return "paperplane.fill"
        case .clay: return "cloud.fill"
        case .chrome: return "drop.fill"
        case .glass: return "cube.transparent"
        case .pearl: return "circle.grid.2x2.fill"
        case .hologram: return "sparkles"
        }
    }
}

struct LabPalette {
    let background: Color
    let surface: Color
    let ink: Color
    let secondary: Color
    let accent: Color
    let accent2: Color
    let board: Color
    let isDark: Bool
    var line: Color { ink.opacity(isDark ? 0.16 : 0.12) }
    var uiBackground: UIColor { UIColor(background) }
    var uiAccent: UIColor { UIColor(accent) }
    var uiAccent2: UIColor { UIColor(accent2) }
    var uiBoard: UIColor { UIColor(board) }
}

enum LabTheme: String, CaseIterable, Identifiable {
    case atelier, zen, arcade, observatory, gallery, dashboard, paper, candy, terminal, aurora
    var id: String { rawValue }
    var number: Int { Self.allCases.firstIndex(of: self)! + 1 }
    var code: String { String(format: "T%02d", number) }
    var title: String {
        switch self {
        case .atelier: return labText("轻盈工作室", "Atelier")
        case .zen: return labText("侘寂庭院", "Zen garden")
        case .arcade: return labText("午夜街机", "Midnight arcade")
        case .observatory: return labText("轨道观测站", "Observatory")
        case .gallery: return labText("艺术画廊", "Art gallery")
        case .dashboard: return labText("专注仪表盘", "Focus dashboard")
        case .paper: return labText("纸上手记", "Paper journal")
        case .candy: return labText("糖果游乐场", "Candy playground")
        case .terminal: return labText("极客终端", "Green terminal")
        case .aurora: return labText("极光沉浸", "Aurora flow")
        }
    }
    var detail: String {
        switch self {
        case .atelier: return labText("留白、胶囊操作、轻量卡片", "Whitespace, pill controls, light cards")
        case .zen: return labText("居中排版、圆形计时、自然色", "Centered rhythm and natural tones")
        case .arcade: return labText("像素计分、霓虹框线、街机面板", "Neon framing and arcade counters")
        case .observatory: return labText("轨道仪表、分栏状态、太空蓝", "Orbital gauges and space-blue panels")
        case .gallery: return labText("展签、衬框、画作式棋盘", "A framed canvas with gallery captions")
        case .dashboard: return labText("指标卡片、信息栅格、清晰层级", "Metric cards and a structured grid")
        case .paper: return labText("便签、横线纸、手记式布局", "Notebook rules and journal typography")
        case .candy: return labText("大圆角、贴纸、玩具式操作", "Playful stickers and chunky controls")
        case .terminal: return labText("命令行标题、字符分隔、荧光绿", "Monospace prompts and phosphor green")
        case .aurora: return labText("渐变光场、浮动操作、沉浸棋盘", "Gradient light fields and floating controls")
        }
    }
    var recommendedForm: LabSnakeForm {
        switch self {
        case .atelier: return .clay
        case .zen: return .ink
        case .arcade: return .neon
        case .observatory: return .chrome
        case .gallery: return .origami
        case .dashboard: return .glass
        case .paper: return .ribbon
        case .candy: return .pearl
        case .terminal: return .pixel
        case .aurora: return .hologram
        }
    }
    var palette: LabPalette {
        switch self {
        case .atelier: return colors("F5F4F0", "FFFFFF", "242D32", "657177", "428978", "B0CEAD", "E9EEE9")
        case .zen: return colors("EDEADF", "F7F5EA", "374231", "727563", "536D49", "B9A87D", "E0E5D5")
        case .arcade: return colors("100D22", "201A37", "F4EDFF", "A69DBD", "41F0E1", "ED5CCC", "17162C", dark: true)
        case .observatory: return colors("101B2D", "1C2B42", "EDF4FF", "8DA6C3", "75B9FF", "D0AB70", "142239", dark: true)
        case .gallery: return colors("F0EAE2", "FFFCF8", "2B2525", "8A7872", "B85F42", "D4B47C", "E7DCD0")
        case .dashboard: return colors("EDF1F7", "FFFFFF", "26334A", "75839A", "4B70D7", "6ABCB3", "E0E8F1")
        case .paper: return colors("F6EEDC", "FFF9EB", "4A3B30", "8C7B67", "A66148", "C7A85B", "F0E4CD")
        case .candy: return colors("F9EAF1", "FFF7FB", "5F365E", "9B7994", "B566C0", "EDB85F", "EDE1F1")
        case .terminal: return colors("07150F", "10251B", "C0F3B2", "6FA07B", "8AE86D", "DFD07B", "0A1C13", dark: true)
        case .aurora: return colors("0C1730", "1B2945", "F0F0FF", "98AACD", "8FD9E1", "C790EC", "14213A", dark: true)
        }
    }
    private func colors(_ bg: String, _ surface: String, _ ink: String, _ secondary: String,
                        _ accent: String, _ accent2: String, _ board: String, dark: Bool = false) -> LabPalette {
        LabPalette(background: Color(labHex: bg), surface: Color(labHex: surface), ink: Color(labHex: ink), secondary: Color(labHex: secondary), accent: Color(labHex: accent), accent2: Color(labHex: accent2), board: Color(labHex: board), isDark: dark)
    }
}

extension Color {
    init(labHex: String) {
        let v = UInt64(labHex, radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}
