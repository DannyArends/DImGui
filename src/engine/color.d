/** 
 * Authors: Danny Arends
 * License: GPL-v3 (See accompanying file LICENSE.txt or copy at https://www.gnu.org/licenses/gpl-3.0.en.html)
 */

import std.random : uniform;

/* Generate a random color
 */
float[4] randomColor(float alpha = 1.0f) { return([uniform(0.0f, 1.0f), uniform(0.0f, 1.0f), uniform(0.0f, 1.0f), alpha]); }

/* Amino Acid Residue to 'official' colors
 */
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

/* Atom to Jmol color scheme
 */
@nogc float[4] atomToColor(string atom) nothrow {
  switch (atom) {
    case "H" :  return [0.933, 0.933, 0.933, 1.0];
    case "He":  return [0.851, 1.000, 1.000, 1.0];
    case "Li":  return [0.800, 0.502, 1.000, 1.0];
    case "Be":  return [0.761, 1.000, 0.000, 1.0];
    case "B" :  return [1.000, 0.710, 0.710, 1.0];
    case "C" :  return [0.565, 0.565, 0.565, 1.0];
    case "N" :  return [0.188, 0.314, 0.973, 1.0];
    case "O" :  return [1.000, 0.051, 0.051, 1.0];
    case "F" :  return [0.565, 0.878, 0.314, 1.0];
    case "Ne":  return [0.702, 0.890, 0.961, 1.0];
    case "Na":  return [0.671, 0.361, 0.949, 1.0];
    case "Mg":  return [0.541, 1.000, 0.000, 1.0];
    case "Al":  return [0.749, 0.651, 0.651, 1.0];
    case "Si":  return [0.941, 0.784, 0.627, 1.0];
    case "P" :  return [1.000, 0.502, 0.000, 1.0];
    case "S" :  return [1.000, 1.000, 0.188, 1.0];
    case "Cl":  return [0.122, 0.941, 0.122, 1.0];
    case "Ar":  return [0.502, 0.820, 0.890, 1.0];
    case "K" :  return [0.561, 0.251, 0.831, 1.0];
    case "Ca":  return [0.239, 1.000, 0.000, 1.0];
    case "Sc":  return [0.902, 0.902, 0.902, 1.0];
    case "Ti":  return [0.749, 0.761, 0.780, 1.0];
    case "V" :  return [0.651, 0.651, 0.671, 1.0];
    case "Cr":  return [0.541, 0.600, 0.780, 1.0];
    case "Mn":  return [0.612, 0.478, 0.780, 1.0];
    case "Fe":  return [0.878, 0.400, 0.200, 1.0];
    case "Co":  return [0.941, 0.565, 0.627, 1.0];
    case "Ni":  return [0.314, 0.820, 0.314, 1.0];
    case "Cu":  return [0.784, 0.502, 0.200, 1.0];
    case "Zn":  return [0.490, 0.502, 0.690, 1.0];
    case "Ga":  return [0.761, 0.561, 0.561, 1.0];
    case "Ge":  return [0.400, 0.561, 0.561, 1.0];
    case "As":  return [0.741, 0.502, 0.890, 1.0];
    case "Se":  return [1.000, 0.631, 0.000, 1.0];
    case "Br":  return [0.651, 0.161, 0.161, 1.0];
    case "Kr":  return [0.361, 0.722, 0.820, 1.0];
    case "Rb":  return [0.439, 0.180, 0.690, 1.0];
    case "Sr":  return [0.000, 1.000, 0.000, 1.0];
    case "Y" :  return [0.580, 1.000, 1.000, 1.0];
    case "Zr":  return [0.580, 0.878, 0.878, 1.0];
    case "Nb":  return [0.451, 0.761, 0.788, 1.0];
    case "Mo":  return [0.329, 0.710, 0.710, 1.0];
    case "Tc":  return [0.231, 0.620, 0.620, 1.0];
    case "Ru":  return [0.141, 0.561, 0.561, 1.0];
    case "Rh":  return [0.039, 0.490, 0.549, 1.0];
    case "Pd":  return [0.000, 0.412, 0.522, 1.0];
    case "Ag":  return [0.753, 0.753, 0.753, 1.0];
    case "Cd":  return [1.000, 0.851, 0.561, 1.0];
    case "In":  return [0.651, 0.459, 0.451, 1.0];
    case "Sn":  return [0.400, 0.502, 0.502, 1.0];
    case "Sb":  return [0.620, 0.388, 0.710, 1.0];
    case "Te":  return [0.831, 0.478, 0.000, 1.0];
    case "I" :  return [0.580, 0.000, 0.580, 1.0];
    case "Xe":  return [0.259, 0.620, 0.690, 1.0];
    case "Cs":  return [0.341, 0.090, 0.561, 1.0];
    case "Ba":  return [0.000, 0.788, 0.000, 1.0];
    case "La":  return [0.439, 0.831, 1.000, 1.0];
    case "Ce":  return [1.000, 1.000, 0.780, 1.0];
    case "Pr":  return [0.851, 1.000, 0.780, 1.0];
    case "Nd":  return [0.780, 1.000, 0.780, 1.0];
    case "Pm":  return [0.639, 1.000, 0.780, 1.0];
    case "Sm":  return [0.561, 1.000, 0.780, 1.0];
    case "Eu":  return [0.380, 1.000, 0.780, 1.0];
    case "Gd":  return [0.271, 1.000, 0.780, 1.0];
    case "Tb":  return [0.188, 1.000, 0.780, 1.0];
    case "Dy":  return [0.122, 1.000, 0.780, 1.0];
    case "Ho":  return [0.000, 1.000, 0.612, 1.0];
    case "Er":  return [0.000, 0.902, 0.459, 1.0];
    case "Tm":  return [0.000, 0.831, 0.322, 1.0];
    case "Yb":  return [0.000, 0.749, 0.219, 1.0];
    case "Lu":  return [0.000, 0.671, 0.141, 1.0];
    case "Hf":  return [0.302, 0.761, 1.000, 1.0];
    case "Ta":  return [0.302, 0.651, 1.000, 1.0];
    case "W" :  return [0.129, 0.580, 0.839, 1.0];
    case "Re":  return [0.149, 0.490, 0.671, 1.0];
    case "Os":  return [0.149, 0.400, 0.588, 1.0];
    case "Ir":  return [0.090, 0.329, 0.529, 1.0];
    case "Pt":  return [0.816, 0.816, 0.878, 1.0];
    case "Au":  return [1.000, 0.820, 0.137, 1.0];
    case "Hg":  return [0.722, 0.722, 0.816, 1.0];
    case "Tl":  return [0.651, 0.329, 0.302, 1.0];
    case "Pb":  return [0.341, 0.349, 0.380, 1.0];
    case "Bi":  return [0.620, 0.310, 0.710, 1.0];
    case "Po":  return [0.671, 0.361, 0.000, 1.0];
    case "At":  return [0.459, 0.310, 0.271, 1.0];
    case "Rn":  return [0.259, 0.510, 0.588, 1.0];
    case "Fr":  return [0.259, 0.000, 0.400, 1.0];
    case "Ra":  return [0.000, 0.490, 0.000, 1.0];
    case "Ac":  return [0.439, 0.671, 0.980, 1.0];
    case "Th":  return [0.000, 0.729, 1.000, 1.0];
    case "Pa":  return [0.000, 0.631, 1.000, 1.0];
    case "U" :  return [0.000, 0.561, 1.000, 1.0];
    default: return Colors.white;
  }
}

/* Named colors
 */
enum Colors : float[4] {
    white = [1.0f, 1.0f, 1.0f, 1.0f],
    black = [0.0f, 0.0f, 0.0f, 1.0f],

    red  = [1.0f, 0.0f, 0.0f, 1.0f],
    green = [0.0f, 1.0f, 0.0f, 1.0f],
    blue = [0.0f, 0.0f, 1.0f, 1.0f],

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
    slategrey = [0.439f, 0.502f, 0.565f, 1.0f],
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
    yellowgreen = [0.604f, 0.804f, 0.196f, 1.0f]
}

