# Planning ↔ Core Integration — Opgaver til Core-gruppen

Disse opgaver er nødvendige for at fuldføre integrationen med Planning-backenden.
Planning-siden er klar. Core mangler de to nedenstående dele.

---

## Opgave 1: Eksponér `GET /game-state` endpoint

Planning-backenden kalder dette endpoint for at validere at units og ressourcer
rent faktisk eksisterer i spillet inden en plan accepteres.

**Endpoint:**
```
GET http://127.0.0.1:8085/game-state?gameId={gameId}
```

**Forventet JSON-respons:**
```json
{
  "units":     [{"id": "1"}, {"id": "2"}],
  "resources": [{"id": "42"}, {"id": "17"}]
}
```

**Implementering:**
- `id`-feltet er `entity_id` som **string** (ikke int)
- Brug `SenseAPI.get_all_units()` til units
- Brug `SenseAPI.get_all_resources()` til ressourcer
- Endpointet kan tilføjes til `PlanReceiver.gd` ved at håndtere `GET /game-state` i `_handle_connection`

**Vigtig note:** Hvis Core er nede eller endpointet mangler, springes valideringen over
og planen accepteres alligevel (best-effort). Så validering virker først når Core er oppe.

---

## Opgave 2: Håndtér `stop_unit_ids` i `/plan-updated` notifikation

Planning sender nu et ekstra felt `stop_unit_ids` i notifikationen. Units i dette felt
kørte under den forrige plan men er **ikke** med i den nye plan — de skal stoppes.

**Ny notifikationsstruktur:**
```json
{
  "game_id":      "game_abc",
  "player_id":    "player_xyz",
  "unit_ids":     ["u2", "u3"],
  "stop_unit_ids": ["u1"]
}
```

**Implementering i `PlanReceiver.gd`:**

I `_fetch_and_store`-funktionen, efter at `unit_ids` og `stop_unit_ids` er udtrukket fra body:

```gdscript
var stop_ids: Array = body.get("stop_unit_ids", [])

for uid_str in stop_ids:
    var uid_int = int(str(uid_str))
    # Fjern fra _store så unit_idled-signalet ikke genstartes
    _store.erase(str(uid_str))
    # Stop CommandQueue for denne unit
    if gateway:
        var unit = gateway._find_unit(uid_int)
        if unit and unit.command_queue:
            unit.command_queue.clear()
    print("PlanReceiver: Stoppede unit %s (ikke i ny plan)" % uid_str)
```

Dette sikrer at units der ikke er med i den nye plan holder op med at arbejde.

---

## Koordinering

- Kontakt Magnus (Gruppe 4) når Opgave 1 er implementeret, så entity-validering kan testes
- `stop_unit_ids` håndtering kan testes ved at submitte to planer i træk med færre units
