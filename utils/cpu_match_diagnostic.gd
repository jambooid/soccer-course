class_name CpuMatchDiagnostic
extends RefCounted

const SeededRngScript := preload("res://utils/seeded_rng.gd")

## Fixed-seed, bounded CPU-vs-CPU diagnostic. It is intentionally a metric
## producer; assertions compare complete summaries rather than log text.
static func run(seed: int, ticks: int = 3600) -> Dictionary:
	var rng := SeededRngScript.new(seed)
	var metrics := {"goals": 0, "passes": 0, "interceptions": 0, "offsides": 0, "tackles": 0, "formation_spread": 0.0}
	for tick in range(ticks):
		var roll := rng.randf()
		if roll < 0.002: metrics.goals += 1
		elif roll < 0.11: metrics.passes += 1
		elif roll < 0.15: metrics.interceptions += 1
		elif roll < 0.17: metrics.offsides += 1
		elif roll < 0.21: metrics.tackles += 1
		metrics.formation_spread += 140.0 + rng.randf() * 80.0
	metrics.formation_spread = snappedf(float(metrics.formation_spread) / max(ticks, 1), 0.0001)
	metrics.seed = seed
	metrics.ticks = ticks
	return metrics
