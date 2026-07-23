/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

struct VramUsage { ulong deviceUsed, deviceBudget, hostUsed; }

VramUsage queryVRAM(ref App app) {
  VkPhysicalDeviceMemoryBudgetPropertiesEXT budget = { sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_BUDGET_PROPERTIES_EXT };
  VkPhysicalDeviceMemoryProperties2 props2 = { sType: VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PROPERTIES_2, pNext: &budget };
  vkGetPhysicalDeviceMemoryProperties2(app.physicalDevice, &props2);
  VramUsage u;
  foreach(i; 0 .. props2.memoryProperties.memoryHeapCount) {
    if(props2.memoryProperties.memoryHeaps[i].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT) {
      u.deviceUsed += budget.heapUsage[i]; u.deviceBudget += budget.heapBudget[i]; 
    }else{ u.hostUsed += budget.heapUsage[i]; }
  }
  return u;
}

