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
#pragma once
#include "Falcor.h"

using namespace Falcor;

class StereoRendering : public Renderer
{
public:
    void onLoad(SampleCallbacks* pSample, RenderContext* pRenderContext) override;
    void onFrameRender(SampleCallbacks* pSample, RenderContext* pRenderContext, const Fbo::SharedPtr& pTargetFbo) override;
    void onResizeSwapChain(SampleCallbacks* pSample, uint32_t width, uint32_t height) override;
    bool onKeyEvent(SampleCallbacks* pSample, const KeyboardEvent& keyEvent) override;
    bool onMouseEvent(SampleCallbacks* pSample, const MouseEvent& mouseEvent) override;
    void onGuiRender(SampleCallbacks* pSample, Gui* pGui) override;
    void onPrePresent(RenderContext* pContext) override;
    void onPostPresent(RenderContext* pContext) override;

private:
    
    Scene::SharedPtr mpScene;
    SceneRenderer::SharedPtr mpSceneRenderer;

    GraphicsProgram::SharedPtr mpMonoSPSProgram = nullptr;
    GraphicsVars::SharedPtr mpMonoSPSVars = nullptr;

    GraphicsProgram::SharedPtr mpStereoProgram = nullptr;
    GraphicsVars::SharedPtr mpStereoVars = nullptr;

    GraphicsState::SharedPtr mpGraphicsState = nullptr;
    Sampler::SharedPtr mpTriLinearSampler;

    void loadScene();
    void loadScene(const std::string & filename);

    enum class RenderMode
    {
        Mono,
        Stereo,
        SinglePassStereo
    };

    bool mSPSSupported = false;
    RenderMode mRenderMode = RenderMode::Mono;
    Gui::DropdownList mSubmitModeList;

    void submitToScreen(RenderContext* pContext, Fbo::SharedPtr pTargetFbo);
    void initVR(Fbo* pTargetFbo);
    void blitTexture(RenderContext* pContext, Fbo* pTargetFbo, Texture::SharedPtr pTexture, uint32_t xStart);
    VrFbo::UniquePtr mpVrFbo;
    bool mShowStereoViews = true;
    void submitStereo(RenderContext* pContext, Fbo::SharedPtr pTargetFbo, bool singlePassStereo);
    void setRenderMode();

    static const std::string skDefaultScene;
};
