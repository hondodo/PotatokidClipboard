// 家庭级主档案模型（D-02）：服务端存储与投影。
//
// 设计意图（与 docs/parent-app-v2-implementation-plan.md 2.3 / CR-01 / CR-02 / D-01 一致）：
// - 家庭主档案 FamilyChild 按 childId 全局唯一，不含 deviceId / sharedTo / 解锁方式。
// - 分配 Assignment 为「电视 × 档案」：某台电视启用哪些家庭档案。
// - 电视本台设置 DeviceLocal 按 deviceId 存儿童模式开关与解锁方式/PIN（CR-02，U1 每台电视一个）。
// - 题库 Quiz / 头像按家庭 childId 分库；跨家庭只以复制副本流转（CR-01 Q1）。
// - 当日时长账主键 (childId, date) 在家庭内跨电视累计（S3），本模块不负责时长结算，
//   只负责把 durationAnchorKey 统一到 childId。
//
// 本模块不依赖 express，读写集中在 load/save；所有实体自带服务端维护的 revision
// （D-01 基础，冲突判定由写入收口负责），客户端不得自行生成或递增。
//
// 接入方式：admin.js 在 USE_FAMILY_MODEL 开启时把 resolveMachineConfig 切到
// projectDevice，并把 PUT /machines/:id 的 parental 分支改写成对 store 的拆分写入。
// 标志默认关闭，故未部署/未开标志时完全沿用旧行为，不构成硬阻塞风险。

'use strict';

const fs = require('fs');

/** 服务端单调时间（毫秒）。 */
function nowMs() {
    return Date.now();
}

/** 安全取字符串。 */
function str(v, fallback = '') {
    return typeof v === 'string' ? v : fallback;
}

/** 安全取正整数（含 0）。 */
function intOr(v, fallback) {
    const n = Number(v);
    return Number.isFinite(n) && n >= 0 ? Math.trunc(n) : fallback;
}

class FamilyStore {
    constructor(file) {
        this.file = file;
        this.data = emptyData();
        this._loaded = false;
    }

    load() {
        if (this._loaded) return;
        try {
            if (fs.existsSync(this.file)) {
                const raw = JSON.parse(fs.readFileSync(this.file, 'utf8'));
                if (raw && typeof raw === 'object') {
                    this.data = Object.assign(emptyData(), raw);
                }
            }
        } catch (error) {
            console.error('[family] 读取失败，使用空数据:', error.message);
            this.data = emptyData();
        }
        this._loaded = true;
    }

    save() {
        try {
            fs.writeFileSync(this.file, JSON.stringify(this.data, null, 2), 'utf8');
        } catch (error) {
            console.error('[family] 保存失败:', error.message);
        }
    }

    /** D-01 基础：写入时递增版本并记录操作者与时间。 */
    _touch(entity, operator) {
        entity.revision = intOr(entity.revision, 0) + 1;
        entity.updatedBy = str(operator);
        entity.updatedAt = nowMs();
        return entity;
    }

