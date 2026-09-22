# Development contract

- Implement docs/SCOPE.md without silently shrinking the frozen batch scope.
- Keep codecs, indexing, validation and trace operations in MoonBit. Node handles IO/arguments only.
- Comment byte offsets (zero-based in code), standard references, units, scaling, rounding and loss boundaries.
- Use real semantic commits with Why/Checked/Limits. No empty commits, false attribution or history rewriting.
- Verify binary changes with independent segyio/struct fixtures. Own round trips alone are insufficient.
- Local project only: no push, publish, account creation or subagent dispatch.
- Mark partial milestones honestly; local tests are not remote CI or formal acceptance.
