#!/usr/bin/env python3
"""Time every Pipeline read as a signed-in member of a fake company built by pipeline-volume-seed.sql.

LOCAL REBUILD ONLY. usage: pipeline-volume-bench.py <vol|mid> <owner|restricted> [text a case name must contain]
Results: docs/sales-pipeline-performance-verification.md
"""
import subprocess, sys, re, statistics, hashlib, uuid

def md5uuid(s): return str(uuid.UUID(hashlib.md5(s.encode()).hexdigest()))
SLUG = {'vol': 'perf-volume', 'mid': 'perf-midsize'}
LAST = {'vol': 12, 'mid': 6}
org_key, who = sys.argv[1], sys.argv[2]
only = sys.argv[3] if len(sys.argv) > 3 else None
ORG = md5uuid('perf-org:' + SLUG[org_key])
def uid(n): return md5uuid(f'{ORG}:user:{n}')
USER = uid(1 if who == 'owner' else LAST[org_key])
REP = uid(2)
STAGE_Q = md5uuid(f'{ORG}:stage:2')
STAGE_R = md5uuid(f'{ORG}:stage:1')
T = "board_today => '2026-10-02'"
O = f"target_organization_id => '{ORG}'"
def board(stage, extra='', limit=26):
    return f"select count(*) from pipeline_board_page({O}, target_stage => '{stage}', page_limit => {limit}, {extra})"
def counts(extra=''):
    return f"select count(*) from pipeline_stage_counts({O}{', ' + extra if extra else ''})"

cases = []
cols = ['new_request', 'assessment', 'quote_draft', 'quote_awaiting_response', 'quote_changes_requested', STAGE_Q, STAGE_R]
names = ['New', 'Assessment(grouped)', 'Draft', 'Awaiting', 'Changes', 'CustomQuote', 'CustomRequest']
for c, n in zip(cols, names):
    cases.append((f'board {n} task-order', board(c, T)))
for sk in ['stage_entered_at', 'created_at', 'estimated_value', 'expected_close_on']:
    for d in ['desc', 'asc']:
        if who != 'owner' and sk == 'estimated_value': continue
        cases.append((f'board Awaiting sort {sk} {d}', board('quote_awaiting_response', f"sort_key => '{sk}', sort_direction => '{d}'")))
        cases.append((f'board Assessment sort {sk} {d}', board('assessment', f"sort_key => '{sk}', sort_direction => '{d}'")))
cases.append(('table all task-order (50)', board('all', T, 51)))
for sk in ['stage_entered_at', 'created_at', 'estimated_value', 'expected_close_on']:
    if who != 'owner' and sk == 'estimated_value': continue
    cases.append((f'table all sort {sk} desc (50)', board('all', f"sort_key => '{sk}'", 51)))
cases.append(('board Awaiting owner=rep', board('quote_awaiting_response', f"{T}, owner_filter => 'member', filter_owner_user_id => '{REP}'")))
cases.append(('board Awaiting unassigned', board('quote_awaiting_response', f"{T}, owner_filter => 'unassigned'")))
cases.append(('board Awaiting last 30 days', board('quote_awaiting_response', f"{T}, created_from => '2026-09-03', created_to => '2026-10-03'")))
cases.append(('table all last 30 days', board('all', f"{T}, created_from => '2026-09-03', created_to => '2026-10-03'", 51)))
searches = {
    'name common (Kowalski)': "search_like => '%Kowalski%'",
    'title (roof)': "search_like => '%roof%'",
    'no match': "search_like => '%qqzzxx%'",
    'phone digits': "search_like => '%555-0142%', search_digits => '5550142'",
    'quote number': "search_like => '%33%', search_digits => NULL, search_number => 33",
    'lead source Google': "lead_source_filter => 'Google'",
}
for label, s in searches.items():
    cases.append((f'board Awaiting search {label}', board('quote_awaiting_response', f"{T}, {s}")))
    cases.append((f'board Assessment search {label}', board('assessment', f"{T}, {s}")))
    cases.append((f'table all search {label}', board('all', f"{T}, {s}", 51)))
    cases.append((f'counts search {label}', counts(s)))
cases.append(('counts plain', counts()))
cases.append(('counts owner=rep', counts(f"owner_filter => 'member', filter_owner_user_id => '{REP}'")))
cases.append(('counts last 30 days', counts("created_from => '2026-09-03', created_to => '2026-10-03'")))
cases.append(('lead sources list', f"select count(*) from pipeline_lead_sources('{ORG}')"))
for t in ['won', 'lost', 'direct_job']:
    cases.append((f'outcome page {t} default', f"select count(*) from pipeline_outcome_page({O}, outcome_type => '{t}', page_limit => 51)"))
for sk in ['title', 'client', 'created', 'outcome_at', 'total']:
    if who != 'owner' and sk == 'total': continue
    for d in ['asc', 'desc']:
        cases.append((f'outcome page won sort {sk} {d}', f"select count(*) from pipeline_outcome_page({O}, outcome_type => 'won', page_limit => 51, sort_key => '{sk}', sort_direction => '{d}')"))
cases.append(('outcome page won last month', f"select count(*) from pipeline_outcome_page({O}, outcome_type => 'won', page_limit => 51, outcome_from => '2026-09-01', outcome_to => '2026-10-01')"))
for label, rng in [('one month', "'2026-09-01', '2026-10-01'"), ('12 months', "'2025-10-02', '2026-10-03'"), ('all time', "NULL, NULL")]:
    cases.append((f'outcome tiles {label}', f"select count(*) from pipeline_outcome_tiles('{ORG}', {rng})"))
    cases.append((f'outcomes report {label}', f"select length(pipeline_outcomes_report('{ORG}', {rng})::text)"))
    cases.append((f'conversion report {label}', f"select length(pipeline_conversion_report('{ORG}', {rng})::text)"))
for label, rng in [('one month', "'2026-09-01', '2026-09-30'"), ('12 months', "'2025-10-02', '2026-10-02'"), ('3 years', "'2023-10-01', '2026-10-02'")]:
    cases.append((f'financial sales outcomes page {label}', f"select count(*) from financial_sales_outcomes_page('{ORG}', {rng}, NULL, NULL, 51, 'desc')"))
    cases.append((f'financial sales outcomes summary {label}', f"select count(*) from financial_sales_outcomes_summary('{ORG}', {rng})"))

RUNS = 5
print(f"# org={org_key} who={who} user={USER}")
print(f"{'case':58} {'rows':>7} {'first':>8} {'median':>8} {'max':>8}")
for name, sql in cases:
    if only and only not in name: continue
    script = ("begin;\nset local role authenticated;\n"
              f"set local request.jwt.claims = '{{\"sub\":\"{USER}\",\"role\":\"authenticated\"}}';\n"
              "\\timing on\n" + (sql + ";\n") * RUNS + "\\timing off\nrollback;\n")
    r = subprocess.run(['docker', 'exec', '-i', 'supabase_db_ucrm', 'psql', '-U', 'postgres', '-d', 'postgres', '-At'],
                       input=script, capture_output=True, text=True)
    times = [float(x) for x in re.findall(r'Time: ([\d.]+) ms', r.stdout)]
    if 'ERROR' in r.stderr or len(times) < RUNS:
        print(f"{name:58} ERROR {r.stderr.strip()[:200]}"); continue
    rows = [l for l in r.stdout.splitlines() if re.fullmatch(r'\d+', l)]
    rest = times[1:]
    print(f"{name:58} {rows[0] if rows else '?':>7} {times[0]:8.1f} {statistics.median(rest):8.1f} {max(rest):8.1f}")
