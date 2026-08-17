import SwiftUI

struct ChatView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatStore.self) private var chat
    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        @Bindable var chat = chat
        VStack(spacing: 0) {
            if !settings.hasAnthropicCredentials {
                MissingCredentialsBanner(message: "Add your Anthropic API key to chat.")
                    .padding([.horizontal, .top])
            }

            Toggle("Include my portfolio as context", isOn: $chat.includePortfolioContext)
                .font(.caption)
                .padding(.horizontal)
                .padding(.top, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty {
                            Text("Ask about a stock, sector, or your portfolio. This is research and discussion only — it never places trades.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                        ForEach(chat.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                        if chat.isSending {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Thinking...").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal)
                        }
                        if let error = chat.lastError {
                            Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }
                .onChange(of: chat.messages) { _, messages in
                    guard let last = messages.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                Button {
                    let text = draft
                    draft = ""
                    Task { await chat.send(text) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || chat.isSending)
            }
            .padding()
        }
    }
}

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .padding(12)
                .background(message.role == .user ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .textSelection(.enabled)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }
}
