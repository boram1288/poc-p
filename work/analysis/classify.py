#!/usr/bin/env python3
# 858 커밋 토픽 분류기. 7.1 태그 매칭 우선, 나머지는 경로+제목 규칙.
import json, re, collections

d = json.load(open('/tmp/base858.json'))
subj = d['subj']; tier = d['tier']; order = d['order']; short = d['short']; date = d['date']
m71 = json.load(open('/tmp/match71.json'))
tag71 = dict(m71['exact']); tag71.update(m71['fuzzy'])
files = json.load(open('/tmp/files858.json'))

ACKPAT = ('/configs/', 'BUILD.bazel', '.bzl', '.fragment', 'build.config', 'OWNERS', 'TEST_MAPPING')
def isack(f):
    return any(k in f for k in ACKPAT) or f.startswith(('android/', 'gki/', 'kmi/')) \
        or f.startswith(('tools/testing/selftests/android', 'tools/testing/kunit', 'tools/testing/android'))

# 7.1 태그 -> 최종 토픽
T71 = {
 'pvm-core':'pvm-core', 'tlbi':'lock-tlb', 'sme':'sve-sme', 'rwlock':'lock-tlb',
 'pvmfw':'pvmfw', 'sve-donate':'sve-sme', 'mondebug':'pvm-core', 'mmioguard':'mmioguard',
 'mmio-autoenroll':'mmioguard', 'mem-relinquish':'mem-relinquish', 'psci-memprotect':'psci-memprotect',
 'modules-core':'modules', 'modules-perms':'modules', 'fgt':'lock-tlb', 'getleaf':'modules',
 'modprot':'modules', 'modlock':'modules', 'modearly':'modules', 'hypmem':'hypmem-hypexport',
 'coalesce':'mem-opt', 'hypexport':'hypmem-hypexport', 'smchandlers':'smc-handlers',
 'pinpage':'mem-opt', 'c089817range':'mem-opt', 'smctrng':'smc-handlers', 'cma':'mem-opt',
 'buddyrace':'hyp-alloc', 'sve':'sve-sme', 'spine-complete':None, 'postsnap':None,
 'ffa-foundation':'ffa', 'hyp-req':'hyp-req', 'ffa-backhalf':'ffa', 'ffa-blockb':'ffa',
 'sidefixes':None, 'thp-infra':'mem-opt', 'audit-fixes':None, 'modtracing':'tracing', 'base':None,
}

RX = lambda p: re.compile(p, re.I)

# (토픽, 제목 정규식, 경로 정규식) - 위에서부터 먼저 맞는 것 채택
RULES = [
 # --- 명확한 하위 서브시스템 ---
 ('pviommu',  RX(r'pviommu|pv[- ]iommu|virtio.?iommu|paravirt.*iommu'), RX(r'pviommu|smmu-v3/pkvm/pv/|arm-smmu-v3-kvm-pv|arm-smmu-v3-pv')),
 ('smmu-v3',  RX(r'smmuv3|smmu-v3|smmu v3'), RX(r'arm-smmu-v3')),
 ('iommu-core', RX(r'iommu|smmu'), RX(r'nvhe/iommu|include/nvhe/iommu|kvm/iommu\.c|drivers/iommu/|include/linux/iommu\.h|include/uapi/linux/iommu\.h|kvm_iommu')),
 ('ffa',      RX(r'\bff-?a\b|ffa_'), RX(r'ffa')),
 ('pvmfw',    RX(r'pvmfw|pvm firmware|guest firmware|protected.*firmware'), RX(r'pvmfw')),
 ('sve-sme',  RX(r'\bsve\b|\bsme\b|fpsimd|zcr_el|smcr_el|vector length|\bvl\b'), None),
 ('tracing',  RX(r'hyp_?printk|hyp[ _-]?event|hyp[ _-]?trace|tracefs|ftrace|trace remote|remote_event|ring[ _-]?buffer|simple_ring_buffer|trace_hyp|stack ?trace|stacktrace|hyp_?dbg|dump_on_panic'),
              RX(r'kvm/hyp_trace|hyp_events|kvm_define_hypevents|tracing/|ring_buffer|hyp/nvhe/trace|hyp/nvhe/ftrace|selftests/hyp-trace')),
 ('modules',  RX(r'\bmodule|modprobe'), RX(r'nvhe/modules\.c|kvm_pkvm_module|nvhe/mod|pkvm_module')),
 ('mmioguard', RX(r'mmio[ _-]?guard'), None),
 ('psci-memprotect', RX(r'mem_protect|memprotect|psci.*(mem|protect)|MEM_PROTECT'), None),
 ('mem-relinquish', RX(r'relinquish'), None),
 ('hyp-req',  RX(r'hyp_?req|pkvm_hyp_req|HYP_REQ|hyp request'), None),
 ('hypmem-hypexport', RX(r'hyp_?mem|protected_hyp_mem|hyp[ _-]?export|non-?cacheable|hyp_fixmap|__pkvm_host_(un)?share_hyp|hypexport'), None),
 ('hyp-alloc', RX(r'hyp[ _-]?alloc|hyp_pool|buddy|memcache|hyp_page|private_range|shrinker|topup|reclaim_hyp|refill'), None),
 ('mem-opt',  RX(r'pinned.?page|\bcma\b|pin_?page|coalesce|\bthp\b|huge|prefault|split|block mapping|sglist|range-based|\brange\b|contiguous|donate_guest|swiotlb|dma[- ]buf|dma[- ]heap|zone_dma'), None),
 ('lock-tlb', RX(r'\btlbi?\b|tlb |rwlock|\bfgt\b|fine.?grain|spinlock|\block\b|barrier|hcrx|hcr_el2'), None),
 ('smc-handlers', RX(r'\bsmc\b|smccc|\btrng\b|host_smc|entropy'), None),
 ('selftests', None, RX(r'tools/testing/selftests|tools/include|tools/headers')),
 ('guest-side', RX(r'pkvm-guest|guest.*mmio guard'), RX(r'arch/arm64/kernel/pkvm|drivers/virt/coco|drivers/virt/pkvm|arch/arm64/mm/mem_encrypt')),
 ('device-assign', RX(r'\bvfio\b|device assign|assignable device|assigned device|\bpm driver\b|power domain|DEV_REQ_PWR|device mmio|\bdevices:'), RX(r'drivers/vfio|nvhe/device/|kvm/device\.c')),
 ('pvm-core', RX(r'protected vm|pvm|protected guest|vcpu|vgic|sysreg|sys_reg|psci|hypercall|hvc|memslot|\bmte\b|kvm ioctl|kvm_get_one_reg|documentation'), None),
 ('host-stage2', None, RX(r'nvhe/mem_protect\.c|nvhe/mem_protect\.h|include/nvhe/mem_protect\.h|nvhe/setup\.c')),
 ('hyp-alloc', None, RX(r'nvhe/page_alloc\.c|nvhe/gfp\.h|nvhe/alloc|nvhe/mm\.c|include/nvhe/mm\.h')),
 ('kvm-generic', None, RX(r'^virt/kvm|^include/linux/kvm_host\.h|^include/uapi/linux/kvm\.h')),
 ('pvm-core', None, RX(r'arch/arm64/kvm|arch/arm64/include/asm/kvm|arch/arm64/kernel|arch/arm64/mm|Documentation')),
]

