/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import geometry : Geometry, position, scale, rotate, texture, bumpmap, opacity;
import textures : mapTextures;

/** Show the GUI window which allows us to manipulate 3D objects
 */
void showObjectswindow(ref App app, bool* show, uint font = 0) {
  igPushFont(app.gui.fonts[font]);
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
          igText(toStringz(format("%s: %s", text, object.mName)), ImVec2(0.0f, 0.0f));
        igTableNextColumn();
          if(igButton("Info", ImVec2(0.0f, 0.0f))){ app.objects[i].window = true; } igSameLine(0,5);
          if(igButton((app.objects[i].isVisible?"Hide":"Show"), ImVec2(0.0f, 0.0f))) {
            app.objects[i].isVisible = !app.objects[i].isVisible; 
          } igSameLine(0,5);
          if(igButton("DeAllocate", ImVec2(0.0f, 0.0f))){ app.objects[i].deAllocate = true; } igSameLine(0,5);
        igPopID();
        }
      igEndTable();
      igEnd();
    }
  }else { igEnd(); }
  igPopFont();
}

struct DropdownItem {
    const char* name;
    ImTextureID texture_id; // This would be your actual loaded texture ID
};

extern(C) const(char)* MyComboItemDrawer(void* user_data, int idx) {
  DropdownItem* items = cast(DropdownItem*)user_data;
  if(idx >= 0){
    DropdownItem* cItem = &items[idx];
    ImVec2 size = {24.0f, 24.0f}; // Example size for the image

    igImage(cItem.texture_id, ImVec2(24, 24), ImVec2(0, 0), ImVec2(1, 1)); igSameLine(0,5);
    return cItem.name; // Indicate that the item was drawn
  }else{
    return "-- None Selected --"; // Indicate that the item was drawn
  }
}

/** Individual Object
 */
