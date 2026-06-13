/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : cleanup;
import framebuffer : cleanup;

struct DeletionQueue {
  void delegate()[] queue;
  alias queue this;

  void add(void delegate() fn){ queue ~= fn; }
  void flush(){
    foreach_reverse(fn; queue){ fn(); }
    queue = [];
  }
}

struct CheckedDeletionQueue {
  bool delegate(bool)[] queue;
  alias queue this;

  void add(bool delegate(bool) fn){ queue ~= fn; }
  void flush(bool force = false) {
    bool delegate(bool)[] keep;
    foreach(fn; queue){ if(!fn(force)) keep ~= fn; }
    queue = keep;
  }
}

/** Defer destruction of any resource until its frame's fence signals (or force). */
void deAllocate(T)(ref App app, T object) {
  auto deadline = app.totalFramesRendered + app.framesInFlight;
  app.bufferDeletionQueue.add((bool force){
    if(force || app.totalFramesRendered >= deadline) { app.cleanup(object); return true; }
    return false;
  });
}
