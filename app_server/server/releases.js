'use strict';

const fs = require('fs');
const path = require('path');
const express = require('express');

const { ApiError, ok, wrap } = require('./apiutil');
const { validateReleaseMeta, PLATFORMS, nowIso } = require('./store');
const { enforceKeepPrevious } = require('./cleanup');
const { makeDownloadUrl } = require('./update_api');

function releaseView(config, secret, release) {
  const view = {
    releaseId: release.releaseId,
    appId: release.appId,
    platform: release.platform,
    version: release.version,
    build: release.build,
    filename: release.filename,
    size: release.size,
    sha256: release.sha256,
    distribution: release.distribution,
    externalUrl: release.externalUrl || null,
    fileAvailable: Boolean(release.fileAvailable),
    fileDeletedAt: release.fileDeletedAt || null,
    notes: release.notes || '',
    forceUpdate: Boolean(release.forceUpdate),
    status: release.status,
    publishedAt: release.publishedAt,
    archivedAt: release.archivedAt,
    createdAt: release.createdAt,
    downloadCount: Number(release.downloadCount || 0),
    lastDownloadAt: release.lastDownloadAt,
    uploadedBy: release.uploadedBy,
  };
  if (release.distribution === 'file' && release.fileAvailable) {
    view.download = makeDownloadUrl(config, secret, release.releaseId);
  }
  return view;
}

function assertExternalUrl(raw) {
  const text = String(raw || '').trim();
  if (!text || text.length > 500) throw new ApiError(200, 400005, 'externalUrl 必须为合法链接（≤500 字）');
  let url;
  try {
    url = new URL(text);
  } catch (_) {
    throw new ApiError(200, 400005, 'externalUrl 不是合法链接');
  }
  if (!['http:', 'https:'].includes(url.protocol)) throw new ApiError(200, 400005, 'externalUrl 必须是 http/https 链接');
  return text;
}

