# PMind Eval Baseline

PMind will be evaluated by downstream delivery outcomes, not by whether an
optimized prompt sounds polished.

## Initial experiment

Collect at least 30 real tasks. For each task preserve:

- raw Intent and target Downstream Executor;
- baseline handoff without PMind;
- Clarifications and Evidence used by PMind;
- generated Prompt Package;
- downstream output and human corrections;
- latency, model / search cost, and number of clarification and rework rounds;
- acceptance result and failure reason.

## Primary metrics

- First-pass Delivery Success;
- material clarification and rework reduction;
- time from Intent to Handoff;
- Evidence citation coverage and validity;
- acceptance-criterion pass rate;
- user acceptance, cost, and latency.

## Case quality rules

- Inputs must be real or explicitly labeled synthetic.
- Expected outcomes must be independently defined, not copied from model
  output.
- Facts, judgement rubrics, and safety requirements are scored separately.
- Model, prompt, Skill, Reference, and dataset versions must be recorded.
- Failed and ambiguous cases remain in the dataset as regression evidence.

The executable Eval schema and runner will be selected with the application
stack; no framework is assumed at this stage.
