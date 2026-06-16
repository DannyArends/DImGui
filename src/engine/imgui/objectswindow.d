/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : faIcon;
import widgets : dropDownItems, applySelection, texturesToDropdown, getKeys, text, cstr, labelCol, objectActions, materialRow, colSlider;
import textures : mapTextures, ImTextureRefFromID;

/** Window to manipulate 3D objects: list view, or per-object detail when an object's window flag is set. */
void showObjectsContent(ref App app, uint font = 0) {
  foreach(ref obj; app.objects) if(obj.window) { app.showObjectwindow(obj); return; }

  if(!igBeginTable("Object_Tbl", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0,0), 0.0f)) return;
  foreach(i, ref object; app.objects) {
    if(object.hideInObjectsWindow || object.instances.length == 0) continue;
    igPushID_Int(to!int(i)); scope(exit) igPopID();
    igTableNextRow(0, 5.0f);
    string lbl = object.geometry() ? object.geometry() ~ " " ~ to!string(i) : to!string(i);
    igTableNextColumn();
      igText(cstr("%s: %s (%d)", lbl, object.mName, object.uid));
    igTableNextColumn();
      if(igButton(faIcon(cast(string)ICON_FA_INFO), ImVec2(0,0))) object.window = true;
      igSameLine(0,5);
      app.objectActions(object);
  }
  igEndTable();
}

/** Per-object detail: transform, animation, and material editing. */
void showObjectwindow(ref App app, ref Geometry obj) {
  text("Name: %s %s", obj.geometry(), obj.mName);
  text("Vertices: %s", obj.vertices.length);
  text("Indices: %s", obj.indices.length);
  text("Instances: %s", obj.instances.length);
  text("Topology: %s", obj.topology);

  if(igButton(faIcon(cast(string)ICON_FA_CUBES), ImVec2(0,0))) obj.window = false; igSameLine(0,5);
  app.objectActions(obj);

  if(obj.animations.length > 0) {
    igText(faIcon(cast(string)ICON_FA_FILM)); igSameLine(0,5);
    igPushItemWidth(100 * app.gui.uiscale);
    int[2] limits = [0, cast(int)(obj.animations.length-1)];
    igSliderScalar("##a", ImGuiDataType_U32, &obj.animation, &limits[0], &limits[1], "%d", 0);
    igPopItemWidth();
  }

  if(igBeginTable(cstr("%s_Tbl", obj.geometry()), 4, ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0,0), 0.0f)) {
    auto p = obj.position;
    igTableNextColumn();
    if(igButton(faIcon(cast(string)ICON_FA_ARROWS_UP_DOWN_LEFT_RIGHT), ImVec2(0,0))) {}
    igTableNextColumn(); app.colSlider("##x", &p[0], app.gui.pos[0], app.gui.pos[1]);
    igTableNextColumn(); app.colSlider("##y", &p[1], app.gui.pos[0], app.gui.pos[1]);
    igTableNextColumn(); app.colSlider("##z", &p[2], app.gui.pos[0], app.gui.pos[1]);
    obj.position = p;

    igTableNextColumn();
      if(igButton(faIcon(cast(string)ICON_FA_COMPRESS), ImVec2(0,0))) {
        obj.scale([app.gui.scaleF, app.gui.scaleF, app.gui.scaleF]); app.gui.scaleF = 1.0f;
      }
    igTableNextColumn(); app.colSlider("##zS", &app.gui.scaleF, app.gui.scale[0], app.gui.scale[1], "%.3f");
    igTableNextColumn(); igTableNextColumn();

    igTableNextColumn();
      if(igButton(faIcon(cast(string)ICON_FA_ARROWS_ROTATE), ImVec2(0,0))) { obj.rotate(app.gui.rotF); app.gui.rotF = [0.0f,0.0f,0.0f]; }
    igTableNextColumn(); app.colSlider("##xR", &app.gui.rotF[0], app.gui.rot[0], app.gui.rot[1], "%.0f");
    igTableNextColumn(); app.colSlider("##yR", &app.gui.rotF[1], app.gui.rot[0], app.gui.rot[1], "%.0f");
    igTableNextColumn(); app.colSlider("##zR", &app.gui.rotF[2], app.gui.rot[0], app.gui.rot[1], "%.0f");
    igEndTable();
  }

  if(obj.meshes.length == 0) return;

  auto mesh0 = obj.meshes.keys[0];
  DropDownItem[] items = app.texturesToDropdown();
  auto selected = app.getKeys(items, obj.meshes[mesh0]);

  if(igBeginTable(cstr("%s_TexTbl", obj.geometry()), 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0,0), 0.0f)) {
    labelCol("Diffuse:"); igPushItemWidth(250 * app.gui.uiscale);
    igCombo_FnStrPtr("##tid:all", &selected.tid, &dropDownItems, cast(void*)&items[0], cast(int)items.length, -1); igPopItemWidth();
    labelCol("BumpMap:"); igPushItemWidth(250 * app.gui.uiscale);
    igCombo_FnStrPtr("##nid:all", &selected.nid, &dropDownItems, cast(void*)&items[0], cast(int)items.length, -1); igPopItemWidth();
    labelCol("Opacity:"); igPushItemWidth(250 * app.gui.uiscale);
    igCombo_FnStrPtr("##oid:all", &selected.oid, &dropDownItems, cast(void*)&items[0], cast(int)items.length, -1); igPopItemWidth();
    igEndTable();
  }
  if(app.applySelection(obj, items, obj.meshes[mesh0], selected)) app.mapTextures(obj);

  auto treeFlags = ImGuiTreeNodeFlags_OpenOnArrow | ImGuiTreeNodeFlags_OpenOnDoubleClick;
  if(igTreeNodeEx_Str("Mesh textures", treeFlags)) {
    int[2] limits = [-1, cast(int)(app.textures.length-1)];
    if(igBeginTable(cstr("%s_Textures", obj.geometry()), 4, ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0,0), 0.0f)) {
      foreach(name; obj.meshes.byKey()) app.materialRow(cstr("%s", name), app.materials[obj.meshes[name].mid], limits[0], limits[1]);
      igEndTable();
    }
    igTreePop();
  }
}
