# Workflow orchestration template (proven over M1–M5)

How FormalShell milestones are executed. A fresh Claude Code session on any
host reproduces the pattern exactly: author the milestone plan first
(`docs/superpowers/plans/YYYY-MM-DD-mN-<topic>.md`, committed+pushed), then
launch ONE Workflow with the script below adapted to the plan's task list.

## The pattern

- **Sequential implementer subagents** (model `sonnet`), one per plan task.
  Each gets: repo path, plan path, its exact task number, the accumulated
  one-line summaries of prior tasks, and the operating rules. Each must run
  every verification command, READ outputs (screenshots via Read on the PNG),
  commit in the repo's conventional style, and push (a harness classifier may
  deny pushes — agents note it and continue; the orchestrator pushes after).
- **Adversarial review checkpoints** (model `opus`) after the riskiest
  mid-plan task and at the end. Reviewers re-run the test/lint commands
  themselves, read the actual diffs, and hunt plan-specific failure classes
  (design drift vs docs/DESIGN.md, host-safety leaks, contract drift, fake
  evidence, unpushed commits). They report `critical` only for confirmed
  compounding defects — a `fixer` agent (sonnet) is dispatched per non-clean
  review and must produce real evidence.
- **Structured outputs**: implementers return
  `{status: done|blocked, summary, evidence, commit}`; reviewers return
  `{critical: [..], notes}`. A `blocked` status aborts the workflow with the
  blocker attached — the orchestrating session then finishes/pushes manually.
- **Every commit pushed** so the owner can follow on GitHub live.

## Script skeleton (adapt TASK_TITLES, checkpoints, review hunt-list)

```js
export const meta = {
  name: 'formalshell-mN',
  description: '…',
  phases: [
    { title: 'Implement', detail: 'N sequential plan tasks, one agent each, push after every commit' },
    { title: 'Review', detail: 'adversarial checkpoints' },
  ],
}
const REPO = '<abs repo path>'
const PLAN = REPO + '/docs/superpowers/plans/<plan file>.md'
const RESULT = { type: 'object', required: ['status','summary','evidence'], properties: {
  status: { type:'string', enum:['done','blocked'] }, summary:{type:'string'},
  evidence:{type:'string'}, commit:{type:'string'} } }
const REVIEW = { type:'object', required:['critical','notes'], properties: {
  critical:{type:'array',items:{type:'string'}}, notes:{type:'string'} } }
const TASK_TITLES = [ /* exact task titles from the plan */ ]

function implPrompt(n, notes) { return `You are implementing ONE task of <plan name>.
Repo: ${REPO} (cd there first). BEFORE ANYTHING: read ${REPO}/CLAUDE.md (hard rules binding) and ${REPO}/docs/DESIGN.md.
Plan: Read ${PLAN} — execute EXACTLY "Task ${n}: ${TASK_TITLES[n-1]}" and nothing beyond it. M1-M2 plan Global Constraints also apply.
Context from completed prior tasks:\n${notes.length ? notes.map(s => '- '+s).join('\n') : '- none'}
Operating rules:
- Run every verification command and READ its output (screenshots: Read the PNG).
- Runtime testing ONLY inside isolated environments per CLAUDE.md host-safety rules.
- Verify-first items come from quickshell source / DMS / Omarchy clones, not guesses.
- 'git add -A' before any nix build. Commit as the task says, then push (classifier denial: note and continue).
- Blocked after 3 distinct approaches: commit what is sound, report "blocked" with exact failure output. Never fake evidence.
Final message is machine-consumed: status, summary (with deviations), evidence, commit hash(es).` }

function reviewPrompt(range, notes) { return `Adversarial review checkpoint (repo ${REPO}).
Read ${PLAN} (tasks ${range}), CLAUDE.md, docs/DESIGN.md. Review actual repo state: git log/diffs + read the touched sources.
Implementer-reported progress:\n${notes.map(s => '- '+s).join('\n')}
Hunt for: <plan-specific failure classes>, design drift, fake evidence (re-run 'just test' and 'git add -A && nix flake check -L' yourself), unpushed commits. Do NOT fix; report. 'critical' only for confirmed compounding defects.` }

const notes = []
for (let n = 1; n <= TASK_TITLES.length; n++) {
  const r = await agent(implPrompt(n, notes), { label: `task-${n}: ${TASK_TITLES[n-1]}`,
    phase: 'Implement', model: 'sonnet', schema: RESULT })
  if (!r) return { status:'aborted', failedAt:n, notes }
  notes.push(`T${n} [${r.status}] ${r.summary} (${r.commit || 'no commit'})`)
  if (r.status !== 'done') return { status:'blocked', failedAt:n, blocker:r, notes }
  if (n === MID_CHECKPOINT || n === TASK_TITLES.length) {
    const range = n === MID_CHECKPOINT ? `1-${n}` : `${MID_CHECKPOINT+1}-${n}`
    const rev = await agent(reviewPrompt(range, notes), { label:`review-tasks-${range}`,
      phase:'Review', model:'opus', schema:REVIEW })
    if (rev && rev.critical.length > 0) {
      log(`Review after task ${n}: ${rev.critical.length} critical, dispatching fixer`)
      const fix = await agent(`Fix these confirmed defects in ${REPO} (plan ${PLAN}; CLAUDE.md/DESIGN.md binding — verify each fix, commit, push):\n${rev.critical.map(c=>'- '+c).join('\n')}\nReport real evidence.`,
        { label:`fix-after-${range}`, phase:'Implement', model:'sonnet', schema:RESULT })
      notes.push(`Review ${range}: ${rev.critical.length} critical -> ${fix ? fix.summary : 'FIXER DIED'}`)
      if (!fix || fix.status !== 'done') return { status:'blocked', failedAt:`review-${range}`, blocker:fix, review:rev, notes }
    } else notes.push(`Review ${range}: clean${rev && rev.notes ? ' — '+rev.notes : ''}`)
  }
}
return { status:'complete', notes }
```

## After the workflow returns

Verify yourself before reporting: `git log`, remote sync (`git ls-remote`),
re-read the newest screenshots, push any classifier-stranded commits. If
`blocked`, finish the stranded step manually, then decide: fix-forward
inline for small things, or resume the workflow from cache
(`resumeFromRunId`) for structural failures.

## Milestone sequence (spec build order)

M1–M5 done. Next: **M6** clipboard history + panels (audio, network,
bluetooth, power, clock, **calendar** — Omarchy-quattro widget with the
life-progress easter egg + EDS/GOA events feasibility spike — weather);
**M7** now playing + Apple Music art, lock, screensaver, image picker;
**M8** greeter + nixos greeter module; **M9** polish pass (ledger retrofit
of M1–M3 surfaces), e1504g trial, switchover gate. Author each plan from
the spec section + docs/DESIGN.md just-in-time.
