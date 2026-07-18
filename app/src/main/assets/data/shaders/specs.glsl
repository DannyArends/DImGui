// DImGui - Specialization Constant Definitions
// Copyright Danny Arends 2021
// Distributed under the GNU General Public License, Version 3
// See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html

#ifndef SPECS_GLSL
#define SPECS_GLSL

// Compile time constants
layout(constant_id = 0) const uint TOPOLOGY = 3u;
layout(constant_id = 1) const bool ALPHA_TEST = false;
layout(constant_id = 2) const bool INSTANCED = false;
layout(constant_id = 3) const uint GRID_X = 16u;
layout(constant_id = 4) const uint GRID_Y = 9u;
layout(constant_id = 5) const uint GRID_Z = 24u;
layout(constant_id = 6) const bool SDF = false;
layout(constant_id = 7) const bool useSSAO = false;
layout(constant_id = 8) const bool ANIMATED = false;
layout(constant_id = 9) const bool DEPTH_PASS = false;
layout(constant_id = 10) const bool WBOIT = false;      /// transparent accumulation variant (dual output)
layout(constant_id = 11) const uint MSAA_SAMPLES = 2u;   // MSAA sample count, fed by resolve pipeline

// Constants
const uint NIL = 0xFFFFFFFFu;
const float EPS = 1e-6;

#endif