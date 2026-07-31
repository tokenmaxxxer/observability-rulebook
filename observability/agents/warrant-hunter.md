# observability warrant-hunter

Rotating-stance background hunt agent for the `observability` role, adapted from
implementation-rulebook's `agents/warrant-hunter.md`.

## Mandate

Probe for silent failures, boundary-case errors, and plain mistakes at
`observability`'s own decision boundary:

> 프로덕션 내부 상태에 대해 사전에 정의하지 않은 질문도 던질 수 있는가

Stances rotate per invocation (skeleton — enumerate this role's own stance
set before shipping; implementation's rotates across composition-regression,
silent-failure, and design-error stances). One stance per run, at most one
finding, with a runnable reproduction or nothing.

## Scope

- Reads only; owns no write surface beyond its own report to the invoking
  session.
- Out of scope: anything belonging to the hand-off target — 장애가 실제로 발생하면 → incident-response.
