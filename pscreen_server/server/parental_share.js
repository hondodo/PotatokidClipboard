// 档案引用共享：纯逻辑模块（被 admin.js 接线，被单测直接驱动）。
//
// 语义（与 docs/parent-app-redesign-prototype.html 的「档案共享」页一致）：
// - 主本档案存在某台电视 `machine.parental.children[]`，每个档案可选带
//   `sharedTo: [家长号]` 白名单——只有名单内的家长能看到并引用它（owner opt-in）。
// - 引用方电视 `machine.parental.shared[]` 只存坐标 {refId, owner, machineId,
//   childId, createdAt}，不存副本；改主本规则/限额时所有引用方下次读取自动同步。
// - 来源电视解绑原家长 / 来源档案被删 / 当前家长被移出 sharedTo → 引用标
//   `status:'broken'` 保留占位，提示重新选择，绝不静默丢弃配置。
// - 引用档案在引用方只读：规则、题库、头像的写入都被护栏拒绝，读则重定向到主本。
// - 观看时长按「主本档案坐标」跨电视合并，明细仍分别记录在哪台电视。
//
// 本模块不读写磁盘、不依赖 express；所有数据由调用方注入，便于隔离单测。

'use strict';

const MAX_SHARED_REFS = 12;
const MAX_SHARED_TO = 32;
const MAX_ACCOUNT_LEN = 64;

/** 家长号白名单：缺失→[]；非数组/非字符串→拒绝；去重、去空、限长。 */
function normalizeSharedTo(value, field) {
    if (value === undefined || value === null) return [];
    if (!Array.isArray(value)) throw new Error(`${field} 必须是数组`);
    const out = [];
    for (const item of value) {
        if (typeof item !== 'string') throw new Error(`${field} 的元素必须是字符串`);
        const name = item.trim();
        if (!name || name.length > MAX_ACCOUNT_LEN) continue;
        if (!out.includes(name)) out.push(name);
        if (out.length >= MAX_SHARED_TO) break;
    }
    return out;
}

/** 引用坐标数组：缺失→[]；结构非法→拒绝；去重（同 owner+machineId+childId）、限长。 */
function normalizeSharedRefs(value) {
    if (value === undefined || value === null) return [];
    if (!Array.isArray(value)) throw new Error('parental.shared 必须是数组');
    if (value.length > MAX_SHARED_REFS) throw new Error(`parental.shared 最多 ${MAX_SHARED_REFS} 条引用`);
    const out = [];
    const seen = new Set();
    for (let i = 0; i < value.length; i++) {
        const item = value[i];
        const at = `parental.shared[${i}]`;
        if (!item || typeof item !== 'object' || Array.isArray(item)) throw new Error(`${at} 必须是对象`);
        const owner = typeof item.owner === 'string' ? item.owner.trim() : '';
        const machineId = typeof item.machineId === 'string' ? item.machineId.trim() : '';
        const childId = typeof item.childId === 'string' ? item.childId.trim() : '';
        if (!owner || owner.length > MAX_ACCOUNT_LEN) throw new Error(`${at}.owner 必须是非空家长号（≤${MAX_ACCOUNT_LEN} 字符）`);
        if (!machineId || childId === '') throw new Error(`${at}.machineId / childId 无效`);
        if (childId.length > 64) throw new Error(`${at}.childId 过长`);
        const dedupeKey = `${owner}\u0000${machineId}\u0000${childId}`;
        if (seen.has(dedupeKey)) continue;
        seen.add(dedupeKey);
        out.push({
            refId: typeof item.refId === 'string' && item.refId.trim() ? item.refId.trim() : `${machineId}:${childId}`,
            owner,
            machineId,
            childId,
            createdAt: Number.isFinite(Number(item.createdAt)) ? Number(item.createdAt) : 0,
        });
    }
    return out;
}

/** 按机器 id 取机器（machines 为 id→machine 映射）。 */
function findMachine(machines, id) {
    if (!id) return null;
    return machines[id] || Object.values(machines).find((m) => m.commAccount === id || m.id === id) || null;
}

/**
 * 判定某台电视上 viewer 家长对 childId 的可见性来源。
 * 返回：
 * - { kind:'master', child }           本台主本档案，可读写；
 * - { kind:'shared', child, ref, source } 引用档案，只读；child 是主本档案内容副本；
 * - { kind:'broken', ref }             来源失效（电视不存在/档案被删/被移出白名单），仅占位；
 * - { kind:'missing', childId }        既非本台档案也无此引用。
 *
 * viewerParent 为空（TV 端内部展开）时跳过 sharedTo 白名单校验，只校验主本存在。
 */
