# Lab NN — <title>

| | |
|---|---|
| Clean snapshot | `NN-<stage>-clean` |
| Fault introduced | one sentence |
| Date run | |
| Evidence | `evidence-working/NN-<slug>/` |

## Expected behavior (before the fault)

What the stack does correctly at this stage, and the command that demonstrates it.

## Deliberate fault

The exact single change made. One fault at a time — compound faults produce evidence that
cannot be attributed.

```text
```

## Prediction

> Written before the fault was introduced. **Not edited afterwards.**

- What will the client see (status code, body, timing)?
- Which component generates that response?
- Which log holds the first useful evidence?
- How far does the request travel — nginx, Apache, PHP-FPM, application?
- Immediate failure, queued, or timeout-driven?
- What process or socket state is expected (`ss`, `ps`, journal)?

## Actual result

Client-visible outcome, verbatim.

```text
```

## Investigation path

The order things were actually checked, including the checks that led nowhere. The dead ends
are part of the value — a write-up that goes straight to the answer describes a lookup, not
an investigation.

1.
2.

## First useful log line

Which file, and why this was the first line that actually narrowed the problem.

```text
```

## Root cause

Mechanism, not restatement of the symptom.

## Corrected model

Only if the prediction was wrong. What the mental model got wrong and what replaces it.
This section is the point of the exercise; a lab with no wrong predictions across the whole
set suggests the faults were too easy.

## Remediation

```text
```

## Verification

Proof the fault is resolved — the failing request now succeeding, or the attack now failing.
Re-run after remediation, output captured.

```text
```

## Lesson

Two or three sentences. What this changes about how the stack is understood, and what the
equivalent production ticket would have looked like arriving from a customer.
