import SwiftUI

struct EditorStatusBar: View {
    let line: Int
    let column: Int

    var body: some View {
        HStack {
            Spacer()
            Text("Line: \(line)  Col: \(column)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(.bar)
    }
}
