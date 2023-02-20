
import Rendering.PLT;


/** Types of samplable lights */
enum class SampledLightType {
    EnvMap   = 0,
    Emissive = 1,
    Analytic = 2,
};

/** Describes a light sample */
struct LightSample {
    float   pdf;        ///< Pdf with respect to solid angle at the shading point.
    float3  origin;     ///< Ray origin for visibility evaluation (offseted to avoid self-intersection).
    float   distance;   ///< Ray distance for visibility evaluation (shortened to avoid self-intersection).
    float3  dir;        ///< Ray direction for visibility evaluation (normalized).

    PLTBeam beam;       ///< Sourced beam

    uint    lightType;  ///< Light type this sample comes from (LightType casted to uint).

    RayDesc getVisibilityRay() {
        RayDesc ray;
        ray.Origin = origin;
        ray.Direction = dir;
        ray.TMin = .0f;
        ray.TMax = distance;
        return ray;
    }
};
