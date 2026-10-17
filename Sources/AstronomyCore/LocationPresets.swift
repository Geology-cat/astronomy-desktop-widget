import Foundation

/// 設定画面で選べる観測地点です。都道府県庁所在地と、北海道の主な都市を収録します。
public struct LocationPreset: Equatable, Identifiable, Sendable {
    /// UserDefaults へ保存する識別子です。
    public let id: String
    /// 地方区分（「北海道」「東北」など）です。メニューの見出しに使います。
    public let region: String
    /// 都道府県名です。
    public let prefecture: String
    /// 地点名（市名）です。
    public let city: String
    public let latitude: Double
    public let longitude: Double

    public init(id: String, region: String, prefecture: String, city: String, latitude: Double, longitude: Double) {
        self.id = id
        self.region = region
        self.prefecture = prefecture
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
    }

    /// 「北海道 函館」「東京都 新宿区」のような表示名です。
    public var title: String { "\(prefecture) \(city)" }

    /// ウィジェットのヘッダーに出す短い地点名です。
    public var shortName: String { city }

    public var location: ObserverLocation {
        ObserverLocation(latitude: latitude, longitude: longitude, name: city)
    }

    public static func preset(id: String) -> LocationPreset? {
        all.first { $0.id == id }
    }

    /// 地方区分ごとにまとめた一覧です（収録順を保ちます）。
    public static var groupedByRegion: [(region: String, presets: [LocationPreset])] {
        var result: [(region: String, presets: [LocationPreset])] = []
        for preset in all {
            if let index = result.firstIndex(where: { $0.region == preset.region }) {
                result[index].presets.append(preset)
            } else {
                result.append((preset.region, [preset]))
            }
        }
        return result
    }

