from falcor import *

def render_graph_PLTPT():
    g = RenderGraph("PLTPT")
    loadRenderPassLibrary("AccumulatePass.dll")
    loadRenderPassLibrary("GBuffer.dll")
    loadRenderPassLibrary("PLTPT.dll")
    loadRenderPassLibrary("ToneMapper.dll")


    PLTPT = createPass("PLTPT")
    g.addPass(PLTPT, "PLTPT")

    GBufferRT = createPass("GBufferRT", {'samplePattern': SamplePattern.Halton, 'sampleCount': 16, 'useAlphaTest': True})
    g.addPass(GBufferRT, "GBufferRT")

    AccumulatePass = createPass("AccumulatePass", {'enabled': True, 'precisionMode': AccumulatePrecision.Double})
    g.addPass(AccumulatePass, "AccumulatePass")

    ToneMapper = createPass("ToneMapper", {'autoExposure': True, 'exposureCompensation': 0.0})
    g.addPass(ToneMapper, "ToneMapper")

    g.addEdge("PLTPT.color", "AccumulatePass.input")

    g.addEdge("GBufferRT.vbuffer", "PLTPT.vbuffer")
    g.addEdge("GBufferRT.viewW", "PLTPT.viewW")

    g.addEdge("AccumulatePass.output", "ToneMapper.src")

    g.markOutput("ToneMapper.dst")


    return g


PLTPT = render_graph_PLTPT()
try: m.addGraph(PLTPT)
except NameError: None

m.frameCapture.outputDir = "./captures/"
