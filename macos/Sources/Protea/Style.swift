import AppKit
import SwiftUI

extension Color {
    static let ink = Color(nsColor: Palette.ink)
    static let sidebarBG = Color(nsColor: Palette.sidebar)
    static let paneBG = Color(nsColor: Palette.pane)
    static let raised = Color(nsColor: Palette.raised)
    static let line = Color(nsColor: Palette.line)
    static let lineStrong = Color(nsColor: Palette.lineStrong)
    static let marble = Color(nsColor: Palette.marble)
    static let marble2 = Color(nsColor: Palette.marble2)
    static let marble3 = Color(nsColor: Palette.marble3)
    static let azure = Color(nsColor: Palette.azure)
    static let azureDeep = Color(nsColor: Palette.azureDeep)
    static let sky = Color(nsColor: Palette.sky)
    static let coral = Color(nsColor: Palette.coral)
    static let sea = Color(nsColor: Palette.sea)
}

// MARK: - Shared SwiftUI pieces

struct AgentBadge: View {
    let agent: Agent
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Color(nsColor: agent.tint).opacity(0.16))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .strokeBorder(Color(nsColor: agent.tint).opacity(0.28), lineWidth: 0.5)
            )
            .overlay(
                Image(systemName: agent.symbol)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(Color(nsColor: agent.tint))
            )
            .frame(width: size, height: size)
    }
}

struct StateDot: View {
    let state: SessionState
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(state.color)
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .stroke(state.color, lineWidth: 1)
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 0.7)
                    .opacity(state.pulses ? 1 : 0)
            )
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
            }
    }
}

extension View {
    /// A rounded glass panel (Liquid Glass on macOS 26).
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = 22) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(Color.ink.opacity(0.45)), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        }
    }

    /// Liquid Glass on macOS 26, a quiet material everywhere else.
    @ViewBuilder
    func glassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(Color.ink.opacity(0.35)), in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
        }
    }
}
