//
//  OAuthCallbackServer.swift
//  Doris
//
//  Created by Adam Bell on 12/31/25.
//

import Foundation
import Network

actor OAuthCallbackServer {
    private let port: UInt16
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?
    
    init(port: UInt16) {
        self.port = port
    }
    
    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("📧 OAuth: Server listening on port \(self.port)")
            case .failed(let error):
                print("🔴 OAuth: Server failed: \(error)")
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }
        
        listener?.start(queue: .main)
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        print("📧 OAuth: Server stopped")
    }
    
    func waitForCode(timeout: TimeInterval) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            // Set up timeout
            Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                if self.continuation != nil {
                    self.continuation?.resume(throwing: OAuthError.timeout)
                    self.continuation = nil
                }
            }
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, error in
            guard let self = self else { return }
            
            if let error = error {
                print("🔴 OAuth: Connection error: \(error)")
                return
            }
            
            guard let data = data, let request = String(data: data, encoding: .utf8) else {
                return
            }
            
            // Parse the authorization code from the request
            if let code = self.parseAuthCode(from: request) {
                // Send success response
                let response = """
                    HTTP/1.1 200 OK\r
                    Content-Type: text/html\r
                    Connection: close\r
                    \r
                    <!DOCTYPE html>
                    <html>
                    <head><title>Doris - Gmail Connected</title></head>
                    <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 50px;">
                        <h1>✅ Gmail Connected!</h1>
                        <p>You can close this window and return to Doris.</p>
                    </body>
                    </html>
                    """
                
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
                
                Task {
                    await self.completeWithCode(code)
                }
            } else {
                // Send error response
                let response = """
                    HTTP/1.1 400 Bad Request\r
                    Content-Type: text/html\r
                    Connection: close\r
                    \r
                    <!DOCTYPE html>
                    <html>
                    <head><title>Doris - Error</title></head>
                    <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 50px;">
                        <h1>❌ Authentication Failed</h1>
                        <p>Could not complete Gmail authentication. Please try again.</p>
                    </body>
                    </html>
                    """
                
                connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }
    
    private nonisolated func parseAuthCode(from request: String) -> String? {
        // Parse "GET /oauth/callback?code=XXXX&scope=... HTTP/1.1"
        guard let urlLine = request.split(separator: "\r\n").first,
              let urlPart = urlLine.split(separator: " ").dropFirst().first else {
            return nil
        }
        
        let urlString = "http://localhost\(urlPart)"
        guard let components = URLComponents(string: urlString),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            return nil
        }
        
        return code
    }
    
    private func completeWithCode(_ code: String) {
        continuation?.resume(returning: code)
        continuation = nil
    }
}

enum OAuthError: LocalizedError {
    case timeout
    case noCode
    
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Authentication timed out. Please try again."
        case .noCode:
            return "No authorization code received."
        }
    }
}
