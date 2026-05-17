/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry : texture, bumpmap, opacity;
import imgui : faIcon;
import textures : ImTextureRefFromID;

struct DropDownItem {
  int i;
  string name;
  ImTextureID imID;
}

struct SelectionKey {
  int tid;
  int nid;
  int oid;
}

ImVec2 textSize(const(char)* txt) { ImVec2 textSize; igCalcTextSize(&textSize, txt, null, false, -1.0f); return(textSize); }

/** Render three inline scaled float sliders for a vec3 */
void sliderFloat3(string[3] ids, float* x, float* y, float* z, float* min, float* max, float width, float uiscale) {
  igPushItemWidth(width * uiscale); igSliderScalar(toStringz(ids[0]), ImGuiDataType_Float, x, min, max, "%.2f", 0); igSameLine(0,5);
  igPushItemWidth(width * uiscale); igSliderScalar(toStringz(ids[1]), ImGuiDataType_Float, y, min, max, "%.2f", 0); igSameLine(0,5);
  igPushItemWidth(width * uiscale); igSliderScalar(toStringz(ids[2]), ImGuiDataType_Float, z, min, max, "%.2f", 0);
}

/** Render a label + widget as a 2-column table row */
void labelCol(const(char)* label) { igTableNextColumn(); igText(label); igTableNextColumn(); }

extern(C) const(char)* dropDownItems(void* user_data, int idx) {
  DropDownItem* items = cast(DropDownItem*)user_data;
  DropDownItem* cItem = &items[idx];
  ImVec2 size = {24.0f, 24.0f};
  if(idx != 0){
    igImage(ImTextureRefFromID(cItem.imID), size, ImVec2(0, 0), ImVec2(1, 1)); igSameLine(0,5);
    return toStringz(cItem.name); // Indicate that the item was drawn
  }else{
    igDummy(size); igSameLine(0,5);
    return "-- None Selected --"; // Indicate that the item was drawn
  }
}

DropDownItem[] texturesToDropdown(ref App app){
  DropDownItem[] items;
  foreach(i, texture; app.textures){
    items ~= DropDownItem(cast(int)i, stripExtension(baseName(texture.path)), cast(ulong)texture.imID);
  }
  items.sort!("a.name < b.name");
  items = DropDownItem(-1, "-- None Selected --", -1) ~ items;
  return(items);
}

SelectionKey getKeys(DropDownItem[] items, ref App app, Mesh mesh) {
  SelectionKey key;
  auto ref mat = app.materials[mesh.mid];
  foreach(i, item; items) {
    if(mat.tid == item.i) key.tid = cast(int)i;
    if(mat.nid == item.i) key.nid = cast(int)i;
    if(mat.oid == item.i) key.oid = cast(int)i;
  }
  return(key);
}

bool applySelection(ref App app, ref Geometry obj, DropDownItem[] items, Mesh mesh, SelectionKey key) {
  bool needUpdate = false;
  auto ref mat = app.materials[mesh.mid];
  if(items[key.tid].i != mat.tid){ obj.texture(items[(key.tid)].name); needUpdate = true; }
  if(items[key.nid].i != mat.nid){ obj.bumpmap(items[(key.nid)].name); needUpdate = true; }
  if(items[key.oid].i != mat.oid){ obj.opacity(items[(key.oid)].name); needUpdate = true; }
  return(needUpdate);
}
