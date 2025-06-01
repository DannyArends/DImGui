/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import std.algorithm : remove, reverse;

struct DeletionQueue {
  void delegate()[] queue;
  alias queue this;

  void add(void delegate() fn){ queue ~= fn; }
  void flush(){
    foreach(fn; queue.reverse){ fn(); }
    queue = [];
  }
}

struct CheckedDeletionQueue {
  bool delegate()[] queue;
  alias queue this;

  void add(bool delegate() fn){ queue ~= fn; }
  void flush(){
    size_t[] idx;
    foreach(i, fn; queue.reverse){ if(fn()) idx ~= i;}
    foreach(i; idx.reverse) { queue = queue.remove(i); }
  }
}
