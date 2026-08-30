## Roadmap
Planned and possible future work for DImGui. Items are aspirational, not commitments, and roughly ordered by interest rather than priority.

### Engine / renderer

- Bloom / HDR (scaffolding is present; a big visual improvement)
- GPU-driven indirect draw (likely not feasible given how the current pipeline works)
- SSAO bilateral blur pass (denoise the ambient occlusion)
- Screen-space reflections on water
- Chunk / object level-of-detail (LOD)
- Omnidirectional (cube-map) shadows for point lights (torches are currently faked as downward spot lights, since the engine uses one 2D shadow map per light)

### Game

- Workshops, and crafting at workshops
- Liquid barrels for wine / drinks from berries
- Barrels and bins for stockpiles
- Allow stockpiles to be extended / shrunk / redrawn
- Render crafted objects through assimp models
- Per-dwarf labour roles / job filtering (plus stockpile priorities and hauling logistics)
- Dwarf skills & experience
- Item quality tiers
- Farming / planting
- Furniture placement (beds, tables) as world objects
- Wildlife & combat