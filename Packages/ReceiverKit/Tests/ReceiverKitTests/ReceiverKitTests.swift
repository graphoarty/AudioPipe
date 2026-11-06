import CAudioCore
import CoreAudio
import XCTest
@testable import ReceiverKit

final class RingBufferTests: XCTestCase {
    func testWrapAround() {
        let s = ap_slot_create(100, 44_100)!
        defer { ap_slot_destroy(s) }
        var l = [Float](repeating: 0, count: 70), r = l
        for round in 0..<10 {
            let inL = (0..<70).map { Float(round * 1000 + $0) }
            let inR = inL.map { -$0 }
            XCTAssertEqual(ap_slot_write(s, inL, inR, 70), 70)
            XCTAssertEqual(ap_slot_available(s), 70)
            XCTAssertEqual(ap_slot_read(s, &l, &r, 70), 70)
            XCTAssertEqual(l, inL)
            XCTAssertEqual(r, inR)
        }
    }

    func testOverflowDropsAndCounts() {
        let s = ap_slot_create(10, 44_100)!
        defer { ap_slot_destroy(s) }
        let data = [Float](repeating: 1, count: 15)
        XCTAssertEqual(ap_slot_write(s, data, data, 15), 10)
        XCTAssertEqual(ap_slot_dropped_frames(s), 5)
    }

    /// Run under Thread Sanitizer: `swift test --sanitize=thread`.
    func testConcurrentProducerConsumer() {
        let s = ap_slot_create(4096, 44_100)!
        defer { ap_slot_destroy(s) }
        let total = 2_000_000
        let done = expectation(description: "consumer")
        var errors = 0

        let producer = Thread {
            var next = 0
            var l = [Float](repeating: 0, count: 333), r = l
            while next < total {
                let n = min(333, total - next)
                for i in 0..<n { l[i] = Float(next + i); r[i] = -Float(next + i) }
                var off = 0
                while off < n {
                    let w = l.withUnsafeBufferPointer { lp in r.withUnsafeBufferPointer { rp in
                        ap_slot_write(s, lp.baseAddress! + off, rp.baseAddress! + off, UInt32(n - off)) } }
                    off += Int(w)
                    if w == 0 { usleep(10) }
                }
                next += n
            }
        }
        let consumer = Thread {
            var expected = 0
            var l = [Float](repeating: 0, count: 512), r = l
            while expected < total {
                let n = Int(ap_slot_read(s, &l, &r, 512))
                if n == 0 { usleep(10); continue }
                for i in 0..<n where l[i] != Float(expected + i) || r[i] != -Float(expected + i) { errors += 1 }
                expected += n
            }
            done.fulfill()
        }
        producer.start()
        consumer.start()
        wait(for: [done], timeout: 60)
        XCTAssertEqual(errors, 0)
        XCTAssertEqual(ap_slot_dropped_frames(s), 0)
    }

    func testRenderPrimesUnderrunsAndFlushes() {
        let s = ap_slot_create(44_100, 44_100)!
        defer { ap_slot_destroy(s) }
        ap_slot_set_target(s, 1000)
        var l = [Float](repeating: 7, count: 512), r = l
        func render(_ frames: Int) {
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    let abl = AudioBufferList.allocate(maximumBuffers: 2)
                    defer { free(abl.unsafeMutablePointer) }
                    abl[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: lp.baseAddress)
                    abl[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: rp.baseAddress)
                    ap_slot_render(s, UInt32(frames), abl.unsafeMutablePointer)
                }
            }
        }
        let ones = [Float](repeating: 1, count: 800)
        _ = ap_slot_write(s, ones, ones, 800)
        render(512)
        XCTAssertEqual(ap_slot_is_primed(s), 0, "below target: silence")
        XCTAssertTrue(l.allSatisfy { $0 == 0 })

        _ = ap_slot_write(s, ones, ones, 800)  // 1600 >= 1000
        render(512)
        XCTAssertEqual(ap_slot_is_primed(s), 1)
        XCTAssertEqual(l[0], 0, "fade-in starts at zero")
        XCTAssertEqual(l[511], 1)

        render(512)
        render(512)  // 1600 - 1536 = 64 left, then underrun
        render(512)
        XCTAssertEqual(ap_slot_is_primed(s), 0)
        XCTAssertGreaterThanOrEqual(ap_slot_underruns(s), 1)

        let more = [Float](repeating: 1, count: 4000)
        _ = ap_slot_write(s, more, more, 4000)
        render(512)
        ap_slot_request_flush(s)
        render(512)
        render(512)
        XCTAssertEqual(ap_slot_available(s), 0, "flush clears after 20 ms fade")
        XCTAssertEqual(ap_slot_flush_pending(s), 0)
    }
}