void showObjectwindow(ref App app, ref Geometry obj) {
  igText(toStringz(format("Name: %s %s", obj.name(), obj.mName)), ImVec2(0.0f, 0.0f));
  igText(toStringz(format("Vertices: %s", obj.vertices.length)), ImVec2(0.0f, 0.0f));
  igText(toStringz(format("Indices: %s", obj.indices.length)), ImVec2(0.0f, 0.0f));
  igText(toStringz(format("Instances: %s", obj.instances.length)), ImVec2(0.0f, 0.0f));
  igText(toStringz(format("Topology: %s", obj.topology)), ImVec2(0.0f, 0.0f));
  auto p = obj.position;
  if(igButton("Overview", ImVec2(0.0f, 0.0f))) { obj.window = false; } igSameLine(0,5);
  if(igButton((obj.isVisible?"Hide":"Show"), ImVec2(0.0f, 0.0f))) { obj.isVisible = !obj.isVisible; } igSameLine(0,5);
  if(igButton("DeAllocate", ImVec2(0.0f, 0.0f))){ obj.deAllocate = true; }
  if(obj.animations.length > 0) {
    igText("Animation:", ImVec2(0.0f, 0.0f)); igSameLine(0,5);
    igPushItemWidth(100 * app.gui.size);
      int[2] limits = [0, cast(uint)(obj.animations.length-1)];
      igSliderScalar("##a", ImGuiDataType_U32,  &obj.animation, &limits[0], &limits[1], "%d", 0);
  }
  igBeginTable(toStringz(obj.name() ~ "_Tbl"), 4,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
    igTableNextColumn();
      igText("Position", ImVec2(0.0f, 0.0f)); 
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##x", ImGuiDataType_Float,  &p[0], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
      igPopItemWidth();
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##y", ImGuiDataType_Float,  &p[1], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
      igPopItemWidth();
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##z", ImGuiDataType_Float,  &p[2], &app.gui.pos[0], &app.gui.pos[1], "%.2f", 0);
      igPopItemWidth();

    igTableNextColumn();
      if(igButton("Scale", ImVec2(0.0f, 0.0f))){ obj.scale([app.gui.scaleF, app.gui.scaleF, app.gui.scaleF]); app.gui.scaleF = 1.0f; }
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##zS", ImGuiDataType_Float, &app.gui.scaleF, &app.gui.scale[0], &app.gui.scale[1], "%.3f", 0); 
      igPopItemWidth();
    igTableNextColumn();
    igTableNextColumn();

    igTableNextColumn();
      if(igButton("Rotate", ImVec2(0.0f, 0.0f))){ obj.rotate(app.gui.rotF); app.gui.rotF = [0.0f,0.0f,0.0f]; }
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##xR", ImGuiDataType_Float,  &app.gui.rotF[0], &app.gui.rot[0], &app.gui.rot[1], "%.0f", 0);
      igPopItemWidth();
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##yR", ImGuiDataType_Float,  &app.gui.rotF[1], &app.gui.rot[0], &app.gui.rot[1], "%.0f", 0);
      igPopItemWidth();
    igTableNextColumn();
      igPushItemWidth(100 * app.gui.size);
        igSliderScalar("##zR", ImGuiDataType_Float,  &app.gui.rotF[2], &app.gui.rot[0], &app.gui.rot[1], "%.0f", 0);
      igPopItemWidth();

    obj.position = p;
  igEndTable();
  if(obj.meshes.length > 0) {
    int[2] limits = [-1, cast(int)(app.textures.length-1)];
    string key0 = obj.meshes.keys[0];
    int tid = obj.meshes[key0].tid;
    int nid = obj.meshes[key0].nid;
    int oid = obj.meshes[key0].oid;
    DropdownItem[] items;
    foreach(i, texture; app.textures){
      items ~= DropdownItem(toStringz(stripExtension(baseName(texture.path))), cast(ulong)texture.imID);
    }

    igPushItemWidth(250 * app.gui.size);
      igCombo_FnStrPtr("##tid:all", &tid, &MyComboItemDrawer, cast(void*)&items[0], cast(int)items.length, -1);
    igPopItemWidth();
    igPushItemWidth(250 * app.gui.size);
      igCombo_FnStrPtr("##nid:all", &nid, &MyComboItemDrawer, cast(void*)&items[0], cast(int)items.length, -1);
    igPopItemWidth();
    igPushItemWidth(250 * app.gui.size);
      igCombo_FnStrPtr("##oid:all", &oid, &MyComboItemDrawer, cast(void*)&items[0], cast(int)items.length, -1);
    igPopItemWidth();

    igText("Mesh textures:", ImVec2(0.0f, 0.0f));
    igBeginTable(toStringz(obj.name() ~ "_Textures"), 4,  ImGuiTableFlags_Resizable | ImGuiTableFlags_SizingFixedFit, ImVec2(0.0f, 0.0f), 0.0f);
    foreach(name; obj.meshes.byKey()){
      igTableNextColumn();
        igText(toStringz(format("%s", name)), ImVec2(0.0f, 0.0f)); igSameLine(0,5);
      igTableNextColumn();
        igPushItemWidth(100 * app.gui.size);
          igSliderScalar(toStringz(format("##tid:%s", name)), ImGuiDataType_S32,  &obj.meshes[name].tid, &limits[0], &limits[1], "%d", 0); igSameLine(0,5);
        igPopItemWidth();
      igTableNextColumn();
        igPushItemWidth(100 * app.gui.size);
          igSliderScalar(toStringz(format("##nid:%s", name)), ImGuiDataType_S32,  &obj.meshes[name].nid, &limits[0], &limits[1], "%d", 0);
        igPopItemWidth();
      igTableNextColumn();
        igPushItemWidth(100 * app.gui.size);
          igSliderScalar(toStringz(format("##oid:%s", name)), ImGuiDataType_S32,  &obj.meshes[name].oid, &limits[0], &limits[1], "%d", 0);
        igPopItemWidth();
    }
    igEndTable();
    if(tid != obj.meshes[key0].tid){ obj.texture(app.textures[tid].path); app.mapTextures(obj); }
    if(nid != obj.meshes[key0].nid){ obj.bumpmap(app.textures[nid].path); app.mapTextures(obj); }
    if(oid != obj.meshes[key0].oid){ obj.opacity(app.textures[oid].path); app.mapTextures(obj); }
  }
  igEnd();
}