    /**
     * 从旧模型迁移：把每台电视 machine.parental.children 投影成家庭主档案 +
     * 该电视的分配 + 本台解锁设置。仅当家庭库为空时执行一次，幂等。
     * machines：id → machine 映射（含 parental / parents 字段）。
     */
    migrateFromLegacy(machines) {
        this.load();
        if (Object.keys(this.data.children).length > 0) return false;
        let seeded = false;
        for (const machine of Object.values(machines)) {
            const parental = machine && machine.parental;
            if (!parental || !Array.isArray(parental.children) || parental.children.length === 0) continue;
            const deviceId = machine.id;
            const assigned = [];
            for (const c of parental.children) {
                const id = str(c.id);
                if (!id) continue;
                if (!this.data.children[id]) {
                    this.data.children[id] = this._touch(
                        {
                            childId: id,
                            name: str(c.name),
                            age: intOr(c.age, 0),
                            avatarId: str(c.avatarId),
                            profileMode: str(c.profileMode, 'mild'),
                            dailyLimitMin: intOr(c.dailyLimitMin, 0),
                            sessionLimitMin: intOr(c.sessionLimitMin, 0),
                            bedtimeStart: str(c.bedtimeStart),
                            bedtimeEnd: str(c.bedtimeEnd),
                            blacklist: Array.isArray(c.blacklist) ? c.blacklist.slice() : [],
                            whitelist: Array.isArray(c.whitelist) ? c.whitelist.slice() : [],
                            locked: c.locked === true,
                        },
                        machine.owner || '',
                    );
                    seeded = true;
                }
                assigned.push(id);
            }
            if (assigned.length > 0) {
                this.data.assignments[deviceId] = { deviceId, childIds: assigned, revision: 1, updatedBy: machine.owner || '', updatedAt: nowMs() };
            }
            this.data.deviceLocal[deviceId] = this._touch(
                {
                    deviceId,
                    mode: str(parental.mode, 'off') === 'on' ? 'on' : 'off',
                    unlockMode: str(parental.unlockMode, 'remote'),
                    pin: str(parental.pin),
                    activeChildIds: Array.isArray(parental.activeChildIds) ? parental.activeChildIds.slice() : assigned.slice(),
                },
                machine.owner || '',
            );
        }
        if (seeded) this.save();
        return seeded;
    }

    /** 给某台电视投影出生效 parental 配置（电视端消费的形状，保持旧字段兼容）。 */
    projectDevice(deviceId) {
        this.load();
        const assignment = this.data.assignments[deviceId];
        const childIds = assignment ? assignment.childIds.slice() : [];
        const children = [];
        for (const id of childIds) {
            const fc = this.data.children[id];
            if (!fc) continue;
            children.push({
                id: fc.childId,
                name: fc.name,
                age: fc.age,
                avatarId: fc.avatarId,
                // 投影出设备端能识别的 `avatar`（preset:xxx / 公网 URL），
                // 否则 TV 选人页读不到头像、只回落名字首字。
                avatar: fc.avatarId,
                profileMode: fc.profileMode,
                dailyLimitMin: fc.dailyLimitMin,
                sessionLimitMin: fc.sessionLimitMin,
                bedtimeStart: fc.bedtimeStart,
                bedtimeEnd: fc.bedtimeEnd,
                blacklist: fc.blacklist,
                whitelist: fc.whitelist,
                locked: fc.locked === true,
            });
        }
        const dl = this.data.deviceLocal[deviceId] || emptyDeviceLocal(deviceId);
        return {
            mode: dl.mode === 'on' ? 'on' : 'off',
            children,
            unlockMode: dl.unlockMode,
            pin: dl.pin,
            activeChildIds: dl.activeChildIds && dl.activeChildIds.length > 0 ? dl.activeChildIds : childIds,
            shared: [], // CR-01 后不再有档案引用坐标；保留空数组兼容旧 TV fromJson
        };
    }

    // -------------------------------------------------- 写入接口（供批量部署时接线）
    upsertChild(child, operator) {
        this.load();
        const id = str(child.childId || child.id);
        if (!id) throw new Error('childId 不能为空');
        const prev = this.data.children[id];
        const next = {
            childId: id,
            name: str(child.name),
            age: intOr(child.age, 0),
            avatarId: str(child.avatarId),
            profileMode: str(child.profileMode, 'mild'),
            dailyLimitMin: intOr(child.dailyLimitMin, 0),
            sessionLimitMin: intOr(child.sessionLimitMin, 0),
            bedtimeStart: str(child.bedtimeStart),
            bedtimeEnd: str(child.bedtimeEnd),
            blacklist: Array.isArray(child.blacklist) ? child.blacklist.slice() : [],
            whitelist: Array.isArray(child.whitelist) ? child.whitelist.slice() : [],
            locked: child.locked === true,
            revision: 0,
            updatedBy: '',
            updatedAt: 0,
        };
        if (prev) {
            next.revision = prev.revision;
            next.updatedBy = prev.updatedBy;
            next.updatedAt = prev.updatedAt;
        }
        this._touch(next, operator);
        this.data.children[id] = next;
        this.save();
        return next;
    }

