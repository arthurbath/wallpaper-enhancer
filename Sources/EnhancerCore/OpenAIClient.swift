import Foundation

public struct HTTPResult: Sendable {
    public let data: Data
    public let status: Int
    public let requestID: String?
    public init(data: Data, status: Int, requestID: String? = nil) { self.data = data; self.status = status; self.requestID = requestID }
}

public protocol ImageTransport: Sendable {
    func upload(request: URLRequest, file: URL) async throws -> HTTPResult
}

public struct URLSessionImageTransport: ImageTransport {
    public init() {}
    public func upload(request: URLRequest, file: URL) async throws -> HTTPResult {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = false
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.upload(for: request, fromFile: file)
        guard let http = response as? HTTPURLResponse else { throw EnhancerError.api("OpenAI returned an unreadable response. The request may have used credits.", uncertain: true, stopBatch: false) }
        return HTTPResult(data: data, status: http.statusCode, requestID: http.value(forHTTPHeaderField: "x-request-id"))
    }
}

public struct APIImageResult: Sendable {
    public let data: Data
    public let usage: TokenUsage?
    public let requestID: String?
    public let returnedQuality: String?
    public let returnedSize: String?
}

public struct OpenAIClient: Sendable {
    private let transport: any ImageTransport
    public init(transport: any ImageTransport = URLSessionImageTransport()) { self.transport = transport }

    public func enhance(guide: Data, geometry: SquareGeometry, quality: EnhancementQuality = EnhancementConfiguration.defaultQuality, credential: String, requestFile: URL, clientRequestID: UUID) async throws -> APIImageResult {
        let boundary = "Wallpaper-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", EnhancementConfiguration.model)
        field("quality", quality.rawValue)
        field("size", "2880x2880")
        field("output_format", "png")
        field("background", "opaque")
        field("n", "1")
        field("prompt", EnhancementConfiguration.prompt(for: geometry))
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"image[]\"; filename=\"square-guide.png\"\r\nContent-Type: image/png\r\n\r\n".utf8))
        body.append(guide)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        try body.write(to: requestFile, options: .atomic)
        defer { try? FileManager.default.removeItem(at: requestFile) }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/edits")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(clientRequestID.uuidString, forHTTPHeaderField: "X-Client-Request-Id")
        let response: HTTPResult
        do { response = try await transport.upload(request: request, file: requestFile) }
        catch let error as EnhancerError { throw error }
        catch {
            let error = error as NSError
            let preflight = error.domain == NSURLErrorDomain && [NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorSecureConnectionFailed].contains(error.code)
            throw EnhancerError.api(preflight
                ? "OpenAI could not be reached. Check your connection, then try again."
                : "The connection ended before a complete result arrived. OpenAI may have used credits. This image will not be submitted again automatically.",
                uncertain: !preflight, stopBatch: preflight)
        }
        guard (200..<300).contains(response.status) else {
            let error = try? JSONDecoder().decode(ErrorEnvelope.self, from: response.data)
            let code = error?.error.code ?? ""
            let message: String
            switch response.status {
            case 401, 403: message = "OpenAI did not authorize this request. Check the existing developer key and its image-model permissions."
            case 429 where code == "insufficient_quota": message = "The OpenAI developer account has insufficient credits or has reached its spending limit."
            case 429: message = "OpenAI is temporarily rate-limiting image requests. Wait a little, then retry this image."
            default: message = SafeErrorText.redact(error?.error.message ?? "OpenAI could not complete this image (HTTP \(response.status)).", credential: credential)
            }
            throw EnhancerError.api(message, uncertain: response.status >= 500,
                                    stopBatch: [401, 403, 429].contains(response.status))
        }
        let decoded: Envelope
        do { decoded = try JSONDecoder().decode(Envelope.self, from: response.data) }
        catch { throw EnhancerError.api("The returned response could not be decoded. The request may have used credits and will not be repeated automatically.", uncertain: true, stopBatch: false) }
        guard decoded.data.count == 1, let data = Data(base64Encoded: decoded.data[0].b64JSON) else {
            throw EnhancerError.api("OpenAI did not return one complete image. The request may have used credits and will not be repeated automatically.", uncertain: true, stopBatch: false)
        }
        return APIImageResult(data: data, usage: decoded.usage, requestID: response.requestID,
                              returnedQuality: decoded.quality, returnedSize: decoded.size)
    }

    private struct Envelope: Decodable {
        let data: [Item]
        let usage: TokenUsage?
        let quality: String?
        let size: String?
        struct Item: Decodable {
            let b64JSON: String
            enum CodingKeys: String, CodingKey { case b64JSON = "b64_json" }
        }
    }
    private struct ErrorEnvelope: Decodable {
        let error: APIError
        struct APIError: Decodable { let message: String; let code: String? }
    }
}
