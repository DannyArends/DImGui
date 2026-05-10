/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import ctfeparse : generateColorsEnum, generateResourceEnum, generateHeightToResource, generateFeatureData;

/** NOTE: changes to .txt files require: dub build --force
 * import() is resolved at compile-time; dub does not track these as dependencies */
mixin(generateColorsEnum(import("data/raws/colors.txt")));
mixin(generateResourceEnum(import("data/raws/materials.txt")));
mixin(generateHeightToResource(import("data/raws/terrain.txt")));
mixin(generateFeatureData(import("data/raws/features.txt")));
