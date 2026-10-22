# VEHICLE_SYSTEM — City of Shadows

## Catalogue (arcade stats; top speed in m/s, HUD shows km/h)
| Car | Price | Top | Accel | Brake | Turn | Grip | Drift |
|---|---|---|---|---|---|---|---|
| Vega Sedan | starter | 38 | 9.5 | 18 | 1.55 | 0.72 | 0.40 |
| Bison SUV | $9000 | 43 | 10.5 | 17 | 1.25 | 0.86 | 0.25 |
| Falco GT | $12000 | 54 | 14.5 | 22 | 1.75 | 0.66 | 0.62 |
| Ravage V8 (muscle) | $22000 | 60 | 17 | 19 | 1.50 | 0.62 | 0.75 |
| Komo Hatch (hatchback) | $6000 | 42 | 12 | 19 | 1.85 | 0.78 | 0.45 |
| Nyx Hyper | $45000 | 69 | 19.5 | 26 | 1.95 | 0.60 | 0.72 |
| Interceptor (police) | — | 56 | 15 | 23 | 1.80 | 0.78 | 0.35 |

Every car has a simple interior (dashboard, two seats, steering wheel) visible
through semi-transparent cabin glass (transparency 0.55).

## Physics model (arcade, velocity-vector)
Velocity is decomposed into forward + lateral components. The lateral part is
bled off by grip each frame — the handbrake lowers grip, producing drift.
Steering yaw scales with forward speed and the car's Turn stat. Collisions use
circle-vs-AABB push-out; hard hits damage the car and (when witnessed or when
already wanted) raise the wanted level.

## Tuning (per car, saved)
- Paint: 8 colours, $250. Wheels: 4 colours, $150.
- Neon underglow: 6 colours, $600 (changing colour); turning it off is free.
  Per car, saved in tuning. At night the car glows from below via an emissive
  plane plus a real point light (off = no light, day = hidden).
- Engine Lv1–3: +8% top speed and +9% acceleration per level.
- Brakes Lv1–3: +10% braking per level.
- Handling Lv1–3: +8% steering per level.
Purchases happen at Vega Custom Garage (industrial quarter); the dealership
(Hale Motors) sells/selects cars. Your selected car respawns near you.
