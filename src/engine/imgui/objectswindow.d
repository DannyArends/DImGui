/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import mesh : Mesh;
import geometry : Geometry, position, scale, rotate, texture, bumpmap, opacity;
import textures : mapTextures, ImTextureRefFromID;

/** Show the GUI window which allows us to manipulate 3D objects
 */
void showObjectswindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font], app.gui.fontsize);
  if(igBegin("Objects", show, 0)) {
    bool list = true;
    for(size_t x = 0; x < app.objects.length; x++) {
      if(app.objects[x].window){
        app.showObjectwindow(app.objects[x]);
        list = false;
      }
    }
    if(list){
      igBeginTable("Object_Tbl", 2, ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
      foreach(i, object; app.objects){
        igPushID_Int(to!int(i));
        auto p = app.objects[i].position;
        igTableNextRow(0, 5.0f);
        string text = to!string(i);
        if(object.name) text = object.name() ~ " " ~ text;
        igTableNextColumn();
          igText(toStringz(format("%s: %s (%d)", text, object.mName, object.uid)), ImVec2(0.0f, 0.0f));
        igTableNextColumn();
          if(igButton("Info", ImVec2(0.0f, 0.0f))){ app.objects[i].window = true; } igSameLine(0,5);
          if(igButton((app.objects[i].isVisible?"Hide":"Show"), ImVec2(0.0f, 0.0f))) {
            app.objects[i].isVisible = !app.objects[i].isVisible; 
          } igSameLine(0,5);
          //if(igButton("DeAllocate", ImVec2(0.0f, 0.0f))){ app.objects[i].deAllocate = true; } igSameLine(0,5);
        igPopID();
        }
      igEndTable();
      igEnd();
    }
  }else { igEnd(); }
  igPopFont();
}

struct DropdownItem {
  int i;
  string name;
  ImTextureID imID;
};

extern(C) const(char)* MyComboItemDrawer(void* user_data, int idx) {
  DropdownItem* items = cast(DropdownItem*)user_data;
  DropdownItem* cItem = &items[idx];
  ImVec2 size = {24.0f, 24.0f};
  if(idx != 0){
    igImage(ImTextureRefFromID(cItem.imID), size, ImVec2(0, 0), ImVec2(1, 1)); igSameLine(0,5);
    return toStringz(cItem.name); // Indicate that the item was drawn
  }else{
    igDummy(size); igSameLine(0,5);
    return "-- None Selected --"; // Indicate that the item was drawn
  }
}
struct SelectionKey {
  int tid;
  int nid;
  int oid;
}

DropdownItem[] texturesToDropdown(ref App app){
  DropdownItem[] items;
  foreach(i, texture; app.textures){
    items ~= DropdownItem(cast(int)i, stripExtension(baseName(texture.path)), cast(ulong)texture.imID);
  }
  items.sort!("a.name < b.name");
  items = DropdownItem(-1, "-- None Selected --", -1) ~ items;
  return(items);
}

SelectionKey getKeys(DropdownItem[] items, Mesh mesh){
  SelectionKey key;
  foreach(i, item; items){
    if(mesh.tid == item.i) key.tid = cast(int)i;
    if(mesh.nid == item.i) key.nid = cast(int)i;
    if(mesh.oid == item.i) key.oid = cast(int)i;
  }
  return(key);
}

bool applySelection(ref Geometry obj, DropdownItem[] items, Mesh mesh, SelectionKey key){
  bool needUpdate = false;
  if(items[key.tid].i != mesh.tid){ obj.texture(items[(key.tid)].name); needUpdate = true; }
  if(items[key.nid].i != mesh.nid){ obj.bumpmap(items[(key.nid)].name); needUpdate = true; }
  if(items[key.oid].i != mesh.oid){ obj.opacity(items[(key.oid)].name); needUpdate = true; }
  return(needUpdate);
}

/** Individual Object
 */
