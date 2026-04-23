// Reads per-workspace result JSON files and writes a formatted table to the
// GitHub Actions job summary. Invoked by the tf-summarize composite action.
//
// Env vars (set by action.yml):
//   SUMMARY_TYPE    — "plan", "drift", or "release"
//   PROJECT         — Terraform project name (used as heading)
//   SKIPPED_RESULT  — value of needs.<job>.result from the calling workflow
//   SKIPPED_MESSAGE — warning body to show when the upstream job was skipped

const fs   = require('fs');
const path = require('path');

const type           = process.env.SUMMARY_TYPE;
const project        = process.env.PROJECT;
const skippedResult  = process.env.SKIPPED_RESULT;
const skippedMessage = process.env.SKIPPED_MESSAGE;

const resultsDir = `/tmp/${type}-results`;

await core.summary.addHeading(project, 2);

if (skippedResult === 'skipped') {
  await core.summary
    .addRaw(`> [!WARNING]\n> ${skippedMessage}\n`)
    .write();
  return;
}

let files = [];
try {
  files = fs.readdirSync(resultsDir)
    .filter(f => f.endsWith('.json'))
    .sort()
    .map(f => path.join(resultsDir, f));
} catch {}

if (files.length === 0) {
  await core.summary.addRaw('No results found.\n').write();
  return;
}

const isDrift = type === 'drift';

const successLabel = isDrift     ? '✅ No drift'
                   : type === 'release' ? '✅ Applied'
                   :                      '✅';

const rows = await Promise.all(files.map(async f => {
  const r = JSON.parse(fs.readFileSync(f, 'utf8'));

  const wsCell = r.job_url
    ? `<a href="${r.job_url}">${r.workspace}</a>`
    : r.workspace;

  if (r.status === 'success') {
    return isDrift
      ? [wsCell, successLabel]
      : [wsCell, successLabel, r.to_add, r.to_change, r.to_destroy];
  }

  // Drift: "changes-to-apply" means drift was detected (not a Terraform error)
  let statusMsg = (isDrift && r.failure_reason === 'changes-to-apply')
    ? '❌ Drift detected'
    : (r.failure_reason ? `❌ ${r.failure_reason}` : '❌ Failed');

  // Fetch check-run annotations for real failures (skip for known drift state)
  const skipAnnotations = isDrift && r.failure_reason === 'changes-to-apply';
  if (r.check_run_id && !skipAnnotations) {
    try {
      const { data: annotations } = await github.rest.checks.listAnnotations({
        owner:        context.repo.owner,
        repo:         context.repo.repo,
        check_run_id: r.check_run_id,
      });
      const errAnnotation = annotations.find(a => a.annotation_level === 'failure');
      if (errAnnotation?.message) {
        const truncated = errAnnotation.message.replace(/\n/g, ' ').slice(0, 150);
        const ellipsis  = errAnnotation.message.length > 150 ? '…' : '';
        statusMsg += ` — ${truncated}${ellipsis}`;
      }
    } catch (_) {
      // annotations unavailable — fall back to failure_reason only
    }
  }

  return isDrift
    ? [wsCell, statusMsg]
    : [wsCell, statusMsg, '', '', ''];
}));

const headers = isDrift
  ? [
      { data: 'Workspace', header: true },
      { data: 'Status',    header: true },
    ]
  : [
      { data: 'Workspace', header: true },
      { data: 'Status',    header: true },
      { data: '+Add',      header: true },
      { data: '~Change',   header: true },
      { data: '-Destroy',  header: true },
    ];

await core.summary.addTable([headers, ...rows]).write();
