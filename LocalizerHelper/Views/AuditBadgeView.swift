import SwiftUI

struct AuditBadgeView: View {
    let severity: AuditSeverity

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var label: String {
        switch severity {
        case .error: return "Error"
        case .warning: return "Warning"
        case .ignored: return "Ignored"
        case .ok: return "OK"
        }
    }

    private var color: Color {
        switch severity {
        case .error: return .red
        case .warning: return .orange
        case .ignored: return .secondary
        case .ok: return .green
        }
    }
}

#Preview {
    HStack {
        AuditBadgeView(severity: .error)
        AuditBadgeView(severity: .warning)
        AuditBadgeView(severity: .ok)
    }
    .padding()
}