    removeChild(childId, operator) {
        this.load();
        if (!this.data.children[childId]) return false;
        delete this.data.children[childId];
        for (const a of Object.values(this.data.assignments)) {
            a.childIds = a.childIds.filter((id) => id !== childId);
            this._touch(a, operator);
        }
        this.save();
        return true;
    }

    setAssignment(deviceId, childIds, operator) {
        this.load();
        const ids = Array.isArray(childIds) ? childIds.map((x) => str(x)).filter(Boolean) : [];
        const prev = this.data.assignments[deviceId];
        const next = { deviceId, childIds: ids, revision: 0, updatedBy: '', updatedAt: 0 };
        if (prev) {
            next.revision = prev.revision;
            next.updatedBy = prev.updatedBy;
            next.updatedAt = prev.updatedAt;
        }
        this._touch(next, operator);
        this.data.assignments[deviceId] = next;
        // 本台 activeChildIds 跟随分配收敛
        const dl = this.data.deviceLocal[deviceId] || emptyDeviceLocal(deviceId);
        dl.activeChildIds = ids.slice();
        this._touch(dl, operator);
        this.data.deviceLocal[deviceId] = dl;
        this.save();
        return next;
    }

    setDeviceLocal(deviceId, patch, operator) {
        this.load();
        const dl = this.data.deviceLocal[deviceId] || emptyDeviceLocal(deviceId);
        if (patch && typeof patch === 'object') {
            if (patch.mode !== undefined) dl.mode = str(patch.mode, 'off') === 'on' ? 'on' : 'off';
            if (patch.unlockMode !== undefined) dl.unlockMode = str(patch.unlockMode, dl.unlockMode);
            if (patch.pin !== undefined) dl.pin = str(patch.pin);
            if (Array.isArray(patch.activeChildIds)) dl.activeChildIds = patch.activeChildIds.map((x) => str(x)).filter(Boolean);
        }
        this._touch(dl, operator);
        this.data.deviceLocal[deviceId] = dl;
        this.save();
        return dl;
    }

    setQuiz(childId, questions, operator) {
        this.load();
        const q = this.data.quizzes[childId] || { childId, questions: [], sharedTo: [], sourceAccount: '', isCopy: false, revision: 0, updatedBy: '', updatedAt: 0 };
        q.questions = Array.isArray(questions) ? questions.slice() : [];
        this._touch(q, operator);
        this.data.quizzes[childId] = q;
        this.save();
        return q;
    }

    setQuizSharedTo(childId, sharedTo, operator) {
        this.load();
        const q = this.data.quizzes[childId] || { childId, questions: [], sharedTo: [], sourceAccount: '', isCopy: false, revision: 0, updatedBy: '', updatedAt: 0 };
        q.sharedTo = Array.isArray(sharedTo) ? sharedTo.map((x) => str(x)).filter(Boolean) : [];
        this._touch(q, operator);
        this.data.quizzes[childId] = q;
        this.save();
        return q;
    }

    /** CR-01 Q1：把来源题库整体复制为归属 targetChildId 的独立副本。 */
    importQuizCopy(targetChildId, sourceQuiz, sourceAccount, operator) {
        this.load();
        if (!sourceQuiz || !Array.isArray(sourceQuiz.questions)) throw new Error('来源题库无效');
        const copy = {
            childId: targetChildId,
            questions: sourceQuiz.questions.slice(),
            sharedTo: [],
            sourceAccount: str(sourceAccount),
            isCopy: true,
            revision: 0,
            updatedBy: '',
            updatedAt: 0,
        };
        this._touch(copy, operator);
        this.data.quizzes[targetChildId] = copy;
        this.save();
        return copy;
    }
}

function emptyData() {
    return { children: {}, assignments: {}, deviceLocal: {}, quizzes: {}, grants: {} };
}

function emptyDeviceLocal(deviceId) {
    return {
        deviceId: str(deviceId),
        mode: 'off',
        unlockMode: 'remote',
        pin: '',
        activeChildIds: [],
        revision: 0,
        updatedBy: '',
        updatedAt: 0,
    };
}

module.exports = { FamilyStore, nowMs };
