//
//  AIChatViewModel+Persistence.swift
//  TablePro
//

import Foundation

extension AIChatViewModel {
    /// Lists what this session may switch to, and adopts none of it.
    ///
    /// This used to load every conversation in the app and adopt the most recent one whenever
    /// `messages` was empty, so every session created after the first inherited another
    /// connection's transcript and then persisted over it under the same id.
    func loadConversations() {
        let storage = chatStorage
        let scope = connection?.id
        Task.detached(priority: .utility) { [weak self] in
            let loaded = await storage.loadAll(connectionId: scope)
            await MainActor.run {
                self?.conversations = loaded
            }
        }
    }

    /// Clears this session only. It used to call `deleteAll`, which erased every conversation in
    /// the app from a control that names one.
    func clearConversation() {
        cancelStream()
        resetProviderConversation()
        if let activeConversationID {
            let id = activeConversationID
            Task { await chatStorage.delete(id) }
            conversations.removeAll { $0.id == id }
        }
        messages.removeAll()
        activeConversationID = nil
        clearError()
    }

    func deleteConversation(_ id: UUID) {
        if activeConversationID == id {
            resetProviderConversation()
        }
        Task { await chatStorage.delete(id) }
        conversations.removeAll { $0.id == id }
        if activeConversationID == id {
            activeConversationID = nil
            messages.removeAll()
        }
    }

    func persistCurrentConversation() {
        guard !messages.isEmpty else { return }
        let wireMessages = messages.map { $0.wireSnapshot }

        if let existingID = activeConversationID,
           var conversation = conversations.first(where: { $0.id == existingID }) {
            conversation.messages = wireMessages
            conversation.updatedAt = Date()
            conversation.updateTitle()
            conversation.connectionId = connection?.id ?? conversation.connectionId
            conversation.connectionName = connection?.name
            Task { await chatStorage.save(conversation) }

            if let index = conversations.firstIndex(where: { $0.id == existingID }) {
                conversations[index] = conversation
            }
        } else {
            var conversation = AIConversation(
                messages: wireMessages,
                connectionId: connection?.id,
                connectionName: connection?.name
            )
            conversation.updateTitle()
            Task { await chatStorage.save(conversation) }
            activeConversationID = conversation.id
            conversations.insert(conversation, at: 0)
        }
    }
}
