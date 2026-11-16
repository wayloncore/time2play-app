import Foundation
import T2PCore

/// A room's socket: URLSessionWebSocketTask, with its own pings (free on the server, unlike a message) every 20 s.
final class WebSocketTransport: NSObject, RoomTransport, URLSessionWebSocketDelegate {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var onEvent: ((TransportEvent) -> Void)?
    private var pinger: Timer?
    private var generation = 0

    func open(_ url: URL, onEvent: @escaping (TransportEvent) -> Void) {
        close()
        generation += 1
        self.onEvent = onEvent
        let s = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        let t = s.webSocketTask(with: req)
        session = s; task = t
        t.resume()
        receive(t, generation)
    }

    private func receive(_ t: URLSessionWebSocketTask, _ gen: Int) {
        t.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, gen == self.generation else { return }
                switch result {
                case let .success(.string(s)): self.onEvent?(.text(s)); self.receive(t, gen)
                case let .success(.data(d)): self.onEvent?(.text(String(decoding: d, as: UTF8.self))); self.receive(t, gen)
                case .success: self.receive(t, gen)
                case .failure: self.finish(code: t.closeCode == .invalid ? nil : t.closeCode.rawValue, gen)
                }
            }
        }
    }

    private func finish(code: Int?, _ gen: Int) {
        guard gen == generation else { return }
        generation += 1
        pinger?.invalidate(); pinger = nil
        let e = onEvent
        task = nil; session?.invalidateAndCancel(); session = nil
        e?(.closed(code: code))
    }

    func send(_ text: String) {
        task?.send(.string(text)) { _ in }
    }

    func close() {
        generation += 1
        pinger?.invalidate(); pinger = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel(); session = nil
    }

    // URLSessionWebSocketDelegate
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard webSocketTask === task else { return }
        onEvent?(.opened)
        let gen = generation
        pinger = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self, gen == self.generation, let t = self.task else { return }
            t.sendPing { err in if err != nil { DispatchQueue.main.async { self.finish(code: nil, gen) } } }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard webSocketTask === task else { return }
        finish(code: closeCode.rawValue, generation)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === self.task else { return }
        finish(code: nil, generation)
    }
}
