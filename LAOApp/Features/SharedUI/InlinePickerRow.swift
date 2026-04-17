import LAODomain
import SwiftUI

struct InlinePickerRow<T: Hashable>: View {
    @Environment(\.theme) private var theme

    let label: String
    @Binding var selection: T
    let options: [T]
    let optionTitle: (T) -> String
    let optionTone: ((T) -> StatusTone)?
    let isSaving: Bool

    init(
        _ label: String,
        selection: Binding<T>,
        options: [T],
        isSaving: Bool = false,
        optionTone: ((T) -> StatusTone)? = nil,
        optionTitle: @escaping (T) -> String
    ) {
        self.label = label
        self._selection = selection
        self.options = options
        self.isSaving = isSaving
        self.optionTone = optionTone
        self.optionTitle = optionTitle
    }

    var body: some View {
        HStack {
            Text(label)
                .font(AppTheme.Typography.label)
                .foregroundStyle(theme.foregroundTertiary)
                .frame(width: 80, alignment: .leading)

            if isSaving {
                ProgressView()
                    .controlSize(.small)
            } else if let optionTone {
                Menu {
                    ForEach(options, id: \.self) { option in
                        Button {
                            selection = option
                        } label: {
                            if option == selection {
                                Label(optionTitle(option), systemImage: "checkmark")
                            } else {
                                Text(optionTitle(option))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(toneColor(optionTone(selection)))
                            .frame(width: 8, height: 8)
                        Text(optionTitle(selection))
                            .font(AppTheme.Typography.label)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            } else {
                Picker(label, selection: $selection) {
                    ForEach(options, id: \.self) { option in
                        Text(optionTitle(option))
                            .tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .buttonStyle(.borderless)
            }
        }
    }

    private func toneColor(_ tone: StatusTone) -> Color {
        switch tone {
        case .neutral: theme.foregroundSecondary
        case .blue: theme.accentPrimary
        case .green: theme.positiveAccent
        case .amber: theme.warningAccent
        case .red: theme.criticalAccent
        case .purple: Color.purple
        }
    }
}
