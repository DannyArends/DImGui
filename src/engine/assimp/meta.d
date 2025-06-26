/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;
import assimp : OpenAsset, name;

struct MetaData {
  int[4] upAxis;
  int[2] frontAxis;
  int[2] coordAxis;
  double scalefactor;
}

MetaData loadMetaData(ref App app, aiScene* scene) {
  aiMetadata* mData = scene.mMetaData;
  MetaData meta;
  for (uint i = 0; i < mData.mNumProperties; ++i) {
    auto key = name(mData.mKeys[i]);
    if (key == "UpAxis") { meta.upAxis[0] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "UpAxisSign") { meta.upAxis[1] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "OriginalUpAxis") { meta.upAxis[2] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "OriginalUpAxisSign") { meta.upAxis[3] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "FrontAxis") { meta.frontAxis[0] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "FrontAxisSign") { meta.frontAxis[1] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "CoordAxis") { meta.coordAxis[0] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "CoordAxisSign") { meta.coordAxis[1] = *cast(int*)(mData.mValues[i].mData); }
    if (key == "UnitScaleFactor") { meta.scalefactor = *cast(float*)(mData.mValues[i].mData); }
  }
  if (app.verbose) {
    SDL_Log(toStringz(format("MetaData UP: %s", meta.upAxis)));
    SDL_Log(toStringz(format("MetaData Front: %s", meta.frontAxis)));
    SDL_Log(toStringz(format("MetaData Coord: %s", meta.coordAxis)));
    SDL_Log(toStringz(format("MetaData Scale: %s", meta.scalefactor)));
  }
  return(meta);
}
