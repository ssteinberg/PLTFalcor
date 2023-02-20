
#include "Utils/Math/MathConstants.slangh"

import Scene.Scene;
import Utils.Math.MathHelpers;

struct float3pdv {
    float3 v, ddu, ddv;

    [mutating] void flip() {
        v = -v;
        ddu = -ddu;
        ddv = -ddv;
    }
};

struct float3kpdv {
    float3 v, ddu, ddv, ddl;
};

struct DifferentialShadingGeometry {
    float3pdv p;
    float3pdv n, s, t;
    float2 uv;
    float3 ngeo;

    [mutating] void makeOrthonormal() {
        const float ilu = 1.0f / length(p.ddu);
        p.ddu *= ilu;
        n.ddu *= ilu;
        const float dp = dot(p.ddu, p.ddv);
        const float3 pddvTmp = p.ddv - dp * p.ddu;
        const float3 nddvTmp = n.ddv - dp * n.ddu;
        const float ilv = 1.0f / length(pddvTmp);
        p.ddv = pddvTmp * ilv;
        n.ddv = nddvTmp * ilv;
    }

    /** Partial directives for direction vector from x on shading geometry to dst
     */
    float3pdv pdw(const float3 dst) {
        float3pdv w;

        w.v = dst - p.v;
        const float ilo = 1.f/length(w.v);
        w.v *= ilo;
        w.ddu = -ilo * (p.ddu - w.v*dot(w.v, p.ddu));
        w.ddv = -ilo * (p.ddv - w.v*dot(w.v, p.ddv));

        return w;
    }

    /** Transform vector from the local surface frame to world space.
        \param[in] v Vector in local space.
        \return Vector in world space.
    */
    float3 fromLocal(float3 v) {
        return s.v * v.x + t.v * v.y + n.v * v.z;
    }

    /** Transform vector from world space to the local surface frame.
        \param[in] v Vector in world space.
        \return Vector in local space.
    */
    float3 toLocal(float3 v) {
        return float3(dot(v, s.v), dot(v, t.v), dot(v, n.v));
    }

    /** Transform vector from the local surface frame to world space.
        \param[in] v Vector in local space.
        \return Vector in world space.
    */
    float3pdv fromLocal(float3pdv v) {
        float3pdv ret;
        ret.v   = fromLocal(v.v);
        ret.ddu = fromLocal(v.ddu);
        ret.ddv = fromLocal(v.ddv);
        return ret;
    }

    /** Transform vector from world space to the local surface frame.
        \param[in] v Vector in world space.
        \return Vector in local space.
    */
    float3pdv toLocal(float3pdv v) {
        float3pdv ret;
        ret.v   = toLocal(v.v);
        ret.ddu = toLocal(v.ddu);
        ret.ddv = toLocal(v.ddv);
        return ret;
    }
};

