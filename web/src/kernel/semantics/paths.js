// PathPolicy 的文本侧：URL 组装/解码/规范化。纯函数、不抛错、不碰文件系统。
// 编码口径与 Swift `URL.absoluteString`（现行行为）逐字节对齐：
// 路径段允许 pchar（unreserved + sub-delims + ':' + '@'），只编码空格、非 ASCII 与控制字符。

const PATH_HARDENED = /%(21|24|26|27|28|29|2A|2B|2C|3A|3B|3D|40)/gi;

function encodeSegment(segment) {
  return encodeURIComponent(segment).replace(PATH_HARDENED, (match) =>
    String.fromCharCode(parseInt(match.slice(1), 16)));
}

/** 绝对文件系统路径 → file:// URL（与 Swift URL.absoluteString 同口径） */
export function fileUrlFromPath(absPath) {
  if (typeof absPath !== 'string' || absPath.length === 0) return null;
  return `file://${absPath.split('/').map(encodeSegment).join('/')}`;
}

/** file:// 之后的部分 → 路径：手工分段解码（不用整体解码，见 Util.swift 注释的 %2520 陷阱） */
export function percentDecodedPath(afterScheme) {
  return String(afterScheme)
    .split('/')
    .map((segment) => {
      try {
        return decodeURIComponent(segment);
      } catch {
        return segment;
      }
    })
    .join('/');
}

/** file:// URL → 文件系统路径；非 file:// 返回 null（调用方保持原文） */
export function urlToPath(url) {
  if (typeof url !== 'string' || !url.startsWith('file://')) return null;
  return percentDecodedPath(url.slice('file://'.length));
}

/**
 * 规范化：折叠重复分隔符、消解 . 与 ..、去尾斜杠。
 * 不做符号链接解析（Swift 用 standardizedFilePath，同样不解析软链）。
 */
export function normalizePath(path, { style = 'posix' } = {}) {
  if (typeof path !== 'string' || path.length === 0) return '';
  if (style === 'win32') {
    const drive = /^[a-zA-Z]:/.exec(path);
    const prefix = drive ? drive[0] : '';
    const rest = prefix ? path.slice(prefix.length) : path;
    const parts = rest.replaceAll('/', '\\').split('\\');
    const out = [];
    for (const part of parts) {
      if (part === '' || part === '.') continue;
      if (part === '..') {
        if (out.length > 0) out.pop();
        continue;
      }
      out.push(part);
    }
    return `${prefix}\\${out.join('\\')}`;
  }
  const absolute = path.startsWith('/');
  const out = [];
  for (const part of path.split('/')) {
    if (part === '' || part === '.') continue;
    if (part === '..') {
      if (out.length > 0) out.pop();
      continue;
    }
    out.push(part);
  }
  const joined = out.join('/');
  return absolute ? `/${joined}` : joined;
}

/** 文档目录 + 相对引用 → 绝对路径（已规范化）。绝对引用原样返回。 */
export function joinBase(baseDir, ref, { style = 'posix' } = {}) {
  if (typeof ref !== 'string' || ref.length === 0) return '';
  if (style === 'win32') {
    if (/^[a-zA-Z]:/.test(ref) || ref.startsWith('\\\\')) return normalizePath(ref, { style });
    return normalizePath(`${baseDir}\\${ref}`, { style });
  }
  if (ref.startsWith('/')) return normalizePath(ref, { style });
  return normalizePath(`${baseDir}/${ref}`, { style });
}
