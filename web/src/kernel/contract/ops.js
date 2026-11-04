// 契约 op 清单（单一来源）：握手返回的 ops[]、壳侧对齐、契约测试都读这里。
// 形状只约束「必填字段 + 类型」，不做完整 JSON Schema（校验成本与宽度按调用方需要裁剪）。

export const HOST_OPS = Object.freeze([
  // 会话与文档
  'init', 'setMarkdown', 'getMarkdown', 'getSaveMarkdown', 'markClean',
  'setBaseDir', 'setTitle', 'setTheme', 'setZoom', 'getState', 'toggleSource', 'focus', 'focusAt',
  // 代码视图
  'setCode', 'setCodeLanguage', 'setCodeLineNumbers', 'codeInfo', 'hasLanguages',
  // 缩略图
  'setMinimapVisible', 'minimapInfo',
  // 命令
  'undo', 'redo', 'requestStats', 'formatCommand', 'tableCommand', 'insertTable',
  'insertMarkdown', 'insertImage',
  // 查找
  'openFindBar', 'closeFindBar', 'findNext', 'findPrev', 'findInfo',
  // 输出
  'exportStandaloneHTML', 'print', 'getContentSize',
  // 资源
  'getResourceRefs',
  // 诊断档
  'hasCommands', 'debugFocusTable', 'tableInfo', 'testImagePayload',
]);

export const NOTIFICATIONS = Object.freeze([
  'boot', 'ready', 'changed', 'stats', 'sourceMode', 'selinfo', 'jserror',
]);

export const KERNEL_REQUESTS = Object.freeze(['resolveResources', 'importImage']);

const REQUIRED = {
  init: [['markdown', 'string'], ['opts', 'object']],
  setMarkdown: [['md', 'string']],
  setBaseDir: [['path', 'string']],
  setTitle: [['title', 'string']],
  setTheme: [['theme', 'string']],
  setZoom: [['scale', 'number']],
  focusAt: [['x', 'number'], ['y', 'number']],
  setCode: [['text', 'string']],
  setCodeLanguage: [['id', 'string']],
  setCodeLineNumbers: [['visible', 'boolean']],
  setMinimapVisible: [['visible', 'boolean']],
  hasLanguages: [['ids', 'array']],
  formatCommand: [['name', 'string']],
  tableCommand: [['name', 'string']],
  insertTable: [['row', 'number'], ['col', 'number']],
  insertMarkdown: [['md', 'string']],
  insertImage: [['src', 'string']],
  hasCommands: [['names', 'array']],
};

/** 返回 null 表示合法；否则返回出错字段名 */
export function validatePayload(op, payload) {
  const rule = REQUIRED[op];
  if (!rule) return null;
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) return '<payload>';
  for (const [field, type] of rule) {
    const value = payload[field];
    if (type === 'array' ? !Array.isArray(value) : typeof value !== type) return field;
  }
  return null;
}

/** 通知 payload 的必填字段（仅 changed/stats/selinfo/sourceMode 有意义） */
const NOTIFICATION_REQUIRED = {
  changed: [['dirty', 'boolean']],
  stats: [['words', 'number'], ['chars', 'number']],
  sourceMode: [['value', 'boolean']],
  selinfo: [['inTable', 'boolean']],
  jserror: [['message', 'string']],
};

export function validateNotification(op, payload) {
  const rule = NOTIFICATION_REQUIRED[op];
  if (!rule) return null;
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) return '<payload>';
  for (const [field, type] of rule) {
    if (typeof payload[field] !== type) return field;
  }
  return null;
}
