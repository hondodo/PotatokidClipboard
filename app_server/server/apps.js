'use strict';

const express = require('express');
const { ok, wrap } = require('./apiutil');
const { ABIS } = require('./store');
const { makeDownloadUrl } = require('./update_api');

function appSummary(store, app) {
  return {
    ...app,
    releaseCount: store.listReleases(app.appId).length,
    latest: store.latestSummary(app.appId),
  };
}

// 应用 CRUD：仅挂在管理端口 47293 的 /api/admin 下，且已通过会话校验。
function createAppsRouter({ store, audit, config, secret }) {
  const router = express.Router();

  // 文件在且是本地分发 → 给管理页签名下载直链（15 分钟有效）。
  const signDownload = (r) =>
    r && r.fileAvailable && r.distribution === 'file' && r.status !== 'deleted'
      ? makeDownloadUrl(config, secret, r.releaseId)
      : null;

  // 每个 (平台, ABI) 轨的 latest：管理页按轨显示最新版本与下载入口。
  const buildLatestTracks = (app) => {
    const latestTracks = {};
    for (const platform of app.platforms || []) {
      const tracks = {};
      for (const abi of ABIS) {
        const rel = store.getLatest(app.appId, platform, abi);
        if (!rel) continue;
        tracks[abi] = {
          releaseId: rel.releaseId,
          version: rel.version,
          build: rel.build,
          forceUpdate: !!rel.forceUpdate,
          fileAvailable: !!rel.fileAvailable,
          distribution: rel.distribution,
          externalUrl: rel.externalUrl || null,
          download: signDownload(rel),
          publishedAt: rel.publishedAt,
        };
      }
      if (Object.keys(tracks).length) latestTracks[platform] = tracks;
    }
    return latestTracks;
  };

  router.get(
    '/apps',
    wrap((req, res) => {
      const items = store.listApplications().map((app) => ({
        ...appSummary(store, app),
        latestTracks: buildLatestTracks(app),
      }));
      ok(res, { items });
    })
  );

  router.post(
    '/apps',
    wrap(async (req, res) => {
      const body = req.body || {};
      const created = await store.mutate(() =>
        store.createApplication({
          appId: body.appId,
          name: body.name,
          description: body.description,
          platforms: body.platforms,
          enabled: body.enabled,
        })
      );
      await audit.log({
        actor: req.admin.username,
        ip: req.clientIp,
        action: 'app_create',
        target: created.appId,
        before: null,
        after: { name: created.name, platforms: created.platforms, enabled: created.enabled },
      });
      ok(res, appSummary(store, created), '应用已创建');
    })
  );

  router.get(
    '/apps/:appId',
    wrap((req, res) => {
      const app = store.getApplication(req.params.appId);
      const releases = store.listReleases(app.appId).map((r) => ({
        releaseId: r.releaseId,
        platform: r.platform,
        abi: r.abi || 'universal',
        version: r.version,
        build: r.build,
        status: r.status,
        forceUpdate: r.forceUpdate,
        fileAvailable: r.fileAvailable,
        distribution: r.distribution,
        externalUrl: r.externalUrl || null,
        download: signDownload(r),
        size: r.size,
        notes: r.notes,
        publishedAt: r.publishedAt,
        archivedAt: r.archivedAt,
        createdAt: r.createdAt,
      }));
      // 每个 (平台, ABI) 轨的 latest：管理页按轨显示最新版本与下载入口。
      const latestTracks = buildLatestTracks(app);
      ok(res, {
        app: appSummary(store, app),
        latest: store.latestSummary(app.appId),
        latestTracks,
        releases,
      });
    })
  );

  router.put(
    '/apps/:appId',
    wrap(async (req, res) => {
      const appId = req.params.appId;
      const body = req.body || {};
      const before = store.getApplication(appId);
      const snapshot = {
        name: before.name,
        description: before.description,
        platforms: [...before.platforms],
        enabled: before.enabled,
      };
      const updated = await store.mutate(() =>
        store.updateApplication(appId, {
          name: body.name,
          description: body.description,
          platforms: body.platforms,
          enabled: body.enabled,
        })
      );
      await audit.log({
        actor: req.admin.username,
        ip: req.clientIp,
        action: 'app_update',
        target: appId,
        before: snapshot,
        after: { name: updated.name, description: updated.description, platforms: updated.platforms, enabled: updated.enabled },
      });
      ok(res, appSummary(store, updated), '应用已更新');
    })
  );

  router.delete(
    '/apps/:appId',
    wrap(async (req, res) => {
      const appId = req.params.appId;
      const before = store.getApplication(appId);
      await store.mutate(() => store.deleteApplication(appId));
      await audit.log({
        actor: req.admin.username,
        ip: req.clientIp,
        action: 'app_delete',
        target: appId,
        before: { name: before.name, platforms: before.platforms },
        after: null,
      });
      ok(res, { appId }, '应用已删除');
    })
  );

  return router;
}

module.exports = { createAppsRouter };
