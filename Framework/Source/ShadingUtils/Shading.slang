/***************************************************************************
# Copyright (c) 2015, NVIDIA CORPORATION. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#  * Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#  * Neither the name of NVIDIA CORPORATION nor the names of its
#    contributors may be used to endorse or promote products derived
#    from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS ``AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
# OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
***************************************************************************/
#ifndef _FALCOR_SHADING_SLANG_
#define _FALCOR_SHADING_SLANG_
#include "HostDeviceData.h"
__exported __import DefaultVS;
__exported __import ShaderCommon;
__import Lights;
__import BRDF;
__import Helpers;


/** Interface for texture sampling techniques.
    Types implementing this interface support sampling using different LOD computation techniques
*/
interface ITextureSampler
{
    /** Sample from a 2D texture using the level of detail computed by this method
    */
    float4 sampleTexture(Texture2D t, SamplerState s, float2 uv);
};

/** Texture sampling using implicit fragment-quad finite differences
*/
struct ImplicitLodTextureSampler : ITextureSampler
{
    float4 sampleTexture(Texture2D t, SamplerState s, float2 uv)
    {
        return t.Sample(s, uv);
    }
};

/** Texture sampling using an explicit scalar level of detail
*/
struct ExplicitLodTextureSampler : ITextureSampler
{
    float lod; ///< The explicit level of detail to use

    float4 sampleTexture(Texture2D t, SamplerState s, float2 uv)
    {
        return t.SampleLevel(s, uv, lod);
    }
};

/** Texture sampling using explicit screen-space gradients
*/
struct ExplicitGradientTextureSampler : ITextureSampler
{
    float2 gradX; ///< Gradient of texture coordinate in the screen-space X direction
    float2 gradY; ///< Gradient of texture coordiante in teh screen-space Y direction

    float4 sampleTexture(Texture2D t, SamplerState s, float2 uv)
    {
        return t.SampleGrad(s, uv, gradX, gradY);
    }
};


/** Load data from a texture

    The `lod` parameter represents the method to use for computing
    texture level of detail, and must implement the `ITextureSampler` interface.
*/
float4 sampleTexture<L:ITextureSampler>(Texture2D t, SamplerState s, float2 uv, float4 factor, uint mode, L lod)
{
    if(mode == ChannelTypeUnused) return 0;
    if(mode == ChannelTypeConst) return factor;
    // else mode == ChannelTypeTexture
    return lod.sampleTexture(t, s, uv);
}

/** Shading result struct
*/
struct ShadingResult
{
    float3 diffuseBrdf;             // The result of the diffuse BRDF
    float3 specularBrdf;            // The result of the specular BRDF
    float3 diffuse;                 // The diffuse component of the result
    float3 specular;                // The specular component of the result
    float4 color;                   // The final color. Alpha holds the opacity valua
};

/** Convert RGB to normal
*/
float3 RgbToNormal(float3 rgb)
{
    float3 n = rgb * 2 - 1;
    return normalize(n);
}

/** Convert RG to normal
*/
float3 RgToNormal(float2 rg)
{
    float3 n;
    n.xy = rg * 2 - 1;

    // Saturate because error from BC5 can break the sqrt
    n.z = saturate(dot(rg, rg)); // z = r*r + g*g
    n.z = sqrt(1 - n.z);
    return normalize(n);
}

/** Apply normal map

    The `lod` parameter represents the method to use for computing
    texture level of detail, and must implement the `ITextureSampler` interface.
*/
void applyNormalMap<L:ITextureSampler>(MaterialData m, inout ShadingData sd, L lod)
{
    uint mapType = EXTRACT_NORMAL_MAP_TYPE(m.flags);
    if(mapType == NormalMapUnused) return;

    float3 mapN = lod.sampleTexture(m.resources.normalMap, m.resources.samplerState, sd.uv).xyz;
    switch(mapType)
    {
    case NormalMapRGB:
        mapN = RgbToNormal(mapN);
        break;
    case NormalMapRG:
        mapN = RgToNormal(mapN.rg);
        break;
    default:
        return;
    }

    // Apply the transformation. Everything is normalized already
    sd.N = sd.T * mapN.x + sd.B * mapN.y + sd.N * mapN.z;
    sd.B = normalize(sd.B - sd.N * dot(sd.B, sd.N));
    sd.T = normalize(cross(sd.B, sd.N));
}

