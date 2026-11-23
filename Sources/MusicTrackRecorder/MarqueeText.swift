import SwiftUI
import AppKit

struct MarqueeText: View {
    let text: String
    let font: Font
    let fontSize: CGFloat
    let weight: NSFont.Weight
    let color: Color
    let height: CGFloat
    var isActive: Bool = true

    @State private var startedAt = Date()
    private static let gap: CGFloat = 28
    private static let speed: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let textWidth = measure(text)
            let overflows = Self.overflows(textWidth: textWidth, containerWidth: proxy.size.width)

            if overflows && isActive {
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                    textContent(
                        textWidth: textWidth,
                        containerWidth: proxy.size.width,
                        elapsed: timeline.date.timeIntervalSince(startedAt)
                    )
                }
                .onChange(of: proxy.size.width) { _ in
                    startedAt = Date()
                }
            } else {
                textContent(textWidth: textWidth, containerWidth: proxy.size.width, elapsed: 0)
                    .onChange(of: proxy.size.width) { _ in
                        startedAt = Date()
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: height)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onChange(of: text) { _ in
            startedAt = Date()
        }
        .onChange(of: isActive) { active in
            if active { startedAt = Date() }
        }
    }

    private func textContent(
        textWidth: CGFloat,
        containerWidth: CGFloat,
        elapsed: TimeInterval
    ) -> some View {
        HStack(spacing: Self.gap) {
            Text(text)
            if Self.overflows(textWidth: textWidth, containerWidth: containerWidth) {
                Text(text)
                    .accessibilityHidden(true)
            }
        }
        .font(font)
        .foregroundStyle(color)
        .fixedSize(horizontal: true, vertical: false)
        .offset(x: Self.offset(
            textWidth: textWidth,
            containerWidth: containerWidth,
            elapsed: elapsed
        ))
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
