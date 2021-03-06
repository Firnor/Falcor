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
#ifndef _FALCOR_HELPERS_SLANG_
#define _FALCOR_HELPERS_SLANG_
#include "HostDeviceData.h"

/*******************************************************************
    Spherical map sampling
*******************************************************************/
float2 dirToSphericalCrd(float3 direction)
{
    float3 p = normalize(direction);
    float2 uv;
    uv.x = (1 + atan2(-p.z, p.x) / M_PI) * 0.5;
    uv.y = acos(p.y) / M_PI;
    return uv;
}

float3 sphericalCrdToDir(float2 uv)
{
    float phi = M_PI * uv.y;
    float theta = M_PI2 * uv.x - (M_PI / 2.0f);

    float3 dir;
    dir.x = sin(phi) * sin(theta);
    dir.y = cos(phi);
    dir.z = sin(phi) * cos(theta);

    return normalize(dir);
}

/*******************************************************************
   	Random numbers based on Mersenne Twister
*******************************************************************/  
uint rand_init(uint val0, uint val1, uint backoff = 16)
{
    uint v0 = val0;
    uint v1 = val1;
    uint s0 = 0;

    for (uint n = 0; n < backoff; n++)
    {
        s0 += 0x9e3779b9;
        v0 += ((v1 << 4) + 0xa341316c) ^ (v1 + s0) ^ ((v1 >> 5) + 0xc8013ea4);
        v1 += ((v0 << 4) + 0xad90777d) ^ (v0 + s0) ^ ((v0 >> 5) + 0x7e95761e);
    }

    return v0;
}

float rand_next(inout uint s)
{
    uint LCG_A = 1664525u;
    uint LCG_C = 1013904223u;
    s = (LCG_A * s + LCG_C);
    return float(s & 0x00FFFFFF) / float(0x01000000);
}

/*******************************************************************
    Sample Patterns
*******************************************************************/

float radicalInverse(uint i)
{
    i = (i & 0x55555555) << 1 | (i & 0xAAAAAAAA) >> 1;
    i = (i & 0x33333333) << 2 | (i & 0xCCCCCCCC) >> 2;
    i = (i & 0x0F0F0F0F) << 4 | (i & 0xF0F0F0F0) >> 4;
    i = (i & 0x00FF00FF) << 8 | (i & 0xFF00FF00) >> 8;
    i = (i << 16) | (i >> 16);
    return float(i) * 2.3283064365386963e-10f;
}

float2 getHammersley(uint i, uint N)
{
    return float2(float(i) / float(N), radicalInverse(i));
}

float Halton(int b, uint i)
{
    float r = 0.0f;
    float f = 1.0f;
    while (i > 0)
    {
        f = f / float(b);
        r = r + f * float(i % b);
        i = uint(floor(float(i) / float(b)));
    }
    return r;
}

float2 Halton23(inout uint i)
{
    float2 r = float2(Halton(2, (int) i), Halton(3, (int) i));
    i++;
    return r;
}

float2 Halton23fixed(uint i)
{
    return float2(Halton(2, (int) i), Halton(3, (int) i));
}

// Utility function to get a vector perpendicular to an input vector 
//    (from "Efficient Construction of Perpendicular Vectors Without Branching")
float3 getPerpendicularStark(float3 u)
{
    float3 a = abs(u);
    uint xm = ((a.x - a.y) < 0 && (a.x - a.z) < 0) ? 1 : 0;
    uint ym = (a.y - a.z) < 0 ? (1 ^ xm) : 0;
    uint zm = 1 ^ (xm | ym);
    return cross(u, float3(xm, ym, zm));
}

float3 getPerpendicularSimple(float3 u)
{
    float3 up = abs(u.z) < 0.999999f ? float3(0, 0, 1) : float3(1, 0, 0);
    return normalize(cross(up, u));
}