void showObjectwindow(ref App app, ref Geometry obj) {
  igText(toStringz(format("Name: %s %s", obj.name(), obj.mName)), ImVec2(0.0f, 0.0f));
  igText(toStringz(format("Vertices: %s", obj.vertices.length)), ImVec2(0.0f, 0.0f));
  igText(toStringz(format("Indices: %s", obj.indices.length)), ImVec2(0.0f, 0.0f));
  igText(toStringz(format("Instances: %s", obj.instances.length)), ImVec2(0.0f, 0.0f));
  igText(toStringz(format("Topology: %s", obj.topology)), ImVec2(0.0f, 0.0f));

  if(igButton("Overview", ImVec2(0.0f, 0.0f))) { obj.window = false; } igSameLine(0,5);
  if(igButton((obj.isVisible?"Hide":"Show"), ImVec2(0.0f, 0.0f))) { obj.isVisible = !obj.isVisible; } igSameLine(0,5);
  if(igButton("DeAllocate", ImVec2(0.0f, 0.0f))){ obj.deAllocate = true; }
  if(obj.animations.length > 0) {
    igText("Animation:", ImVec2(0.0f, 0.0f)); igSameLine(0,5);
    igPushItemWidth(100 * app.gui.uiscale);
      int[2] limits = [0, cast(uint)(obj.animations.length-1)];
      igSliderScalar("##a", ImGuiDataType_U32,  &obj.animation, &limits[0], &limits[1], "%d", 0);
  }
  igBeginTable(toStringz(obj.name() ~ "_Tbl"), 4,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
    auto p = obj.position;
    igTableNextColumn();
      igText("Position", ImVec2(0.0f, 0.0f)); 
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.uiscale);
        igSliderScalar("##x", ImGuiDataType_Float,  &p[0], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
      igPopItemWidth();
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.uiscale);
        igSliderScalar("##y", ImGuiDataType_Float,  &p[1], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
      igPopItemWidth();
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.uiscale);
        igSliderScalar("##z", ImGuiDataType_Float,  &p[2], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
      igPopItemWidth();
    obj.position = p;

    igTableNextColumn();
      if(igButton("Scale", ImVec2(0.0f, 0.0f))){ obj.scale([app.gui.scaleF, app.gui.scaleF, app.gui.scaleF]); app.gui.scaleF = 1.0f; }
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.uiscale);
        igSliderScalar("##zS", ImGuiDataType_Float, &app.gui.scaleF, &app.gui.scale[0], &app.gui.scale[1], "%.3f", 0); 
      igPopItemWidth();
    igTableNextColumn();
    igTableNextColumn();

    igTableNextColumn();
      if(igButton("Rotate", ImVec2(0.0f, 0.0f))){ obj.rotate(app.gui.rotF); app.gui.rotF = [0.0f,0.0f,0.0f]; }
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.uiscale);
        igSliderScalar("##xR", ImGuiDataType_Float,  &app.gui.rotF[0], &app.gui.rot[0], &app.gui.rot[1], "%.0f", 0);
      igPopItemWidth();
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.uiscale);
        igSliderScalar("##yR", ImGuiDataType_Float,  &app.gui.rotF[1], &app.gui.rot[0], &app.gui.rot[1], "%.0f", 0);
      igPopItemWidth();
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.uiscale);
        igSliderScalar("##zR", ImGuiDataType_Float,  &app.gui.rotF[2], &app.gui.rot[0], &app.gui.rot[1], "%.0f", 0);
      igPopItemWidth();


  igEndTable();
  if(obj.meshes.length > 0) {
    int[2] limits = [-1, cast(int)(app.textures.length-1)];
    auto mesh0 = obj.meshes.keys[0];
    DropdownItem[] items = app.texturesToDropdown();
    auto selected = items.getKeys(obj.meshes[mesh0]);

    igBeginTable(toStringz(obj.name() ~ "_TexTbl"), 2,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
      igTableNextColumn();
      igText("Diffuse:", ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      igPushItemWidth(250 * app.gui.uiscale);
        igCombo_FnStrPtr("##tid:all", &selected.tid, &MyComboItemDrawer, cast(void*)&items[0], cast(int)items.length, -1);
      igPopItemWidth();
      igTableNextColumn();
      igText("BumpMap:", ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      igPushItemWidth(250 * app.gui.uiscale);
        igCombo_FnStrPtr("##nid:all", &selected.nid, &MyComboItemDrawer, cast(void*)&items[0], cast(int)items.length, -1);
      igPopItemWidth();
      igTableNextColumn();
      igText("Opacity:", ImVec2(0.0f, 0.0f));
      igTableNextColumn();
      igPushItemWidth(250 * app.gui.uiscale);
        igCombo_FnStrPtr("##oid:all", &selected.oid, &MyComboItemDrawer, cast(void*)&items[0], cast(int)items.length, -1);
      igPopItemWidth();
    igEndTable();
    if(obj.applySelection(items, obj.meshes[mesh0], selected)) app.mapTextures(obj);

    auto flags = ImGuiTreeNodeFlags_OpenOnArrow | ImGuiTreeNodeFlags_OpenOnDoubleClick;
    bool node_open = igTreeNodeEx_Str("Mesh textures", flags);
    if (node_open) {
      igBeginTable(toStringz(obj.name() ~ "_Textures"), 4,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
      foreach(name; obj.meshes.byKey()){
        igTableNextColumn();
          igText(toStringz(format("%s", name)), ImVec2(0.0f, 0.0f)); igSameLine(0,5);
        igTableNextColumn();
          igPushItemWidth(100 * app.gui.uiscale);
            igSliderScalar(toStringz(format("##tid:%s", name)), ImGuiDataType_S32,  &obj.meshes[name].tid, &limits[0], &limits[1], "%d", 0); igSameLine(0,5);
          igPopItemWidth();
        igTableNextColumn();
          igPushItemWidth(100 * app.gui.uiscale);
            igSliderScalar(toStringz(format("##nid:%s", name)), ImGuiDataType_S32,  &obj.meshes[name].nid, &limits[0], &limits[1], "%d", 0);
          igPopItemWidth();
        igTableNextColumn();
          igPushItemWidth(100 * app.gui.uiscale);
            igSliderScalar(toStringz(format("##oid:%s", name)), ImGuiDataType_S32,  &obj.meshes[name].oid, &limits[0], &limits[1], "%d", 0);
          igPopItemWidth();
      }
      igEndTable();
      igTreePop();
    }
  }
  igEnd();
}

