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
  immutable(char)* name;
  ImTextureID imID;
}

struct SelectionKey {
  int tid;
  int nid;
  int oid;
}

struct GameWindow {
  string label;
  void delegate(uint font) show;
  bool visible = false;
  bool floating = false;
  bool direct = false;
}

ImVec2 textSize(const(char)* txt) { ImVec2 textSize; igCalcTextSize(&textSize, txt, null, false, -1.0f); return(textSize); }

/** Map a D scalar type to its cimgui ImGuiDataType (ImGui 1.92.1) */
template imDataType(T) {
       static if (is(T == float))  enum imDataType = ImGuiDataType_Float;
  else static if (is(T == double)) enum imDataType = ImGuiDataType_Double;
  else static if (is(T == uint))   enum imDataType = ImGuiDataType_U32;
  else static if (is(T == int))    enum imDataType = ImGuiDataType_S32;
  else static assert(false, "imDataType: no ImGuiDataType for " ~ T.stringof);
}

/** D-formatted C string. One home for the per-frame toStringz allocation. */
const(char)* cstr(A...)(string fmt, A a) { return toStringz(format(fmt, a)); }

/** igText with D-side formatting. */
void text(A...)(string fmt, A a) { igText(cstr(fmt, a)); }

/** Default printf format for a scalar type */
template imFormat(T) { static if (isFloatingPoint!T) enum imFormat = "%.2f"; else enum imFormat = "%d"; }

/** label + bounded slider as a 2-column table row. Returns true if changed. */
bool setting(T)(string label, ref T v, T min, T max, float width = 150, float uiscale = 1.0f, string fmt = imFormat!T) if (isFloatingPoint!T || isIntegral!T) {
  labelCol(toStringz(label));
  igPushItemWidth(width * uiscale); scope(exit) igPopItemWidth();
  return igSliderScalar(toStringz("##" ~ label), imDataType!T, &v, &min, &max, toStringz(fmt), 0);
}

/** label + checkbox as a 2-column table row. Returns true if changed. */
bool setting(string label, ref bool v) { labelCol(toStringz(label)); return igCheckbox(toStringz("##" ~ label), &v); }

/** label + read-only formatted value as a 2-column table row. */
void infoRow(Args...)(string label, string fmt, Args a) {
  labelCol(toStringz(label));
  igText(toStringz(format(fmt, a)));
}

/** Render three inline scaled float sliders for a vec3 */
void sliderFloat3(string[3] ids, float* x, float* y, float* z, float* min, float* max, float width, float uiscale) {
  igPushItemWidth(width * uiscale); igSliderScalar(toStringz(ids[0]), ImGuiDataType_Float, x, min, max, "%.2f", 0); igPopItemWidth(); igSameLine(0,5);
  igPushItemWidth(width * uiscale); igSliderScalar(toStringz(ids[1]), ImGuiDataType_Float, y, min, max, "%.2f", 0); igPopItemWidth(); igSameLine(0,5);
  igPushItemWidth(width * uiscale); igSliderScalar(toStringz(ids[2]), ImGuiDataType_Float, z, min, max, "%.2f", 0); igPopItemWidth();
}

/** Eye (visibility) + trash (delete) buttons for an object; shared by list and detail views. */
void objectActions(ref App app, ref Geometry obj) {
  if(igButton(obj.isVisible ? faIcon(cast(string)ICON_FA_EYE_SLASH) : faIcon(cast(string)ICON_FA_EYE), ImVec2(0,0)))
    obj.isVisible = !obj.isVisible;
  igSameLine(0,5);
  if(igButton(faIcon(cast(string)ICON_FA_TRASH), ImVec2(0,0))) obj.deAllocate = true;
}

/** Scaled, label-less int slider in the current table column. */
void colSliderInt(ref App app, const(char)* id, int* v, int lo, int hi) {
  igPushItemWidth(100 * app.gui.uiscale); scope(exit) igPopItemWidth();
  igSliderScalar(id, ImGuiDataType_S32, v, &lo, &hi, "%d", 0);
}

/** Scaled, label-less float slider in the current table column. */
void colSlider(ref App app, const(char)* id, float* v, float lo, float hi, string fmt = "%.2f") {
  igPushItemWidth(100 * app.gui.uiscale); scope(exit) igPopItemWidth();
  igSliderScalar(id, ImGuiDataType_Float, v, &lo, &hi, toStringz(fmt), 0);
}

/** One mesh's tid/nid/oid sliders across a 4-column row; material by ref so edits persist. */
void materialRow(ref App app, const(char)* name, ref Material mat, int lo, int hi) {
  igTableNextColumn(); igText(name); igSameLine(0,5);   // name inline, same column
  igTableNextColumn(); app.colSliderInt(cstr("##tid:%s", name), &mat.tid, lo, hi);
  igTableNextColumn(); app.colSliderInt(cstr("##nid:%s", name), &mat.nid, lo, hi);
  igTableNextColumn(); app.colSliderInt(cstr("##oid:%s", name), &mat.oid, lo, hi);
}

