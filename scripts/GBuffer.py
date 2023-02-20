from falcor import *

def render_graph_GBuffer():
    g = RenderGraph("GBuffer")
    loadRenderPassLibrary("GBuffer.dll")
    
    GBufferPass = createPass("GBufferRT")
    g.addPass(GBufferPass, "GBufferRT")
    g.markOutput("GBufferRT.normW")
    g.markOutput("GBufferRT.faceNormalW")
    g.markOutput("GBufferRT.tangentW")
    g.markOutput("GBufferRT.texC")

    g.markOutput("GBufferRT.frameS")
    g.markOutput("GBufferRT.frameT")
    g.markOutput("GBufferRT.posU")
    g.markOutput("GBufferRT.posV")
    g.markOutput("GBufferRT.normU")
    g.markOutput("GBufferRT.normV")

    # loadRenderPassLibrary("AccumulatePass.dll")
    # AccumulatePass = createPass("AccumulatePass", {'enabled': True, 'precisionMode': AccumulatePrecision.Single})
    # g.addPass(AccumulatePass, "AccumulatePass")

    # g.addEdge("GBufferRT.frameS", "AccumulatePass.input")
    # g.markOutput("AccumulatePass.output")

    return g

GBufferGraph = render_graph_GBuffer()
try: m.addGraph(GBufferGraph)
except NameError: None
