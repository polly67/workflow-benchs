import Foundation
import Metal
import MetalPerformanceShaders

print("========================================")
print("🍎 macOS Metal / GPU Capabilities Probe")
print("========================================")

struct GPUProbeReport: Codable {
    var timestamp: String
    var metalDevicesFound: Int
    var defaultDeviceName: String?
    var isHeadless: Bool?
    var isLowPower: Bool?
    var isRemovable: Bool?
    var hasUnifiedMemory: Bool?
    var recommendedMaxWorkingSetMB: Double?
    var maxBufferLengthMB: Double?
    var supportsMetal3: Bool?
    var supportsApple7: Bool?
    var supportsApple8: Bool?
    var supportsRaytracing: Bool?
    var vectorAddSuccess: Bool
    var vectorAddLatencyMs: Double?
    var vectorAddBandwidthGBs: Double?
    var computeStressLatencyMs: Double?
    var computeGFLOPS: Double?
    var mpsSupported: Bool
    var gemm2048LatencyMs: Double?
    var gemmTFLOPS: Double?
    var error: String?
}

var report = GPUProbeReport(
    timestamp: ISO8601DateFormatter().string(from: Date()),
    metalDevicesFound: 0,
    vectorAddSuccess: false,
    mpsSupported: false
)

let devices = MTLCopyAllDevices()
report.metalDevicesFound = devices.count
print("Total Metal devices discovered: \(devices.count)")

if devices.isEmpty {
    print("❌ No Metal GPU devices found on this macOS runner.")
    report.error = "No Metal GPU devices detected."
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let data = try? encoder.encode(report) {
        try? data.write(to: URL(fileURLWithPath: "results/metal_report.json"))
    }
    exit(0)
}

for (i, dev) in devices.enumerated() {
    print("\n[Device \(i)]: \(dev.name)")
    print("  Registry ID: \(dev.registryID)")
    print("  Headless: \(dev.isHeadless)")
    print("  Low Power: \(dev.isLowPower)")
    print("  Removable: \(dev.isRemovable)")
    print("  Unified Memory: \(dev.hasUnifiedMemory)")
    print("  Recommended Max Working Set: \(dev.recommendedMaxWorkingSetSize / 1024 / 1024) MB")
    print("  Max Buffer Length: \(dev.maxBufferLength / 1024 / 1024) MB")
    print("  Supports Apple 7 (A14/M1): \(dev.supportsFamily(.apple7))")
    print("  Supports Apple 8 (A15/M2): \(dev.supportsFamily(.apple8))")
    print("  Supports Metal 3: \(dev.supportsFamily(.metal3))")
    if #available(macOS 11.0, *) {
        print("  Supports Raytracing: \(dev.supportsRaytracing)")
    }
}

guard let device = MTLCreateSystemDefaultDevice() else {
    print("❌ Default Metal device is nil.")
    report.error = "Default Metal device could not be acquired."
    exit(0)
}

report.defaultDeviceName = device.name
report.isHeadless = device.isHeadless
report.isLowPower = device.isLowPower
report.isRemovable = device.isRemovable
report.hasUnifiedMemory = device.hasUnifiedMemory
report.recommendedMaxWorkingSetMB = Double(device.recommendedMaxWorkingSetSize) / (1024.0 * 1024.0)
report.maxBufferLengthMB = Double(device.maxBufferLength) / (1024.0 * 1024.0)
report.supportsApple7 = device.supportsFamily(.apple7)
report.supportsApple8 = device.supportsFamily(.apple8)
report.supportsMetal3 = device.supportsFamily(.metal3)
if #available(macOS 11.0, *) {
    report.supportsRaytracing = device.supportsRaytracing
}

print("\n========================================")
print("🧪 Metal Compute Kernel Test & Benchmark")
print("========================================")

let mslSource = """
#include <metal_stdlib>
using namespace metal;

kernel void vector_add(const device float* inA [[buffer(0)]],
                       const device float* inB [[buffer(1)]],
                       device float* out [[buffer(2)]],
                       constant uint& count [[buffer(3)]],
                       uint id [[thread_position_in_grid]]) {
    if (id < count) {
        out[id] = inA[id] + inB[id];
    }
}

kernel void compute_heavy(const device float* inA [[buffer(0)]],
                          device float* out [[buffer(1)]],
                          constant uint& iterations [[buffer(2)]],
                          constant uint& count [[buffer(3)]],
                          uint id [[thread_position_in_grid]]) {
    if (id < count) {
        float val = inA[id];
        for (uint i = 0; i < iterations; i++) {
            val = sin(val) * cos(val) + 1.0001f;
            val = fma(val, 0.9999f, 0.0001f);
        }
        out[id] = val;
    }
}
"""

