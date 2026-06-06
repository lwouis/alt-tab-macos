import SwiftUI

/// 分段选项定义
struct SegmentOption<T>: Identifiable {
    let id = UUID()
    let value: T
    let icon: String
    let title: String
    let width: CGFloat
}

/// 自定义分段选择器，支持自定义每个分段的宽度和显示图标
@available(macOS 13.0, *)
struct SegmentedPicker<T: Hashable>: View {
    let options: [SegmentOption<T>]
    @Binding var selection: T
    let proSegmentIndex: Int?
    var onProLockedTap: (() -> Void)?

    @EnvironmentObject var proState: ProStateTracker

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) {
                index,
                option in
                let isProGated =
                    proSegmentIndex == index && proState.isProLocked
                SegmentButton(
                    option: option,
                    isSelected: selection == option.value,
                    isLast: index == options.count - 1,
                    isPro: proSegmentIndex == index && proState.isProLocked
                )
                .onTapGesture {
                    if isProGated {
                        onProLockedTap?()
                        return
                    }
                    selection = option.value
                }
            }
        }
        .frame(height: 25)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.5), lineWidth: 0.5)
        )
    }
}

/// 单个分段按钮
@available(macOS 13.0, *)
struct SegmentButton<T: Hashable>: View {
    let option: SegmentOption<T>
    let isSelected: Bool
    let isLast: Bool
    let isPro: Bool

    var body: some View {
        Text("\(option.icon) \(option.title)")
            .foregroundColor(isSelected ? .white : .primary)
            .frame(width: option.width, height: 24)
            .contentShape(Rectangle())
            .overlay(alignment: .trailing) {
                if isPro {
                    ProBadgeLabel()
                        .padding(.trailing, 4)
                }
            }
            .background(
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor)
                    }
                    if !isLast {
                        VStack {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 1)
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            )
    }
}
