/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import std.algorithm : reverse;

struct DeletionQueue {
  void delegate()[] queue;

  void add(void delegate() fn){ queue ~= fn; }
  void flush(){
    foreach(fn; queue.reverse){ fn(); }
    queue = [];
  }
}
