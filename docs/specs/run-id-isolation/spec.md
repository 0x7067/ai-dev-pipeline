# Run-ID-Based Artifact Isolation — Notes

## Parser Contract

```
RunId regex: ^[0-9]{8}T[0-9]{6}Z?-[a-f0-9]{6}(-[a-f0-9]{2})?$
Length:       22..24
Allowlist:    [0-9 a-f T Z -]
Reject:       empty, '..', '/', '\', NUL, whitespace, anything outside allowlist
```

Parser exits zero with input echoed on stdout when valid; nonzero with a
structured single-line error to stderr when not.

## Testing Scope

| Layer | Test type | Coverage |
|-------|-----------|----------|
| Boundary | Contract | parser accept/reject corpus; round-trip mint→parse |
| Core (mint id-generation) | Property | uniqueness over 100 iterations; format-invariant |
| Core (prune policy) | Property | retention math (which ids to delete) |
| Shell | Integration | concurrent /ship smoke; parallel-gate timing; hint-file truncation |
