import AppKit
import CoreFoundation
import EdgeSwipeCore

private struct MTPoint: Sendable {
    var x: Float
    var y: Float
}

private struct MTReadout: Sendable {
    var pos: MTPoint
    var vel: MTPoint
}

private struct MTContact: Sendable {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var fingerID: Int32
    var handID: Int32
    var normalized: MTReadout
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTReadout
    var zero2: Int32
    var zero3: Int32
    var density: Float
}

struct GlobalTouchPoint: Sendable {
    let id: Int
    let x: Double
    let y: Double
}

extension Notification.Name {
    static let edgeSwipeGlobalTouchesDidUpdate = Notification.Name("EdgeSwipeGlobalTouchesDidUpdate")
}

private typealias MTContactFrameCallback = @convention(c) (
    Int32,
    UnsafeMutableRawPointer?,
    Int32,
    Double,
    Int32
) -> Int32

private typealias MTDeviceCreateList = @convention(c) () -> Unmanaged<CFArray>
private typealias MTDeviceStart = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
private typealias MTDeviceStop = @convention(c) (UnsafeMutableRawPointer) -> Void
private typealias MTDeviceRelease = @convention(c) (UnsafeMutableRawPointer) -> Void
private typealias MTRegisterContactFrameCallback = @convention(c) (UnsafeMutableRawPointer, MTContactFrameCallback?) -> Void
private typealias MTUnregisterContactFrameCallback = @convention(c) (UnsafeMutableRawPointer, MTContactFrameCallback?) -> Void

nonisolated(unsafe) private weak var activePrivateMultitouchMonitor: PrivateMultitouchMonitor?

@MainActor
final class PrivateMultitouchMonitor {
    private let runner: ActionRunner
    private var recognizer: EdgeGestureRecognizer
    private var settings: AppSettings
    private var handle: UnsafeMutableRawPointer?
    private var devices: [UnsafeMutableRawPointer] = []
    private var startFunction: MTDeviceStart?
    private var stopFunction: MTDeviceStop?
    private var releaseFunction: MTDeviceRelease?
    private var registerFunction: MTRegisterContactFrameCallback?
    private var unregisterFunction: MTUnregisterContactFrameCallback?
    private var lastFrameHadContacts = false
    private var deviceList: CFArray?

    init(settings: AppSettings, runner: ActionRunner) {
        self.settings = settings
        self.runner = runner
        self.recognizer = EdgeGestureRecognizer(config: settings.config)
    }

    var isRunning: Bool {
        !devices.isEmpty
    }

    func update(settings: AppSettings) {
        self.settings = settings
        recognizer.config = settings.config
    }

    func start() -> Bool {
        stop()

        guard loadFramework(), let deviceList = createDeviceList() else {
            return false
        }

        activePrivateMultitouchMonitor = self
        self.deviceList = deviceList

        let count = CFArrayGetCount(deviceList)
        guard count > 0 else {
            return false
        }

        for index in 0..<count {
            guard let value = CFArrayGetValueAtIndex(deviceList, index) else {
                continue
            }

            let device = UnsafeMutableRawPointer(mutating: value)
            registerFunction?(device, privateMultitouchCallback)
            startFunction?(device, 0)
            devices.append(device)
        }

        return !devices.isEmpty
    }

    func stop() {
        for device in devices {
            unregisterFunction?(device, privateMultitouchCallback)
            stopFunction?(device)
        }
        devices.removeAll()
        deviceList = nil

        if activePrivateMultitouchMonitor === self {
            activePrivateMultitouchMonitor = nil
        }
    }

    fileprivate func handleFrame(contacts: [MTContact], timestamp: Double) {
        guard !contacts.isEmpty else {
            if lastFrameHadContacts {
                _ = recognizer.ingest([])
                lastFrameHadContacts = false
            }
            publish(points: [])
            return
        }

        lastFrameHadContacts = true

        let samples = contacts.map { contact in
            return TouchSample(
                id: Int(contact.identifier),
                x: Double(contact.normalized.pos.x),
                y: Double(contact.normalized.pos.y),
                phase: .moved,
                timestamp: timestamp
            )
        }

        publish(points: samples.map { GlobalTouchPoint(id: $0.id, x: $0.x, y: $0.y) })

        if settings.debugLogging {
            NSLog("EdgeSwipe private MT: contacts=\(samples.count)")
        }

        guard let gesture = recognizer.ingest(samples) else {
            return
        }

        runner.run(edge: gesture.edge, action: settings.action(for: gesture.edge))
    }

    private func loadFramework() -> Bool {
        if handle != nil {
            return true
        }

        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW) else {
            NSLog("EdgeSwipe: MultitouchSupport unavailable: \(String(cString: dlerror()))")
            return false
        }

        guard
            let createSymbol = dlsym(handle, "MTDeviceCreateList"),
            let startSymbol = dlsym(handle, "MTDeviceStart"),
            let stopSymbol = dlsym(handle, "MTDeviceStop"),
            let registerSymbol = dlsym(handle, "MTRegisterContactFrameCallback"),
            let unregisterSymbol = dlsym(handle, "MTUnregisterContactFrameCallback")
        else {
            NSLog("EdgeSwipe: MultitouchSupport symbols unavailable")
            return false
        }

        self.handle = handle
        createDeviceListFunction = unsafeBitCast(createSymbol, to: MTDeviceCreateList.self)
        startFunction = unsafeBitCast(startSymbol, to: MTDeviceStart.self)
        stopFunction = unsafeBitCast(stopSymbol, to: MTDeviceStop.self)
        registerFunction = unsafeBitCast(registerSymbol, to: MTRegisterContactFrameCallback.self)
        unregisterFunction = unsafeBitCast(unregisterSymbol, to: MTUnregisterContactFrameCallback.self)

        if let releaseSymbol = dlsym(handle, "MTDeviceRelease") {
            releaseFunction = unsafeBitCast(releaseSymbol, to: MTDeviceRelease.self)
        }

        return true
    }

    private var createDeviceListFunction: MTDeviceCreateList?

    private func createDeviceList() -> CFArray? {
        createDeviceListFunction?().takeRetainedValue()
    }

    private func publish(points: [GlobalTouchPoint]) {
        NotificationCenter.default.post(
            name: .edgeSwipeGlobalTouchesDidUpdate,
            object: points
        )
    }
}

private func privateMultitouchCallback(
    device: Int32,
    contacts: UnsafeMutableRawPointer?,
    count: Int32,
    timestamp: Double,
    frame: Int32
) -> Int32 {
    guard let monitor = activePrivateMultitouchMonitor else {
        return 0
    }

    let copiedContacts: [MTContact]
    if let contacts, count > 0 {
        let typedContacts = contacts.bindMemory(to: MTContact.self, capacity: Int(count))
        copiedContacts = (0..<Int(count)).map { typedContacts[$0] }
    } else {
        copiedContacts = []
    }

    Task { @MainActor [copiedContacts, timestamp] in
        monitor.handleFrame(contacts: copiedContacts, timestamp: timestamp)
    }

    return 0
}
