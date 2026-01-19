//
//  DorisServer.swift
//  Doris
//
//  Created by Adam Bell on 12/30/25.
//

import Foundation
import Hummingbird
import NIOCore
import NIOFoundationCompat

actor DorisServer {
    private let port: Int

    init(port: Int = 8080) {
        self.port = port
    }

    func start() async throws {
        let router = Router()

        // Health check / status
        router.get("/status") { _, _ -> Response in
            let body = ByteBuffer(string: #"{"status":"ok","service":"doris"}"#)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: body)
            )
        }

        // Main chat endpoint
        router.post("/chat") { request, _ -> Response in
            // Parse request body
            let buffer = try await request.body.collect(upTo: 1024 * 1024)
            guard let json = try? JSONSerialization.jsonObject(with: Data(buffer: buffer)) as? [String: Any],
                  let message = json["message"] as? String else {
                return Response(status: .badRequest)
            }

            let includeAudio = json["include_audio"] as? Bool ?? false

            do {
                let (text, audioData) = try await DorisCore.shared.chat(
                    message: message,
                    includeAudio: includeAudio
                )

                var responseDict: [String: Any] = ["text": text]
                if let audio = audioData {
                    responseDict["audio"] = audio.base64EncodedString()
                }

                let responseData = try JSONSerialization.data(withJSONObject: responseDict)
                let body = ByteBuffer(data: responseData)

                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: body)
                )
            } catch {
                let errorDict = ["error": error.localizedDescription]
                let errorData = try! JSONSerialization.data(withJSONObject: errorDict)
                return Response(
                    status: .internalServerError,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: ByteBuffer(data: errorData))
                )
            }
        }

        // Memory endpoints
        router.get("/memory") { _, _ -> Response in
            let memories = await DorisCore.shared.claudeService.getAllMemories()
            let memoryDicts = memories.map { memory -> [String: Any] in
                return [
                    "id": memory.id,
                    "content": memory.content,
                    "category": memory.category.rawValue,
                    "subject": memory.subject ?? "",
                    "confidence": memory.confidence
                ]
            }
            let responseData = try! JSONSerialization.data(withJSONObject: ["memories": memoryDicts])
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: responseData))
            )
        }

        // Clear conversation history
        router.post("/clear") { _, _ -> Response in
            await DorisCore.shared.clearHistory()
            let body = ByteBuffer(string: #"{"status":"cleared"}"#)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: body)
            )
        }
        
        // Get all conversations (paginated)
        router.get("/conversations") { request, _ -> Response in
            let limit = Int(request.uri.queryParameters.get("limit") ?? "50") ?? 50
            let offset = Int(request.uri.queryParameters.get("offset") ?? "0") ?? 0
            
            let conversations = await DorisCore.shared.claudeService.memory.getConversations(limit: limit, offset: offset)
            
            let dateFormatter = ISO8601DateFormatter()
            let conversationDicts = conversations.map { conv -> [String: Any] in
                return [
                    "id": conv.id,
                    "title": conv.title ?? "",
                    "summary": conv.summary ?? "",
                    "message_count": conv.messageCount,
                    "created_at": dateFormatter.string(from: conv.createdAt),
                    "updated_at": dateFormatter.string(from: conv.updatedAt)
                ]
            }
            
            let responseData = try! JSONSerialization.data(withJSONObject: ["conversations": conversationDicts])
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: responseData))
            )
        }
        
        // Get single conversation with messages
        router.get("/conversations/{id}") { request, context -> Response in
            guard let idString = context.parameters.get("id"),
                  let id = Int(idString) else {
                return Response(status: .badRequest)
            }
            
            guard let conversation = await DorisCore.shared.claudeService.memory.getConversation(id) else {
                return Response(status: .notFound)
            }
            
            let messages = await DorisCore.shared.claudeService.memory.getMessages(conversationId: id)
            
            let dateFormatter = ISO8601DateFormatter()
            let messageDicts = messages.map { msg -> [String: Any] in
                return [
                    "id": msg.id,
                    "role": msg.role,
                    "content": msg.content,
                    "created_at": dateFormatter.string(from: msg.createdAt)
                ]
            }
            
            let responseDict: [String: Any] = [
                "id": conversation.id,
                "title": conversation.title ?? "",
                "summary": conversation.summary ?? "",
                "message_count": conversation.messageCount,
                "created_at": dateFormatter.string(from: conversation.createdAt),
                "updated_at": dateFormatter.string(from: conversation.updatedAt),
                "messages": messageDicts
            ]
            
            let responseData = try! JSONSerialization.data(withJSONObject: responseDict)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: responseData))
            )
        }
        
        // Search conversations
        router.get("/conversations/search") { request, _ -> Response in
            guard let query = request.uri.queryParameters.get("q"), !query.isEmpty else {
                let body = ByteBuffer(string: #"{"error":"Missing search query 'q'"}"#)
                return Response(
                    status: .badRequest,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: body)
                )
            }
            
            let results = await DorisCore.shared.claudeService.memory.searchConversations(query: query)
            
            let dateFormatter = ISO8601DateFormatter()
            let resultDicts = results.map { result -> [String: Any] in
                return [
                    "message_id": result.messageId,
                    "conversation_id": result.conversationId,
                    "conversation_title": result.conversationTitle ?? "",
                    "role": result.role,
                    "content": result.content,
                    "created_at": dateFormatter.string(from: result.createdAt)
                ]
            }
            
            let responseData = try! JSONSerialization.data(withJSONObject: ["results": resultDicts])
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: responseData))
            )
        }
        
        // Delete a conversation
        router.delete("/conversations/{id}") { request, context -> Response in
            guard let idString = context.parameters.get("id"),
                  let id = Int(idString) else {
                return Response(status: .badRequest)
            }
            
            let success = await DorisCore.shared.claudeService.memory.deleteConversation(id)
            
            if success {
                let body = ByteBuffer(string: #"{"status":"deleted"}"#)
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: body)
                )
            } else {
                return Response(status: .notFound)
            }
        }
        
        // Get current conversation ID
        router.get("/conversations/current") { _, _ -> Response in
            let currentId = await DorisCore.shared.claudeService.getCurrentConversationId()
            let responseDict: [String: Any] = ["conversation_id": currentId ?? NSNull()]
            let responseData = try! JSONSerialization.data(withJSONObject: responseDict)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: responseData))
            )
        }
        
        // Gmail authentication status
        router.get("/auth/gmail/status") { _, _ -> Response in
            let isAuthenticated = await DorisCore.shared.gmailService.isAuthenticated
            let responseDict: [String: Any] = ["authenticated": isAuthenticated]
            let responseData = try! JSONSerialization.data(withJSONObject: responseDict)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: ByteBuffer(data: responseData))
            )
        }
        
        // Gmail authenticate - triggers OAuth flow
        router.post("/auth/gmail") { _, _ -> Response in
            do {
                try await DorisCore.shared.gmailService.authenticate()
                let body = ByteBuffer(string: #"{"status":"authenticated"}"#)
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: body)
                )
            } catch {
                let errorDict = ["error": error.localizedDescription]
                let errorData = try! JSONSerialization.data(withJSONObject: errorDict)
                return Response(
                    status: .internalServerError,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: ByteBuffer(data: errorData))
                )
            }
        }
        
        // Gmail logout
        router.post("/auth/gmail/logout") { _, _ -> Response in
            await DorisCore.shared.gmailService.logout()
            let body = ByteBuffer(string: #"{"status":"logged_out"}"#)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: body)
            )
        }

        let app = Application(
            router: router,
            configuration: .init(address: .hostname("0.0.0.0", port: port))
        )

        print("🌐 DorisServer: Starting on port \(port)...")
        try await app.runService()
    }

    func stop() async {
        // Hummingbird handles graceful shutdown
        print("🌐 DorisServer: Stopping...")
    }
}
