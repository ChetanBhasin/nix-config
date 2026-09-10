---
name: kraken-experiment-contract
description: Use when planning or evaluating Kraken trading/simulation experiments, strategy comparisons, live-versus-replay claims, or account-aware PnL reports.
---
# Trading experiment contract

Read the repository's domain instructions and actual execution interfaces first. Research/backtesting authorization is not real-order authorization.

## Freeze before running

- Objective: net economic outcome and risk, not price-prediction accuracy alone.
- Account assumptions: starting capital, sizing, leverage/margin where relevant, fees, spread/slippage, fills, latency, funding and liquidation constraints.
- Strategy semantics: entry/exit, TP/SL, execution versus prediction, horizon, baseline and explicit stopping rule.
- Evidence: dataset/source, time range, timezone, sample/trade count, split/leakage controls, live/replay/synthetic provenance and uncertainty.
- Report schema: net/gross PnL, win rate, drawdown/exposure, costs, rejected/unfilled orders, sample size, baseline comparison and unsupported conclusions. Include requested interactive/presentation/video deliverables as mandatory requirements.

Record these in the active ledger with stable IDs and actual interface journeys. Keep raw runs and campaign manifests outside source roots; fingerprint any load-bearing inputs/artifacts. See [the workflow protocol](../../extensions/auto-mode/WORKFLOW.md) for evidence and lease semantics.

## Execution and interpretation

- Use Rust for durable production, data collection, experimental harnesses and assertions in Rust repositories. Preserve healthy existing tooling. Disposable Python presentation/analysis needs an explicit reason; it must not quietly become the production or acceptance path.
- Pin sibling API revisions and contracts. Do not opportunistically edit `kraken-ready` or another owner’s repository to make this experiment pass.
- Never read secret file contents to prove configuration. Use safe metadata and approved auth paths, redact logs, and do not publish raw private data.
- Use deterministic replay/isolated checks before the smallest authorized live qualification. No real order placement, account changes or cancellation of unrelated orders/processes without explicit authority.
- Separate market-data freshness, replay realism, live TLS/connectivity, account simulation and actual execution claims. Insufficient reconnect coverage or samples must remain visible.
- Inspect the generated report and actual success/failure interface results. Report confidence and limitations; do not claim universal profitability from a narrow period or substitute classification accuracy for PnL.
