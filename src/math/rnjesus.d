/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */
import engine;
enum NameStyle { Dwarf, Elf, Human, Orc }

string pick(immutable string[] arr) { return arr[uniform(0, $)]; }

string dwarfName() {
  static immutable string[] c1 = ["B","D","G","K","T","N","M","F","Th","Kh","Gr","Dr","Br"];
  static immutable string[] v  = ["ur","or","ar","os","ot","ok","ir","al","am","ak"];
  static immutable string[] c2 = ["in","im","ul","un","ot","ok","is","ith","uth","ast"];
  return (pick(c1) ~ pick(v) ~ pick(c2)).capitalize;
}

string elfName() {
  static immutable string[] c1 = ["L","C","G","F","Th","El","Ar","Gl","Er","Cel","Gal","Lin"];
  static immutable string[] v  = ["a","e","i","o","ae","ai","ie","ia","el","al"];
  static immutable string[] c2 = ["n","l","r","iel","wen","mir","dir","las","ron","rian","dor"];
  return (pick(c1) ~ pick(v) ~ pick(c2)).capitalize;
}

string humanName() {
  static immutable string[] c1 = ["Al","Ed","God","Os","Wulf","Har","Beo","Sig","Aed","Cyn"];
  static immutable string[] v  = ["ric","win","red","bert","mund","wulf","here","wyn","mer","stan"];
  return (pick(c1) ~ pick(v)).capitalize;
}

string orcName() {
  static immutable string[] c1 = ["Gr","Kr","Br","Tr","Ug","Gh","Kh","Sk","Zg","Rak"];
  static immutable string[] v  = ["ak","ok","uk","ag","og","ug","ash","oth","akh","rak"];
  static immutable string[] c2 = ["nar","nur","nul","nak","nor","gar","gur","kar","kur","rak"];
  return (pick(c1) ~ pick(v) ~ pick(c2)).capitalize;
}

void randomizeName(T)(ref T d, NameStyle style = NameStyle.Dwarf) {
  string fn, ln;
  final switch(style) {
    case NameStyle.Dwarf: fn = dwarfName(); do { ln = dwarfName(); } while(ln == fn); break;
    case NameStyle.Elf: fn = elfName(); do { ln = elfName(); } while(ln == fn); break;
    case NameStyle.Human: fn = humanName(); do { ln = humanName(); } while(ln == fn); break;
    case NameStyle.Orc: fn = orcName(); do { ln = orcName(); } while(ln == fn); break;
  }
  d.first[] = '\0'; d.first[0..min(fn.length, d.first.length)] = fn[0..min(fn.length, d.first.length)];
  d.last[]  = '\0'; d.last[0..min(ln.length, d.last.length)] = ln[0..min(ln.length, d.last.length)];
}