function resolveChild(machine, allMachines, childId, viewerParent) {
    const children = machine && machine.parental && Array.isArray(machine.parental.children)
        ? machine.parental.children : [];
    const master = children.find((c) => c.id === childId);
    if (master) return { kind: 'master', child: master };

    const refs = machine && machine.parental && Array.isArray(machine.parental.shared)
        ? machine.parental.shared : [];
    const ref = refs.find((r) => r.childId === childId);
    if (!ref) return { kind: 'missing', childId };

    return resolveRef(machine, allMachines, ref, viewerParent);
}

/** 展开一条引用坐标：取主本内容 + 权限/失效判定。 */
function resolveRef(machine, allMachines, ref, viewerParent) {
    const source = findMachine(allMachines, ref.machineId);
    if (!source) return { kind: 'broken', ref, reason: 'machine-missing' };
    const sourceChildren = source.parental && Array.isArray(source.parental.children)
        ? source.parental.children : [];
    const child = sourceChildren.find((c) => c.id === ref.childId);
    if (!child) return { kind: 'broken', ref, reason: 'child-missing' };
    // owner 必须仍是来源电视的绑定家长（来源解绑原家长 → 失效）。
    const bound = Array.isArray(source.parents) ? source.parents : [];
    if (!bound.includes(ref.owner)) return { kind: 'broken', ref, reason: 'owner-unbound' };
    // 可见性口径必须与「写入引用」(admin.js POST /parental/shared) 及「候选列表」
    // (buildShareView) 完全一致，否则同账号引用一落地就被误判失效：
    //   viewer 命中任一即 ok —— ① 来源电视的绑定家长（同一家长号名下其它电视默认可见）；
    //   ② 主本档案的 sharedTo 白名单（跨家长：对方 owner opt-in 分享给我）。
    // TV 端内部展开（viewerParent 空）跳过此项，引用建立时已校验过。
    if (viewerParent) {
        const bound = Array.isArray(source.parents) ? source.parents : [];
        const sameAccount = bound.includes(viewerParent);
        const allow = Array.isArray(child.sharedTo) ? child.sharedTo : [];
        if (!sameAccount && !allow.includes(viewerParent)) {
            return { kind: 'broken', ref, reason: 'not-shared-to-viewer' };
        }
    }
    return { kind: 'shared', ref, source, child };
}

/**
 * 家长端「档案共享」页的展开视图。
 * 返回 { masters, imported, candidates }：
 * - masters：本台主本档案（含 sharedTo），标 isMaster；
 * - imported：本台已引用档案，含 status ok|broken、readOnly、source；
 * - candidates：可引用候选——① 同一家长号名下其它电视的主本（默认可见）；
 *   ② 其它家长电视里 sharedTo 含 viewer 的主本（对方 opt-in 分享给我）。
 */
function buildShareView(machine, allMachines, viewerParent) {
    const masters = (machine.parental && Array.isArray(machine.parental.children)
        ? machine.parental.children : []).map((child) => ({
        id: child.id,
        name: child.name,
        profileMode: child.profileMode || 'mild',
        dailyLimitMin: child.dailyLimitMin || 0,
        sessionLimitMin: child.sessionLimitMin || 0,
        locked: child.locked === true,
        isMaster: true,
        readOnly: false,
        sharedTo: Array.isArray(child.sharedTo) ? child.sharedTo : [],
    }));

    const refs = machine.parental && Array.isArray(machine.parental.shared)
        ? machine.parental.shared : [];
    const imported = refs.map((ref) => {
        const r = resolveRef(machine, allMachines, ref, viewerParent);
        if (r.kind === 'shared') {
            return {
                refId: ref.refId, id: r.child.id, name: r.child.name,
                profileMode: r.child.profileMode || 'mild',
                dailyLimitMin: r.child.dailyLimitMin || 0,
                sessionLimitMin: r.child.sessionLimitMin || 0,
                locked: r.child.locked === true,
                isMaster: false, readOnly: true, status: 'ok',
                source: { machineId: r.source.id, machineName: r.source.name, owner: ref.owner, childId: ref.childId },
            };
        }
        return {
            refId: ref.refId, id: ref.childId, name: ref.name || ref.childId,
            isMaster: false, readOnly: true, status: 'broken', reason: r.reason,
            source: { machineId: ref.machineId, owner: ref.owner, childId: ref.childId },
        };
    });

    // 可引用候选：遍历全部电视的主本档案。排除本台；分「同账号」与「对方分享给我」两类。
    const candidates = [];
    const already = new Set(refs.map((r) => `${r.machineId}\u0000${r.childId}`));
    for (const source of Object.values(allMachines)) {
        if (!source || source.id === machine.id) continue;
        const isTv = source.commApp && String(source.commApp).indexOf('screen.potatokid') >= 0;
        const sourceChildren = source.parental && Array.isArray(source.parental.children)
            ? source.parental.children : [];
        const sourceParents = Array.isArray(source.parents) ? source.parents : [];
        const sameAccount = !!viewerParent && sourceParents.includes(viewerParent);
        for (const child of sourceChildren) {
            const key = `${source.id}\u0000${child.id}`;
            if (already.has(key)) continue;
            const sharedTo = Array.isArray(child.sharedTo) ? child.sharedTo : [];
            const viaShared = !!viewerParent && sharedTo.includes(viewerParent) && !sameAccount;
            if (!sameAccount && !viaShared) continue;
            candidates.push({
                machineId: source.id,
                machineName: source.name,
                owner: sourceParents[0] || '',
                childId: child.id,
                name: child.name,
                profileMode: child.profileMode || 'mild',
                dailyLimitMin: child.dailyLimitMin || 0,
                via: sameAccount ? 'same-account' : 'shared-to-me',
                isTv,
            });
        }
    }
    return { masters, imported, candidates };
}

