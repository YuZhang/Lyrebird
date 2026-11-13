import SwiftUI
import AppKit

struct MarqueeText: View {
    let text: String
    let font: Font
    let fontSize: CGFloat
    let weight: NSFont.Weight
    let color: Color
    let height: CGFloat

    @State private var startedAt = Date()
    private static let gap: CGFloat = 28
    private static let speed: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let textWidth = measure(text)
                let overflows = Self.overflows(textWidth: textWidth, containerWidth: proxy.size.width)

                HStack(spacing: Self.gap) {
                    Text(text)
                    if overflows {
                        Text(text)
                            .accessibilityHidden(true)
                    }
                }
                .font(font)
                .foregroundStyle(color)
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: Self.offset(
                    textWidth: textWidth,
                    containerWidth: proxy.size.width,
                    elapsed: timeline.date.timeIntervalSince(startedAt)
                ))
            }
            .onChange(of: text) { _ in
                startedAt = Date()
            }
            .onChange(of: proxy.size.width) { _ in
                startedAt = Date()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    static func overflows(textWidth: CGFloat, containerWidth: CGFloat) -> Bool {
        containerWidth > 0 && textWidth > containerWidth
    }

    static func offset(
        textWidth: CGFloat,
        containerWidth: CGFloat,
        elapsed: TimeInterval
    ) -> CGFloat {
        guard overflows(textWidth: textWidth, containerWidth: containerWidth) else { return 0 }
        let distance = textWidth + gap
        let movingTime = max(0, elapsed - 1)
        return -(movingTime * speed).truncatingRemainder(dividingBy: distance)
    }

    private func measure(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
