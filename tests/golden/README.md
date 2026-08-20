# Golden cases

Regression fixtures for the rollup engine (spec §3.2). Every case is a real
panel with a known-correct outcome supplied by the owner — never fabricated
values.

Each `case_*.json` file:

```jsonc
{
  "golden_case": "0001",          // stable id
  "title": "...",
  "status": "todo_owner_verify",  // or "ready"
  "notes": "...",
  "export": { ... },              // full FaultCorral project export (schema-versioned)
  "expected": {                   // known-correct outcome
    "panel_sccr_ka_by_voltage": { "480.0V_3ph_wye": 10.0 },
    "limiting_component_ids": ["..."]
  }
}
```

Cases with `status: "todo_owner_verify"` are structural placeholders: the
harness (core/test/golden_test.dart) checks they parse but skips comparison.
Cases with `status: "ready"` are executed on every test run.
