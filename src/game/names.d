/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import phobos;

enum NameStyle { Dwarf, Elf, Human, Orc }

string pick(immutable string[] arr) { return arr[uniform(0, $)]; }

/** Per-style syllable pools: prefix, vowel, and optional suffix (empty = two-syllable names). */
struct Syllables { immutable string[] c1, v, c2; }

static immutable Syllables[NameStyle.max + 1] nameTables = [
  NameStyle.Dwarf: Syllables(["B","D","G","K","T","N","M","F","Th","Kh","Gr","Dr","Br"],
                             ["ur","or","ar","os","ot","ok","ir","al","am","ak"],
                             ["in","im","ul","un","ot","ok","is","ith","uth","ast"]),
  NameStyle.Elf:   Syllables(["L","C","G","F","Th","El","Ar","Gl","Er","Cel","Gal","Lin"],
                             ["a","e","i","o","ae","ai","ie","ia","el","al"],
                             ["n","l","r","iel","wen","mir","dir","las","ron","rian","dor"]),
  NameStyle.Human: Syllables(["Al","Ed","God","Os","Wulf","Har","Beo","Sig","Aed","Cyn"],
                             ["ric","win","red","bert","mund","wulf","here","wyn","mer","stan"],
                             []),
  NameStyle.Orc:   Syllables(["Gr","Kr","Br","Tr","Ug","Gh","Kh","Sk","Zg","Rak"],
                             ["ak","ok","uk","ag","og","ug","ash","oth","akh","rak"],
                             ["nar","nur","nul","nak","nor","gar","gur","kar","kur","rak"]),
];

/** Random race-styled name: two or three syllables, capitalized. */
string randomName(NameStyle style) {
  auto s = nameTables[style];
  string name = pick(s.c1) ~ pick(s.v);
  if(s.c2.length) name ~= pick(s.c2);
  return (name.capitalize);
}

void randomizeName(T)(ref T d, NameStyle style = NameStyle.Dwarf) {
  string fn = randomName(style), ln;
  do { ln = randomName(style); } while(ln == fn);
  d.first[] = '\0'; d.first[0..min(fn.length, d.first.length)] = fn[0..min(fn.length, d.first.length)];
  d.last[]  = '\0'; d.last[0..min(ln.length, d.last.length)] = ln[0..min(ln.length, d.last.length)];
}