/**
 * 题库/头像读取落点：引用档案重定向到主本电视 id；本台档案用本台 id。
 * 返回 { ok:true, deviceIdForLookup, childIdForLookup, readOnly:boolean }
 * 或 { ok:false, reason }。
 */
function resolveQuizTarget(machine, allMachines, childId, viewerParent) {
    const r = resolveChild(machine, allMachines, childId, viewerParent);
    if (r.kind === 'master') {
        return { ok: true, deviceIdForLookup: machine.id, childIdForLookup: childId, readOnly: false };
    }
    if (r.kind === 'shared') {
        return { ok: true, deviceIdForLookup: r.source.id, childIdForLookup: r.child.id, readOnly: true };
    }
    if (r.kind === 'broken') return { ok: false, reason: '引用来源已失效，请在「档案共享」页重新选择' };
    return { ok: false, reason: '儿童档案不存在' };
}

/**
 * 观看时长按主本档案坐标归并的 key。
 * 本台档案 → `<本台id>:<childId>`；引用档案 → `<来源机器id>:<来源childId>`（与主本一致）。
 * 明细里仍保留实际观看的 machineId / machineName。
 */
function durationAnchorKey(machine, allMachines, childId) {
    const r = resolveChild(machine, allMachines, childId, null);
    if (r.kind === 'shared') return `${r.source.id}:${r.child.id}`;
    return `${machine.id}:${childId}`;
}

/**
 * TV 端配置展开：把本台引用（`parental.shared`）解析成完整档案，追加到
 * `children` 尾部后随设备 config 下发。
 *
 * 引用记录里只有坐标（machineId / childId / name），没有档位、时长、黑白名单
 * 等规则；电视端要执行限时与频道过滤，必须拿到主本内容，故在服务端展开。
 *
 * - 只做派生，不落盘，也不修改传入的 machine / parental；
 * - viewerParent 传空：引用建立时已校验可见性，设备侧只校验主本仍存在；
 * - 来源失效（电视/档案/绑定关系消失）→ 跳过，不影响本机其它档案；
 * - id 与本机 children 重复的引用跳过，避免选人页出现重复卡片。
 *
 * 返回 null 表示没有可展开的引用（调用方沿用原始 parental）。
 */
function expandSharedChildren(machine, allMachines) {
    const parental = machine && machine.parental;
    if (!parental || !Array.isArray(parental.shared) || parental.shared.length === 0) return null;
    const masters = Array.isArray(parental.children) ? parental.children : [];
    const taken = new Set(masters.map((c) => c.id));
    const imported = [];
    for (const ref of parental.shared) {
        const resolved = resolveRef(machine, allMachines, ref, null);
        if (resolved.kind !== 'shared' || !resolved.child || taken.has(resolved.child.id)) continue;
        taken.add(resolved.child.id);
        imported.push({
            ...resolved.child,
            // 只读标记：电视端不编辑共享档案（改动回到主本所在电视）。
            readOnly: true,
            sourceMachineId: resolved.source ? resolved.source.id : ref.machineId,
            sourceMachineName: resolved.source ? resolved.source.name : '',
        });
    }
    if (imported.length === 0) return null;
    return { ...parental, children: masters.concat(imported) };
}

module.exports = {
    MAX_SHARED_REFS,
    MAX_SHARED_TO,
    normalizeSharedTo,
    normalizeSharedRefs,
    findMachine,
    resolveChild,
    resolveRef,
    buildShareView,
    expandSharedChildren,
    resolveQuizTarget,
    durationAnchorKey,
};