/** Get a cosine-weighted random vector centered around a specified normal direction.

    \param[in] u Uniformly distributed random numbers between 0 and 1
    \param[in] N Surface normal
    \param[in] T A vector perpendicular to N
*/
float3 getCosHemisphereSample(float2 u, float3 N, float3 T)
{
    float3 B = normalize(cross(N, T));

    float r = sqrt(u.x);
    float phi = u.y * M_PI2;

    float3 L = float3(r * cos(phi),
                    r * sin(phi),
                    sqrt(max(0.0f, 1.0f - u.x)));

    return normalize(T * L.x + B * L.y + N * L.z);
}

/** Get a GGX half vector / microfacet normal, sampled according to the GGX distribution
    When using this function to sample, the probability density is pdf = D * NdotH / (4 * HdotV)

    \param[in] u Uniformly distributed random numbers between 0 and 1
    \param[in] N Surface normal
    \param[in] roughness Roughness^2 of material
*/
float3 getGGXMicrofacet(float2 u, float3 N, float roughness)
{
    float a2 = roughness * roughness;

    float phi = M_PI2 * u.x;
    float cosTheta = sqrt(max(0, (1 - u.y)) / (1 + (a2 - 1) * u.y));
    float sinTheta = sqrt(max(0, 1 - cosTheta * cosTheta));

    // Tangent space H
    float3 tH;
    tH.x = sinTheta * cos(phi);
    tH.y = sinTheta * sin(phi);
    tH.z = cosTheta;

    float3 T = getPerpendicularStark(N);
    float3 B = normalize(cross(N, T));

    // World space H
    return normalize(T * tH.x + B * tH.y + N * tH.z);
}


float3 getUniformConeSample(float2 u, float3 N, float cosThetaMax)
{
    float cosTheta = (1.0f - u.x) + u.x * cosThetaMax;
    float sinTheta = sqrt(1.0f - cosTheta * cosTheta);
    float phi = u.y * 2.0 * M_PI;
    float3 T = getPerpendicularStark(N);
    float3 B = normalize(cross(N, T));
    float3 tH = float3(cos(phi) * sinTheta, sin(phi) * sinTheta, cosTheta);
    return normalize(T * tH.x + B * tH.y + N * tH.z);
}

float getUniformConePdf(float cosThetaMax)
{
    return 1.0f / (2.0f * M_PI * (1.0f - cosThetaMax));
}

float powerHeuristic(int nf, float fPdf, int ng, float gPdf)
{
    float f = nf * fPdf;
    float g = ng * gPdf;
    return (f * f) / (f * f + g * g);
}

/*******************************************************************
    Other
*******************************************************************/

bool intersectRaySphere(float3 rayPos, float3 rayDir, float3 spherePos, float sphereRadius, out float3 intersectionPos)
{
    float3 m = rayPos - spherePos;
    float b = dot(m, rayDir);
    float c = dot(m, m) - (sphereRadius * sphereRadius);

    // If ray origin is outside sphere (c > 0) and ray is pointing away from sphere (b > 0)
    // For now assume input always produces valid intersection
    // if(c > 0.0f && b > 0.0f) return false;

    float discr = b * b - c;
    // Negative discriminant means ray missed sphere
    // if(discr < 0.0f) return false;

    float t = -b - sqrt(discr);

    // t will be negative if origin is inside sphere, 
    // take the abs since we want the position on the sphere's surface
    intersectionPos = rayPos + abs(t) * rayDir;

    return true;
}

float4 applyAmbientOcclusion(float4 color, Texture2D aoTex, SamplerState s, float2 texC)
{
    float aoFactor = aoTex.SampleLevel(s, texC, 0).r;
    return float4(color.rgb * aoFactor, color.a);
}

float getMetallic(float diffuse, float spec)
{
    // This is based on the way that UE4 and Substance Painter 2 converts base+metallness+specular level to diffuse/spec colors
    // We don't have the specular level information, so the assumption is that it is equal to 0.5 (based on the UE4 documentation)
    float a = 0.04;
    float b = spec + diffuse - 0.08;
    float c = 0.04 - spec;
    float root = sqrt(b*b - 0.16*c);
    float m = (root - b) * 12.5;
    return m;
}

/*******************************************************************
                    Alpha test
*******************************************************************/
// Evaluate alpha test and return true if point should be discarded
bool evalBasicAlphaTest(float alpha, float threshold)
{
    return alpha < threshold;
}

