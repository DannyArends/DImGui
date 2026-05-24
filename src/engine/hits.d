/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import boundingbox : computeBoundingBox;
import camera : castRay, tryDrag, tryZoom;
import geometry : setColor;
import intersection : intersects;
import line : createLine;

/** Get a list of intersections between the ray and the objects in the scene */
Intersection[] getHits(ref App app, float[3][2] ray, bool showRay = true) {
  Intersection[] hits;
  for(size_t x = 0; x < app.objects.length; x++) {
    if(!app.objects[x].isVisible) continue;
    if(!app.objects[x].isSelectable) continue;
    if(cast(Line)(app.objects[x]) !is null) continue;
    if(!app.objects[x].skipBoundingBox && app.objects[x].box is null) app.objects[x].computeBoundingBox(app.trace);
    auto intersections = ray.intersects(app.objects[x].box, x);
    app.objects[x].window = false;
    if(intersections.any!(i => i.intersects)) hits ~= intersections;
    else app.objects[x].box.setColor();
  }
  if(showRay) app.objects ~= createLine(ray);
  hits.sort!("a.tmin < b.tmin");
  return hits;
}
