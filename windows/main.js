// Campus Recreation Center — Windows desktop app.
// Opens the live booking system in its own window. Content updates come from the
// website, so the installed app stays current without reinstalling.
// © 2026 Services Squire LLC. All rights reserved.
'use strict';
const { app, BrowserWindow, Menu, shell, session } = require('electron');
const path = require('path');
const fs = require('fs');

const START = 'https://kss9393-om.github.io/rec-center-booking/';
const ORIGIN = new URL(START).origin;
const ALLOWED_PERMISSIONS = new Set(['media', 'notifications', 'clipboard-sanitized-write', 'fullscreen']);

app.setAppUserModelId('com.servicessquire.crc');

if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  let win = null;

  const stateFile = path.join(app.getPath('userData'), 'window.json');
  const loadState = () => { try { return JSON.parse(fs.readFileSync(stateFile, 'utf8')); } catch { return {}; } };
  const saveState = () => {
    if (!win) return;
    try { fs.writeFileSync(stateFile, JSON.stringify({ ...win.getNormalBounds(), maximized: win.isMaximized() })); } catch {}
  };

  const isInside = (url) => url.startsWith(START) || url.startsWith('file:');

  function showOffline() {
    if (win) win.loadFile(path.join(__dirname, 'offline.html'), { query: { u: START } });
  }

  function createWindow() {
    const s = loadState();
    win = new BrowserWindow({
      x: s.x, y: s.y, width: s.width || 1280, height: s.height || 840,
      minWidth: 380, minHeight: 560,
      title: 'مركز الترفيه الطلابي',
      icon: path.join(__dirname, 'build', 'icon.ico'),
      backgroundColor: '#ffffff',
      autoHideMenuBar: true,
      show: false,
      webPreferences: { contextIsolation: true, sandbox: true, nodeIntegration: false, spellcheck: false },
    });
    if (s.maximized) win.maximize();
    win.once('ready-to-show', () => win.show());
    win.on('close', saveState);
    win.on('closed', () => { win = null; });

    // Links to other sites open in the normal browser.
    win.webContents.setWindowOpenHandler(({ url }) => {
      if (url.startsWith(START)) return { action: 'allow' };
      if (/^https?:|^mailto:|^tel:/.test(url)) shell.openExternal(url);
      return { action: 'deny' };
    });
    win.webContents.on('will-navigate', (e, url) => {
      if (!isInside(url)) { e.preventDefault(); if (/^https?:/.test(url)) shell.openExternal(url); }
    });

    // No connection: show a page with a retry button.
    win.webContents.on('did-fail-load', (_e, code, _desc, _url, isMainFrame) => {
      if (isMainFrame && code !== -3) showOffline();
    });

    win.loadURL(START);
  }

  app.on('second-instance', () => {
    if (!win) return;
    if (win.isMinimized()) win.restore();
    win.focus();
  });

  app.whenReady().then(() => {
    // Camera (ticket scanning) and notifications only for the booking site.
    session.defaultSession.setPermissionRequestHandler((_wc, permission, cb, details) => {
      cb(ALLOWED_PERMISSIONS.has(permission) && String(details.requestingUrl || '').startsWith(ORIGIN));
    });
    session.defaultSession.setPermissionCheckHandler((_wc, permission, origin) =>
      ALLOWED_PERMISSIONS.has(permission) && String(origin || '').startsWith(ORIGIN));

    // PDF / Excel exports: ask where to save, starting in Downloads.
    session.defaultSession.on('will-download', (_e, item) => {
      item.setSaveDialogOptions({ defaultPath: path.join(app.getPath('downloads'), item.getFilename()) });
    });

    const reload = () => { if (win) win.webContents.getURL().startsWith('file:') ? win.loadURL(START) : win.webContents.reload(); };
    Menu.setApplicationMenu(Menu.buildFromTemplate([
      {
        label: 'عرض · View',
        submenu: [
          { label: 'إعادة التحميل · Reload', accelerator: 'F5', click: reload },
          { label: 'إعادة التحميل · Reload', accelerator: 'CmdOrCtrl+R', click: reload, visible: false },
          { label: 'الصفحة الرئيسية · Home', accelerator: 'Alt+Home', click: () => win && win.loadURL(START) },
          { type: 'separator' },
          { role: 'zoomIn', label: 'تكبير · Zoom in', accelerator: 'CmdOrCtrl+=' },
          { role: 'zoomOut', label: 'تصغير · Zoom out' },
          { role: 'resetZoom', label: 'الحجم الأصلي · Actual size' },
          { type: 'separator' },
          { role: 'togglefullscreen', label: 'ملء الشاشة · Full screen', accelerator: 'F11' },
        ],
      },
      {
        label: 'تحرير · Edit',
        submenu: [
          { role: 'undo', label: 'تراجع · Undo' }, { role: 'redo', label: 'إعادة · Redo' }, { type: 'separator' },
          { role: 'cut', label: 'قص · Cut' }, { role: 'copy', label: 'نسخ · Copy' },
          { role: 'paste', label: 'لصق · Paste' }, { role: 'selectAll', label: 'تحديد الكل · Select all' },
        ],
      },
      {
        label: 'حول · About',
        submenu: [
          { label: `الإصدار ${app.getVersion()} · Version ${app.getVersion()}`, enabled: false },
          { label: '© 2026 Services Squire LLC', enabled: false },
          { label: 'فتح في المتصفح · Open in browser', click: () => shell.openExternal(START) },
        ],
      },
    ]));

    createWindow();
  });

  app.on('window-all-closed', () => app.quit());
}