/** Render a label + widget as a 2-column table row */
void labelCol(const(char)* label) { igTableNextColumn(); igText(label); igTableNextColumn(); }

/** */
bool cDropDown(T)(string label, ref T v, const(T)[] values, const(char*)[] labels, float width = 150, float uiscale = 1.0f) {
  assert(values.length == labels.length, "choice: values/labels length mismatch");
  labelCol(toStringz(label));
  int idx = 0;
  foreach(i, val; values) if(val == v) { idx = cast(int)i; break; }
  igPushItemWidth(width * uiscale); scope(exit) igPopItemWidth();
  if(igCombo_Str_arr(toStringz("##" ~ label), &idx, labels.ptr, cast(int)labels.length, -1)) {
    v = values[idx];
    return true;
  }
  return false;
}

/** label + snap slider over a fixed set of values, as a 2-column table row. Returns true if changed. */
bool cSlider(T)(string label, ref T v, const(T)[] values, const(char*)[] labels, float width = 150, float uiscale = 1.0f) {
  labelCol(toStringz(label));
  int idx = 0;
  foreach(i, val; values) if(val == v) { idx = cast(int)i; break; }
  igPushItemWidth(width * uiscale); scope(exit) igPopItemWidth();
  if(igSliderInt(toStringz("##" ~ label), &idx, 0, cast(int)values.length - 1, labels[idx], 0)) {
    v = values[idx];
    return true;
  }
  return false;
}

extern(C) const(char)* dropDownItems(void* user_data, int idx) nothrow @nogc {
  DropDownItem* items = cast(DropDownItem*)user_data;
  DropDownItem* cItem = &items[idx];
  ImVec2 size = {24.0f, 24.0f};
  if(idx != 0){
    igImage(ImTextureRefFromID(cItem.imID), size, ImVec2(0, 0), ImVec2(1, 1)); igSameLine(0,5);
    return(cItem.name);
  }else{ igDummy(size); igSameLine(0,5); return("-- None Selected --"); }
}

void drawCenteredText(ImDrawList* drawList, ImVec2 min, ImVec2 max, const(char)* text) {
  auto font = igGetFont();
  float fontSize = igGetFontSize();
  ImVec2 textSize;
  igCalcTextSize(&textSize, text, null, false, -1.0f);
  float tx = min.x + (max.x - min.x - textSize.x) * 0.5f;
  float ty = min.y + (max.y - min.y - textSize.y) * 0.5f;
  ImDrawList_PushClipRectFullScreen(drawList);
  foreach (off; [ImVec2(-1,-1), ImVec2(1,-1), ImVec2(-1,1), ImVec2(1,1)]) {
    ImDrawList_AddText_FontPtr(drawList, font, fontSize, ImVec2(tx+off.x, ty+off.y), 0xFF000000, text, null, 0.0f, null);
  }
  ImDrawList_AddText_FontPtr(drawList, font, fontSize, ImVec2(tx, ty), 0xFFFFFFFF, text, null, 0.0f, null);
  ImDrawList_PopClipRect(drawList);
}

DropDownItem[] texturesToDropdown(ref App app){
  DropDownItem[] items;
  foreach(i, texture; app.textures){
    items ~= DropDownItem(cast(int)i, toStringz(stripExtension(baseName(texture.path))), cast(ulong)texture.imID);
  }
  items.sort!((a, b) => strcmp(a.name, b.name) < 0);
  items = DropDownItem(-1, toStringz("-- None Selected --"), -1) ~ items;
  return(items);
}

SelectionKey getKeys(ref App app, DropDownItem[] items, Mesh mesh) {
  SelectionKey key;
  if(mesh.mid >= app.materials.length) return key;
  auto mat = app.materials[mesh.mid];
  foreach(i, item; items) {
    if(mat.tid == item.i) key.tid = cast(int)i;
    if(mat.nid == item.i) key.nid = cast(int)i;
    if(mat.oid == item.i) key.oid = cast(int)i;
  }
  return(key);
}

bool applySelection(ref App app, ref Geometry obj, DropDownItem[] items, Mesh mesh, SelectionKey key) {
  if(mesh.mid >= app.materials.length) return false;
  bool needUpdate = false;
  auto mat = app.materials[mesh.mid];
  if(items[key.tid].i != mat.tid){ obj.texture(to!string(items[(key.tid)].name)); needUpdate = true; }
  if(items[key.nid].i != mat.nid){ obj.bumpmap(to!string(items[(key.nid)].name)); needUpdate = true; }
  if(items[key.oid].i != mat.oid){ obj.opacity(to!string(items[(key.oid)].name)); needUpdate = true; }
  return(needUpdate);
}