final class DriftControllerTests: XCTestCase {
    /// Simulates a producer running `ppm` fast/slow against the output clock.
    private func simulate(ppm: Double, hours: Double = 2) -> (maxError: Double, finalRate: Double) {
        let rate = 44_100.0
        let target = 0.040
        var depth = target * rate  // frames
        var controller = DriftController()
        let dt = 0.1
        var maxError = 0.0
        var t = 0.0
        while t < hours * 3600 {
            depth += rate * (1 + ppm / 1e6) * dt          // producer
            depth -= rate * controller.rate * dt           // consumer via varispeed
            _ = controller.addSample(depthSeconds: depth / rate, targetSeconds: target, dt: dt)
            if t > 600 { maxError = max(maxError, abs(depth / rate - target)) }  // after settling
            t += dt
        }
        return (maxError, controller.rate)
    }

    func testSettlesWithinTwentyMillisecondsForPlusMinus100ppm() {
        for ppm in [-100.0, -40, 0, 40, 100] {
            let result = simulate(ppm: ppm)
            XCTAssertLessThan(result.maxError, 0.020, "ppm \(ppm)")
            XCTAssertEqual(result.finalRate, 1 + ppm / 1e6, accuracy: 2e-5, "ppm \(ppm)")
        }
    }

    func testRateIsClampedToPointOnePercent() {
        var c = DriftController()
        for _ in 0..<100 { _ = c.addSample(depthSeconds: 1.0, targetSeconds: 0.04, dt: 0.1) }
        XCTAssertLessThanOrEqual(c.rate, 1.001 + 1e-12)
        for _ in 0..<1000 { _ = c.addSample(depthSeconds: 0, targetSeconds: 0.04, dt: 0.1) }
        XCTAssertGreaterThanOrEqual(c.rate, 0.999 - 1e-12)
    }
}

final class RingCatchUpTests: XCTestCase {
    func testRenderDropsLargeBacklogToTarget() {
        let s = ap_slot_create(44_100, 44_100)!
        defer { ap_slot_destroy(s) }
        ap_slot_set_target(s, 1764)  // 40 ms
        let big = [Float](repeating: 0.5, count: 20_000)  // ~450 ms backlog
        _ = ap_slot_write(s, big, big, 20_000)
        var l = [Float](repeating: 0, count: 512), r = l
        l.withUnsafeMutableBufferPointer { lp in
            r.withUnsafeMutableBufferPointer { rp in
                let abl = AudioBufferList.allocate(maximumBuffers: 2)
                defer { free(abl.unsafeMutablePointer) }
                abl[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 2048, mData: lp.baseAddress)
                abl[1] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 2048, mData: rp.baseAddress)
                ap_slot_render(s, 512, abl.unsafeMutablePointer)
            }
        }
        XCTAssertEqual(ap_slot_available(s), 1764)
    }
}

final class SlotAudioBufferTests: XCTestCase {
    func testPushFillsRingAndTracksSound() {
        let buffer = SlotAudioBuffer(capacitySeconds: 1.0)
        let silence = [Float](repeating: 0, count: 441)
        silence.withUnsafeBufferPointer { s in buffer.push(left: s.baseAddress!, right: s.baseAddress!, frames: 441) }
        XCTAssertEqual(buffer.depthFrames, 441)
        XCTAssertLessThan(buffer.secondsSinceAudio, 1, "silence counts as audio arriving")
        XCTAssertGreaterThan(buffer.secondsSinceSound, 1000, "but not as sound")

        let tone = [Float](repeating: 0.5, count: 441)
        tone.withUnsafeBufferPointer { t in buffer.push(left: t.baseAddress!, right: t.baseAddress!, frames: 441) }
        XCTAssertEqual(buffer.depthFrames, 882)
        XCTAssertLessThan(buffer.secondsSinceSound, 1)
        XCTAssertEqual(buffer.takeLevels().peak, 0.5)
    }
}
