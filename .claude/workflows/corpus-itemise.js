export const meta = {
  name: 'corpus-itemise',
  description: 'Judge unitemised prompts in the Hill90 prompt corpus, in parallel chunks',
  phases: [
    { title: 'Judge', detail: 'one agent per 40-prompt chunk; each writes judgements to JSON only' },
    { title: 'Load', detail: 'single serial agent loads every JSON into the ledger' },
  ],
}

const CHUNKS = 12
const SIZE = 40
const TMP = '/Users/jon/.claude/jobs/c5aa6462/tmp/corpus'

const SCHEMA = {
  type: 'object',
  required: ['chunk', 'prompts_read', 'items_written', 'out_file'],
  properties: {
    chunk: { type: 'integer' },
    prompts_read: { type: 'integer' },
    items_written: { type: 'integer' },
    out_file: { type: 'string' },
    notes: { type: 'string' },
  },
}

phase('Judge')

const judged = await parallel(
  Array.from({ length: CHUNKS }, (_, i) => () =>
    agent(
      `You are judging chunk ${i} of Jon's prompt corpus. This is the ONE step that needs a model; every read afterwards is plain SQL.

STEP 1 -- extract YOUR chunk only, no other chunk:

mkdir -p ${TMP}
python3 - <<'PY'
import sqlite3, os, json
db=os.path.expanduser('~/.local/state/agent-dotfiles-supervisor/ledger.sqlite3')
c=sqlite3.connect(db)
rows=c.execute("""select id, text_raw, context, project from prompts p
  where not exists(select 1 from items i where i.prompt_id=p.id)
  order by p.at limit ${SIZE} offset ${i * SIZE}""").fetchall()
out=[{"id":r[0],"text_raw":r[1],"context":r[2],"project":r[3]} for r in rows]
json.dump(out, open("${TMP}/chunk-${i}.json","w"), indent=1)
print("extracted", len(out))
PY

STEP 2 -- read ${TMP}/chunk-${i}.json and JUDGE each prompt.

Produce ${TMP}/judged-${i}.json: a JSON ARRAY, one entry per prompt, shape:

  {"prompt_id": "...", "items": [
     {"kind": "parameter|question|directive|thought|correction",
      "body": "one clear sentence in Jon's meaning, not his typos",
      "weight": "hard|preference|retracted",
      "status": "open|acknowledged|acted|resolved|dropped",
      "status_reason": "required ONLY if status is dropped",
      "resolved_to": "key=value, ONLY for kind=parameter that pins something"}]}

RULES, all of these are Jon's own and are not negotiable:

- EVERY prompt in the chunk gets an entry. A prompt worth nothing durable gets ONE item with kind=thought, weight=retracted, status=dropped and a status_reason saying why. Never omit a prompt -- omitted prompts resurface in the next chunk forever.
- \`resolved_to\` is for things that CONSTRAIN, e.g. \`tooling=cli_first\`, \`ui_fidelity=1:1\`, \`repo_root=clean\`. A question or a one-off directive has no resolved_to.
- \`weight=hard\` means binding. \`preference\` means he leans that way. Getting this wrong manufactures false conflicts -- a preference was once treated as binding and cost a session.
- Do NOT soften his tone. If he was blunt, the body stays blunt. You are recording what he meant, not making it polite.
- Do NOT invent context. If a prompt is ambiguous, say so in the body rather than guessing a meaning.
- Machine-authored text (dispatch briefs, skill definitions, context reports, command output) is dropped with a status_reason -- it is not Jon.

STEP 3 -- validate before returning:
python3 -c "import json;d=json.load(open('${TMP}/judged-${i}.json'));print('entries',len(d),'items',sum(len(e['items']) for e in d))"

Return the counts. DO NOT write to the ledger -- a later serial stage does that. Concurrent writers would contend on one SQLite file.`,
      { label: `judge:${i}`, phase: 'Judge', schema: SCHEMA }
    )
  )
)

const ok = judged.filter(Boolean)
log(`judged ${ok.length}/${CHUNKS} chunks, ${ok.reduce((a, r) => a + (r.items_written || 0), 0)} items pending load`)

phase('Load')

const loaded = await agent(
  `Load every judged chunk into the ledger, SERIALLY. There are ${ok.length} files.

for f in ${TMP}/judged-*.json; do
  echo "== $f"
  python3 /Users/jon/.claude/jobs/c5aa6462/tmp/itemize.py --load "$f" 2>&1 | tail -2
done

Then report, with real output pasted:
  sqlite3 ~/.local/state/agent-dotfiles-supervisor/ledger.sqlite3 "select (select count(*) from items) items, (select count(*) from prompts p where not exists(select 1 from items i where i.prompt_id=p.id)) unitemised, (select count from possibility_count) params, (select count(*) from unacknowledged) unack;"

Then re-run ONE of the loads and confirm it writes 0 -- idempotency must hold.

If a file fails to load, say which and why. Do not skip it silently.`,
  {
    label: 'load-serial',
    phase: 'Load',
    schema: {
      type: 'object',
      required: ['items_total', 'unitemised_remaining', 'params', 'idempotent'],
      properties: {
        items_total: { type: 'integer' },
        unitemised_remaining: { type: 'integer' },
        params: { type: 'integer' },
        unack: { type: 'integer' },
        idempotent: { type: 'boolean' },
        failures: { type: 'string' },
      },
    },
  }
)

return { chunks_judged: ok.length, load: loaded }
