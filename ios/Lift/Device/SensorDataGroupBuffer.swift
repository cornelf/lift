import Foundation

let sensorDataGroupBufferQueue: dispatch_queue_t = dispatch_queue_create("SensorDataGroupBuffer", nil)

protocol SensorDataGroupBufferDelegate {
    
    func sensorDataGroupBuffer(buffer: SensorDataGroupBuffer, continuousSensorDataEncodedAt time: CFAbsoluteTime, data: NSData)
    
}

class SensorDataGroupBuffer {
    var sensorDataGroup: SensorDataGroup = SensorDataGroup()
    var lastDecodeTime: CFAbsoluteTime? = nil
    let windowSize: CFTimeInterval!
    let windowDelay: CFTimeInterval!
    let queue: dispatch_queue_t!
    let timer: dispatch_source_t!
    let delegate: SensorDataGroupBufferDelegate!
    
    init(delegate: SensorDataGroupBufferDelegate) {
        self.delegate = delegate
        windowSize = Double(DevicePace.samplesPerPacket) / 100.0   // matches 124 samples at 100 Hz
        windowDelay = windowSize / 2.0
        queue = dispatch_get_main_queue()
        timer = createDispatchTimer(windowSize, queue: queue, block: { self.encodeWindow() })
    }
    
    private func createDispatchTimer(interval: CFTimeInterval, queue: dispatch_queue_t, block: dispatch_block_t) -> dispatch_source_t {
        let timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue)
        if timer != nil  {
            let interval64: Int64 = Int64(interval * Double(NSEC_PER_SEC))
            dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, interval64), UInt64(interval64), (1 * NSEC_PER_SEC) / 10)
            dispatch_source_set_event_handler(timer, block)
            dispatch_resume(timer)
        }
        return timer
    }

    /* mutating */
    func decodeAndAdd(data: NSData, fromDeviceId id: DeviceId, maximumGap gap: CFTimeInterval = 0.3, gapValue: UInt8 = 0x00) -> Void {
        let time = CFAbsoluteTimeGetCurrent()
        sensorDataGroup.decodeAndAdd(data, fromDeviceId: id, at: time, maximumGap: gap, gapValue: gapValue)
        NSLog("INFO: sensorDataGroup.rawCount = %d, sensorDataGroup.length = %d", sensorDataGroup.rawCount, sensorDataGroup.length)
        
        lastDecodeTime = time
    }
    
    func stop() {
        dispatch_source_cancel(timer)
    }
    
    /* mutating */
    func encodeWindow() {
        if let x = lastDecodeTime {
            let start = x - windowDelay - windowSize
            let end   = x - windowDelay
            
            NSLog("INFO: sensorDataGroup.rawCount = %d, sensorDataGroup.length = %d", sensorDataGroup.rawCount, sensorDataGroup.length)
            let csdas = sensorDataGroup.continuousSensorDataArrays(within: TimeRange(start: start, end: end), maximumGap: 0.3, gapValue: 0x00)
            if !csdas.isEmpty {
                let result = NSMutableData()
                // TODO: Multi-packet header
                csdas.foreach { $0.encode(mutating: result) }
                delegate.sensorDataGroupBuffer(self, continuousSensorDataEncodedAt: start, data: result)
                NSLog("INFO: Data \(result.length)")
            } else {
                NSLog("WARN: Empty range \(start) - \(end)")
            }
            sensorDataGroup.removeSensorDataArraysEndingBefore(start)
        }
        
    }
    
}