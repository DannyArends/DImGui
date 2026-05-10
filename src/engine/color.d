/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

import ctfeparse : generateColorsEnum;

mixin(generateColorsEnum(import("data/raws/colors.txt")));

/** Color index */
uint colorIndex(Colors c) { foreach(i, m; [EnumMembers!Colors]) { if(m == c) return(cast(uint)i); } return(0u); }

/** Generate a random color */
float[4] randomColor(float alpha = 1.0f) { return([uniform(0.0f, 1.0f), uniform(0.0f, 1.0f), uniform(0.0f, 1.0f), alpha]); }

/** Amino Acid Residue to 'official' colors */
@nogc float[4] residueToColor(string residue) nothrow {
  switch (residue) {
    case "ALA": return Colors.aliceblue;
    case "ARG": return Colors.bisque;
    case "ASN": return Colors.chartreuse;
    case "ASP": return Colors.darkgoldenrod;
    case "ASX": return Colors.darkolivegreen;
    case "CYS": return Colors.yellowgreen;
    case "GLU": return Colors.lime;
    case "GLN": return Colors.lavenderblush;
    case "GLX": return Colors.lightcoral;
    case "GLY": return Colors.lightskyblue;
    case "HIS": return Colors.mediumaquamarine;
    case "ILE": return Colors.mediumspringgreen;
    case "LEU": return Colors.papayawhip;
    case "LYS": return Colors.fuchsia;
    case "MET": return Colors.firebrick;
    case "PHE": return Colors.teal;
    case "PRO": return Colors.seashell;
    case "SER": return Colors.moccasin;
    case "THR": return Colors.peru;
    case "TRP": return Colors.turquoise;
    case "TYR": return Colors.rosybrown;
    case "VAL": return Colors.wheat;
    default: return Colors.white;
  }
}

/** Atom to Jmol color scheme */
@nogc float[4] atomToColor(string atom) nothrow {
  switch (atom) {
    case "H" :  return Colors.jmolWhitesmoke;
    case "He":  return Colors.jmolLightcyan;
    case "Li":  return Colors.jmolViolet;
    case "Be":  return Colors.jmolGreenyellow;
    case "B" :  return Colors.jmolLightpink;
    case "C" :  return Colors.black;
    case "N" :  return Colors.jmolRoyalblue;
    case "O" :  return Colors.jmolRed;
    case "F" :  return Colors.jmolYellowgreen;
    case "Ne":  return Colors.jmolPaleturquoise;
    case "Na":  return Colors.jmolMediumorchid;
    case "Mg":  return Colors.jmolChartreuse;
    case "Al":  return Colors.jmolDarkgray;
    case "Si":  return Colors.jmolWheat;
    case "P" :  return Colors.jmolDarkorange;
    case "S" :  return Colors.jmolYellow;
    case "Cl":  return Colors.jmolLimegreen;
    case "Ar":  return Colors.jmolSkyblue;
    case "K" :  return Colors.jmolDarkorchid;
    case "Ca":  return Colors.jmolLime;
    case "Sc":  return Colors.jmolGainsboro;
    case "Ti":  return Colors.jmolSilver;
    case "V" :  return Colors.jmolDarkgray2;
    case "Cr":  return Colors.jmolDarkgray3;
    case "Mn":  return Colors.jmolMediumpurple;
    case "Fe":  return Colors.jmolChocolate;
    case "Co":  return Colors.jmolLightcoral;
    case "Ni":  return Colors.jmolLimegreen2;
    case "Cu":  return Colors.jmolPeru;
    case "Zn":  return Colors.jmolLightslategray;
    case "Ga":  return Colors.jmolRosybrown;
    case "Ge":  return Colors.jmolSlategray;
    case "As":  return Colors.jmolOrchid;
    case "Se":  return Colors.jmolOrange;
    case "Br":  return Colors.jmolBrown;
    case "Kr":  return Colors.jmolMediumturquoise;
    case "Rb":  return Colors.jmolDarkorchid2;
    case "Sr":  return Colors.lime;
    case "Y" :  return Colors.jmolPaleturquoise2;
    case "Zr":  return Colors.jmolSkyblue2;
    case "Nb":  return Colors.jmolMediumaquamarine;
    case "Mo":  return Colors.jmolMediumaquamarine2;
    case "Tc":  return Colors.jmolLightseagreen;
    case "Ru":  return Colors.jmolDarkcyan;
    case "Rh":  return Colors.jmolTeal;
    case "Pd":  return Colors.jmolTeal2;
    case "Ag":  return Colors.silver;
    case "Cd":  return Colors.jmolKhaki;
    case "In":  return Colors.jmolGray;
    case "Sn":  return Colors.jmolSlategray2;
    case "Sb":  return Colors.jmolMediumpurple2;
    case "Te":  return Colors.jmolDarkgoldenrod;
    case "I" :  return Colors.jmolDarkmagenta;
    case "Xe":  return Colors.jmolSteelblue;
    case "Cs":  return Colors.jmolIndigo;
    case "Ba":  return Colors.jmolLime2;
    case "La":  return Colors.jmolLightskyblue;
    case "Ce":  return Colors.jmolLemonchiffon;
    case "Pr":  return Colors.jmolLightgoldenrodyellow;
    case "Nd":  return Colors.jmolGainsboro2;
    case "Pm":  return Colors.jmolAquamarine;
    case "Sm":  return Colors.jmolAquamarine2;
    case "Eu":  return Colors.jmolAquamarine3;
    case "Gd":  return Colors.jmolTurquoise;
    case "Tb":  return Colors.jmolTurquoise2;
    case "Dy":  return Colors.jmolTurquoise3;
    case "Ho":  return Colors.jmolMediumspringgreen;
    case "Er":  return Colors.jmolSpringgreen;
    case "Tm":  return Colors.jmolLimegreen3;
    case "Yb":  return Colors.jmolLimegreen4;
    case "Lu":  return Colors.jmolForestgreen;
    case "Hf":  return Colors.jmolMediumturquoise2;
    case "Ta":  return Colors.jmolCornflowerblue;
    case "W" :  return Colors.jmolDodgerblue;
    case "Re":  return Colors.jmolSteelblue2;
    case "Os":  return Colors.jmolTeal3;
    case "Ir":  return Colors.jmolTeal4;
    case "Pt":  return Colors.jmolLightgray;
    case "Au":  return Colors.jmolGold;
    case "Hg":  return Colors.jmolSilver2;
    case "Tl":  return Colors.jmolSienna;
    case "Pb":  return Colors.jmolDimgray;
    case "Bi":  return Colors.jmolDarkorchid3;
    case "Po":  return Colors.jmolSaddlebrown;
    case "At":  return Colors.jmolDimgray2;
    case "Rn":  return Colors.jmolSteelblue3;
    case "Fr":  return Colors.jmolIndigo2;
    case "Ra":  return Colors.jmolGreen;
    case "Ac":  return Colors.jmolCornflowerblue2;
    case "Th":  return Colors.jmolDeepskyblue;
    case "Pa":  return Colors.jmolDeepskyblue2;
    case "U" :  return Colors.jmolDodgerblue2;
    default: return Colors.white;
  }
}
