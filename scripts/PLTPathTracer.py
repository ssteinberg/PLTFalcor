from falcor import *

def render_graph_PLTPT():
    g = RenderGraph("PLTPT")
    loadRenderPassLibrary("AccumulatePass.dll")
    loadRenderPassLibrary("GBuffer.dll")
    loadRenderPassLibrary("PLTPT.dll")
    loadRenderPassLibrary("ToneMapper.dll")
    loadRenderPassLibrary("OptixDenoiser.dll")
    # loadRenderPassLibrary("DLSSPass.dll")


    PLTPT = createPass("PLTPT")
    g.addPass(PLTPT, "PLTPT")

    GBufferRT = createPass("GBufferRT", {'samplePattern': SamplePattern.Halton, 'sampleCount': 16, 'useAlphaTest': True})
    g.addPass(GBufferRT, "GBufferRT")

    AccumulatePass = createPass("AccumulatePass", {'enabled': True, 'precisionMode': AccumulatePrecision.Double})
    g.addPass(AccumulatePass, "AccumulatePass")
    AlbedoAccumulatePass = createPass("AccumulatePass", {'enabled': True, 'precisionMode': AccumulatePrecision.Single})
    g.addPass(AlbedoAccumulatePass, "AlbedoAccumulatePass")
    NormalAccumulatePass = createPass("AccumulatePass", {'enabled': True, 'precisionMode': AccumulatePrecision.Single})
    g.addPass(NormalAccumulatePass, "NormalAccumulatePass")

    ToneMapper = createPass("ToneMapper", {'autoExposure': True, 'exposureCompensation': 0.0})
    g.addPass(ToneMapper, "ToneMapper")

    OptixDenoiser = createPass("OptixDenoiser", {'model': OptixDenoiserModel.HDR})
    g.addPass(OptixDenoiser, "OptixDenoiser")

    # DLSS = createPass("DLSSPass", {'enabled': True, 'profile': DLSSProfile.Balanced, 'motionVectorScale': DLSSMotionVectorScale.Relative, 'isHDR': True, 'sharpness': 0.0, 'exposure': 0.0})
    # g.addPass(DLSS, "DLSS")


    g.addEdge("PLTPT.color", "AccumulatePass.input")
    g.addEdge("PLTPT.albedo", "AlbedoAccumulatePass.input")
    g.addEdge("PLTPT.normal", "NormalAccumulatePass.input")

    g.addEdge("GBufferRT.vbuffer", "PLTPT.vbuffer")
    g.addEdge("GBufferRT.viewW", "PLTPT.viewW")

    # g.addEdge("GBufferRT.mvec", "DLSS.mvec")
    # g.addEdge("GBufferRT.linearZ", "DLSS.depth")
    # g.addEdge("AccumulatePass.output", "DLSS.color")

    g.addEdge("AccumulatePass.output", "OptixDenoiser.color")
    # g.addEdge("DLSS.output", "OptixDenoiser.color")
    g.addEdge("NormalAccumulatePass.output", "OptixDenoiser.normal")
    g.addEdge("AlbedoAccumulatePass.output", "OptixDenoiser.albedo")
    g.addEdge("OptixDenoiser.output", "ToneMapper.src")

    g.markOutput("ToneMapper.dst")
    g.markOutput("OptixDenoiser.output")


    return g


PLTPT = render_graph_PLTPT()
try: m.addGraph(PLTPT)
except NameError: None

m.frameCapture.outputDir = "./captures/"
