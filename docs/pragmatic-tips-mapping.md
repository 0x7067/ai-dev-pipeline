# Pragmatic Programmer — Pipeline Mapping

Audit trail for how each of the 100 tips from *The Pragmatic Programmer* (20th Anniversary Edition, 2nd Edition) maps onto this pipeline.

Buckets:
- **covered** — already enforced by an existing rule, command, or skill. No new work needed.
- **rule:`<file>`** — codified as a constraint in `.claude/rules/<file>`.
- **skill:`<section>`** — surfaced as an item in `.claude/skills/pragmatic-review-checklist/SKILL.md` under the named section.
- **skip:`<reason>`** — out of scope for a code pipeline (philosophy, team/process, ethics, tooling preference).

| # | Tip | Bucket | Notes |
|---|-----|--------|-------|
| 1 | Care About Your Craft | skip:philosophy | |
| 2 | Think! About Your Work | skip:philosophy | |
| 3 | You Have Agency | skip:philosophy | |
| 4 | Provide Options, Don't Make Lame Excuses | skill:Change-amenability | Implicit in step-size and reversibility checks. |
| 5 | Don't Live with Broken Windows | skill:Documentation and naming | Surfaces commented-out code, unlinked TODOs. |
| 6 | Be a Catalyst for Change | skip:team | |
| 7 | Remember the Big Picture | skill:Change-amenability | Boiling-frog detection in step-size review. |
| 8 | Make Quality a Requirements Issue | skip:process | Already in `requirement-analysis` skill. |
| 9 | Invest Regularly in Your Knowledge Portfolio | skip:career | |
| 10 | Critically Analyze What You Read and Hear | skip:career | Echoed in `release-and-verification.md` evidence-quality. |
| 11 | English is Just Another Programming Language | skill:Documentation and naming | Applies to commits, ADRs. |
| 12 | It's Both What You Say and the Way You Say It | skip:communication | |
| 13 | Build Documentation In, Don't Bolt It On | skill:Documentation and naming | |
| 14 | Good Design Is Easier to Change Than Bad Design | skill:Change-amenability | Reversibility check. |
| 15 | DRY—Don't Repeat Yourself | covered | Implicit in `code-style.md` (composable functions). |
| 16 | Make It Easy to Reuse | covered | `code-style.md`. |
| 17 | Eliminate Effects Between Unrelated Things (Orthogonality) | covered | `architecture-fcis.md`. |
| 18 | There Are No Final Decisions | skill:Change-amenability | Reversibility check. |
| 19 | Forgo Following Fads | skip:taste | |
| 20 | Use Tracer Bullets to Find the Target | skill:Change-amenability | Tracer-vs-prototype declaration. |
| 21 | Prototype to Learn | skill:Change-amenability | Same. |
| 22 | Program Close to the Problem Domain | covered | `code-style.md` (name by domain intent). |
| 23 | Estimate to Avoid Surprises | skip:process | |
| 24 | Iterate the Schedule with the Code | skip:process | |
| 25 | Keep Knowledge in Plain Text | covered | All rules and reports are markdown. |
| 26 | Use the Power of Command Shells | skip:tooling | |
| 27 | Achieve Editor Fluency | skip:tooling | |
| 28 | Always Use Version Control | covered | `release-and-verification.md` references VCS gates. |
| 29 | Fix the Problem, Not the Blame | skip:philosophy | |
| 30 | Don't Panic | skip:philosophy | |
| 31 | Failing Test Before Fixing Code | skill:Correctness and contracts | Escalates to warning if missing on bug-fix PRs. |
| 32 | Read the Damn Error Message | skip:philosophy | |
| 33 | "select" Isn't Broken | skip:philosophy | |
| 34 | Don't Assume It—Prove It | skill:Correctness and contracts | "Programming by coincidence" item. |
| 35 | Learn a Text Manipulation Language | skip:tooling | |
| 36 | You Can't Write Perfect Software | skip:philosophy | Lead-in to DBC. |
| 37 | Design with Contracts | rule:assertions-and-invariants.md | DBC for core. |
| 38 | Crash Early | rule:assertions-and-invariants.md | Crash early, crash loud. |
| 39 | Use Assertions to Prevent the Impossible | rule:assertions-and-invariants.md | Assert the impossible. |
| 40 | Finish What You Start | rule:assertions-and-invariants.md | Resource ownership. |
| 41 | Act Locally | skill:State and data | Local scope and ownership for ephemeral resources. |
| 42 | Take Small Steps—Always | skill:Change-amenability | Step-size check. |
| 43 | Avoid Fortune-Telling | skill:Change-amenability | No speculative generality. |
| 44 | Decoupled Code Is Easier to Change | rule:decoupling-and-configuration.md | Train wrecks, globals. |
| 45 | Tell, Don't Ask | rule:decoupling-and-configuration.md | |
| 46 | Don't Chain Method Calls | rule:decoupling-and-configuration.md | One Dot at a Time. |
| 47 | Avoid Global Data | rule:decoupling-and-configuration.md | |
| 48 | If It's Important Enough to Be Global, Wrap It in an API | rule:decoupling-and-configuration.md | |
| 49 | Programming Is About Code, But Programs Are About Data | skill:State and data | Plain data through pipelines. |
| 50 | Don't Hoard State; Pass It Around | covered | `architecture-fcis.md` (core accepts explicit parameters). |
| 51 | Don't Pay Inheritance Tax | skill:Decoupling | Prefer composition. |
| 52 | Prefer Interfaces to Express Polymorphism | skill:Decoupling | |
| 53 | Delegate to Services: Has-A Trumps Is-A | skill:Decoupling | |
| 54 | Use Mixins to Share Functionality | skip:language-specific | |
| 55 | Parameterize Your App Using External Configuration | rule:decoupling-and-configuration.md | Externalize what changes. |
| 56 | Analyze Workflow to Improve Concurrency | skip:project-dependent | |
| 57 | Shared State Is Incorrect State | rule:decoupling-and-configuration.md | No global mutable state. |
| 58 | Random Failures Are Often Concurrency Issues | skill:Concurrency | |
| 59 | Use Actors For Concurrency Without Shared State | skip:architecture-choice | |
| 60 | Use Blackboards to Coordinate Workflow | skip:architecture-choice | |
| 61 | Listen to Your Inner Lizard | skip:philosophy | |
| 62 | Don't Program by Coincidence | skill:Correctness and contracts | |
| 63 | Estimate the Order of Your Algorithms | skill:Change-amenability | Big-O on hot paths (implicit; raise on review). |
| 64 | Test Your Estimates | skill:Change-amenability | |
| 65 | Refactor Early, Refactor Often | covered | `/refactor` command and `refactor` skill. |
| 66 | Testing Is Not About Finding Bugs | skill:Tests | |
| 67 | A Test Is the First User of Your Code | skill:Tests | |
| 68 | Build End-to-End, Not Top-Down or Bottom Up | skill:Change-amenability | Tracer-bullet item. |
| 69 | Design to Test | skill:Tests | Test as first user. |
| 70 | Test Your Software, or Your Users Will | skip:motto | |
| 71 | Use Property-Based Tests to Validate Your Assumptions | covered | `testing-formal-lite.md`. |
| 72 | Keep It Simple and Minimize Attack Surfaces | covered | `security-baseline.md` (least privilege). |
| 73 | Apply Security Patches Quickly | skill:Change-amenability | Surface during `/audit`. |
| 74 | Name Well; Rename When Needed | covered | `code-style.md`. |
| 75 | No One Knows Exactly What They Want | skip:process | |
| 76 | Programmers Help People Understand What They Want | skip:process | |
| 77 | Requirements Are Learned in a Feedback Loop | skip:process | |
| 78 | Work with a User to Think Like a User | skip:process | |
| 79 | Policy Is Metadata | rule:decoupling-and-configuration.md | Externalize what changes. |
| 80 | Use a Project Glossary | skip:process | |
| 81 | Don't Think Outside the Box—Find the Box | skip:philosophy | |
| 82 | Don't Go into the Code Alone | skip:process | |
| 83 | Agile Is Not a Noun; Agile Is How You Do Things | skip:process | |
| 84 | Maintain Small, Stable Teams | skip:team | |
| 85 | Schedule It to Make It Happen | skip:process | |
| 86 | Organize Fully Functional Teams | skip:team | |
| 87 | Do What Works, Not What's Fashionable | skip:taste | |
| 88 | Deliver When Users Need It | skip:process | |
| 89 | Use Version Control to Drive Builds, Tests, and Releases | covered | `/verify`, `release-and-verification.md`. |
| 90 | Test Early, Test Often, Test Automatically | covered | `/verify`, `/test`. |
| 91 | Coding Ain't Done 'Til All the Tests Run | covered | `release-and-verification.md` gate policy. |
| 92 | Use Saboteurs to Test Your Testing | skill:Tests | Mutation-style item. |
| 93 | Test State Coverage, Not Code Coverage | skill:Tests | |
| 94 | Find Bugs Once | skill:Correctness and contracts | Regression test for every fix. |
| 95 | Don't Use Manual Procedures | covered | `/verify` gate runner is canonical. |
| 96 | Delight Users, Don't Just Deliver Code | skip:product | |
| 97 | Sign Your Work | skip:commit-metadata | |
| 98 | First, Do No Harm | skip:ethics | |
| 99 | Don't Enable Scumbags | skip:ethics | |
| 100 | It's Your Life. Share it. Celebrate it. Build it. AND HAVE FUN! | skip:closing | |

## Counts

- covered: 13
- rule:decoupling-and-configuration.md: 8
- rule:assertions-and-invariants.md: 4
- skill: 31
- skip: 44

Total: 100.

## Reference
- Thomas, David & Hunt, Andrew. *The Pragmatic Programmer: Your Journey to Mastery*, 20th Anniversary Edition, 2nd Edition. Addison-Wesley, 2019.