/** Internal implementation of `alphaTest`.
    The `lod` parameter represents the method to use for computing texture level of detail, and must implement the `ITextureSampler` interface.
    \return True if hit should be ignored/discarded.
*/
bool _alphaTest<L:ITextureSampler>(VertexOut v, MaterialData m, L lod)
{
    if (EXTRACT_ALPHA_MODE(m.flags) != AlphaModeMask) return false;

    // Load opacity from the alpha channel of the diffuse texture.
    float alpha = sampleTexture(m.resources.baseColor, m.resources.samplerState, v.texC, m.baseColor, EXTRACT_DIFFUSE_TYPE(m.flags), lod).a;
    return evalAlphaTest(m.flags, alpha, m.alphaThreshold, v.posW);
}

/** Apply alpha test and return the result.
    This version samples alpha using implicit gradients and only works in pixel shaders.
    \return True if hit should be ignored/discarded.
*/
bool alphaTest(VertexOut v, MaterialData m)
{
    ImplicitLodTextureSampler lod = {};
    return _alphaTest(v, m, lod);
}

/** Apply alpha test and return the result.
    This version samples alpha at a level of detail specified by the `lod` parameter.
    \return True if hit should be ignored/discarded.
*/
bool alphaTest(VertexOut v, MaterialData m, float lod)
{
    ExplicitLodTextureSampler explicitLOD = { lod };
    return _alphaTest(v, m, explicitLOD);
}

/** Apply alpha test and return the result.
    This version samples alpha at a level of detail computed from screen-space gradients `gradX` and `gradY`.
    \return True if hit should be ignored/discarded.
*/
bool alphaTest(VertexOut v, MaterialData m, float2 gradX, float2 gradY)
{
    ExplicitGradientTextureSampler lod = { gradX, gradY };
    return _alphaTest(v, m, lod);
}

void applyAlphaTest(uint matFlags, float alpha, float threshold, float3 posW)
{
#ifndef _MS_DISABLE_ALPHA_TEST
    if (evalAlphaTest(matFlags, alpha, threshold, posW))
        discard;
#endif
}

ShadingData initShadingData()
{
    ShadingData sd;
    sd.posW = 0;
    sd.V = 0;
    sd.N = 0;
    sd.T = 0;
    sd.B = 0;
    sd.uv = 0;
    sd.NdotV = 0;
    sd.diffuse = 0;
    sd.opacity = 1;
    sd.specular = 0;
    sd.linearRoughness = 0;
    sd.roughness = 0;
    sd.emissive = 0;
    sd.occlusion = 1;
    sd.lightMap = 0;
    sd.height = 0;
    sd.IoR = 0;
    sd.doubleSidedMaterial = false;
    sd.materialID = 0;

    return sd;
}

/** Internal implementation of `prepareShadingData`

The `lod` parameter represents the method to use for computing
texture level of detail, and must implement the `ITextureSampler` interface.
*/
ShadingData _prepareShadingData<L:ITextureSampler>(VertexOut v, MaterialData m, float3 camPosW, L lod)
{
    ShadingData sd = initShadingData();

#ifdef _MS_STATIC_MATERIAL_FLAGS
    m.flags = _MS_STATIC_MATERIAL_FLAGS;
#endif

    // Sample the diffuse texture and apply the alpha test
    float4 baseColor = sampleTexture(m.resources.baseColor, m.resources.samplerState, v.texC, m.baseColor, EXTRACT_DIFFUSE_TYPE(m.flags), lod);
    sd.opacity = m.baseColor.a;
    applyAlphaTest(m.flags, baseColor.a, m.alphaThreshold, v.posW);

    sd.posW = v.posW;
    sd.uv = v.texC;
    sd.V = normalize(camPosW - v.posW);
    sd.N = normalize(v.normalW);

    sd.B = normalize(v.bitangentW - sd.N * (dot(v.bitangentW, sd.N)));
    sd.T = normalize(cross(sd.B, sd.N));

    if(true) {
        // Sample the spec texture
        //bool sampleOcclusion = EXTRACT_OCCLUSION_MAP(m.flags) > 0;
        float4 spec = sampleTexture(m.resources.specular, m.resources.samplerState, v.texC, m.specular, EXTRACT_SPECULAR_TYPE(m.flags), lod);

        // R - Material ID; G - Roughness; B - Metalness
        sd.diffuse = max(0.001f, baseColor.rgb);
        sd.linearRoughness = spec.g;
        sd.metalness = spec.b;
        sd.materialID = int(spec.r * 255.0f);
        if(sd.materialID > 2) sd.materialID = 0; // default to diffuse
        if(sd.metalness > 0) sd.materialID = 1; // if metalness is set, use GGX

        sd.linearRoughness = max(0.08, sd.linearRoughness); // Clamp the roughness so that the BRDF won't explode
        sd.roughness = sd.linearRoughness * sd.linearRoughness;
        //sd.emissive = sampleTexture(m.resources.emissive, m.resources.samplerState, v.texC, float4(m.emissive, 1), EXTRACT_EMISSIVE_TYPE(m.flags), lod).rgb;
        //sd.IoR = m.IoR;
        sd.doubleSidedMaterial = EXTRACT_DOUBLE_SIDED(m.flags);

        /*
        #define channel_type(extract) (extract(m.flags) ? ChannelTypeTexture : ChannelTypeUnused)
            sd.lightMap = sampleTexture(m.resources.lightMap, m.resources.samplerState, v.lightmapC, 1, channel_type(EXTRACT_LIGHT_MAP), lod).rgb;
            sd.height = sampleTexture(m.resources.heightMap, m.resources.samplerState, v.texC, 1, channel_type(EXTRACT_HEIGHT_MAP), lod).xy;
            sd.height = sd.height * m.heightScaleOffset.x + m.heightScaleOffset.y;
        #undef channel_type
        */

    } else {

        // TEST
        sd.diffuse = float3(0.8f);
        sd.materialID = 0;
        sd.linearRoughness = 0.8f;
        sd.metalness = 0;
        sd.roughness = sd.linearRoughness * sd.linearRoughness;
    }

    sd.NdotV = dot(sd.N, sd.V);

    // Flip the normal if it's backfacing
    if(sd.NdotV <= 0 && sd.doubleSidedMaterial)
    {
        sd.N = -sd.N;
        sd.NdotV = -sd.NdotV;
    }

    return sd;
}

