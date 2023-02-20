add_plugin(PLTPT)

target_sources(PLTPT PRIVATE
    PLTPT.cpp
    PLTPT.h

    pltpt.slangh
    pltpt_sample.rt.slang
    pltpt_solve.rt.slang
    Path.slang
    pltpt_constants.slangh

    LightSampling.slangh
    ShadowRays.slangh
    Manifolds.slangh

    pltpt_debug.slangh
    DebugViewType.slangh
    ColourCoding.slang
)

target_copy_shaders(PLTPT RenderPasses/PLTPT)

target_source_group(PLTPT "RenderPasses")