DifferentialShadingGeometry differentialShadingGeometry(const Scene scene, TriangleHit hit) {
    // Fetch relevant information from mesh
    float3 bary = hit.getBarycentricWeights();
    const uint3 vtxIndices = scene.getIndices(hit.instanceID, hit.primitiveIndex);
    StaticVertexData vertices[3] = { scene.getVertex(vtxIndices[0]), scene.getVertex(vtxIndices[1]), scene.getVertex(vtxIndices[2]) };

    float2 uv0 = vertices[0].texCrd;
    float2 uv1 = vertices[1].texCrd;
    float2 uv2 = vertices[2].texCrd;
    if (all(uv0 == 0.0f) && all(uv1 == .0f) && all(uv2 == .0f)) {
        // Resort to a very basic triangle parameterization
        uv1 = {1.0f, 0.0f};
        uv2 = {0.0f, 1.0f};
    }

    float3 p0 = vertices[0].position;
    float3 p1 = vertices[1].position;
    float3 p2 = vertices[2].position;

    float3 n0 = vertices[0].normal;
    float3 n1 = vertices[1].normal;
    float3 n2 = vertices[2].normal;

    DifferentialShadingGeometry sdg = {};

    sdg.ngeo = normalize(cross(p1 - p0, p2 - p0));

    // Interpolate primary quantities
    sdg.uv  = bary[0] * uv0 + bary[1] + uv1 + bary[2] * uv2;
    sdg.p.v = bary[0] *  p0 + bary[1] *  p1 + bary[2] *  p2;
    sdg.n.v = bary[0] *  n0 + bary[1] *  n1 + bary[2] *  n2;
    float il = 1.0f / length(sdg.n.v);
    sdg.n.v *= il;

    // Compute partial derivatives
    sdg.p.ddu = perp_stark(sdg.n.v);
    sdg.p.ddv = cross(sdg.n.v, sdg.p.ddu);
    sdg.n.ddu = {};
    sdg.n.ddv = {};

    float2 duv0 = uv1 - uv0;
    float2 duv1 = uv2 - uv0;
    float3  dp0 =  p1 -  p0;
    float3  dp1 =  p2 -  p0;

    sdg.n.ddu = (n1 - n0) * il;
    sdg.n.ddv = (n2 - n0) * il;
    sdg.n.ddu -= sdg.n.v * dot(sdg.n.v, sdg.n.ddu);
    sdg.n.ddv -= sdg.n.v * dot(sdg.n.v, sdg.n.ddv);

    float det = duv0.x * duv1.y - duv0.y * duv1.x;
    if (abs(det) > FLT_EPSILON) {
        float invDet = 1.0f / det;
        sdg.p.ddu = ( duv1.y * dp0 - duv0.y * dp1) * invDet;
        sdg.p.ddv = (-duv1.x * dp0 + duv0.x * dp1) * invDet;

        float3 nddu = ( duv1.y * sdg.n.ddu - duv0.y * sdg.n.ddv) * invDet;
        float3 nddv = (-duv1.x * sdg.n.ddu + duv0.x * sdg.n.ddv) * invDet;
        sdg.n.ddu = nddu;
        sdg.n.ddv = nddv;
    } else {
        sdg.n.ddu = float3(0.0f);
        sdg.n.ddv = float3(0.0f);
    }

    // Initialize shading frame
    sdg.s.v = sdg.p.ddu - sdg.n.v * dot(sdg.n.v, sdg.p.ddu);
    float ils = 1.0f / length(sdg.s.v);
    sdg.s.v *= ils;
    if (all(sdg.p.ddu == 0.0f)) {
        sdg.s.v = perp_stark(sdg.n.v);
        ils = 1.0f;
    }
    sdg.t.v = cross(sdg.n.v, sdg.s.v);

    sdg.s.ddu = ils * (-sdg.n.ddu * dot(sdg.n.v, sdg.p.ddu) - sdg.n.v * dot(sdg.n.ddu, sdg.p.ddu));
    sdg.s.ddv = ils * (-sdg.n.ddv * dot(sdg.n.v, sdg.p.ddu) - sdg.n.v * dot(sdg.n.ddv, sdg.p.ddu));
    sdg.s.ddu -= sdg.s.v * dot(sdg.s.ddu, sdg.s.v);
    sdg.s.ddv -= sdg.s.v * dot(sdg.s.ddv, sdg.s.v);

    sdg.t.ddu = cross(sdg.n.ddu, sdg.s.v) + cross(sdg.n.v, sdg.s.ddu);
    sdg.t.ddv = cross(sdg.n.ddv, sdg.s.v) + cross(sdg.n.v, sdg.s.ddv);

    return sdg;
}

float3kpdv reflectDerivatives(float3pdv wi, float3pdv n) {
    const float wn = dot(wi.v, n.v);
    const float dwdun = dot(wi.ddu, n.v);
    const float dwdvn = dot(wi.ddv, n.v);
    const float dnduw = dot(n.ddu, wi.v);
    const float dndvw = dot(n.ddv, wi.v);

    float3kpdv ret;
    ret.v   = 2.f * wn * n.v - wi.v;
    ret.ddu = 2.f*((dwdun + dnduw) * n.v + wn * n.ddu) - wi.ddu;
    ret.ddv = 2.f*((dwdvn + dndvw) * n.v + wn * n.ddv) - wi.ddv;
    ret.ddl = .0f;
    return ret;
}

float3kpdv refractDerivatives(float3pdv wi, float3pdv n, float eta, float dEta_dLambda = .0f, float dInvEta_dLamda = .0f) {
    const float wn = dot(wi.v, n.v);

    eta = wn<.0f ? eta : 1.f / eta;
    const float dEdl = wn<.0f ? dEta_dLambda : dInvEta_dLamda;
    if (wn<.0f)
        n.flip();

    const float eta2 = sqr(eta);
    const float dwdun = dot(wi.ddu, n.v);
    const float dwdvn = dot(wi.ddv, n.v);
    const float dnduw = dot(n.ddu, wi.v);
    const float dndvw = dot(n.ddv, wi.v);

    const float root = sqrt(max(.0f, 1.f - eta2*(1.0f - sqr(wn))));
    if (root == .0f)
        return {};
    const float dRoot_dLambda = -(1.0f - sqr(wn)) * eta * dEdl / root;
    const float a = eta - eta2*wn/root;

    float3kpdv ret;
    ret.v   = -eta*(wi.v - n.v*wn) - n.v*root;
    ret.ddu = a*(dnduw+dwdun)*n.v + (eta*wn-root)*n.ddu - eta*wi.ddu;
    ret.ddv = a*(dndvw+dwdvn)*n.v + (eta*wn-root)*n.ddv - eta*wi.ddv;
    ret.ddl = -dEdl*(wi.v - n.v*wn) - n.v*dRoot_dLambda;

    return ret;
}