/*******************************************************************
                    Hashed Alpha Test
*******************************************************************/
// Evaluate alpha test and return true if point should be discarded
bool evalHashedAlphaTest(float alpha, float materialThreshold, float hashedThreshold)
{
    float compareTo = hashedThreshold <= 0 ? materialThreshold : saturate(hashedThreshold);
    return alpha < compareTo;
}

float sineHash(float2 p)
{
    return frac(1e4 * sin(17.0 * p.x + p.y * 0.1) * (0.1 + abs(sin(p.y * 13.0 + p.x))));
}

float sineHash3D(float3 p)
{
    return sineHash(float2(sineHash(p.xy), p.z));
}

float calculateHashedAlpha(float3 hashInputCoord, float hashScale, bool useAnisotropy)
{
    // Provide a decent default to our alpha threshold
    float alphaCompare = 0.5f;

    if (useAnisotropy)
    {
        //////  Anisotropic version

        // Find the discretized derivatives of our coordinates
        float3 anisoDeriv = max(abs(ddx(hashInputCoord)), abs(ddy(hashInputCoord)));
        float3 anisoScales = float3(0.707f / (hashScale * anisoDeriv.x),
                                0.707f / (hashScale * anisoDeriv.y),
                                0.707f / (hashScale * anisoDeriv.z));
        // Find log-discretized noise scales
        float3 scaleFlr = float3(exp2(floor(log2(anisoScales.x))),
                                exp2(floor(log2(anisoScales.y))),
                                exp2(floor(log2(anisoScales.z))));
        float3 scaleCeil = float3(exp2(ceil(log2(anisoScales.x))),
                                exp2(ceil(log2(anisoScales.y))),
                                exp2(ceil(log2(anisoScales.z))));

        // Compute alpha thresholds at our two noise scales
        float2 alpha = float2(sineHash3D(floor(scaleFlr * hashInputCoord)),
                            sineHash3D(floor(scaleCeil * hashInputCoord)));

        // Factor to linearly interpolate with
        float3 fractLoc = float3(frac(log2(anisoScales.x)),
                                frac(log2(anisoScales.y)),
                                frac(log2(anisoScales.z)));

        float2 toCorners = float2(length(fractLoc),
                                length(float3(1.0f, 1.0f, 1.0f) - fractLoc));
        float lerpFactor = toCorners.x / (toCorners.x + toCorners.y);

        // Interpolate alpha threshold from noise at two scales
        float x = (1 - lerpFactor) * alpha.x + lerpFactor * alpha.y;

        // Pass into CDF to compute uniformly distrib threshold
        float a = min(lerpFactor, 1 - lerpFactor);
        float3 cases = float3(x * x / (2 * a * (1 - a)), (x - 0.5 * a) / (1 - a), 1.0 - ((1 - x) * (1 - x) / (2 * a * (1 - a))));

        // Find our final, uniformly distributed alpha threshold
        alphaCompare = (x < (1 - a)) ? ((x < a) ? cases.x : cases.y) : cases.z;
        alphaCompare = clamp(alphaCompare, 1.0e-6, 1.0f);
    }
    else
    {
        //////  Isotropic version

        // Find the discretized derivatives of our coordinates
        float maxDeriv = max(length(ddx(hashInputCoord)), length(ddy(hashInputCoord)));
        float pixScale = 1.0 / (hashScale * maxDeriv);

        // Find two nearest log-discretized noise scales
        float2 pixScales = float2(exp2(floor(log2(pixScale))), exp2(ceil(log2(pixScale))));

        // Compute alpha thresholds at our two noise scales
        float2 alpha = float2(sineHash3D(floor(pixScales.x * hashInputCoord)), sineHash3D(floor(pixScales.y * hashInputCoord)));

        // Factor to interpolate lerp with
        float lerpFactor = frac(log2(pixScale));

        // Interpolate alpha threshold from noise at two scales
        float x = (1 - lerpFactor) * alpha.x + lerpFactor * alpha.y;
        float a = min(lerpFactor, 1 - lerpFactor);

        // Pass into CDF to compute uniformly distrib threshold
        float3 cases = float3(x * x / (2 * a * (1 - a)), (x - 0.5 * a) / (1 - a), 1.0 - ((1 - x) * (1 - x) / (2 * a * (1 - a))));

        // Find our final, uniformly distributed alpha threshold
        alphaCompare = (x < (1 - a)) ? ((x < a) ? cases.x : cases.y) : cases.z;
        alphaCompare = clamp(alphaCompare, 1e-6f, 1.0f);
    }

    return alphaCompare;
}

