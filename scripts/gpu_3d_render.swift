import Foundation
import Metal
import simd

print("========================================")
print("🎨 macOS 3D Metal Offscreen Render Benchmark")
print("========================================")

struct Render3DReport: Codable {
    var deviceName: String
    var renderWidth: Int
    var renderHeight: Int
    var totalTrianglesPerFrame: Int
    var framesRendered: Int
    var totalElapsedSec: Double
    var averageFps: Double
    var frameLatencyMs: Double
    var trianglesPerSecond: Double
    var rasterizationVerified: Bool
    var error: String?
}

var report = Render3DReport(
    deviceName: "Unknown",
    renderWidth: 1920,
    renderHeight: 1080,
    totalTrianglesPerFrame: 0,
    framesRendered: 0,
    totalElapsedSec: 0,
    averageFps: 0,
    frameLatencyMs: 0,
    trianglesPerSecond: 0,
    rasterizationVerified: false
)

guard let device = MTLCreateSystemDefaultDevice() else {
    print("❌ No Metal device found.")
    report.error = "No Metal device available."
    exit(0)
}

report.deviceName = device.name
print("Using Metal Device: \(device.name)")

// 1. Shading Language for 3D Rasterization
let msl3DSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexInput {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
    float4 color    [[attribute(2)]];
};

struct VertexOutput {
    float4 position [[position]];
    float3 worldNormal;
    float3 eyeVec;
    float4 color;
};

struct Uniforms {
    float4x4 mvp;
    float3x3 normalMatrix;
};

vertex VertexOutput vertex_3d(VertexInput in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(1)]]) {
    VertexOutput out;
    out.position = uniforms.mvp * float4(in.position, 1.0);
    out.worldNormal = uniforms.normalMatrix * in.normal;
    out.eyeVec = -in.position;
    out.color = in.color;
    return out;
}

