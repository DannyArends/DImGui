## Roadmap
Planned and possible future work for DImGui. Items are aspirational, not commitments, and roughly ordered by interest rather than priority.

### Engine / renderer

- **Bloom / HDR** — scaffolding is present. Extract bright areas above a luminance threshold, blur them, and composite back for glow on emissive surfaces and highlights. The main visual bang-for-buck item.
- **GPU-driven indirect draw** — issue draws from a GPU buffer (`vkCmdDrawIndexedIndirect`) with GPU-side culling, instead of CPU-recorded draw calls. Likely not feasible as-is: the current pipeline builds per-object descriptor/instance state on the CPU, so this would need a larger restructure of how draws are assembled.
- **SSAO bilateral blur pass** — the SSAO compute pass exists but its raw output is noisy. Add an edge-aware (depth/normal-preserving) blur so occlusion is smooth without bleeding across geometry edges.
- **Screen-space reflections on water** — ray-march the depth buffer from the water surface to reflect scene geometry, as a cheaper alternative to planar reflection passes. Pairs with the existing WBOIT water rendering.
- **Chunk / object LOD** — swap distant chunks and objects for lower-detail meshes (or skip fine detail) to cut vertex load. The chunk system already has the spatial structure (AABB proxies) to drive distance-based selection.
- **Omnidirectional (cube-map) shadows for point lights** — torches are currently faked as downward spot lights because the shadow system uses one 2D shadow map per light. True point-light shadows need a cube-map (6 faces) per light, which is a shadow-pass and sampling change.

### Game

- **Workshops, and crafting at workshops** — placeable workshop objects where dwarves convert input items into crafted outputs; the anchor for most other crafting items below.
- **Liquid barrels for wine / drinks from berries** — a production chain (gather berries → ferment → store liquid) plus a liquid-in-container representation.
- **Barrels and bins for stockpiles** — container objects that hold multiple items, so stockpiles store in containers rather than loose tiles.
- **Stockpile editing** — allow an existing stockpile to be extended, shrunk, or redrawn after placement, rather than delete-and-recreate.
- **Render crafted objects through assimp models** — display crafted items and furniture using the existing assimp model pipeline instead of placeholder geometry.
- **Per-dwarf labour roles / job filtering** — assign which job types each dwarf will take, with stockpile priorities and hauling logistics so work is distributed sensibly.
- **Dwarf skills & experience** — dwarves gain experience per labour type, affecting speed and (later) output quality.
- **Item quality tiers** — crafted items carry a quality level, driven by dwarf skill, feeding value and desirability.
- **Farming / planting** — designate plots, plant crops, grow and harvest over time as a renewable food/material source.
- **Furniture placement** — beds, tables, and similar as placeable world objects dwarves interact with.
- **Wildlife & combat** — roaming creatures and a basic combat loop (threat, defence, hunting).