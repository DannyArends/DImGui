/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import engine;

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

/* Named colors */
enum Colors : float[4] {
    white = [1.0f, 1.0f, 1.0f, 1.0f],
    black = [0.0f, 0.0f, 0.0f, 1.0f],

    red  = [1.0f, 0.0f, 0.0f, 1.0f],
    green = [0.0f, 1.0f, 0.0f, 1.0f],
    blue = [0.0f, 0.0f, 1.0f, 1.0f],

    skyNight = [0.02f, 0.02f,  0.08f, 1.0f],
    skyDawn = [0.7f, 0.35f,  0.15f, 1.0f],
    skyDay = [0.4f, 0.65f,  0.9f, 1.0f],
    sunNight = [0.0f, 0.0f, 0.0f, 1.0f],
    sunDawn = [0.4f, 0.25f, 0.05f, 1.0f],
    sunNoon = [0.7f, 0.65f, 0.3f, 1.0f],

    aliceblue = [0.941f, 0.973f, 1.000f, 1.0f],
    antiquewhite = [0.980f, 0.922f, 0.843f, 1.0f],
    aqua = [0.000f, 1.000f, 1.000f, 1.0f],
    aquamarine = [0.498f, 1.000f, 0.831f, 1.0f],
    azure = [0.941f, 1.000f, 1.000f, 1.0f],
    beige = [0.961f, 0.961f, 0.863f, 1.0f],
    bisque = [1.000f, 0.894f, 0.769f, 1.0f],
    blanchedalmond = [1.000f, 0.922f, 0.804f, 1.0f],
    blueviolet = [0.541f, 0.169f, 0.886f, 1.0f],
    brown = [0.647f, 0.165f, 0.165f, 1.0f],
    burlywood = [0.871f, 0.722f, 0.529f, 1.0f],
    cadetblue = [0.373f, 0.620f, 0.627f, 1.0f],
    chartreuse = [0.498f, 1.000f, 0.000f, 1.0f],
    chocolate = [0.824f, 0.412f, 0.118f, 1.0f],
    coral = [1.000f, 0.498f, 0.314f, 1.0f],
    cornflowerblue = [0.392f, 0.584f, 0.929f, 1.0f],
    cornsilk = [1.000f, 0.973f, 0.863f, 1.0f],
    crimson = [0.863f, 0.078f, 0.235f, 1.0f],
    cyan = [0.000f, 1.000f, 1.000f, 1.0f],
    darkblue = [0.000f, 0.000f, 0.545f, 1.0f],
    darkcyan = [0.000f, 0.545f, 0.545f, 1.0f],
    darkgoldenrod = [0.722f, 0.525f, 0.043f, 1.0f],
    darkgray = [0.663f, 0.663f, 0.663f, 1.0f],
    darkgreen = [0.000f, 0.392f, 0.000f, 1.0f],
    darkgrey = [0.663f, 0.663f, 0.663f, 1.0f],
    darkkhaki = [0.741f, 0.718f, 0.420f, 1.0f],
    darkmagenta = [0.545f, 0.000f, 0.545f, 1.0f],
    darkolivegreen = [0.333f, 0.420f, 0.184f, 1.0f],
    darkorange = [1.000f, 0.549f, 0.000f, 1.0f],
    darkorchid = [0.600f, 0.196f, 0.800f, 1.0f],
    darkred = [0.545f, 0.000f, 0.000f, 1.0f],
    darksalmon = [0.914f, 0.588f, 0.478f, 1.0f],
    darkseagreen = [0.561f, 0.737f, 0.561f, 1.0f],
    darkslateblue = [0.282f, 0.239f, 0.545f, 1.0f],
    darkslategray = [0.184f, 0.310f, 0.310f, 1.0f],
    darkslategrey = [0.184f, 0.310f, 0.310f, 1.0f],
    darkturquoise = [0.000f, 0.808f, 0.820f, 1.0f],
    darkviolet = [0.580f, 0.000f, 0.827f, 1.0f],
    deeppink = [1.000f, 0.078f, 0.576f, 1.0f],
    deepskyblue = [0.000f, 0.749f, 1.000f, 1.0f],
    dimgray = [0.412f, 0.412f, 0.412f, 1.0f],
    dimgrey = [0.412f, 0.412f, 0.412f, 1.0f],
    dodgerblue = [0.118f, 0.565f, 1.000f, 1.0f],
    firebrick = [0.698f, 0.133f, 0.133f, 1.0f],
    floralwhite = [1.000f, 0.980f, 0.941f, 1.0f],
    forestgreen = [0.133f, 0.545f, 0.133f, 1.0f],
    fuchsia = [1.000f, 0.000f, 1.000f, 1.0f],
    gainsboro = [0.863f, 0.863f, 0.863f, 1.0f],
    ghostwhite = [0.973f, 0.973f, 1.000f, 1.0f],
    gold = [1.000f, 0.843f, 0.000f, 1.0f],
    goldenrod = [0.855f, 0.647f, 0.125f, 1.0f],
    gray = [0.502f, 0.502f, 0.502f, 1.0f],
    lime = [0.000f, 0.502f, 0.000f, 1.0f],
    greenyellow = [0.678f, 1.000f, 0.184f, 1.0f],
    grey = [0.502f, 0.502f, 0.502f, 1.0f],
    honeydew = [0.941f, 1.000f, 0.941f, 1.0f],
    hotpink = [1.000f, 0.412f, 0.706f, 1.0f],
    indianred = [0.804f, 0.361f, 0.361f, 1.0f],
    indigo = [0.294f, 0.000f, 0.510f, 1.0f],
    ivory = [1.000f, 1.000f, 0.941f, 1.0f],
    khaki = [0.941f, 0.902f, 0.549f, 1.0f],
    lavender = [0.902f, 0.902f, 0.980f, 1.0f],
    lavenderblush = [1.000f, 0.941f, 0.961f, 1.0f],
    lawngreen = [0.486f, 0.988f, 0.000f, 1.0f],
    lemonchiffon = [1.000f, 0.980f, 0.804f, 1.0f],
    lightblue = [0.678f, 0.847f, 0.902f, 1.0f],
    lightcoral = [0.941f, 0.502f, 0.502f, 1.0f],
    lightcyan = [0.878f, 1.000f, 1.000f, 1.0f],
    lightgoldenrodyellow = [0.980f, 0.980f, 0.824f, 1.0f],
    lightgray = [0.827f, 0.827f, 0.827f, 1.0f],
    lightgreen = [0.565f, 0.933f, 0.565f, 1.0f],
    lightgrey = [0.827f, 0.827f, 0.827f, 1.0f],
    lightpink = [1.000f, 0.714f, 0.757f, 1.0f],
    lightsalmon = [1.000f, 0.627f, 0.478f, 1.0f],
    lightseagreen = [0.125f, 0.698f, 0.667f, 1.0f],
    lightskyblue = [0.529f, 0.808f, 0.980f, 1.0f],
    lightslategray = [0.467f, 0.533f, 0.600f, 1.0f],
    lightslategrey = [0.467f, 0.533f, 0.600f, 1.0f],
    lightsteelblue = [0.690f, 0.769f, 0.871f, 1.0f],
    lightyellow = [1.000f, 1.000f, 0.878f, 1.0f],
    limegreen = [0.196f, 0.804f, 0.196f, 1.0f],
    linen = [0.980f, 0.941f, 0.902f, 1.0f],
    magenta = [1.000f, 0.000f, 1.000f, 1.0f],
    maroon = [0.502f, 0.000f, 0.000f, 1.0f],
    mediumaquamarine = [0.400f, 0.804f, 0.667f, 1.0f],
    mediumblue = [0.000f, 0.000f, 0.804f, 1.0f],
    mediumorchid = [0.729f, 0.333f, 0.827f, 1.0f],
    mediumpurple = [0.576f, 0.439f, 0.859f, 1.0f],
    mediumseagreen = [0.235f, 0.702f, 0.443f, 1.0f],
    mediumslateblue = [0.482f, 0.408f, 0.933f, 1.0f],
    mediumspringgreen = [0.000f, 0.980f, 0.604f, 1.0f],
    mediumturquoise = [0.282f, 0.820f, 0.800f, 1.0f],
    mediumvioletred = [0.780f, 0.082f, 0.522f, 1.0f],
    midnightblue = [0.098f, 0.098f, 0.439f, 1.0f],
    mintcream = [0.961f, 1.000f, 0.980f, 1.0f],
    mistyrose = [1.000f, 0.894f, 0.882f, 1.0f],
    moccasin = [1.000f, 0.894f, 0.710f, 1.0f],
    navajowhite = [1.000f, 0.871f, 0.678f, 1.0f],
    navy = [0.000f, 0.000f, 0.502f, 1.0f],
    oldlace = [0.992f, 0.961f, 0.902f, 1.0f],
    olive = [0.502f, 0.502f, 0.000f, 1.0f],
    olivedrab = [0.420f, 0.557f, 0.137f, 1.0f],
    orange = [1.000f, 0.647f, 0.000f, 1.0f],
    orangered = [1.000f, 0.271f, 0.000f, 1.0f],
    orchid = [0.855f, 0.439f, 0.839f, 1.0f],
    palegoldenrod = [0.933f, 0.910f, 0.667f, 1.0f],
    palegreen = [0.596f, 0.984f, 0.596f, 1.0f],
    paleturquoise = [0.686f, 0.933f, 0.933f, 1.0f],
    palevioletred = [0.859f, 0.439f, 0.576f, 1.0f],
    papayawhip = [1.000f, 0.937f, 0.835f, 1.0f],
    peachpuff = [1.000f, 0.855f, 0.725f, 1.0f],
    peru = [0.804f, 0.522f, 0.247f, 1.0f],
    pink = [1.000f, 0.753f, 0.796f, 1.0f],
    plum = [0.867f, 0.627f, 0.867f, 1.0f],
    powderblue = [0.690f, 0.878f, 0.902f, 1.0f],
    purple = [0.502f, 0.000f, 0.502f, 1.0f],
    rosybrown = [0.737f, 0.561f, 0.561f, 1.0f],
    royalblue = [0.255f, 0.412f, 0.882f, 1.0f],
    saddlebrown = [0.545f, 0.271f, 0.075f, 1.0f],
    salmon = [0.980f, 0.502f, 0.447f, 1.0f],
    sandybrown = [0.957f, 0.643f, 0.376f, 1.0f],
    seagreen = [0.180f, 0.545f, 0.341f, 1.0f],
    seashell = [1.000f, 0.961f, 0.933f, 1.0f],
    sienna = [0.627f, 0.322f, 0.176f, 1.0f],
    silver = [0.753f, 0.753f, 0.753f, 1.0f],
    skyblue = [0.529f, 0.808f, 0.922f, 1.0f],
    slateblue = [0.416f, 0.353f, 0.804f, 1.0f],
    slategray = [0.439f, 0.502f, 0.565f, 1.0f],
    snow = [1.000f, 0.980f, 0.980f, 1.0f],
    springgreen = [0.000f, 1.000f, 0.498f, 1.0f],
    steelblue = [0.275f, 0.510f, 0.706f, 1.0f],
    tan = [0.824f, 0.706f, 0.549f, 1.0f],
    teal = [0.000f, 0.502f, 0.502f, 1.0f],
    thistle = [0.847f, 0.749f, 0.847f, 1.0f],
    tomato = [1.000f, 0.388f, 0.278f, 1.0f],
    turquoise = [0.251f, 0.878f, 0.816f, 1.0f],
    violet = [0.933f, 0.510f, 0.933f, 1.0f],
    wheat = [0.961f, 0.871f, 0.702f, 1.0f],
    whitesmoke = [0.961f, 0.961f, 0.961f, 1.0f],
    yellow = [1.000f, 1.000f, 0.000f, 1.0f],
    yellowgreen = [0.604f, 0.804f, 0.196f, 1.0f],
    // Jmol element colors
    jmolWhitesmoke = [0.933f, 0.933f, 0.933f, 1.0f],  // H
    jmolLightcyan = [0.851f, 1.000f, 1.000f, 1.0f],  // He
    jmolViolet = [0.800f, 0.502f, 1.000f, 1.0f],  // Li
    jmolGreenyellow = [0.761f, 1.000f, 0.000f, 1.0f],  // Be
    jmolLightpink = [1.000f, 0.710f, 0.710f, 1.0f],  // B
    jmolRoyalblue = [0.188f, 0.314f, 0.973f, 1.0f],  // N
    jmolRed = [1.000f, 0.051f, 0.051f, 1.0f],  // O
    jmolYellowgreen = [0.565f, 0.878f, 0.314f, 1.0f],  // F
    jmolPaleturquoise = [0.702f, 0.890f, 0.961f, 1.0f],  // Ne
    jmolMediumorchid = [0.671f, 0.361f, 0.949f, 1.0f],  // Na
    jmolChartreuse = [0.541f, 1.000f, 0.000f, 1.0f],  // Mg
    jmolDarkgray = [0.749f, 0.651f, 0.651f, 1.0f],  // Al
    jmolWheat = [0.941f, 0.784f, 0.627f, 1.0f],  // Si
    jmolDarkorange = [1.000f, 0.502f, 0.000f, 1.0f],  // P
    jmolYellow = [1.000f, 1.000f, 0.188f, 1.0f],  // S
    jmolLimegreen = [0.122f, 0.941f, 0.122f, 1.0f],  // Cl
    jmolSkyblue = [0.502f, 0.820f, 0.890f, 1.0f],  // Ar
    jmolDarkorchid = [0.561f, 0.251f, 0.831f, 1.0f],  // K
    jmolLime = [0.239f, 1.000f, 0.000f, 1.0f],  // Ca
    jmolGainsboro = [0.902f, 0.902f, 0.902f, 1.0f],  // Sc
    jmolSilver = [0.749f, 0.761f, 0.780f, 1.0f],  // Ti
    jmolDarkgray2 = [0.651f, 0.651f, 0.671f, 1.0f],  // V
    jmolDarkgray3 = [0.541f, 0.600f, 0.780f, 1.0f],  // Cr
    jmolMediumpurple = [0.612f, 0.478f, 0.780f, 1.0f],  // Mn
    jmolChocolate = [0.878f, 0.400f, 0.200f, 1.0f],  // Fe
    jmolLightcoral = [0.941f, 0.565f, 0.627f, 1.0f],  // Co
    jmolLimegreen2 = [0.314f, 0.820f, 0.314f, 1.0f],  // Ni
    jmolPeru = [0.784f, 0.502f, 0.200f, 1.0f],  // Cu
    jmolLightslategray = [0.490f, 0.502f, 0.690f, 1.0f],  // Zn
    jmolRosybrown = [0.761f, 0.561f, 0.561f, 1.0f],  // Ga
    jmolSlategray = [0.400f, 0.561f, 0.561f, 1.0f],  // Ge
    jmolOrchid = [0.741f, 0.502f, 0.890f, 1.0f],  // As
    jmolOrange = [1.000f, 0.631f, 0.000f, 1.0f],  // Se
    jmolBrown = [0.651f, 0.161f, 0.161f, 1.0f],  // Br
    jmolMediumturquoise = [0.361f, 0.722f, 0.820f, 1.0f],  // Kr
    jmolDarkorchid2 = [0.439f, 0.180f, 0.690f, 1.0f],  // Rb
    jmolPaleturquoise2 = [0.580f, 1.000f, 1.000f, 1.0f],  // Y
    jmolSkyblue2 = [0.580f, 0.878f, 0.878f, 1.0f],  // Zr
    jmolMediumaquamarine = [0.451f, 0.761f, 0.788f, 1.0f],  // Nb
    jmolMediumaquamarine2 = [0.329f, 0.710f, 0.710f, 1.0f],  // Mo
    jmolLightseagreen = [0.231f, 0.620f, 0.620f, 1.0f],  // Tc
    jmolDarkcyan = [0.141f, 0.561f, 0.561f, 1.0f],  // Ru
    jmolTeal = [0.039f, 0.490f, 0.549f, 1.0f],  // Rh
    jmolTeal2 = [0.000f, 0.412f, 0.522f, 1.0f],  // Pd
    jmolKhaki = [1.000f, 0.851f, 0.561f, 1.0f],  // Cd
    jmolGray = [0.651f, 0.459f, 0.451f, 1.0f],  // In
    jmolSlategray2 = [0.400f, 0.502f, 0.502f, 1.0f],  // Sn
    jmolMediumpurple2 = [0.620f, 0.388f, 0.710f, 1.0f],  // Sb
    jmolDarkgoldenrod = [0.831f, 0.478f, 0.000f, 1.0f],  // Te
    jmolDarkmagenta = [0.580f, 0.000f, 0.580f, 1.0f],  // I
    jmolSteelblue = [0.259f, 0.620f, 0.690f, 1.0f],  // Xe
    jmolIndigo = [0.341f, 0.090f, 0.561f, 1.0f],  // Cs
    jmolLime2 = [0.000f, 0.788f, 0.000f, 1.0f],  // Ba
    jmolLightskyblue = [0.439f, 0.831f, 1.000f, 1.0f],  // La
    jmolLemonchiffon = [1.000f, 1.000f, 0.780f, 1.0f],  // Ce
    jmolLightgoldenrodyellow = [0.851f, 1.000f, 0.780f, 1.0f],  // Pr
    jmolGainsboro2 = [0.780f, 1.000f, 0.780f, 1.0f],  // Nd
    jmolAquamarine = [0.639f, 1.000f, 0.780f, 1.0f],  // Pm
    jmolAquamarine2 = [0.561f, 1.000f, 0.780f, 1.0f],  // Sm
    jmolAquamarine3 = [0.380f, 1.000f, 0.780f, 1.0f],  // Eu
    jmolTurquoise  = [0.271f, 1.000f, 0.780f, 1.0f],  // Gd
    jmolTurquoise2 = [0.188f, 1.000f, 0.780f, 1.0f],  // Tb
    jmolTurquoise3 = [0.122f, 1.000f, 0.780f, 1.0f],  // Dy
    jmolMediumspringgreen = [0.000f, 1.000f, 0.612f, 1.0f],  // Ho
    jmolSpringgreen = [0.000f, 0.902f, 0.459f, 1.0f],  // Er
    jmolLimegreen3 = [0.000f, 0.831f, 0.322f, 1.0f],  // Tm
    jmolLimegreen4 = [0.000f, 0.749f, 0.219f, 1.0f],  // Yb
    jmolForestgreen = [0.000f, 0.671f, 0.141f, 1.0f],  // Lu
    jmolMediumturquoise2 = [0.302f, 0.761f, 1.000f, 1.0f],  // Hf
    jmolCornflowerblue = [0.302f, 0.651f, 1.000f, 1.0f],  // Ta
    jmolDodgerblue = [0.129f, 0.580f, 0.839f, 1.0f],  // W
    jmolSteelblue2 = [0.149f, 0.490f, 0.671f, 1.0f],  // Re
    jmolTeal3 = [0.149f, 0.400f, 0.588f, 1.0f],  // Os
    jmolTeal4 = [0.090f, 0.329f, 0.529f, 1.0f],  // Ir
    jmolLightgray = [0.816f, 0.816f, 0.878f, 1.0f],  // Pt
    jmolGold = [1.000f, 0.820f, 0.137f, 1.0f],  // Au
    jmolSilver2 = [0.722f, 0.722f, 0.816f, 1.0f],  // Hg
    jmolSienna = [0.651f, 0.329f, 0.302f, 1.0f],  // Tl
    jmolDimgray = [0.341f, 0.349f, 0.380f, 1.0f],  // Pb
    jmolDarkorchid3 = [0.620f, 0.310f, 0.710f, 1.0f],  // Bi
    jmolSaddlebrown = [0.671f, 0.361f, 0.000f, 1.0f],  // Po
    jmolDimgray2 = [0.459f, 0.310f, 0.271f, 1.0f],  // At
    jmolSteelblue3 = [0.259f, 0.510f, 0.588f, 1.0f],  // Rn
    jmolIndigo2 = [0.259f, 0.000f, 0.400f, 1.0f],  // Fr
    jmolGreen = [0.000f, 0.490f, 0.000f, 1.0f],  // Ra
    jmolCornflowerblue2 = [0.439f, 0.671f, 0.980f, 1.0f],  // Ac
    jmolDeepskyblue = [0.000f, 0.729f, 1.000f, 1.0f],  // Th
    jmolDeepskyblue2 = [0.000f, 0.631f, 1.000f, 1.0f],  // Pa
    jmolDodgerblue2 = [0.000f, 0.561f, 1.000f, 1.0f],  // U
}

