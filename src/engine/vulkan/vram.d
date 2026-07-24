/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import utils : humanCount;
import widgets : text;

struct VramUsage {
  long deviceUsed, deviceBudget;   // device-local heaps — true VRAM on a discrete GPU
  long hostUsed, hostBudget;     // non-device-local heaps — system RAM; staging/mapped buffers live here on desktop
  long totalUsed, totalBudget;    // every heap summed
  uint  heapCount;
}

VramUsage queryVRAM(ref App app) {
  VkPhysicalDeviceMemoryBudgetPropertiesEXT budget = { sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT };
  VkPhysicalDeviceMemoryProperties2 props2 = { sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2, pNext: &budget };
  vkGetPhysicalDeviceMemoryProperties2(app.physicalDevice, &props2);

  VramUsage u;
  auto mp = props2.memoryProperties;
  u.heapCount = mp.memoryHeapCount;
  foreach(i; 0 .. mp.memoryHeapCount) {
    immutable used = budget.heapUsage[i];
    immutable cap  = budget.heapBudget[i];
    u.totalUsed += used; u.totalBudget += cap;
    if(mp.memoryHeaps[i].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) {
      u.deviceUsed += used; u.deviceBudget += cap;
    } else { u.hostUsed += used; u.hostBudget += cap; }
  }
  return u;
}

void printVRAM(VramUsage vRam) {
  text("Geometry VRAM: %s | %s & %s | %s", humanCount(vRam.deviceUsed), humanCount(vRam.deviceBudget), humanCount(vRam.totalUsed), humanCount(vRam.totalBudget));
}

extern(C) nothrow @nogc void deviceMemoryReportCallback(const(VkDeviceMemoryReportCallbackDataEXT)* data, void* userData) {
  App* app = cast(App*) userData;
  final switch (data.type) with (VkDeviceMemoryReportEventTypeEXT) {
    case VK_DEVICE_MEMORY_REPORT_EVENT_TYPE_ALLOCATE_EXT: app.vramLedger.deviceUsed += data.size; break;
    case VK_DEVICE_MEMORY_REPORT_EVENT_TYPE_FREE_EXT: app.vramLedger.deviceUsed -= data.size; break;
    case VK_DEVICE_MEMORY_REPORT_EVENT_TYPE_IMPORT_EXT: app.vramLedger.hostUsed += data.size; break;
    case VK_DEVICE_MEMORY_REPORT_EVENT_TYPE_UNIMPORT_EXT: app.vramLedger.hostUsed -= data.size; break;
    case VK_DEVICE_MEMORY_REPORT_EVENT_TYPE_ALLOCATION_FAILED_EXT: SDL_Log("ALLOC_FAIL"); break;
    case VK_DEVICE_MEMORY_REPORT_EVENT_TYPE_MAX_ENUM_EXT: SDL_Log("MAX_ENUM"); break;
  }
}
