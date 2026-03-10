import Foundation
import Network

/// WebSocket client for iTerm2's Python API.
/// Connects via Unix domain socket with manual WebSocket handshake.
/// No Apple Events / TCC required.
final class ITerm2APIClient {
    private var connection: NWConnection?
    private var isConnected = false
    private let queue = DispatchQueue(label: "com.sessionhub.iterm2api")

    /// Pending response handlers keyed by message ID
    private var pending: [Int64: (Result<(Int, Data), Error>) -> Void] = [:]
    private let pendingLock = NSLock()

    // MARK: - Connection

    /// Connect to iTerm2 API via Unix socket with manual WebSocket upgrade
    func connect(completion: @escaping (Bool) -> Void) {
        let socketPath = NSHomeDirectory() + "/Library/Application Support/iTerm2/private/socket"

        guard FileManager.default.fileExists(atPath: socketPath) else {
            SHLog.log("[API] Socket not found at \(socketPath)")
            completion(false)
            return
        }

        SHLog.log("[API] Connecting to Unix socket: \(socketPath)")

        // Raw TCP params (no WebSocket protocol layer — we'll do handshake manually)
        let params = NWParameters(tls: nil)
        let tcp = NWProtocolTCP.Options()
        params.defaultProtocolStack.transportProtocol = tcp

        let conn = NWConnection(to: .unix(path: socketPath), using: params)
        self.connection = conn
        var completed = false

        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                SHLog.log("[API] Raw socket connected, performing WebSocket upgrade...")
                self.performWebSocketHandshake { success in
                    if success {
                        SHLog.log("[API] WebSocket handshake complete")
                        self.isConnected = true
                        if !completed {
                            completed = true
                            completion(true)
                        }
                        self.receiveLoop()
                    } else {
                        SHLog.log("[API] WebSocket handshake failed")
                        if !completed {
                            completed = true
                            completion(false)
                        }
                    }
                }
            case .failed(let error):
                SHLog.log("[API] Connection failed: \(error)")
                if !completed { completed = true; completion(false) }
            case .waiting(let error):
                SHLog.log("[API] Waiting: \(error)")
                if !completed { completed = true; completion(false) }
            case .cancelled:
                SHLog.log("[API] Connection cancelled")
                self.isConnected = false
            default:
                break
            }
        }

        conn.start(queue: queue)

        queue.asyncAfter(deadline: .now() + 5.0) {
            if !completed {
                completed = true
                SHLog.log("[API] Connection timeout")
                conn.cancel()
                completion(false)
            }
        }
    }

    // MARK: - WebSocket Handshake (manual)

    private func performWebSocketHandshake(completion: @escaping (Bool) -> Void) {
        guard let connection else { completion(false); return }

        // Generate random key for Sec-WebSocket-Key
        var keyBytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, 16, &keyBytes)
        let wsKey = Data(keyBytes).base64EncodedString()

        let request = [
            "GET / HTTP/1.1",
            "Host: localhost",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(wsKey)",
            "Sec-WebSocket-Version: 13",
            "Sec-WebSocket-Protocol: api.iterm2.com",
            "Origin: ws://localhost/",
            "x-iterm2-library-version: swift 1.0",
            "x-iterm2-advisory-name: SessionHub",
            "",
            ""
        ].joined(separator: "\r\n")

        connection.send(content: request.data(using: .utf8), completion: .contentProcessed { error in
            if let error {
                SHLog.log("[API] Handshake send error: \(error)")
                completion(false)
                return
            }
        })

        // Read the full HTTP 101 response (until \r\n\r\n)
        self.readHTTPResponse(from: connection, buffer: Data()) { response in
            if let response, response.contains("101") {
                SHLog.log("[API] Got 101 Switching Protocols")
                completion(true)
            } else {
                SHLog.log("[API] Unexpected handshake response: \(response?.prefix(200) ?? "nil")")
                completion(false)
            }
        }
    }

    /// Read HTTP response incrementally until we see \r\n\r\n
    private func readHTTPResponse(from conn: NWConnection, buffer: Data, completion: @escaping (String?) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
            if let error {
                SHLog.log("[API] Handshake receive error: \(error)")
                completion(nil)
                return
            }
            guard let data else {
                completion(nil)
                return
            }
            var accumulated = buffer
            accumulated.append(data)

            // Check if we have the full HTTP response (ends with \r\n\r\n)
            if let str = String(data: accumulated, encoding: .utf8), str.contains("\r\n\r\n") {
                completion(str)
            } else if accumulated.count > 8192 {
                // Safety: don't read forever
                completion(String(data: accumulated, encoding: .utf8))
            } else {
                // Need more data
                self.readHTTPResponse(from: conn, buffer: accumulated, completion: completion)
            }
        }
    }

    // MARK: - WebSocket Framing (manual)

    /// Create a WebSocket binary frame (client must mask data)
    private func createWebSocketFrame(_ payload: Data) -> Data {
        var frame = Data()

        // FIN + opcode 0x2 (binary)
        frame.append(0x82)

        // Mask bit set (client frames must be masked) + payload length
        let len = payload.count
        if len < 126 {
            frame.append(UInt8(len) | 0x80)
        } else if len < 65536 {
            frame.append(126 | 0x80)
            frame.append(UInt8((len >> 8) & 0xFF))
            frame.append(UInt8(len & 0xFF))
        } else {
            frame.append(127 | 0x80)
            for i in (0..<8).reversed() {
                frame.append(UInt8((len >> (i * 8)) & 0xFF))
            }
        }

        // Masking key (4 random bytes)
        var maskKey = [UInt8](repeating: 0, count: 4)
        _ = SecRandomCopyBytes(kSecRandomDefault, 4, &maskKey)
        frame.append(contentsOf: maskKey)

        // Masked payload
        for (i, byte) in payload.enumerated() {
            frame.append(byte ^ maskKey[i % 4])
        }

        return frame
    }

    /// Parse a WebSocket frame, return the payload data
    private func parseWebSocketFrame(_ data: Data) -> (payload: Data, consumed: Int)? {
        guard data.count >= 2 else { return nil }

        let byte0 = data[0]
        let byte1 = data[1]
        let masked = (byte1 & 0x80) != 0
        var payloadLen = Int(byte1 & 0x7F)
        var offset = 2

        if payloadLen == 126 {
            guard data.count >= 4 else { return nil }
            payloadLen = Int(data[2]) << 8 | Int(data[3])
            offset = 4
        } else if payloadLen == 127 {
            guard data.count >= 10 else { return nil }
            payloadLen = 0
            for i in 0..<8 {
                payloadLen = payloadLen << 8 | Int(data[2 + i])
            }
            offset = 10
        }

        if masked { offset += 4 } // skip mask key (server frames usually not masked)

        guard data.count >= offset + payloadLen else { return nil }

        let payload = data[offset..<(offset + payloadLen)]
        let _ = byte0 // opcode in lower 4 bits, we accept any

        return (Data(payload), offset + payloadLen)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        pendingLock.lock()
        let handlers = pending
        pending.removeAll()
        pendingLock.unlock()
        for (_, handler) in handlers {
            handler(.failure(ITerm2APIError.notConnected))
        }
    }

    var connected: Bool { isConnected }

    // MARK: - Send / Receive

    private func send(_ messageData: Data, id: Int64, completion: @escaping (Result<(Int, Data), Error>) -> Void) {
        guard let connection, isConnected else {
            completion(.failure(ITerm2APIError.notConnected))
            return
        }

        pendingLock.lock()
        pending[id] = completion
        pendingLock.unlock()

        let frame = createWebSocketFrame(messageData)

        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            if let error {
                SHLog.log("[API] Send error: \(error)")
                self?.pendingLock.lock()
                let handler = self?.pending.removeValue(forKey: id)
                self?.pendingLock.unlock()
                handler?(.failure(error))
            }
        })

        // Timeout per request
        queue.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.pendingLock.lock()
            let handler = self?.pending.removeValue(forKey: id)
            self?.pendingLock.unlock()
            handler?(.failure(ITerm2APIError.timeout))
        }
    }

    private var receiveBuffer = Data()

    private func receiveLoop() {
        guard let connection, isConnected else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, _, error in
            guard let self else { return }

            if let error {
                SHLog.log("[API] Receive error: \(error)")
                return
            }

            if let data = content {
                self.receiveBuffer.append(data)

                // Try to parse complete frames from the buffer
                while let frame = self.parseWebSocketFrame(self.receiveBuffer) {
                    self.receiveBuffer = Data(self.receiveBuffer.dropFirst(frame.consumed))
                    if !frame.payload.isEmpty {
                        self.handleResponse(frame.payload)
                    }
                }
            }

            if self.isConnected {
                self.receiveLoop()
            }
        }
    }

    private func handleResponse(_ data: Data) {
        do {
            let (id, fieldNumber, payload) = try ITerm2Messages.parseResponse(data)
            pendingLock.lock()
            let handler = pending.removeValue(forKey: id)
            pendingLock.unlock()
            handler?(.success((fieldNumber, payload)))
        } catch {
            SHLog.log("[API] Failed to parse response: \(error)")
        }
    }

    // MARK: - Synchronous API (for bridge compatibility)

    private func sendSync(_ messageData: Data, id: Int64) -> Result<(Int, Data), Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<(Int, Data), Error> = .failure(ITerm2APIError.timeout)

        send(messageData, id: id) { r in
            result = r
            semaphore.signal()
        }

        semaphore.wait()
        return result
    }

    // MARK: - High-Level API

    func listSessions() -> [ITerm2Messages.ParsedWindow] {
        let (id, data) = ITerm2Messages.listSessions()
        switch sendSync(data, id: id) {
        case .success(let (fieldNumber, payload)):
            guard fieldNumber == 106 else {
                SHLog.log("[API] Unexpected response field \(fieldNumber) for listSessions")
                return []
            }
            do {
                return try ITerm2Messages.parseListSessions(payload)
            } catch {
                SHLog.log("[API] Failed to parse ListSessionsResponse: \(error)")
                return []
            }
        case .failure(let error):
            SHLog.log("[API] listSessions failed: \(error)")
            return []
        }
    }

    func getProfileName(sessionId: String) -> String? {
        let (id, data) = ITerm2Messages.getProfileProperty(sessionId: sessionId, keys: ["Name"])
        switch sendSync(data, id: id) {
        case .success(let (fieldNumber, payload)):
            guard fieldNumber == 110 else { return nil }
            if let props = try? ITerm2Messages.parseGetProfileProperty(payload),
               let nameProp = props.first(where: { $0.key == "Name" }) {
                if let jsonData = nameProp.jsonValue.data(using: .utf8),
                   let name = try? JSONSerialization.jsonObject(with: jsonData) as? String {
                    return name
                }
                return nameProp.jsonValue
            }
            return nil
        case .failure:
            return nil
        }
    }

    func activate(sessionId: String) -> Bool {
        let (id, data) = ITerm2Messages.activate(sessionId: sessionId)
        switch sendSync(data, id: id) {
        case .success(let (fieldNumber, _)):
            return fieldNumber == 114
        case .failure(let error):
            SHLog.log("[API] activate failed: \(error)")
            return false
        }
    }

    func createTab(profileName: String, windowId: String? = nil) -> ITerm2Messages.CreateTabResult? {
        let (id, data) = ITerm2Messages.createTab(profileName: profileName, windowId: windowId)
        switch sendSync(data, id: id) {
        case .success(let (fieldNumber, payload)):
            guard fieldNumber == 108 else { return nil }
            return try? ITerm2Messages.parseCreateTab(payload)
        case .failure:
            return nil
        }
    }

    func renameSession(sessionId: String, name: String) -> Bool {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: name),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return false
        }
        let (id, data) = ITerm2Messages.setProfileProperty(sessionId: sessionId, key: "Name", jsonValue: jsonString)
        switch sendSync(data, id: id) {
        case .success(let (fieldNumber, _)):
            return fieldNumber == 105
        case .failure:
            return false
        }
    }
}
