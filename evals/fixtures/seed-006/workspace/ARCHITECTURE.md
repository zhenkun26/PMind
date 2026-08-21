# Current Architecture

- React single-page admin console with TypeScript.
- Route-level data loading and locally managed form state.
- Shared design tokens exist, but seven form clusters duplicate validation and field layout.
- Backend APIs are stable and outside the proposed frontend selection scope.
- Current automated checks cover core account and project flows; broad rewrite coverage is incomplete.
- The team continues to ship product changes during any migration window.

Observed problems are a slow first contentful paint and repeated form code. The
snapshot does not establish that React is the root cause.
