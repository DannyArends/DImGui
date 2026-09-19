/**
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 *
 * Windows-only: supply the CRT SIMD/arch symbols LDC 1.42's ImportC leaves unresolved against MSVC 14.51.
 */
version(Windows){
  import core.bitop : bsf, bsr;

  struct __m128i { long[2] q; } /// 16-byte POD: Win64 returns via sret / passes by ref, matching ImportC's __m128i
  struct __m256i { long[4] q; } /// 32-byte POD: same ABI as ImportC's __m256i

  pragma(mangle, "_mm_cvtsi32_si128") extern(C) __m128i _s_cvtsi32_si128(int a) {
    __m128i r; r.q[0] = cast(uint)a; r.q[1] = 0; return(r);
  }
  pragma(mangle, "_mm_set1_epi16") extern(C) __m128i _s_set1_epi16(short a)  {
    __m128i r; auto p = cast(short*)r.q.ptr; foreach(i; 0 .. 8) p[i] = a; return(r);
  }
  pragma(mangle, "_mm_loadu_si128") extern(C) __m128i _s_loadu_si128(const(__m128i)* s) {
    __m128i r; (cast(ubyte*)r.q.ptr)[0 .. 16] = (cast(const(ubyte)*)s)[0 .. 16]; return(r);
  }
  pragma(mangle, "_mm_loadl_epi64") extern(C) __m128i _s_loadl_epi64(const(__m128i)* s) {
    __m128i r; r.q[1] = 0; (cast(ubyte*)r.q.ptr)[0 .. 8] = (cast(const(ubyte)*)s)[0 .. 8]; return(r); 
  }
  pragma(mangle, "_mm_cmpeq_epi16") extern(C) __m128i _s_cmpeq_epi16(__m128i a, __m128i b) {
    __m128i r; auto pa = cast(short*)a.q.ptr, pb = cast(short*)b.q.ptr, pr = cast(short*)r.q.ptr; foreach(i; 0 .. 8) pr[i] = (pa[i] == pb[i]) ? cast(short)0xFFFF : 0; return(r);
  }
  pragma(mangle, "_mm_movemask_epi8") extern(C) int _s_movemask_epi8(__m128i a) {
    auto p = cast(ubyte*)a.q.ptr; int m = 0; foreach(i; 0 .. 16) if(p[i] & 0x80) m |= (1 << i); return(m);
  }

  pragma(mangle, "_mm256_loadu_si256") extern(C) __m256i _s256_loadu(const(__m256i)* s) {
    __m256i r; (cast(ubyte*)r.q.ptr)[0 .. 32] = (cast(const(ubyte)*)s)[0 .. 32]; return(r);
  }
  pragma(mangle, "_mm256_cmpeq_epi16") extern(C) __m256i _s256_cmpeq_epi16(__m256i a, __m256i b) { 
    __m256i r; auto pa = cast(short*)a.q.ptr, pb = cast(short*)b.q.ptr, pr = cast(short*)r.q.ptr; foreach(i; 0 .. 16) pr[i] = (pa[i] == pb[i]) ? cast(short)0xFFFF : 0; return(r); 
  }
  pragma(mangle, "_mm256_movemask_epi8") extern(C) int _s256_movemask_epi8(__m256i a) { 
    auto p = cast(ubyte*)a.q.ptr; int m = 0; foreach(i; 0 .. 32) if(p[i] & 0x80) m |= (1 << i); return(m);
  }
  pragma(mangle, "_mm256_broadcastw_epi16") extern(C) __m256i _s256_broadcastw(__m128i a) {
    short w = *cast(short*)a.q.ptr; __m256i r; auto pr = cast(short*)r.q.ptr; foreach(i; 0 .. 16) pr[i] = w; return(r);
  }

  // _BitScanForward{,64}: drop once on an LDC with a >=2.114 druntime (they land there and would duplicate)
  pragma(mangle, "_BitScanForward") extern(C) ubyte _s_bsf(uint* index, uint mask)    { if(mask == 0) return(0); *index = bsf(mask); return(1); }
  pragma(mangle, "_BitScanForward64") extern(C) ubyte _s_bsf64(uint* index, ulong mask) { if(mask == 0) return(0); *index = cast(uint)bsf(mask); return(1); }

  pragma(mangle, "_BitScanReverse") extern(C) ubyte _s_bsr(uint* index, uint mask)    { if(mask == 0) return(0); *index = bsr(mask); return(1); }
  pragma(mangle, "_BitScanReverse64") extern(C) ubyte _s_bsr64(uint* index, ulong mask) { if(mask == 0) return(0); *index = cast(uint)bsr(mask); return(1); }
}
