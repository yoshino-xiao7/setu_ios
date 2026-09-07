import SwiftUI

struct MusicCacheSettingsView: View {
    @Bindable var settings: MusicCacheSettings
    @State private var confirmingClear = false
    var body: some View {
        Form {
            Section("存储空间") {
                LabeledContent("已使用", value: ByteCountFormatter.string(fromByteCount: settings.usedBytes, countStyle: .binary))
                Picker("缓存上限", selection: $settings.capacityMB) {
                    ForEach(MusicCacheSettings.capacities, id: \.self) { value in
                        Text(value < 1024 ? "\(value)MB" : "\(value / 1024)GB").tag(value)
                    }
                }.accessibilityIdentifier("music.cache.capacity")
                Text("自动清理较久未使用的音频，最多保留 2GB。缓存用于加快播放，不等同于永久下载。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("预缓存") {
                Picker("使用网络", selection: $settings.policy) {
                    ForEach(MusicCacheSettings.PrefetchPolicy.allCases) { Text($0.title).tag($0) }
                }.accessibilityIdentifier("music.cache.network")
                Text("提前准备下一首歌曲。关闭预缓存后，仍会保留实际播放读取的数据；低数据模式下暂停预缓存。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("清空本机音乐缓存", role: .destructive) { confirmingClear = true }
                    .accessibilityIdentifier("music.cache.clear")
                if settings.pendingRemoval { Text("正在播放的缓存将在释放后清理，不影响当前播放。").font(.footnote) }
                if settings.writesDisabled { Text("缓存空间暂不可用，当前播放会继续。可清理缓存或提高上限。").font(.footnote) }
            }
        }
        .navigationTitle("音乐缓存")
        .tint(SetuColor.brandPink)
        .confirmationDialog("清空本机音乐缓存？", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清空缓存", role: .destructive) { Task { await settings.clear() } }
        } message: { Text("不删除歌单、收藏或播放进度。正在使用的数据会延迟清理。") }
        .task { while !Task.isCancelled { await settings.refresh(); try? await Task.sleep(for: .seconds(2)) } }
    }
}
