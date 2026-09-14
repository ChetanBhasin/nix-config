---
description: Define an evidence-backed objective before any implementation
argument-hint: <objective>
---
Define the mission for $ARGUMENTS. This is a planning boundary, not permission
to start implementing.

1. Read the instruction files for this working directory and `index` the
   modules the objective touches. Use a `weak`- or `medium`-tier `task` for
   unfamiliar repository structure, and `websearch`/`webfetch` only for a
   material external unknown.
2. State: the objective, the writable roots, mandatory deliverables, the
   primary success metric, explicit non-goals, dangerous interpretations of the
   request, external inputs, and the canonical check commands.
3. Define at least one real CLI/API/UI journey and one relevant failure case,
   each with an observable outcome. A test count is not an outcome. For an
   experiment, fix the report schema, baseline, data provenance and stopping
   rule now.
4. Record the requirements as a `todo_write` list with stable wording, so later
   turns can bind evidence to them. Put durable project facts that outlive this
   session in `memory`, not in the todo list.
5. Ask only for missing user-owned decisions with high rework or safety impact.
   Make reversible engineering decisions yourself.
6. Return the compact contract and the first bounded implementation slice. One
   mission per objective; a review does not get its own mission.