/** Prepare the hit-point data
*/
ShadingData prepareShadingData(VertexOut v, MaterialData m, float3 camPosW)
{
    ImplicitLodTextureSampler lod = { };
    return _prepareShadingData(v, m, camPosW, lod);
}

/** Prepare the hit-point data

The `lod` parameter represents the level of detail to use for all material
texture fetches.
*/
ShadingData prepareShadingData(VertexOut v, MaterialData m, float3 camPosW, float lod)
{
    ExplicitLodTextureSampler explicitLOD = { lod };
    return _prepareShadingData(v, m, camPosW, explicitLOD);
}

/** Prepare the hit-point data

The `gradX` and `gradY` parameters should be the screen-space gradients of
`v.texC` with respect to screen-space X and Y, respectively. These gradient
values will be used for all material texture fetches.
*/
ShadingData prepareShadingData(VertexOut v, MaterialData m, float3 camPosW, float2 gradX, float2 gradY)
{
    ExplicitGradientTextureSampler lod = { gradX, gradY };
    return _prepareShadingData(v, m, camPosW, lod);
}

ShadingResult initShadingResult()
{
    ShadingResult sr;
    sr.diffuse = 0;
    sr.color.rgb = 0;
    sr.color.a = 1;
    sr.specular = 0;
    sr.diffuseBrdf = 0;
    sr.specularBrdf = 0;
    return sr;
}

ShadingResult evalMaterial(ShadingData sd, LightData light, float shadowFactor)
{
    ShadingResult sr = initShadingResult();
    LightSample ls = evalLight(light, sd);

    // If the light doesn't hit the surface or we are viewing the surface from the back, return
    if(ls.NdotL <= 0) return sr;
    sd.NdotV = saturate(sd.NdotV);

    // Calculate the diffuse term
    sr.diffuseBrdf = saturate(evalDiffuseBrdf(sd, ls));
    sr.diffuse = ls.diffuse * sr.diffuseBrdf * ls.NdotL;
    //sr.diffuse = ls.diffuse;
    sr.color.rgb = sr.diffuse;
    sr.color.a = sd.opacity;

    // Calculate the specular term
    float prob = 0.0f;
    sr.specularBrdf = saturate(evalGGXBrdf(sd, ls, prob));
    sr.specular = ls.specular * sr.specularBrdf * ls.NdotL;
    //sr.specular = ls.specular * ls.NdotL;
    sr.color.rgb += sr.specular;

    // Apply the shadow factor
    sr.color.rgb *= shadowFactor;

    return sr;
};

ShadingResult evalMaterial(ShadingData sd, LightProbeData probe)
{
    ShadingResult sr = initShadingResult();
    LightSample ls = evalLightProbe(probe, sd);

    sr.diffuse = ls.diffuse;
    sr.color.rgb = sr.diffuse;
    sr.specular = ls.specular;
    sr.color.rgb += sr.specular;
    return sr;
}

#endif	// _FALCOR_SHADING_SLANG_
