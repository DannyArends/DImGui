/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import images : createNamedImage, ImageBuffer;

struct WBOIT {
  ImageBuffer accumulation;                                   /// Accumulation target (RGBA16F, single-sample)
  ImageBuffer revealage;                                      /// Revealage target (R16F, single-sample)
  Shader[] shaders;                                           /// Resolve shader (fullscreen composite)
  GraphicsPipeline resolvePipeline;                           /// Resolve/composite pipeline (subpass 2)
  VkFormat accumFormat     = VK_FORMAT_R16G16B16A16_SFLOAT;
  VkFormat revealageFormat = VK_FORMAT_R16_SFLOAT;
  bool enabled = true;                                        /// Feature toggle
}

/** Allocate the single-sample WBOIT accumulation targets (input attachments for the resolve subpass) */
void createWBOITResources(ref App app) {
  app.createNamedImage(app.wboit.accumulation, app.camera.width, app.camera.height, app.wboit.accumFormat,
                       VK_IMAGE_ASPECT_COLOR_BIT, "WBOIT Accumulation", VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL,
                       VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT);
  app.createNamedImage(app.wboit.revealage, app.camera.width, app.camera.height, app.wboit.revealageFormat,
                       VK_IMAGE_ASPECT_COLOR_BIT, "WBOIT Revealage", VK_SAMPLE_COUNT_1_BIT, VK_IMAGE_TILING_OPTIMAL,
                       VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT);
}
