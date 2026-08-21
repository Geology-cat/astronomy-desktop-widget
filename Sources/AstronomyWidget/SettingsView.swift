import ServiceManagement
import SwiftUI

@MainActor
struct SettingsView: View {
    @State private var useCurrentLocation = true
    @State private var locationName = "東京"
    @State private var latitude = 35.6812
    @State private var longitude = 139.7671
    @State private var widgetTextSize = WidgetTextSize.standard
    @State private var launchAtLogin = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("天文情報ウィジェット")
                    .font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("観測地点と起動方法を設定します。")
                    Text("時刻はMacの現在のタイムゾーンで表示されます。")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }

            GroupBox("観測地点") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("現在地を使用", isOn: $useCurrentLocation)
                    Divider()
                    Text("位置情報を利用できない場合にも、以下の指定地点を使用します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LabeledContent("地点名") {
                        TextField("東京", text: $locationName).frame(width: 190)
                    }
                    LabeledContent("緯度") {
                        TextField("35.6812", value: $latitude, format: .number.precision(.fractionLength(4)))
                            .frame(width: 110)
                    }
                    LabeledContent("経度") {
                        TextField("139.7671", value: $longitude, format: .number.precision(.fractionLength(4)))
                            .frame(width: 110)
                    }
                    Text("緯度は −90〜90°、経度は −180〜180°（東経が正）")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(8)
            }

            GroupBox("表示") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("文字サイズ") {
                        Picker("文字サイズ", selection: $widgetTextSize) {
                            ForEach(WidgetTextSize.allCases) { size in
                                Text(size.title).tag(size)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 230)
                    }
                    HStack {
                        Text("表示例")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("南中  12:34（45.6°）")
                            .font(.system(size: 12 * widgetTextSize.scale, weight: .medium))
                            .monospacedDigit()
                    }
                }
                .padding(8)
            }

            Toggle("ログイン時に自動起動", isOn: $launchAtLogin)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("キャンセル") { closeWindow() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 450)
        .onAppear(perform: load)
    }

    private func load() {
        let preferences = AppPreferences.shared
        useCurrentLocation = preferences.useCurrentLocation
        locationName = preferences.locationName
        latitude = preferences.latitude
        longitude = preferences.longitude
        widgetTextSize = preferences.widgetTextSize
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func save() {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            message = "緯度または経度が範囲外です。"
            return
        }
        do {
            if launchAtLogin, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !launchAtLogin, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            AppPreferences.shared.save(
                useCurrentLocation: useCurrentLocation,
                locationName: locationName,
                latitude: latitude,
                longitude: longitude,
                widgetTextSize: widgetTextSize
            )
            closeWindow()
        } catch {
            message = "自動起動の設定を変更できませんでした：\(error.localizedDescription)"
        }
    }

    private func closeWindow() {
        NSApp.keyWindow?.close()
    }
}