    /// 都道府県庁所在地は都道府県庁の位置（世界測地系）です。
    /// 北海道は道庁所在地の札幌に加え、広い道内をカバーできるよう主な都市の市役所付近を収録しています。
    public static let all: [LocationPreset] = [
        // 北海道
        LocationPreset(id: "hokkaido-sapporo", region: "北海道", prefecture: "北海道", city: "札幌", latitude: 43.0643, longitude: 141.3469),
        LocationPreset(id: "hokkaido-hakodate", region: "北海道", prefecture: "北海道", city: "函館", latitude: 41.7687, longitude: 140.7288),
        LocationPreset(id: "hokkaido-asahikawa", region: "北海道", prefecture: "北海道", city: "旭川", latitude: 43.7706, longitude: 142.3650),
        LocationPreset(id: "hokkaido-muroran", region: "北海道", prefecture: "北海道", city: "室蘭", latitude: 42.3152, longitude: 140.9738),
        LocationPreset(id: "hokkaido-obihiro", region: "北海道", prefecture: "北海道", city: "帯広", latitude: 42.9234, longitude: 143.1962),
        LocationPreset(id: "hokkaido-kushiro", region: "北海道", prefecture: "北海道", city: "釧路", latitude: 42.9849, longitude: 144.3820),
        LocationPreset(id: "hokkaido-kitami", region: "北海道", prefecture: "北海道", city: "北見", latitude: 43.8030, longitude: 143.8945),
        LocationPreset(id: "hokkaido-abashiri", region: "北海道", prefecture: "北海道", city: "網走", latitude: 44.0206, longitude: 144.2733),
        LocationPreset(id: "hokkaido-wakkanai", region: "北海道", prefecture: "北海道", city: "稚内", latitude: 45.4157, longitude: 141.6731),
        LocationPreset(id: "hokkaido-nemuro", region: "北海道", prefecture: "北海道", city: "根室", latitude: 43.3301, longitude: 145.5828),
        // 東北
        LocationPreset(id: "aomori", region: "東北", prefecture: "青森県", city: "青森", latitude: 40.8246, longitude: 140.7405),
        LocationPreset(id: "iwate", region: "東北", prefecture: "岩手県", city: "盛岡", latitude: 39.7035, longitude: 141.1527),
        LocationPreset(id: "miyagi", region: "東北", prefecture: "宮城県", city: "仙台", latitude: 38.2686, longitude: 140.8721),
        LocationPreset(id: "akita", region: "東北", prefecture: "秋田県", city: "秋田", latitude: 39.7186, longitude: 140.1024),
        LocationPreset(id: "yamagata", region: "東北", prefecture: "山形県", city: "山形", latitude: 38.2404, longitude: 140.3637),
        LocationPreset(id: "fukushima", region: "東北", prefecture: "福島県", city: "福島", latitude: 37.7500, longitude: 140.4678),
        // 関東
        LocationPreset(id: "ibaraki", region: "関東", prefecture: "茨城県", city: "水戸", latitude: 36.3417, longitude: 140.4468),
        LocationPreset(id: "tochigi", region: "関東", prefecture: "栃木県", city: "宇都宮", latitude: 36.5659, longitude: 139.8836),
        LocationPreset(id: "gunma", region: "関東", prefecture: "群馬県", city: "前橋", latitude: 36.3907, longitude: 139.0605),
        LocationPreset(id: "saitama", region: "関東", prefecture: "埼玉県", city: "さいたま", latitude: 35.8570, longitude: 139.6490),
        LocationPreset(id: "chiba", region: "関東", prefecture: "千葉県", city: "千葉", latitude: 35.6046, longitude: 140.1232),
        LocationPreset(id: "tokyo", region: "関東", prefecture: "東京都", city: "新宿", latitude: 35.6895, longitude: 139.6917),
        LocationPreset(id: "kanagawa", region: "関東", prefecture: "神奈川県", city: "横浜", latitude: 35.4477, longitude: 139.6425),
        // 中部
        LocationPreset(id: "niigata", region: "中部", prefecture: "新潟県", city: "新潟", latitude: 37.9025, longitude: 139.0232),
        LocationPreset(id: "toyama", region: "中部", prefecture: "富山県", city: "富山", latitude: 36.6953, longitude: 137.2113),
        LocationPreset(id: "ishikawa", region: "中部", prefecture: "石川県", city: "金沢", latitude: 36.5946, longitude: 136.6257),
        LocationPreset(id: "fukui", region: "中部", prefecture: "福井県", city: "福井", latitude: 36.0652, longitude: 136.2217),
        LocationPreset(id: "yamanashi", region: "中部", prefecture: "山梨県", city: "甲府", latitude: 35.6641, longitude: 138.5685),
        LocationPreset(id: "nagano", region: "中部", prefecture: "長野県", city: "長野", latitude: 36.6513, longitude: 138.1809),
        LocationPreset(id: "gifu", region: "中部", prefecture: "岐阜県", city: "岐阜", latitude: 35.3912, longitude: 136.7237),
        LocationPreset(id: "shizuoka", region: "中部", prefecture: "静岡県", city: "静岡", latitude: 34.9769, longitude: 138.3831),
        LocationPreset(id: "aichi", region: "中部", prefecture: "愛知県", city: "名古屋", latitude: 35.1802, longitude: 136.9066),
        // 近畿
        LocationPreset(id: "mie", region: "近畿", prefecture: "三重県", city: "津", latitude: 34.7303, longitude: 136.5086),
        LocationPreset(id: "shiga", region: "近畿", prefecture: "滋賀県", city: "大津", latitude: 35.0045, longitude: 135.8686),
        LocationPreset(id: "kyoto", region: "近畿", prefecture: "京都府", city: "京都", latitude: 35.0212, longitude: 135.7556),
        LocationPreset(id: "osaka", region: "近畿", prefecture: "大阪府", city: "大阪", latitude: 34.6863, longitude: 135.5200),
        LocationPreset(id: "hyogo", region: "近畿", prefecture: "兵庫県", city: "神戸", latitude: 34.6913, longitude: 135.1831),
        LocationPreset(id: "nara", region: "近畿", prefecture: "奈良県", city: "奈良", latitude: 34.6853, longitude: 135.8329),
        LocationPreset(id: "wakayama", region: "近畿", prefecture: "和歌山県", city: "和歌山", latitude: 34.2261, longitude: 135.1675),
        // 中国
        LocationPreset(id: "tottori", region: "中国", prefecture: "鳥取県", city: "鳥取", latitude: 35.5034, longitude: 134.2383),
        LocationPreset(id: "shimane", region: "中国", prefecture: "島根県", city: "松江", latitude: 35.4723, longitude: 133.0505),
        LocationPreset(id: "okayama", region: "中国", prefecture: "岡山県", city: "岡山", latitude: 34.6617, longitude: 133.9350),
        LocationPreset(id: "hiroshima", region: "中国", prefecture: "広島県", city: "広島", latitude: 34.3966, longitude: 132.4596),
        LocationPreset(id: "yamaguchi", region: "中国", prefecture: "山口県", city: "山口", latitude: 34.1860, longitude: 131.4707),
        // 四国
        LocationPreset(id: "tokushima", region: "四国", prefecture: "徳島県", city: "徳島", latitude: 34.0658, longitude: 134.5593),
        LocationPreset(id: "kagawa", region: "四国", prefecture: "香川県", city: "高松", latitude: 34.3401, longitude: 134.0433),
        LocationPreset(id: "ehime", region: "四国", prefecture: "愛媛県", city: "松山", latitude: 33.8416, longitude: 132.7657),
        LocationPreset(id: "kochi", region: "四国", prefecture: "高知県", city: "高知", latitude: 33.5597, longitude: 133.5311),
        // 九州・沖縄
        LocationPreset(id: "fukuoka", region: "九州・沖縄", prefecture: "福岡県", city: "福岡", latitude: 33.6064, longitude: 130.4180),
        LocationPreset(id: "saga", region: "九州・沖縄", prefecture: "佐賀県", city: "佐賀", latitude: 33.2494, longitude: 130.2988),
        LocationPreset(id: "nagasaki", region: "九州・沖縄", prefecture: "長崎県", city: "長崎", latitude: 32.7500, longitude: 129.8673),
        LocationPreset(id: "kumamoto", region: "九州・沖縄", prefecture: "熊本県", city: "熊本", latitude: 32.7898, longitude: 130.7416),
        LocationPreset(id: "oita", region: "九州・沖縄", prefecture: "大分県", city: "大分", latitude: 33.2381, longitude: 131.6126),
        LocationPreset(id: "miyazaki", region: "九州・沖縄", prefecture: "宮崎県", city: "宮崎", latitude: 31.9110, longitude: 131.4239),
        LocationPreset(id: "kagoshima", region: "九州・沖縄", prefecture: "鹿児島県", city: "鹿児島", latitude: 31.5602, longitude: 130.5580),
        LocationPreset(id: "okinawa", region: "九州・沖縄", prefecture: "沖縄県", city: "那覇", latitude: 26.2124, longitude: 127.6809)
    ]
}