do {
    print("Compiling Metal Shading Language (MSL) source...")
    let library = try device.makeLibrary(source: mslSource, options: nil)
    guard let vectorAddFunc = library.makeFunction(name: "vector_add"),
          let heavyFunc = library.makeFunction(name: "compute_heavy") else {
        fatalError("Could not find functions in Metal library")
    }
    
    let vectorAddPipeline = try device.makeComputePipelineState(function: vectorAddFunc)
    let heavyPipeline = try device.makeComputePipelineState(function: heavyFunc)
    guard let commandQueue = device.makeCommandQueue() else {
        fatalError("Failed to create Metal command queue")
    }

    // Benchmark 1: Vector Addition Memory Bandwidth & Accuracy
    let nElements: UInt32 = 10_000_000
    let bufSize = Int(nElements) * MemoryLayout<Float>.stride
    print("Allocating 3 x \(bufSize / 1024 / 1024) MB Metal buffers (\(nElements) elements)...")

    guard let bufA = device.makeBuffer(length: bufSize, options: .storageModeShared),
          let bufB = device.makeBuffer(length: bufSize, options: .storageModeShared),
          let bufOut = device.makeBuffer(length: bufSize, options: .storageModeShared) else {
        fatalError("Failed to allocate buffers")
    }

    var countVal = nElements
    guard let countBuf = device.makeBuffer(bytes: &countVal, length: MemoryLayout<UInt32>.stride, options: .storageModeShared) else {
        fatalError("Failed to allocate count buffer")
    }

    let ptrA = bufA.contents().bindMemory(to: Float.self, capacity: Int(nElements))
    let ptrB = bufB.contents().bindMemory(to: Float.self, capacity: Int(nElements))
    let ptrOut = bufOut.contents().bindMemory(to: Float.self, capacity: Int(nElements))

    for i in 0..<1000 {
        ptrA[i] = Float(i) * 1.5
        ptrB[i] = Float(i) * 2.5
    }

    print("Executing Vector Addition on GPU...")
    let threadsPerGroup1 = MTLSize(width: min(vectorAddPipeline.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1)
    let groups1 = MTLSize(width: (Int(nElements) + threadsPerGroup1.width - 1) / threadsPerGroup1.width, height: 1, depth: 1)

    // Warmup
    if let cmd = commandQueue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() {
        enc.setComputePipelineState(vectorAddPipeline)
        enc.setBuffer(bufA, offset: 0, index: 0)
        enc.setBuffer(bufB, offset: 0, index: 1)
        enc.setBuffer(bufOut, offset: 0, index: 2)
        enc.setBuffer(countBuf, offset: 0, index: 3)
        enc.dispatchThreadgroups(groups1, threadsPerThreadgroup: threadsPerGroup1)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }

    let startVec = CFAbsoluteTimeGetCurrent()
    let vecRuns = 5
    for _ in 0..<vecRuns {
        guard let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else { break }
        enc.setComputePipelineState(vectorAddPipeline)
        enc.setBuffer(bufA, offset: 0, index: 0)
        enc.setBuffer(bufB, offset: 0, index: 1)
        enc.setBuffer(bufOut, offset: 0, index: 2)
        enc.setBuffer(countBuf, offset: 0, index: 3)
        enc.dispatchThreadgroups(groups1, threadsPerThreadgroup: threadsPerGroup1)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }
    let elapsedVec = (CFAbsoluteTimeGetCurrent() - startVec) / Double(vecRuns)

    var passed = true
    for i in 0..<1000 {
        let expected = ptrA[i] + ptrB[i]
        if abs(ptrOut[i] - expected) > 1e-4 {
            passed = false
            break
        }
    }

    report.vectorAddSuccess = passed
    report.vectorAddLatencyMs = elapsedVec * 1000.0
    let totalBytesTransferred = Double(bufSize * 3) / (1024.0 * 1024.0 * 1024.0)
    let bandwidthGBs = totalBytesTransferred / elapsedVec
    report.vectorAddBandwidthGBs = bandwidthGBs

    print("  Vector Addition Correctness: \(passed ? "✅ PASSED" : "❌ FAILED")")
    print(String(format: "  Vector Addition Latency: %.2f ms", elapsedVec * 1000.0))
    print(String(format: "  Effective GPU Bandwidth: %.2f GB/s", bandwidthGBs))

    // Benchmark 2: Compute Heavy Kernel
    var computeElements: UInt32 = 1_000_000
    var iterations: UInt32 = 200
    let computeBufSize = Int(computeElements) * MemoryLayout<Float>.stride
    guard let heavyInBuf = device.makeBuffer(length: computeBufSize, options: .storageModeShared),
          let heavyOutBuf = device.makeBuffer(length: computeBufSize, options: .storageModeShared),
          let iterBuf = device.makeBuffer(bytes: &iterations, length: MemoryLayout<UInt32>.stride, options: .storageModeShared),
          let computeCountBuf = device.makeBuffer(bytes: &computeElements, length: MemoryLayout<UInt32>.stride, options: .storageModeShared) else {
        fatalError("Failed to allocate heavy compute buffers")
    }

    print("\nExecuting Compute Heavy Kernel (\(computeElements) threads x \(iterations) iterations)...")
    let threadsPerGroup2 = MTLSize(width: min(heavyPipeline.maxTotalThreadsPerThreadgroup, 256), height: 1, depth: 1)
    let groups2 = MTLSize(width: (Int(computeElements) + threadsPerGroup2.width - 1) / threadsPerGroup2.width, height: 1, depth: 1)

    let startCompute = CFAbsoluteTimeGetCurrent()
    let computeRuns = 3
    for _ in 0..<computeRuns {
        guard let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else { break }
        enc.setComputePipelineState(heavyPipeline)
        enc.setBuffer(heavyInBuf, offset: 0, index: 0)
        enc.setBuffer(heavyOutBuf, offset: 0, index: 1)
        enc.setBuffer(iterBuf, offset: 0, index: 2)
        enc.setBuffer(computeCountBuf, offset: 0, index: 3)
        enc.dispatchThreadgroups(groups2, threadsPerThreadgroup: threadsPerGroup2)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }
    let elapsedCompute = (CFAbsoluteTimeGetCurrent() - startCompute) / Double(computeRuns)
    let totalOps = Double(computeElements) * Double(iterations) * 20.0
    let gflops = (totalOps / elapsedCompute) / 1e9

    report.computeStressLatencyMs = elapsedCompute * 1000.0
    report.computeGFLOPS = gflops
    print(String(format: "  Compute Stress Latency: %.2f ms", elapsedCompute * 1000.0))
    print(String(format: "  Estimated Compute Throughput: %.2f GFLOPS", gflops))

    // Benchmark 3: Metal Performance Shaders (MPS Matrix Multiplication)
    print("\nTesting MetalPerformanceShaders (MPS GEMM Matrix Multiplication)...")
    if MPSSupportsMTLDevice(device) {
        report.mpsSupported = true
        let M = 2048
        let N = 2048
        let K = 2048
        let descA = MPSMatrixDescriptor(rows: M, columns: K, rowBytes: K * MemoryLayout<Float>.stride, dataType: .float32)
        let descB = MPSMatrixDescriptor(rows: K, columns: N, rowBytes: N * MemoryLayout<Float>.stride, dataType: .float32)
        let descC = MPSMatrixDescriptor(rows: M, columns: N, rowBytes: N * MemoryLayout<Float>.stride, dataType: .float32)

        let matA = MPSMatrix(buffer: device.makeBuffer(length: M * K * MemoryLayout<Float>.stride, options: .storageModeShared)!, descriptor: descA)
        let matB = MPSMatrix(buffer: device.makeBuffer(length: K * N * MemoryLayout<Float>.stride, options: .storageModeShared)!, descriptor: descB)
        let matC = MPSMatrix(buffer: device.makeBuffer(length: M * N * MemoryLayout<Float>.stride, options: .storageModeShared)!, descriptor: descC)

        let matMul = MPSMatrixMultiplication(device: device, transposeLeft: false, transposeRight: false, resultRows: M, resultColumns: N, interiorColumns: K, alpha: 1.0, beta: 0.0)

        // Warmup
        let warmCmd = commandQueue.makeCommandBuffer()!
        matMul.encode(commandBuffer: warmCmd, leftMatrix: matA, rightMatrix: matB, resultMatrix: matC)
        warmCmd.commit()
        warmCmd.waitUntilCompleted()

        let startMatMul = CFAbsoluteTimeGetCurrent()
        let gemmRuns = 5
        for _ in 0..<gemmRuns {
            let cmd = commandQueue.makeCommandBuffer()!
            matMul.encode(commandBuffer: cmd, leftMatrix: matA, rightMatrix: matB, resultMatrix: matC)
            cmd.commit()
            cmd.waitUntilCompleted()
        }
        let elapsedMatMul = (CFAbsoluteTimeGetCurrent() - startMatMul) / Double(gemmRuns)
        let flopPerMatMul = 2.0 * Double(M) * Double(N) * Double(K)
        let tflops = (flopPerMatMul / elapsedMatMul) / 1e12

        report.gemm2048LatencyMs = elapsedMatMul * 1000.0
        report.gemmTFLOPS = tflops

        print(String(format: "  2048x2048 FP32 GEMM Latency: %.2f ms", elapsedMatMul * 1000.0))
        print(String(format: "  GEMM MPS Compute Performance: %.2f TFLOPS", tflops))
    } else {
        print("  ⚠️ MPS is not supported on this device.")
    }

} catch {
    print("❌ Error during Metal testing: \(error)")
    report.error = "\(error)"
}

try? FileManager.default.createDirectory(atPath: "results", withIntermediateDirectories: true)
let encoder = JSONEncoder()
encoder.outputFormatting = .prettyPrinted
if let data = try? encoder.encode(report) {
    try? data.write(to: URL(fileURLWithPath: "results/metal_report.json"))
}

print("\n========================================")
print("🎉 Swift Metal Test Finished")
print("========================================")