function createReleasesRouter({ config, store, audit, secret }) {
  const router = express.Router();

  router.get(
    '/apps/:appId/releases',
    wrap((req, res) => {
      const app = store.getApplication(req.params.appId);
      const platform = req.query.platform ? String(req.query.platform).trim().toLowerCase() : '';
      if (platform && !PLATFORMS.includes(platform)) throw new ApiError(200, 300005, `不支持的平台：${platform}`);
      const items = store.listReleases(app.appId, platform).map((r) => releaseView(config, secret, r));
      ok(res, { appId: app.appId, platform: platform || null, items });
    })
  );

  // 仅 iOS 外部链接版本：JSON 录入，不接收安装包（300009）。
  router.post(
    '/releases',
    wrap(async (req, res) => {
      const body = req.body || {};
      const appId = String(body.appId || '').trim();
      const platform = String(body.platform || '').trim().toLowerCase();
      const app = store.getApplication(appId);
      const allowed = store.assertPlatformAllowed(app, platform);
      if (allowed !== 'ios') {
        throw new ApiError(200, 300009, '只有 iOS 支持外部链接版本；其它平台请使用分片上传');
      }
      if (body.distribution !== 'external') throw new ApiError(200, 400005, 'iOS 版本必须为 distribution=external');
      const externalUrl = assertExternalUrl(body.externalUrl);
      const meta = validateReleaseMeta({
        version: body.version,
        build: body.build,
        pubspecBuildConfirmed: body.pubspecBuildConfirmed,
      });
      if (store.findReleaseByBuild(appId, allowed, meta.build)) {
        throw new ApiError(200, 300002, `该平台已存在 build=${meta.build} 的版本`);
      }
      const wantedPublished = body.status === 'published';

      const created = await store.mutate(() => {
        const release = store.createReleaseRecord({
          appId,
          platform: allowed,
          version: meta.version,
          build: meta.build,
          pubspecBuildConfirmed: true,
          filename: '',
          storedPath: '',
          size: 0,
          sha256: '',
          distribution: 'external',
          externalUrl,
          fileAvailable: false,
          notes: body.notes,
          uploadedBy: req.admin.username,
          forceUpdate: false,
        });
        if (wantedPublished) store.publishRelease(release.releaseId, { forceUpdate: false });
        return release;
      });

      await audit.log({
        actor: req.admin.username,
        ip: req.clientIp,
        action: 'release_create',
        target: created.releaseId,
        before: null,
        after: {
          appId,
          platform: allowed,
          version: created.version,
          build: created.build,
          distribution: 'external',
          externalUrl,
          published: wantedPublished,
        },
      });
      ok(res, releaseView(config, secret, created), wantedPublished ? 'iOS 外部链接版本已创建并发布' : 'iOS 外部链接版本已创建（草稿）');
    })
  );

  router.get(
    '/releases/:id',
    wrap((req, res) => {
      ok(res, releaseView(config, secret, store.getRelease(req.params.id)));
    })
  );

  // 改 notes / 强更开关；只有当前 latest 允许开启强更（300007）。
  router.put(
    '/releases/:id',
    wrap(async (req, res) => {
      const release = store.getRelease(req.params.id);
      const body = req.body || {};
      const before = { notes: release.notes, forceUpdate: release.forceUpdate, status: release.status };
      let after = null;

      await store.mutate(() => {
        if (body.notes !== undefined) {
          const notes = typeof body.notes === 'string' ? body.notes.trim() : '';
          if (notes.length > 2000) throw new ApiError(200, 400005, 'notes 长度不能超过 2000 字');
          release.notes = notes;
        }
        if (body.forceUpdate !== undefined) {
          const wanted = Boolean(body.forceUpdate);
          if (wanted) {
            if (release.platform === 'ios') {
              throw new ApiError(200, 400005, 'iOS 版本不支持强制更新（无法自更新）');
            }
            if (store.getLatestId(release.appId, release.platform) !== release.releaseId) {
              throw new ApiError(200, 300007, '只有当前 latest 版本允许开启强制更新，请先发布/回滚');
            }
          }
          release.forceUpdate = release.platform === 'ios' ? false : wanted;
        }
        after = { notes: release.notes, forceUpdate: release.forceUpdate, status: release.status };
      });

      await audit.log({
        actor: req.admin.username,
        ip: req.clientIp,
        action: 'release_update',
        target: release.releaseId,
        before,
        after,
      });
      ok(res, releaseView(config, secret, release), '版本已更新');
    })
  );

  router.post(
    '/releases/:id/publish',
    wrap(async (req, res) => {
      const body = req.body || {};
      const release = await store.mutate(() => {
        const item = store.getRelease(req.params.id);
        if (item.distribution === 'file' && !item.fileAvailable) {
          throw new ApiError(410, 300008, '该版本安装包已被清理，无法发布，请重新上传');
        }
        const forceUpdate = body.forceUpdate === undefined ? undefined : Boolean(body.forceUpdate);
        if (forceUpdate === true && item.platform === 'ios') {
          throw new ApiError(200, 400005, 'iOS 版本不支持强制更新（无法自更新）');
        }
        return store.publishRelease(item.releaseId, { forceUpdate });
      });

      await enforceKeepPrevious({
        config,
        store,
        audit,
        appId: release.appId,
        platform: release.platform,
        actor: req.admin.username,
        ip: req.clientIp,
      });

      await audit.log({
        actor: req.admin.username,
        ip: req.clientIp,
        action: 'release_publish',
        target: release.releaseId,
        before: null,
        after: {
          appId: release.appId,
          platform: release.platform,
          version: release.version,
          build: release.build,
          forceUpdate: release.forceUpdate,
        },
      });
      ok(
        res,
        {
          releaseId: release.releaseId,
          appId: release.appId,
          platform: release.platform,
          version: release.version,
          build: release.build,
          forceUpdate: release.forceUpdate,
          publishedAt: release.publishedAt,
          isLatest: true,
        },
        '已发布'
      );
    })
  );

  router.post(
    '/releases/:id/rollback',
    wrap(async (req, res) => {
      const release = store.getRelease(req.params.id);
      if (release.distribution === 'file' && !release.fileAvailable) {
        throw new ApiError(410, 300008, '该版本安装包已被清理，无法回滚，请重新上传');
      }
      if (store.getLatestId(release.appId, release.platform) === release.releaseId) {
        throw new ApiError(200, 400005, '该版本已是当前 latest，无需回滚');
      }
      const published = await store.mutate(() => store.publishRelease(release.releaseId, { forceUpdate: false, rollback: true }));

      await enforceKeepPrevious({
        config,
        store,
        audit,
        appId: published.appId,
        platform: published.platform,
        actor: req.admin.username,
        ip: req.clientIp,
      });

      await audit.log({
        actor: req.admin.username,
        ip: req.clientIp,
        action: 'release_rollback',
        target: published.releaseId,
        before: null,
        after: {
          appId: published.appId,
          platform: published.platform,
          version: published.version,
          build: published.build,
        },
      });
      ok(res, releaseView(config, secret, published), '已回滚为最新版本');
    })
  );

  router.delete(
    '/releases/:id',
    wrap(async (req, res) => {
      const release = store.getRelease(req.params.id);
      if (release.status === 'published' || store.getLatestId(release.appId, release.platform) === release.releaseId) {
        throw new ApiError(200, 400005, '已发布/latest 版本不物理删除，请使用停用或回滚');
      }
      if (release.status !== 'draft') throw new ApiError(200, 400005, '仅 draft 状态版本可删除');
      const abs = release.storedPath ? path.resolve(config.storageRoot, release.storedPath) : '';
      if (abs && abs.startsWith(path.resolve(config.storageRoot) + path.sep)) {
        try {
          fs.unlinkSync(abs);
        } catch (_) {
          /* ignore */
        }
      }
      await store.mutate(() => {
        delete store.data.releases[release.releaseId];
      });
      await audit.log({
        actor: req.admin.username,
        ip: req.clientIp,
        action: 'release_delete',
        target: release.releaseId,
        before: { appId: release.appId, platform: release.platform, version: release.version, build: release.build },
        after: null,
      });
      ok(res, { releaseId: release.releaseId }, '草稿版本已删除');
    })
  );

  return router;
}

module.exports = { createReleasesRouter, releaseView };
