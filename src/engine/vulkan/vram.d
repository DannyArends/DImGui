/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import utils : humanCount;
import widgets : text;

struct VramUsage {
  long deviceUsed, deviceBudget;   // device-local heaps — true VRAM on a discrete GPU
}

bool hasMemoryCallback(ref App app) { return(app.deviceExtensions.canFind!(e => fromStringz(e) == "VK_EXT_device_memory_report")); }
bool hasMemoryBudget(ref App app) { return(app.deviceExtensions.canFind!(e => fromStringz(e) == "VK_EXT_memory_budget")); }

void queryVRAM(ref App app) {
  if(!app.hasMemoryBudget()) return;
  VkPhysicalDeviceMemoryBudgetPropertiesEXT budget = { sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT };
  VkPhysicalDeviceMemoryProperties2 props2 = { sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2, pNext: &budget };
  vkGetPhysicalDeviceMemoryProperties2(app.physicalDevice, &props2);
  auto mp = props2.memoryProperties;

  app.vramLedger = VramUsage.init;
  foreach(i; 0 .. mp.memoryHeapCount) {
    immutable used = budget.heapUsage[i];
    immutable cap = budget.heapBudget[i];
    if(mp.memoryHeaps[i].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) { app.vramLedger.deviceUsed += used; app.vramLedger.deviceBudget += cap; }
  }
}

void printVRAM(ref App app) {
  VramUsage vRam = app.vramLedger;
  if(app.hasMemoryBudget()) {
    text("Geometry VRAM: %s | %s", humanCount(vRam.deviceUsed), humanCount(vRam.deviceBudget));
  }else if(app.hasMemoryCallback()) { text("Geometry VRAM: %s", humanCount(vRam.deviceUsed)); }
}

extern(System) nothrow @nogc void memoryReportCallback(const(VkDeviceMemoryReportCallbackDataEXT)* data, void* userData) {
  App* app = cast(App*) userData;
  bool alloc = (data.type == VK_DEVICE_MEMORY_REPORT_EVENT_TYPE_ALLOCATE_EXT);
  bool free = (data.type == VK_DEVICE_MEMORY_REPORT_EVENT_TYPE_FREE_EXT);
  if(!alloc && !free) return;
  app.vramLedger.deviceUsed += (alloc ? cast(long)data.size : -cast(long)data.size);
}

