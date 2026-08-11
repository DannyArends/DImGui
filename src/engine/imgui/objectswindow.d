/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import imgui : faIcon, iconText;
import matrix : translate;
import textures : mapTextures, ImTextureRefFromID;
import widgets : dropDownItems, applySelection, texturesToDropdown, getKeys, text, labelCol, objectActions, materialRow, colValue;

/** Window to manipulate 3D objects: list view, or per-object detail when an object's window flag is set. */
void showObjectsContent(ref App app, uint font = 0) {
  foreach(ref obj; app.objects) if(obj.window) { app.showObjectwindow(obj); return; }

  if(!igBeginTable("Object_Tbl", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0,0), 0.0f)) return;
  foreach(i, ref object; app.objects) {
    if(object.hideInObjectsWindow || object.instances.length == 0) continue;
    igPushID_Int(to!int(i)); scope(exit) igPopID();
    igTableNextRow(0, 5.0f);
    string lbl = object.geometry().length ? object.geometry() ~ " " ~ to!string(i) : to!string(i);
    igTableNextColumn();
      text("%s: %s (%d)", lbl, object.mName, object.uid);
    igTableNextColumn();
      if(igButton(faIcon(cast(string)ICON_FA_INFO), ImVec2(0,0))) object.window = true;
      igSameLine(0,5);
      app.objectActions(object);
  }
  igEndTable();
}

/** Per-object detail: transform, animation, and material editing. */
void showObjectwindow(ref App app, ref Geometry obj) {
  text("Name: %s", obj.mName);
  text("Vertices: %s   Indices: %s   Topology: %s", obj.vertices.length, obj.indices.length, obj.topology);

  if(igButton(faIcon(cast(string)ICON_FA_CUBES), ImVec2(0,0))) obj.window = false;
  igSameLine(0,5); app.objectActions(obj);

  if(obj.instances.length == 0) return;
  if(obj.uiInstance >= obj.instances.length) obj.uiInstance = obj.instances.length - 1;

  // ---- instance navigator:  [<]  i / N  [>]  (>-past-end = add) ----
  igSeparator();
  if(igButton(faIcon(cast(string)ICON_FA_CHEVRON_LEFT), ImVec2(0,0)) && obj.uiInstance > 0) obj.uiInstance--;
  igSameLine(0,5);
  igText(cstr("Instance %d / %d", obj.uiInstance + 1, obj.instances.length));
  igSameLine(0,5);
  if(igButton(faIcon(cast(string)ICON_FA_CHEVRON_RIGHT), ImVec2(0,0))) {
    if(obj.uiInstance + 1 < obj.instances.length) {
      obj.uiInstance++;
    } else {                                   // past the end → create a new instance
      auto inst = obj.instances[obj.uiInstance];
      inst.matrix = translate(inst.matrix, [1.5f, 0.0f, 0.0f]);
      obj.addInstances([inst]);
      obj.syncInstances();
      obj.uiInstance = obj.instances.length - 1;
    }
  }
  if(obj.instances.length > 1) {
    igSameLine(0,5);
    if(igButton(cstr("%s##delInst", cast(string)ICON_FA_TRASH), ImVec2(0,0))) {
      obj.instances.removeAt(obj.uiInstance);
      obj.syncInstances();
      if(obj.uiInstance >= obj.instances.length) obj.uiInstance = obj.instances.length - 1;
  } }

  // ---- animation (this instance's cursor) ----
  if(obj.animations.length > 0 && obj.uiInstance < obj.states.length) {
    igText(faIcon(cast(string)ICON_FA_FILM)); igSameLine(0,5);
    igPushItemWidth(100 * app.gui.uiscale);
    int[2] limits = [0, cast(int)(obj.animations.length-1)];
    igSliderScalar("##anim", ImGuiDataType_U32, &obj.states[obj.uiInstance].animation, &limits[0], &limits[1], "%d", 0);
    igPopItemWidth();
  }

  // ---- transform (this instance) ----
  if(igBeginTable(cstr("%s_Tbl", obj.geometry()), 4, ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0,0), 0.0f)) {
    auto p = obj.position(cast(uint)obj.uiInstance);
    igTableNextColumn();
    if(igButton(faIcon(cast(string)ICON_FA_ARROWS_UP_DOWN_LEFT_RIGHT), ImVec2(0,0))) {}
    igTableNextColumn(); app.colValue("##x", &p[0], app.gui.pos[0], app.gui.pos[1]);
    igTableNextColumn(); app.colValue("##y", &p[1], app.gui.pos[0], app.gui.pos[1]);
    igTableNextColumn(); app.colValue("##z", &p[2], app.gui.pos[0], app.gui.pos[1]);
    obj.position(p, cast(uint)obj.uiInstance);

    igTableNextColumn();
      if(igButton(faIcon(cast(string)ICON_FA_COMPRESS), ImVec2(0,0))) {
        obj.scale([app.gui.scaleF, app.gui.scaleF, app.gui.scaleF], cast(uint)obj.uiInstance); app.gui.scaleF = 1.0f;
      }
    igTableNextColumn(); app.colValue("##zS", &app.gui.scaleF, app.gui.scale[0], app.gui.scale[1], "%.3f");
    igTableNextColumn(); igTableNextColumn();

    igTableNextColumn();
      if(igButton(faIcon(cast(string)ICON_FA_ARROWS_ROTATE), ImVec2(0,0))) {
        obj.rotate(app.gui.rotF, cast(uint)obj.uiInstance); app.gui.rotF = [0.0f,0.0f,0.0f];
      }
    igTableNextColumn(); app.colValue("##xR", &app.gui.rotF[0], app.gui.rot[0], app.gui.rot[1], "%.0f");
    igTableNextColumn(); app.colValue("##yR", &app.gui.rotF[1], app.gui.rot[0], app.gui.rot[1], "%.0f");
    igTableNextColumn(); app.colValue("##zR", &app.gui.rotF[2], app.gui.rot[0], app.gui.rot[1], "%.0f");
    igEndTable();
  }

  // ---- materials (unchanged, per-object) ----
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
