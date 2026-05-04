# +network package

Node registry, link registry, routing engine, outage engine, background traffic model,
geographic utilities, and orbital propagator.

## Contents

- `NodeRegistry.m` — Struct-of-arrays node state storage
- `LinkRegistry.m` — Struct-of-arrays link state storage
- `RoutingEngine.m` — Dijkstra-based path selection wrapping MATLAB `digraph`
- `OutageEngine.m` — Poisson-distributed outage event generator
- `BackgroundTrafficModel.m` — Statistical background traffic sampler
- `GeoUtils.m` — WGS-84 geodesy (Vincenty, LOS visibility)
- `OrbitalPropagator.m` — Keplerian two-body orbital propagator