fragment float4 fragment_3d(VertexOutput in [[stage_in]]) {
    float3 N = normalize(in.worldNormal);
    float3 L = normalize(float3(2.0, 4.0, 3.0));
    float3 V = normalize(in.eyeVec);
    float3 H = normalize(L + V);

    float diffuse = max(dot(N, L), 0.0f);
    float specular = pow(max(dot(N, H), 0.0f), 32.0f);
    float3 ambient = float3(0.2, 0.2, 0.25);

    float3 rgb = in.color.rgb * (ambient + diffuse * 0.7f) + float3(1.0, 1.0, 1.0) * specular * 0.4f;
    return float4(rgb, 1.0);
}
"""

// Matrix Math Helpers
func matrix4x4_perspective(fovyRadians: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
    let ys = 1.0 / tan(fovyRadians * 0.5)
    let xs = ys / aspect
    let zs = farZ / (nearZ - farZ)
    return simd_float4x4(columns: (
        simd_float4(xs, 0, 0, 0),
        simd_float4(0, ys, 0, 0),
        simd_float4(0, 0, zs, -1),
        simd_float4(0, 0, zs * nearZ, 0)
    ))
}

func matrix4x4_rotation(angle: Float, axis: simd_float3) -> simd_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cos(angle)
    let st = sin(angle)
    let ci = 1.0 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    return simd_float4x4(columns: (
        simd_float4(ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
        simd_float4(x * y * ci - z * st, ct + y * y * ci, z * y * ci + x * st, 0),
        simd_float4(x * z * ci + y * st, y * z * ci - x * st, ct + z * z * ci, 0),
        simd_float4(0, 0, 0, 1)
    ))
}

func matrix4x4_translation(tx: Float, ty: Float, tz: Float) -> simd_float4x4 {
    return simd_float4x4(columns: (
        simd_float4(1, 0, 0, 0),
        simd_float4(0, 1, 0, 0),
        simd_float4(0, 0, 1, 0),
        simd_float4(tx, ty, tz, 1)
    ))
}

// 2. Build 3D Sphere Geometry (UV Sphere)
struct Vertex {
    var position: simd_float3
    var normal: simd_float3
    var color: simd_float4
}

let rings = 40
let sectors = 40
var vertices: [Vertex] = []
var indices: [UInt32] = []

let R: Float = 1.0
let PI: Float = Float.pi

for r in 0...rings {
    let phi = PI * Float(r) / Float(rings)
    for s in 0...sectors {
        let theta = 2.0 * PI * Float(s) / Float(sectors)
        let x = R * sin(phi) * cos(theta)
        let y = R * cos(phi)
        let z = R * sin(phi) * sin(theta)
        let pos = simd_float3(x, y, z)
        let norm = normalize(pos)
        let col = simd_float4((x + 1.0) * 0.5, (y + 1.0) * 0.5, (z + 1.0) * 0.5, 1.0)
        vertices.append(Vertex(position: pos, normal: norm, color: col))
    }
}

for r in 0..<rings {
    for s in 0..<sectors {
        let first = UInt32(r * (sectors + 1) + s)
        let second = UInt32((r + 1) * (sectors + 1) + s)
        indices.append(first)
        indices.append(second)
        indices.append(first + 1)

        indices.append(second)
        indices.append(second + 1)
        indices.append(first + 1)
    }
}

let triangleCount = indices.count / 3
report.totalTrianglesPerFrame = triangleCount
print("Generated 3D Mesh: \(vertices.count) vertices, \(triangleCount) triangles")

do {
    let library = try device.makeLibrary(source: msl3DSource, options: nil)
    guard let vertexFunc = library.makeFunction(name: "vertex_3d"),
          let fragFunc = library.makeFunction(name: "fragment_3d") else {
        fatalError("Could not retrieve shader functions")
    }

    // Vertex Descriptor
    let vertexDesc = MTLVertexDescriptor()
    vertexDesc.attributes[0].format = .float3
    vertexDesc.attributes[0].offset = 0
    vertexDesc.attributes[0].bufferIndex = 0

    vertexDesc.attributes[1].format = .float3
    vertexDesc.attributes[1].offset = MemoryLayout<simd_float3>.stride
    vertexDesc.attributes[1].bufferIndex = 0

    vertexDesc.attributes[2].format = .float4
    vertexDesc.attributes[2].offset = MemoryLayout<simd_float3>.stride * 2
    vertexDesc.attributes[2].bufferIndex = 0

    vertexDesc.layouts[0].stride = MemoryLayout<Vertex>.stride
    vertexDesc.layouts[0].stepRate = 1
    vertexDesc.layouts[0].stepFunction = .perVertex

    // Render Pipeline Descriptor
    let pipelineDesc = MTLRenderPipelineDescriptor()
    pipelineDesc.vertexFunction = vertexFunc
    pipelineDesc.fragmentFunction = fragFunc
    pipelineDesc.vertexDescriptor = vertexDesc
    pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
    pipelineDesc.depthAttachmentPixelFormat = .depth32Float

    let renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)

    // Depth Stencil State
    let depthDesc = MTLDepthStencilDescriptor()
    depthDesc.depthCompareFunction = .less
    depthDesc.isDepthWriteEnabled = true
    guard let depthState = device.makeDepthStencilState(descriptor: depthDesc) else {
        fatalError("Failed to create depth stencil state")
    }

    // Textures: 1920x1080 Offscreen Color & Depth
    let width = 1920
    let height = 1080
    let colorTexDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    colorTexDesc.usage = [.renderTarget, .shaderRead]
    colorTexDesc.storageMode = .shared
    guard let colorTexture = device.makeTexture(descriptor: colorTexDesc) else {
        fatalError("Failed to create offscreen color texture")
    }

    let depthTexDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
    depthTexDesc.usage = [.renderTarget]
    depthTexDesc.storageMode = .private
    guard let depthTexture = device.makeTexture(descriptor: depthTexDesc) else {
        fatalError("Failed to create offscreen depth texture")
    }

    // Geometry Buffers
    guard let vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Vertex>.stride, options: .storageModeShared),
          let indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt32>.stride, options: .storageModeShared) else {
        fatalError("Failed to allocate mesh buffers")
    }

    guard let commandQueue = device.makeCommandQueue() else {
        fatalError("Failed to create Metal command queue")
    }

    struct Uniforms {
        var mvp: simd_float4x4
        var normalMatrix: simd_float3x3
    }

    let proj = matrix4x4_perspective(fovyRadians: 60.0 * PI / 180.0, aspect: Float(width) / Float(height), nearZ: 0.1, farZ: 100.0)
    let view = matrix4x4_translation(tx: 0, ty: 0, tz: -3.5)

    let totalFrames = 300
    print("Beginning 3D Render Benchmark: \(totalFrames) frames at \(width)x\(height)...")

    let startTime = CFAbsoluteTimeGetCurrent()

    for frame in 0..<totalFrames {
        let angle = Float(frame) * 0.02
        let rot = matrix4x4_rotation(angle: angle, axis: simd_float3(0.5, 1.0, 0.2))
        let model = rot
        let mvp = proj * view * model

        let nm = simd_float3x3(columns: (
            simd_float3(rot.columns.0.x, rot.columns.0.y, rot.columns.0.z),
            simd_float3(rot.columns.1.x, rot.columns.1.y, rot.columns.1.z),
            simd_float3(rot.columns.2.x, rot.columns.2.y, rot.columns.2.z)
        ))

        var uniforms = Uniforms(mvp: mvp, normalMatrix: nm)

        let renderPassDesc = MTLRenderPassDescriptor()
        renderPassDesc.colorAttachments[0].texture = colorTexture
        renderPassDesc.colorAttachments[0].loadAction = .clear
        renderPassDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)
        renderPassDesc.colorAttachments[0].storeAction = .store

        renderPassDesc.depthAttachment.texture = depthTexture
        renderPassDesc.depthAttachment.loadAction = .clear
        renderPassDesc.depthAttachment.clearDepth = 1.0
        renderPassDesc.depthAttachment.storeAction = .dontCare

        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
            fatalError("Failed to create render command encoder")
        }

        encoder.setRenderPipelineState(renderPipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indices.count,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )

        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
    }

    let elapsed = CFAbsoluteTimeGetCurrent() - startTime
    let fps = Double(totalFrames) / elapsed
    let latencyMs = (elapsed / Double(totalFrames)) * 1000.0
    let triPerSec = Double(totalFrames * triangleCount) / elapsed

    report.framesRendered = totalFrames
    report.totalElapsedSec = elapsed
    report.averageFps = fps
    report.frameLatencyMs = latencyMs
    report.trianglesPerSecond = triPerSec

    // Verify 3D rasterization output by checking center pixels of the render texture
    let pixelRegion = MTLRegionMake2D(width / 2 - 5, height / 2 - 5, 10, 10)
    var pixelData = [UInt8](repeating: 0, count: 10 * 10 * 4)
    colorTexture.getBytes(&pixelData, bytesPerRow: 10 * 4, from: pixelRegion, mipmapLevel: 0)

    // Center pixel should be non-clear (sphere rendered at center)
    var nonClearPixels = 0
    for i in stride(from: 0, to: pixelData.count, by: 4) {
        let b = pixelData[i]
        let g = pixelData[i + 1]
        let r = pixelData[i + 2]
        if r > 20 || g > 20 || b > 25 {
            nonClearPixels += 1
        }
    }
    report.rasterizationVerified = nonClearPixels > 50

    print("✅ 3D Offscreen Render Completed Successfully!")
    print(String(format: "⏱️ Total Render Time (%d frames): %.3f s", totalFrames, elapsed))
    print(String(format: "🚀 Average Frame Rate: %.2f FPS", fps))
    print(String(format: "⚡ Frame Latency: %.2f ms", latencyMs))
    print(String(format: "🔺 Triangle Throughput: %.2f M Triangles/sec", triPerSec / 1e6))
    print("🎨 Rasterization Verification: \(report.rasterizationVerified ? "✅ VERIFIED (Pixels correctly shaded)" : "⚠️ Not fully verified")")

} catch {
    print("❌ 3D Render error: \(error)")
    report.error = "\(error)"
}

try? FileManager.default.createDirectory(atPath: "results", withIntermediateDirectories: true)
let encoder = JSONEncoder()
encoder.outputFormatting = .prettyPrinted
if let data = try? encoder.encode(report) {
    try? data.write(to: URL(fileURLWithPath: "results/metal_3d_render_report.json"))
}
