# Pattern Discovery Calibration

## Objective

Maintain recall ≥ 80% and precision ≥ 80% per language for each rule file.
These metrics are tracked manually in this document after each significant rule change.

## Methodology

1. Select a representative sample corpus for each language (≥ 20 files per bucket).
2. Manually inspect a random sample of detected patterns to measure precision:
   - Precision = (true positives) / (total detected)
3. Manually check known patterns in corpus to measure recall:
   - Recall = (detected known patterns) / (total known patterns in corpus)
4. Record results in the table below with date and corpus source.

## Thresholds

| Metric    | Minimum | Target |
|-----------|---------|--------|
| Precision | 80%     | 90%    |
| Recall    | 80%     | 90%    |

Below 80% on either metric = rule needs revision before production use.

## Rule Calibration Status

| Rule File         | Language    | Precision | Recall | Date       | Notes                        |
|-------------------|-------------|-----------|--------|------------|------------------------------|
| imports.yml       | typescript  | —         | —      | —          | Pending calibration          |
| imports.yml       | python      | —         | —      | —          | Pending calibration          |
| export-shape.yml  | typescript  | —         | —      | —          | Pending calibration          |
| error-handling.yml| go          | —         | —      | —          | Pending calibration          |
| error-handling.yml| rust        | —         | —      | —          | Pending calibration          |
| async-marker.yml  | typescript  | —         | —      | —          | Pending calibration          |
| async-marker.yml  | python      | —         | —      | —          | Pending calibration          |
| return-type.yml   | typescript  | —         | —      | —          | Pending calibration          |
| return-type.yml   | python      | —         | —      | —          | Pending calibration          |
| return-type.yml   | go          | —         | —      | —          | Pending calibration          |

## Suppressed Languages

Languages supported by ast-grep but excluded from calibration in v1:
- `bash`, `c`, `cpp`, `csharp`, `css`, `dart`, `elixir`, `haskell`, `html`,
  `java`, `json`, `kotlin`, `lua`, `ocaml`, `php`, `proto`, `ruby`, `scala`,
  `scheme`, `swift`, `terraform`, `toml`, `tsx`, `vue`, `yaml`

These are accepted by the boundary parser but not targeted by rules in v1.
Add them as rules are authored and calibrated.

## Calibration Corpus Sources

- Use `git ls-files` on a real consumer repo with ≥ 100 files per target language.
- Avoid using the plugin's own repository as the primary corpus — it is biased
  toward shell scripts and markdown.

## Variance Notes

ast-grep pattern matching is tree-sitter based. Results can vary when:
- The language grammar has multiple valid parse trees for the same construct.
- Rule uses `regex:` field with anchors — anchor behavior differs by node type.
- Aliased language names (e.g. `ts` vs `typescript`) may affect node kinds.

Always test with both the aliased and canonical language name when adding a rule.
