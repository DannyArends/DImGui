/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 *
 * Load and render amino acids, atoms, etc stored in a protein database (PDB) and mmCIF file file
 * PDB format description version 3.3, ftp://ftp.wwpdb.org/pub/pdb/doc/format_descriptions/Format_v33_A4.pdf
 * PDB mmCIF File Format, http://mmcif.wwpdb.org/pdbx-mmcif-home-page.html
 */
import engine;

import color : atomToColor, Colors, residueToColor;
import geometry : Instance, Geometry, addVertex;
import io : readFile, isfile;
import vertex : Vertex;

enum : string { 
  ATOM = "ATOM ",
  HETATOM = "HETATM ",
}

struct Atom {
  string element;
  float[3] location;
  alias location this;
}

struct AminoAcid {
  string name;
  Atom[string] atoms;
  alias atoms this;
}

struct Peptide {
  AminoAcid[int] chain;
  alias chain this;

  @property Atom[] atoms() const nothrow {
    Atom[] chain;
    foreach (k; sort(this.keys)) {
      chain ~= this[k].atoms.values;
    }
    return(chain);
  }

  @property bool isAAChain() const nothrow {
    foreach (k; sort(this.keys)) {
      if(residueToColor(this[k].name) == Colors.white) return(false);
    }
    return(true);
  }
}

struct Protein {
  Peptide[string] subunits;
  alias subunits this;

  @property Atom[] atoms() const nothrow {
    Atom[] chain;
    foreach (p; sort(this.keys)) {
      chain ~= this[p].atoms;
      //info("Length of chain[%s]: %d isAA:%d\n", toStringz(p), this[p].atoms.length, this[p].isAAChain());
    }
    return(chain);
  }
}

/** Pointcloud of all Atoms
 */
class AtomCloud : Geometry {
  this(Atom[] atoms) {
    foreach(i, Atom atom; atoms) {
      vertices ~= Vertex(atom.location, [1.0f, 1.0f], atomToColor(atom.element));
      indices ~= cast(uint)i;
    }
    instances = [Instance()];
    topology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
    name = (){ return(typeof(this).stringof); };
  }
}

/** AminoAcids rendering
 */
class AminoAcidCloud : Geometry {
  this(AminoAcid[int] peptides) nothrow {
    uint vs, vi, vp = 0;
    foreach (uint i; sort(peptides.keys)) {
      foreach (s; ["N", "CA", "C"]) {
        if (s in peptides[i].atoms) {
          vertices ~= Vertex(peptides[i].atoms[s].location, [1.0f, 1.0f], residueToColor(peptides[i].name));
          vi = cast(uint)(vertices.length - 1);
          if (s == "N") vs = vi;
          else
            indices ~= [vs, vi];
          if (vp != 0) indices ~= [vp, vi];
          vp = vi;
        }
      }
    }
    instances = [Instance()];
    topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_STRIP;
    name = (){ return(typeof(this).stringof); };
  }
}

// Protein backbone
class Backbone : Geometry {
  this(AminoAcid[int] peptides) nothrow {
    uint vi, vp = 0;
    foreach (uint i; sort(peptides.keys)) {
      foreach (s; ["N", "CA", "C", "O"]) {
        if (s in peptides[i].atoms) {
          vertices ~= Vertex(peptides[i].atoms[s].location, [1.0f, 1.0f]);
          vi =  cast(uint)(vertices.length - 1);
          if (s != "O"){ indices ~= [vp, vi]; vp = vi; }
          if (s == "O"){ indices ~= [vp, vi]; vertices[vi].color = [1.0f, 0.0f, 0.0f, 1.0f]; }
        }
      }
    }
    instances = [Instance()];
    topology = VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
    name = (){ return(typeof(this).stringof); };
  }
}

/** loadProtein
 * See: PDB format description version 3.3, ftp://ftp.wwpdb.org/pub/pdb/doc/format_descriptions/Format_v33_A4.pdf
 */
Protein loadProtein(const(char)* path, bool verbose = false) {
  Protein protein;
  if (!isfile(path)) {
    SDL_Log("Error: No such PDB file: %s\n", path);
    return protein;
  }
  size_t nAtoms = 0, nAminoAcids = 0, nPeptides = 0;
  string chainid;
  int residueid;
  string name, residue;
  string[] content = to!string(readFile(path)).splitLines();
  if(verbose) SDL_Log("Read: %d lines from '%s'\n", content.length, path);
  foreach (string l; content) {
    l = chomp(l);
    if(l.startsWith(ATOM)) {
      if(l.length < 78) continue;
      chainid = to!string(l[21]);
      residueid = to!int(strip(l[22 .. 26]));
      name = strip(l[12 .. 16]);
      residue = strip(l[17 .. 20]);

      Atom atom = Atom(strip(l[76 .. 78]), [to!float(strip(l[30 .. 38])),to!float(strip(l[38 .. 46])),to!float(strip(l[46 .. 54]))]);
      if (!(chainid in protein)) { 
        protein[chainid] = Peptide();
        nPeptides++;
      }
      if (!(residueid in protein[chainid])) {
        protein[chainid][residueid] = AminoAcid(residue);
        nAminoAcids++;
      }
      //writefln("[%s][%d] %s [%s]  %s", chainid, residueid, residue, name, atom);
      protein[chainid][residueid].atoms[name] = atom;
      nAtoms++;
    }
  }
  if(verbose) SDL_Log("Loaded: %d Atoms, %d AA, %d Peptides\n", nAtoms, nAminoAcids, nPeptides);
  return(protein);
}

/** loadProteinCif
 * See: PDB mmCIF File Format, http://mmcif.wwpdb.org/pdbx-mmcif-home-page.html
 */
Protein loadProteinCif(const(char)* path, string chain = "", bool verbose = true) {
  Protein protein;
  if (!isfile(path)) {
    SDL_Log("Error: No such CIF file: %s\n", path);
    return protein;
  }
  size_t nAtoms = 0, nAminoAcids = 0, nPeptides = 0;
  string[] content = to!string(readFile(path)).splitLines();
  if(verbose) SDL_Log("Read: %d lines from '%s'\n", content.length, path);
  auto r = regex(r"(\S+)[ ]+");
  foreach (string l; content) {
    l = chomp(l);
    if(l.startsWith(ATOM)) {
      auto cnt = 0;
      auto matches = matchAll(l, r);
      string[] values;
      foreach (c; matches) { values ~= c[0]; }
      auto chainid = strip(values[6]);
      if (chainid == chain || chain == "") {
        auto residueid = to!int(strip(values[8]));
        auto residue = strip(values[5]);
        auto name = strip(values[3]);

        Atom atom = Atom(strip(values[2]), [to!float(strip(values[10])), to!float(strip(values[11])), to!float(strip(values[12]))] );
        if (!(chainid in protein)) { 
          protein[chainid] = Peptide();
          nPeptides++;
        }
        if (!(residueid in protein[chainid])) {
          protein[chainid][residueid] = AminoAcid(residue);
          nAminoAcids++;
        }
        //writefln("[%s][%d] %s [%s]  %s", chainid, residueid, residue, name, atom);
        protein[chainid][residueid].atoms[name] = atom;
        nAtoms++;
      }
    }
  }
  if(verbose) SDL_Log("Loaded: %d Atoms, %d AA, %d Peptides\n", nAtoms, nAminoAcids, nPeptides);
  return(protein);
}