/*******************************************************************
    Alpha test
*******************************************************************/    

/** Evaluates alpha test, returning true if pixel should be discarded.
    \todo calculateHashedAlpha requires ddx/ddy, so cannot be used in RT mode.
*/
bool evalAlphaTest(uint matFlags, float alpha, float threshold, float3 posW)
{
    if (EXTRACT_ALPHA_MODE(matFlags) != AlphaModeMask) return false;

    float hashedAlphaScale = 1.0f;
#ifdef _HASHED_ALPHA_SCALE
    hashedAlphaScale = _HASHED_ALPHA_SCALE;
#endif

    /* Evaluate alpha test material modifier */
#ifdef _DEFAULT_ALPHA_TEST
    return evalBasicAlphaTest(alpha, threshold);
#elif defined(_HASHED_ALPHA_TEST_ANISOTROPIC)
    float hashedThreshold = calculateHashedAlpha(posW, hashedAlphaScale, true);
    return evalHashedAlphaTest(alpha, threshold, hashedThreshold);
#else
    // Default to isotropic hashed alpha test
    float hashedThreshold = calculateHashedAlpha(posW, hashedAlphaScale, false);
    return evalHashedAlphaTest(alpha, threshold, hashedThreshold);
#endif
}


/*******************************************************************
   	Packing stuff
*******************************************************************/  

float2 TEMP_unpackSnorm2x16(uint val)
{
    uint l = (val) & 0xffff;
    uint h = (val >> 16) & 0xffff;

    return float2(f16tof32(l), f16tof32(h));
}

uint TEMP_packSnorm2x16(float2 val)
{
    uint l = asuint(f32tof16(val.x));
    uint h = asuint(f32tof16(val.y));

    return (h << 16) + l;
}

float2 sign_not_zero(float2 v)
{
    return step(0.0, v) * 2.0 - (float2) (1.0);
}

/** Encodes a float3 direction to an octahedral representation in a 32-bit uint
*/
uint dir_to_oct(float3 normal)
{
    float2 p = normal.xy * (1.0 / dot(abs(normal), float3(1.0f, 1.0f, 1.0f)));
    float2 e = normal.z > 0.0
		? p
		: (1.0 - abs(p.yx)) * sign_not_zero(p);
    return TEMP_packSnorm2x16(e);
}

/** Decodes a 32-bit uint octahedral encoding back to a float3 direction 
*/
float3 oct_to_dir(uint octo)
{
    float2 e = TEMP_unpackSnorm2x16(octo);
    float3 v = float3(e, 1.0 - abs(e.x) - abs(e.y));
    if (v.z < 0.0)
        v.xy = (1.0 - abs(v.yx)) * sign_not_zero(v.xy);
    return normalize(v);
}



float lum(float3 color)
{
    return dot(color, float3(0.2126f, 0.7152f, 0.0722f));
}

// https://en.wikipedia.org/wiki/Lightness
// https://en.wikipedia.org/wiki/CIE_1931_color_space
// https://en.wikipedia.org/wiki/Standard_illuminant
// https://stackoverflow.com/questions/596216/formula-to-determine-brightness-of-rgb-color
float lightness(float3 color)
{
    //return lum(color);
    float Y = lum(color);
    if (Y <= (216.0f / 24389.0f))
    { // The CIE standard states 0.008856 but 216/24389 is the intent for 0.008856451679036
        return Y * (24389.0f / 27.0f) / 100.0f; // The CIE standard states 903.3, but 24389/27 is the intent, making 903.296296296296296
    }
    else
    {
        return (pow(Y, (1.0f / 3.0f)) * 116.0f - 16.0f) / 100.0f;
    }
}

#endif //_FALCOR_HELPERS_SLANG_
