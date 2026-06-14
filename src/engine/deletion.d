/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import buffer : cleanup;
import framebuffer : cleanup;

alias delegateT = @nogc bool delegate(bool) nothrow;

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
  delegateT[] queue;
  alias queue this;

  void add(delegateT fn){ queue ~= fn; }
  @nogc void flush(bool force = false) nothrow {
    size_t i = 0;
    foreach(fn; queue){ if(!fn(force)){ queue[i++] = fn; } }
    queue = queue[0 .. i];
  }
}

/** Defer destruction of any resource until its frame's fence signals (or force). */
void deAllocate(T)(ref App app, T object) {
  auto deadline = app.totalFramesRendered + app.framesInFlight;
  app.bufferDeletionQueue.add( (bool force) @nogc nothrow {
    if(force || app.totalFramesRendered >= deadline) { app.cleanup(object); return true; }
    return false;
  });
}
