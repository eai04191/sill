import Foundation
import SwiftUI

struct RootToml: Decodable {
    var theme: String?
    var position: BarPosition?
    var experimental: ExperimentalConfig?
    var widgets: WidgetsSection

    enum CodingKeys: String, CodingKey {
        case theme, position, experimental, widgets
    }

    init() {
        self.theme = nil
        self.position = nil
        self.widgets = WidgetsSection(displayed: [], others: [:])
    }
}

struct Config {
    let rootToml: RootToml

    init(rootToml: RootToml = RootToml()) {
        self.rootToml = rootToml
    }

    var position: BarPosition {
        rootToml.position ?? .top
    }
    
    var experimental: ExperimentalConfig {
        rootToml.experimental ?? ExperimentalConfig()
    }
}

/// The screen edge where the bar is placed (`position = "top"` or `"bottom"`).
enum BarPosition: String, Decodable {
    case top, bottom
}

typealias ConfigData = [String: TOMLValue]

class ConfigProvider: ObservableObject {
    @Published var config: ConfigData

    init(config: ConfigData) {
        self.config = config
    }
}

struct WidgetsSection: Decodable {
    let displayed: [TomlWidgetItem]
    let others: [String: ConfigData]

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? = nil

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    init(
        displayed: [TomlWidgetItem],
        others: [String: ConfigData]
    ) {
        self.displayed = displayed
        self.others = others
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)

        let displayedKey = DynamicKey(stringValue: "displayed")!
        let displayedArray = try container.decode(
            [TomlWidgetItem].self, forKey: displayedKey)
        self.displayed = displayedArray

        var tempDict = [String: ConfigData]()

        for key in container.allKeys {
            guard key.stringValue != "displayed" else { continue }

            let nested = try container.nestedContainer(
                keyedBy: DynamicKey.self, forKey: key)

            var widgetDict = ConfigData()
            for nestedKey in nested.allKeys {
                let value = try nested.decode(TOMLValue.self, forKey: nestedKey)
                widgetDict[nestedKey.stringValue] = value
            }
            tempDict[key.stringValue] = widgetDict
        }

        self.others = tempDict
    }

    func config(for widgetId: String) -> ConfigData? {
        let keys = widgetId.split(separator: ".").map { String($0) }

        var current: Any? = others

        for key in keys {
            guard let dict = current as? [String: Any] else {
                return nil
            }
            current = dict[key]
        }

        return (current as? TOMLValue)?.dictionaryValue as? ConfigData
    }
}

struct TomlWidgetItem: Decodable {
    let id: String
    let inlineParams: ConfigData

    init(id: String, inlineParams: ConfigData) {
        self.id = id
        self.inlineParams = inlineParams
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let strValue = try? container.decode(String.self) {
            self.id = strValue
            self.inlineParams = [:]
            return
        }

        let dictValue = try container.decode([String: ConfigData].self)

        guard dictValue.count == 1,
            let (widgetId, params) = dictValue.first
        else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription:
                        "Uncorrect inline-table in [widgets.displayed]"
                )
            )
        }

        self.id = widgetId
        self.inlineParams = params
    }
}

enum TOMLValue: Decodable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case array([TOMLValue])
    case dictionary(ConfigData)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let str = try? container.decode(String.self) {
            self = .string(str)
            return
        }
        if let b = try? container.decode(Bool.self) {
            self = .bool(b)
            return
        }
        if let i = try? container.decode(Int.self) {
            self = .int(i)
            return
        }
        if let d = try? container.decode(Double.self) {
            self = .double(d)
            return
        }
        if let arr = try? container.decode([TOMLValue].self) {
            self = .array(arr)
            return
        }
        if let dict = try? container.decode(ConfigData.self) {
            self = .dictionary(dict)
            return
        }

        self = .null
    }
}

extension TOMLValue {
    var stringValue: String? {
        if case let .string(s) = self { return s }
        return nil
    }

    var intValue: Int? {
        if case let .int(i) = self { return i }
        return nil
    }

    var boolValue: Bool? {
        if case let .bool(b) = self { return b }
        return nil
    }

    var arrayValue: [TOMLValue]? {
        if case let .array(arr) = self { return arr }
        return nil
    }

    var dictionaryValue: ConfigData? {
        if case let .dictionary(dict) = self { return dict }
        return nil
    }
}

struct ExperimentalConfig: Decodable {
    let foreground: ForegroundConfig
    let background: BackgroundConfig
    
    enum CodingKeys: String, CodingKey {
        case foreground, background
    }
    
    init() {
        self.foreground = ForegroundConfig()
        self.background = BackgroundConfig()
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        foreground = try container.decodeIfPresent(ForegroundConfig.self, forKey: .foreground) ?? ForegroundConfig()
        background = try container.decodeIfPresent(BackgroundConfig.self, forKey: .background) ?? BackgroundConfig()
    }
}

