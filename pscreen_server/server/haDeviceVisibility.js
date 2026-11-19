// HA 设备「是否显示到中控屏」的持久化存储。
//
// 数据落在 datas/admin/haDeviceVisibility.json，结构：
//   { "<deviceId>": true | false }
//   - true  = 显式显示
//   - false = 显式隐藏（home 端从首页网格移除该设备）
//   - 不存在（未配置）= 保持现状，交给 home 现有的家庭/房间过滤逻辑
//
// 三态设计的目的是「逐步接管」：默认不动任何设备，管理员逐个把不该上屏的
// 设备标记为隐藏，避免一次性把所有设备都隐藏/显示造成突变。

'use strict';

const fs = require('fs');
const path = require('path');

function createHaDeviceVisibilityService({ file } = {}) {
    let data = {};
    if (file && fs.existsSync(file)) {
        try {
            const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
            // 兼容两种结构：直接 map，或 { devices: map }
            const map = raw && typeof raw === 'object'
                ? (raw.devices && typeof raw.devices === 'object' ? raw.devices : raw)
                : {};
            for (const [k, v] of Object.entries(map)) {
                if (typeof v === 'boolean') data[String(k)] = v;
            }
        } catch (error) {
            console.error('[haDeviceVisibility] 读取失败，使用空配置:', error.message);
        }
    }

    function persist() {
        if (!file) return;
        try {
            fs.mkdirSync(path.dirname(file), { recursive: true });
            const tmp = `${file}.tmp`;
            fs.writeFileSync(tmp, JSON.stringify({ devices: data }, null, 2), 'utf8');
            fs.renameSync(tmp, file);
        } catch (error) {
            console.error('[haDeviceVisibility] 写入失败:', error.message);
            throw error;
        }
    }

    /** 返回完整配置 map（deviceId -> boolean）。 */
    function list() {
        return { ...data };
    }

    /** 取单个设备：未配置返回 undefined。 */
    function get(deviceId) {
        const k = String(deviceId == null ? '' : deviceId);
        return Object.prototype.hasOwnProperty.call(data, k) ? data[k] : undefined;
    }

    /** 设置单个设备。visible 必须是布尔。 */
    function set(deviceId, visible) {
        const k = String(deviceId == null ? '' : deviceId);
        if (!k) throw new Error('deviceId 不能为空');
        if (typeof visible !== 'boolean') throw new Error('visible 必须是布尔值');
        data[k] = visible;
        persist();
        return { deviceId: k, visible };
    }

    /** 批量设置。items: [{deviceId, visible}]。 */
    function setMany(items) {
        const changed = [];
        for (const item of items || []) {
            const k = String(item && item.deviceId != null ? item.deviceId : '');
            if (!k || typeof item.visible !== 'boolean') continue;
            data[k] = item.visible;
            changed.push({ deviceId: k, visible: item.visible });
        }
        if (changed.length) persist();
        return changed;
    }

    /** 删除某设备的显式配置，回归「未配置=保持现状」。 */
    function remove(deviceId) {
        const k = String(deviceId == null ? '' : deviceId);
        if (Object.prototype.hasOwnProperty.call(data, k)) {
            delete data[k];
            persist();
        }
        return { deviceId: k, removed: true };
    }

    /** 供 home 下发的精简 map（只含显式配置）。 */
    function publicMap() {
        return { ...data };
    }

    return { list, get, set, setMany, remove, publicMap };
}

module.exports = { createHaDeviceVisibilityService };
