---
inclusion: always
---

# Umbrella: Acquisition Knowledge System

- Goal: demonstrate AI architecting and simulating Air Force enterprise operations, at scale and
  realistically, then AI used in that enterprise, safely and under human authority.
- This repo's role: the network transport and C2 messaging testbed. The network AKS's simulations
  communicate over (D2), UCI under degraded links (D4), C2SIM gateway (D5).
- One shared model, many apps (ADR 0005): ontology changes that affect alignment need an umbrella ADR.
- BFO/CCO pins come from the umbrella's ontology steering (ADR 0006); never change them here alone.
- Full context: https://github.com/semanticarchitectures/acquisition-knowledge-system
