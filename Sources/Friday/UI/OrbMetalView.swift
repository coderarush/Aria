import SwiftUI
import MetalKit
import simd

/// Procedural orb glow rendered with a Metal fragment shader. The shader source
/// is compiled at runtime (no .metal build step needed under SwiftPM), so the
/// orb gets real per-pixel animated glow/pulse/plasma driven by live uniforms:
/// time, mic audio level, tint color, and a pulse amount per state.
struct OrbMetalView: NSViewRepresentable {
    var color: Color
    var audioLevel: Float
    var pulse: Float      // 0…1 extra intensity (listening breathes, thinking swirls)

    func makeCoordinator() -> Renderer { Renderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.delegate = context.coordinator
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.framebufferOnly = false
        view.layer?.isOpaque = false
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 60
        context.coordinator.configure(view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.color = simd_float4(color.components)
        context.coordinator.audioLevel = audioLevel
        context.coordinator.pulse = pulse
    }

    /// Renders a fullscreen quad with the orb glow fragment shader.
    final class Renderer: NSObject, MTKViewDelegate {
        var color = simd_float4(0.36, 0.62, 1.0, 1.0)
        var audioLevel: Float = 0
        var pulse: Float = 0

        private var device: MTLDevice?
        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var startTime = CFAbsoluteTimeGetCurrent()

        /// Uniforms — layout must match `Uniforms` in the shader source below.
        private struct Uniforms {
            var time: Float
            var audioLevel: Float
            var pulse: Float
            var _pad: Float
            var color: simd_float4
            var resolution: simd_float2
            var _pad2: simd_float2
        }

        func configure(_ view: MTKView) {
            guard let device = view.device else { return }
            self.device = device
            self.queue = device.makeCommandQueue()
            buildPipeline(view)
        }

        private func buildPipeline(_ view: MTKView) {
            guard let device else { return }
            do {
                let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = library.makeFunction(name: "orb_vertex")
                desc.fragmentFunction = library.makeFunction(name: "orb_fragment")
                let attachment = desc.colorAttachments[0]
                attachment?.pixelFormat = view.colorPixelFormat
                // Premultiplied alpha blend so the transparent panel shows through.
                attachment?.isBlendingEnabled = true
                attachment?.rgbBlendOperation = .add
                attachment?.alphaBlendOperation = .add
                attachment?.sourceRGBBlendFactor = .one
                attachment?.sourceAlphaBlendFactor = .one
                attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                pipeline = try device.makeRenderPipelineState(descriptor: desc)
            } catch {
                Log.ui.error("Orb shader compile failed: \(error.localizedDescription)")
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let pipeline, let queue,
                  let drawable = view.currentDrawable,
                  let pass = view.currentRenderPassDescriptor,
                  let buffer = queue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }

            var uniforms = Uniforms(
                time: Float(CFAbsoluteTimeGetCurrent() - startTime),
                audioLevel: audioLevel,
                pulse: pulse,
                _pad: 0,
                color: color,
                resolution: simd_float2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                _pad2: .zero)

            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }

        // MARK: Shader source (MSL, compiled at runtime)

        static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct Uniforms {
            float time;
            float audioLevel;
            float pulse;
            float _pad;
            float4 color;
            float2 resolution;
            float2 _pad2;
        };

        struct VOut { float4 pos [[position]]; float2 uv; };

        // Fullscreen triangle.
        vertex VOut orb_vertex(uint vid [[vertex_id]]) {
            float2 p[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
            VOut o;
            o.pos = float4(p[vid], 0.0, 1.0);
            o.uv = (p[vid] * 0.5) + 0.5;
            return o;
        }

        // Cheap value noise for a little plasma "life".
        float hash(float2 p) {
            return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
        }
        float noise(float2 p) {
            float2 i = floor(p), f = fract(p);
            float2 u = f * f * (3.0 - 2.0 * f);
            return mix(mix(hash(i + float2(0,0)), hash(i + float2(1,0)), u.x),
                       mix(hash(i + float2(0,1)), hash(i + float2(1,1)), u.x), u.y);
        }

        fragment float4 orb_fragment(VOut in [[stage_in]], constant Uniforms& U [[buffer(0)]]) {
            // Centered, aspect-corrected coordinates in [-1,1].
            float2 uv = in.uv * 2.0 - 1.0;
            float aspect = U.resolution.x / max(U.resolution.y, 1.0);
            uv.x *= aspect;

            float dist = length(uv);
            float t = U.time;

            // Breathing radius driven by pulse + audio.
            float breathe = 0.55 + 0.05 * sin(t * 2.0) * U.pulse + U.audioLevel * 0.12;

            // Core orb: smooth disc.
            float core = smoothstep(breathe, breathe - 0.18, dist);

            // Outer glow halo.
            float glow = exp(-3.2 * max(dist - breathe * 0.4, 0.0));

            // Swirling plasma inside the orb for life.
            float angle = atan2(uv.y, uv.x);
            float swirl = noise(float2(angle * 1.5 + t * 0.6, dist * 4.0 - t * 0.4));
            float plasma = 0.5 + 0.5 * swirl;

            // Rim highlight.
            float rim = smoothstep(breathe, breathe - 0.04, dist) - smoothstep(breathe - 0.04, breathe - 0.1, dist);

            float3 base = U.color.rgb;
            float3 col = base * (0.45 + 0.55 * plasma) * core;
            col += base * glow * 0.6;
            col += float3(1.0) * rim * 0.5;

            float alpha = clamp(core + glow * 0.5 + rim * 0.5, 0.0, 1.0);
            return float4(col * alpha, alpha);   // premultiplied
        }
        """
    }
}

// MARK: Color → simd helper

extension Color {
    /// RGBA components in 0…1 (best-effort via NSColor sRGB conversion).
    var components: (Float, Float, Float, Float) {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return (Float(ns.redComponent), Float(ns.greenComponent),
                Float(ns.blueComponent), Float(ns.alphaComponent))
    }
}

extension simd_float4 {
    init(_ c: (Float, Float, Float, Float)) { self.init(c.0, c.1, c.2, c.3) }
}
