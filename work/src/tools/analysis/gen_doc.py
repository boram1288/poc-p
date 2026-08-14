#!/usr/bin/env python3
# topic-classification.md 의 데이터 섹션 생성
import collections
import json
from pathlib import Path

ANALYSIS_DIR = Path(__file__).resolve().parents[3] / 'build' / 'analysis'

d = json.load(open(ANALYSIS_DIR / 'base858.json'))
subj = d['subj']; order = d['order']; short = d['short']; date = d['date']; tier = d['tier']
r = json.load(open(ANALYSIS_DIR / 'classified.json'))
files = json.load(open(ANALYSIS_DIR / 'files858.json'))
mm = json.load(open(ANALYSIS_DIR / 'master_map.json'))
inm = set(mm['inm'])
k3 = json.load(open(ANALYSIS_DIR / 'key3.json'))

KEY = ['arch/arm64/kvm/hyp/nvhe/mem_protect.c',
       'arch/arm64/kvm/pkvm.c',
       'arch/arm64/kvm/hyp/nvhe/hyp-main.c']

# 제안 시리즈 순서
ORDER = ['pvm-core', 'host-stage2', 'hyp-alloc', 'lock-tlb', 'sve-sme', 'pvmfw',
         'mmioguard', 'guest-side', 'mem-relinquish', 'psci-memprotect', 'modules',
         'hypmem-hypexport', 'mem-opt', 'smc-handlers', 'hyp-req', 'ffa', 'tracing',
         'iommu-core', 'smmu-v3', 'pviommu', 'device-assign', 'selftests', 'kvm-generic',
         '미분류', 'ack-only', 'non-pkvm']
RANK = {t: i for i, t in enumerate(ORDER)}

by = collections.defaultdict(list)
for s, (t, why) in r.items():
    by[t].append(s)

old = lambda ss: sorted(ss, key=lambda s: -order[s])   # 오래된 순

out = []
W = out.append

# ---- 토픽 요약표 ----
W('| 토픽 | 커밋수 | 최초 | 최종 | master 포함 | 7.1 스택 대응 |')
W('|---|---:|---|---|---:|---|')
T71NAME = {
 'pvm-core': 'base, pvm-core, mondebug', 'host-stage2': '(base에 흡수)', 'hyp-alloc': 'base, buddyrace',
 'lock-tlb': 'tlbi, rwlock, fgt', 'sve-sme': 'sme, sve, sve-donate', 'pvmfw': 'pvmfw',
 'mmioguard': 'mmioguard, mmio-autoenroll', 'guest-side': '(없음)', 'mem-relinquish': 'mem-relinquish',
 'psci-memprotect': 'psci-memprotect',
 'modules': 'modules-core/perms, getleaf, modprot, modlock, modearly',
 'hypmem-hypexport': 'hypmem, hypexport', 'mem-opt': 'coalesce, pinpage, c089817range, cma, thp-infra',
 'smc-handlers': 'smchandlers, smctrng', 'hyp-req': 'hyp-req', 'ffa': 'ffa-foundation/backhalf/blockb',
 'tracing': 'base, modtracing-v1', 'iommu-core': '없음', 'smmu-v3': '없음', 'pviommu': '없음',
 'device-assign': '없음', 'selftests': 'base', 'kvm-generic': '없음', '미분류': '-',
 'ack-only': '-', 'non-pkvm': '-'}
for t in ORDER:
    ss = by.get(t, [])
    if not ss:
        continue
    dts = sorted(date[s] for s in ss)
    W('| `%s` | %d | %s | %s | %d | %s |' % (t, len(ss), dts[0], dts[-1],
      sum(1 for s in ss if s in inm), T71NAME.get(t, '')))

# ---- 토픽별 커밋 목록 ----
W('')
W('<!--TOPICLISTS-->')
for t in ORDER:
    ss = by.get(t, [])
    if not ss:
        continue
    W('')
    W('### %s (%d커밋)' % (t, len(ss)))
    W('')
    for s in old(ss):
        W('- `%s` %s %s' % (short[s], date[s], subj[s]))

# ---- 핵심 3파일 순서표 ----
W('')
W('<!--KEY3-->')
tri = set(k3['tri']); multi = set(k3['multi'])
for k in KEY:
    ss = old(k3['own'][k])
    W('')
    W('#### %s (%d커밋)' % (k, len(ss)))
    W('')
    W('| # | SHA | 날짜 | 토픽 | 다중 | 제목 |')
    W('|---:|---|---|---|---|---|')
    peak = -1
    back = 0
    for i, s in enumerate(ss, 1):
        t = r[s][0]
        mk = '3파일' if s in tri else ('2파일' if s in multi else '')
        rk = RANK.get(t, 99)
        flag = ''
        if rk < peak:
            flag = ' (역행)'
            back += 1
        peak = max(peak, rk)
        W('| %d | `%s` | %s | %s%s | %s | %s |' % (i, short[s], date[s], t, flag, mk, subj[s].replace('|', r'\|')))
    W('')
    W('역행 지점(제안 시리즈 순서 기준 앞 토픽으로 되돌아가는 커밋): **%d개 / %d커밋**' % (back, len(ss)))

# ---- 3파일 동시 변경 ----
W('')
W('<!--MULTI-->')
W('| SHA | 날짜 | 토픽 | 파일수 | 제목 |')
W('|---|---|---|---:|---|')
for s in old(list(multi)):
    n = sum(1 for k in KEY if k in files[s])
    W('| `%s` | %s | %s | %d | %s |' % (short[s], date[s], r[s][0], n, subj[s].replace('|', r'\|')))

open(ANALYSIS_DIR / '_data.md', 'w').write('\n'.join(out) + '\n')
print('sections written', len(out), 'lines')