struct ForegroundConfig: Decodable {
    let height: BackgroundForegroundHeight
    let horizontalPadding: CGFloat
    let widgetsBackground: WidgetBackgroundConfig
    let spacing: CGFloat
    
    init() {
        self.height = .barikDefault
        self.horizontalPadding = Constants.menuBarHorizontalPadding
        self.widgetsBackground = WidgetBackgroundConfig()
        self.spacing = 15
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        height = try container.decodeIfPresent(BackgroundForegroundHeight.self, forKey: .height) ?? .barikDefault
        horizontalPadding = try container.decodeIfPresent(CGFloat.self, forKey: .horizontalPadding) ?? Constants.menuBarHorizontalPadding
        widgetsBackground = try container.decodeIfPresent(WidgetBackgroundConfig.self, forKey: .widgetsBackground) ?? WidgetBackgroundConfig()
        spacing = try container.decodeIfPresent(CGFloat.self, forKey: .spacing) ?? 15
    }
    
    enum CodingKeys: String, CodingKey {
        case height
        case horizontalPadding = "horizontal-padding"
        case widgetsBackground = "widgets-background"
        case spacing
    }
    
    func resolveHeight() -> CGFloat {
        switch height {
        case .barikDefault:
            return CGFloat(Constants.menuBarHeight)
        case .menuBar:
            return NSApplication.shared.mainMenu.map({ CGFloat($0.menuBarHeight) }) ?? 0
        case .float(let value):
            return CGFloat(value)
        }
    }
}

struct WidgetBackgroundConfig: Decodable {
    let displayed: Bool
    
    init() {
        self.displayed = false
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        displayed = try container.decodeIfPresent(Bool.self, forKey: .displayed) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case displayed, height
    }
}

struct BackgroundConfig: Decodable {
    let displayed: Bool
    let height: BackgroundForegroundHeight
    let blur: Material
    let black: Bool

    init() {
        self.displayed = true
        self.height = .barikDefault
        self.blur = .regular
        self.black = false
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayed = try container.decodeIfPresent(Bool.self, forKey: .displayed) ?? true
        height = try container.decodeIfPresent(BackgroundForegroundHeight.self, forKey: .height) ?? .barikDefault
        
        let materialIndex = try container.decodeBlurIndex(forKey: .blur, maximum: 7)
        blur = [.ultraThin, .thin, .regular, .thick, .ultraThick, .bar, .bar][materialIndex - 1]
        self.black = materialIndex == 7
    }

    enum CodingKeys: String, CodingKey {
        case displayed, height, blur
    }

    func resolveHeight() -> CGFloat? {
        switch height {
        case .barikDefault:
            return nil
        case .menuBar:
            return NSApplication.shared.mainMenu.map({ CGFloat($0.menuBarHeight) }) ?? 0
        case .float(let value):
            return CGFloat(value)
        }
    }
}

extension KeyedDecodingContainer {
    /// Reads a `blur` index from 1 up to `maximum`. Without it the blur is 3 (`.regular`), as when the whole table is
    /// not set. A value outside the range is an error instead of being changed to the nearest valid one.
    fileprivate func decodeBlurIndex(forKey key: Key, maximum: Int) throws -> Int {
        let index = try decodeIfPresent(Int.self, forKey: key) ?? 3
        guard (1...maximum).contains(index) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: self, debugDescription: "blur must be from 1 to \(maximum), but is \(index)")
        }
        return index
    }
}

enum ForegroundPadding: Decodable {
    case float(Float)
    
    init(from decoder: Decoder) throws {
        if let floatValue = try? decoder.singleValueContainer().decode(Float.self) {
            self = .float(floatValue)
            return
        }
        
        if let intValue = try? decoder.singleValueContainer().decode(Int.self) {
            self = .float(Float(intValue))
            return
        }
        
        throw DecodingError.typeMismatch(
            ForegroundPadding.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected a float value"
            )
        )
    }
}

enum BackgroundForegroundHeight: Decodable {
    case barikDefault
    case menuBar
    case float(Float)
    
    init(from decoder: Decoder) throws {
        if let floatValue = try? decoder.singleValueContainer().decode(Float.self) {
            self = .float(floatValue)
            return
        }
        
        if let intValue = try? decoder.singleValueContainer().decode(Int.self) {
            self = .float(Float(intValue))
            return
        }
        
        if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
            if stringValue == "default" {
                self = .barikDefault
                return
            }
            
            if stringValue == "menu-bar" {
                self = .menuBar
                return
            }
            
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Expected 'default', 'menu-bar' or a float value, but found \(stringValue)"
            )
        }
        
        throw DecodingError.typeMismatch(
            ForegroundPadding.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected 'default', 'menu-bar' or a float value"
            )
        )
    }
}

