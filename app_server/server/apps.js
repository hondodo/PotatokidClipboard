'use strict';

const express = require('express');
const { ok, wrap } = require('./apiutil');

function appSummary(store, app) {
  return {
    ...app,
    releaseCount: store.listReleases(app.appId).length,
    latest: store.latestSummary(app.appId),
  };
}

// 应用 CRUD：仅挂在管理端口 47293 的 /api/admin 下，且已通过会话校验。
function createAppsRouter({ store, audit }) {
  const router = express.Router();

  router.get(
    '/apps',
    wrap((req, res) => {
      const items = store.listApplications().map((app) => appSummary(store, app));
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
        version: r.version,
        build: r.build,
        status: r.status,
        forceUpdate: r.forceUpdate,
        fileAvailable: r.fileAvailable,
        distribution: r.distribution,
        size: r.size,
        notes: r.notes,
        publishedAt: r.publishedAt,
        archivedAt: r.archivedAt,
        createdAt: r.createdAt,
      }));
      ok(res, {
        app: appSummary(store, app),
        latest: store.latestSummary(app.appId),
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
