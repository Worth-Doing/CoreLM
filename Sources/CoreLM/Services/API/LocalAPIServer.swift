import Foundation
import Network

/// Lightweight local HTTP server providing OpenAI-compatible API
@MainActor
class LocalAPIServer: ObservableObject {
    static let shared = LocalAPIServer()

    @Published var isRunning = false
    @Published var port: UInt16 = 8080
    @Published var requestCount = 0

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.coreLM.api", qos: .userInitiated)

    func start() {
        guard !isRunning else { return }

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                    case .failed, .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.handleConnection(connection)
                }
            }
            listener?.start(queue: queue)
        } catch {
            self.isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveData(on: connection)
    }

    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                Task { @MainActor in
                    self.requestCount += 1
                    self.processHTTPRequest(data: data, connection: connection)
                }
            }

            if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    private func processHTTPRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: 400, body: "{\"error\": \"Invalid request\"}")
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: 400, body: "{\"error\": \"Invalid request\"}")
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: 400, body: "{\"error\": \"Invalid request\"}")
            return
        }

        let method = parts[0]
        let path = parts[1]

        // Extract body (after empty line)
        let bodyString: String?
        if let bodyStart = requestString.range(of: "\r\n\r\n") {
            bodyString = String(requestString[bodyStart.upperBound...])
        } else {
            bodyString = nil
        }

        // Route
        Task { @MainActor in
            await self.route(method: method, path: path, body: bodyString, connection: connection)
        }
    }

    private func route(method: String, path: String, body: String?, connection: NWConnection) async {
        // CORS headers included in all responses

        switch (method, path) {
        case ("GET", "/v1/models"):
            await handleListModels(connection: connection)

        case ("POST", "/v1/chat/completions"):
            await handleChatCompletion(body: body, connection: connection)

        case ("GET", "/health"), ("GET", "/"):
            sendResponse(connection: connection, status: 200, body: "{\"status\": \"ok\", \"service\": \"CoreLM\"}")

        default:
            sendResponse(connection: connection, status: 404, body: "{\"error\": \"Not found\"}")
        }
    }

    private func handleListModels(connection: NWConnection) async {
        let ollama = OllamaService.shared
        await ollama.refreshModels()

        let entries = ollama.installedModels.map { model in
            OpenAIModelEntry(
                id: model.name,
                object: "model",
                created: Int(Date().timeIntervalSince1970),
                ownedBy: "local"
            )
        }

        let response = OpenAIModelList(object: "list", data: entries)
        if let data = try? JSONEncoder().encode(response),
           let json = String(data: data, encoding: .utf8) {
            sendResponse(connection: connection, status: 200, body: json)
        } else {
            sendResponse(connection: connection, status: 500, body: "{\"error\": \"Internal error\"}")
        }
    }

    private func handleChatCompletion(body: String?, connection: NWConnection) async {
        guard let bodyData = body?.data(using: .utf8),
              let request = try? JSONDecoder().decode(OpenAIChatRequest.self, from: bodyData) else {
            sendResponse(connection: connection, status: 400, body: "{\"error\": \"Invalid request body\"}")
            return
        }

        let ollamaMessages = request.messages.map {
            OllamaChatMessage(role: $0.role, content: $0.content)
        }

        let options = OllamaOptions(
            temperature: request.temperature,
            topP: nil,
            topK: nil,
            numCtx: nil,
            seed: nil,
            repeatPenalty: nil
        )

        do {
            let result = try await OllamaService.shared.chatSync(
                model: request.model,
                messages: ollamaMessages,
                options: options
            )

            let responseContent = result.message?.content ?? ""
            let openAIResponse = OpenAIChatResponse(
                id: "chatcmpl-\(UUID().uuidString.prefix(8))",
                object: "chat.completion",
                created: Int(Date().timeIntervalSince1970),
                model: request.model,
                choices: [
                    OpenAIChoice(
                        index: 0,
                        message: OpenAIChatMessage(role: "assistant", content: responseContent),
                        delta: nil,
                        finishReason: "stop"
                    )
                ],
                usage: OpenAIUsage(
                    promptTokens: result.promptEvalCount ?? 0,
                    completionTokens: result.evalCount ?? 0,
                    totalTokens: (result.promptEvalCount ?? 0) + (result.evalCount ?? 0)
                )
            )

            if let data = try? JSONEncoder().encode(openAIResponse),
               let json = String(data: data, encoding: .utf8) {
                sendResponse(connection: connection, status: 200, body: json)
            } else {
                sendResponse(connection: connection, status: 500, body: "{\"error\": \"Encoding error\"}")
            }
        } catch {
            sendResponse(connection: connection, status: 500, body: "{\"error\": \"\(error.localizedDescription)\"}")
        }
    }

    private func sendResponse(connection: NWConnection, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Unknown"
        }

        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Allow-Headers: Content-Type, Authorization\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