PATH_TOPIC = [
 ('pviommu', re.compile(r'pviommu|smmu-v3/pkvm/pv/|arm-smmu-v3-kvm-pv|arm-smmu-v3-pv')),
 ('smmu-v3', re.compile(r'arm-smmu-v3')),
 ('iommu-core', re.compile(r'nvhe/iommu|include/nvhe/iommu|kvm/iommu\.c|drivers/iommu/|include/linux/iommu\.h')),
 ('ffa', re.compile(r'ffa')),
 ('tracing', re.compile(r'hyp_trace|hyp_event|hypevents|tracing/|ring_buffer|hyp-trace')),
 ('modules', re.compile(r'nvhe/modules\.c|kvm_pkvm_module')),
 ('selftests', re.compile(r'tools/testing/selftests|tools/include|tools/arch')),
 ('device-assign', re.compile(r'drivers/vfio|nvhe/device/')),
 ('guest-side', re.compile(r'arch/arm64/kernel/pkvm|drivers/virt/')),
]

# pKVM 무관 Android 캐리오버 (경로가 KVM/IOMMU 밖이고 제목에 pkvm/kvm 없음)
KVMPATH = re.compile(r'arch/arm64/kvm|arch/arm64/include/asm/kvm|arch/arm64/include/asm/virt\.h|include/kvm|virt/kvm|drivers/iommu|Documentation/virt/kvm|tools/testing/selftests/kvm|selftests/hyp-trace|arch/arm64/kernel/pkvm|drivers/virt|drivers/vfio')
KVMTITLE = RX(r'\bkvm\b|pkvm|hyp\b|iommu|smmu|el2|ffa|pvmfw')

result = {}
for sha in subj:
    s = subj[sha]; fs = files.get(sha, [])
    nonack = [f for f in fs if not isack(f)]
    if fs and not nonack:
        result[sha] = ('ack-only', 'ACK 전용 경로만 변경')
        continue
    if not (KVMTITLE.search(s) or any(KVMPATH.search(f) for f in nonack)):
        result[sha] = ('non-pkvm', 'pKVM 무관 Android 캐리오버')
        continue
    t = tag71.get(sha)
    hit = None
    for topic, trx, prx in RULES:
        if trx and trx.search(s):
            hit = (topic, '제목규칙')
            break
        if prx and any(prx.search(f) for f in nonack):
            hit = (topic, '경로규칙')
            break
    if not hit and t:
        mapped = T71.get(t.split('-', 1)[1])
        if mapped:
            hit = (mapped, '7.1 태그')
    if not hit:
        for topic, prx in PATH_TOPIC:
            if any(prx.search(f) for f in nonack):
                hit = (topic, '경로규칙2')
                break
    if not hit:
        hit = ('미분류', '규칙 미적용')
    if t:
        hit = (hit[0], hit[1] + ' / 7.1 %s' % t)
    result[sha] = hit

json.dump(result, open('/tmp/classified.json', 'w'))
c = collections.Counter(v[0] for v in result.values())
for k, n in c.most_common():
    print('%5d  %s' % (n, k))
print('total', sum(c.values()))
