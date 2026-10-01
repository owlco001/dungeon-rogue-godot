#!/usr/bin/env python3
"""把 Godot Web 导出打包成单文件 HTML（双击可玩，file:// 下也能跑）.

原理（沿用已验证的 verify-single.html 方案）:
- index.js 内联（已确认不含 </script>）
- index.wasm / index.pck base64 内联
- window.fetch 钩子拦截 inline://game.wasm / inline://game.pck，从内存返回 Response
- GODOT_CONFIG 里 executable -> inline://game，mainPack -> inline://game.pck
"""
import base64
import json
import re
import sys
from pathlib import Path

WEB_DIR = Path(__file__).resolve().parent.parent / "web"


def main() -> None:
    html = (WEB_DIR / "index.html").read_text(encoding="utf-8")
    js = (WEB_DIR / "index.js").read_text(encoding="utf-8")
    assert "</script" not in js.lower(), "index.js 含有 </script>，不能直接内联"

    wasm_b64 = base64.b64encode((WEB_DIR / "index.wasm").read_bytes()).decode("ascii")
    pck_b64 = base64.b64encode((WEB_DIR / "index.pck").read_bytes()).decode("ascii")

    # 1. 内联 index.js
    html = html.replace('<script src="index.js"></script>',
                        "<script>\n" + js + "\n</script>", 1)

    # 2. 改 GODOT_CONFIG（用 json 解析改键，避免字符串拼错）
    m = re.search(r"const GODOT_CONFIG = (\{.*?\});", html, re.S)
    assert m, "找不到 GODOT_CONFIG"
    cfg = json.loads(m.group(1))
    wasm_size = (WEB_DIR / "index.wasm").stat().st_size
    pck_size = (WEB_DIR / "index.pck").stat().st_size
    cfg["executable"] = "inline://game"
    cfg["mainPack"] = "inline://game.pck"
    cfg["fileSizes"] = {"inline://game.pck": pck_size, "inline://game.wasm": wasm_size}
    new_cfg = "const GODOT_CONFIG = " + json.dumps(cfg, separators=(",", ":")) + ";"
    html = html.replace(m.group(0), new_cfg, 1)

    # 3. 标题
    title = sys.argv[2] if len(sys.argv) > 2 else "地牢肉鸽 v0.1"
    html = html.replace("<title>Dungeon Rogue Godot Demo</title>",
                        "<title>%s</title>" % title, 1)

    # 4. 在 config 脚本内、GODOT_CONFIG 之前插入 base64 + fetch 钩子
    #    注意：这里已经在 <script> 元素内部，只插 JS 语句，不要再包 <script> 标签
    hook = """const WASM_B64 = "%s";
const PCK_B64 = "%s";
let _wasmBytes = null, _pckBytes = null;
function _b64ToBytes(b64) {
    const bin = atob(b64);
    const len = bin.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) bytes[i] = bin.charCodeAt(i);
    return bytes;
}
const _realFetch = window.fetch.bind(window);
window.fetch = function (url, opts) {
    if (typeof url === 'string') {
        if (url === 'inline://game.wasm') {
            if (!_wasmBytes) { _wasmBytes = _b64ToBytes(WASM_B64); }
            return Promise.resolve(new Response(_wasmBytes, { headers: { 'Content-Type': 'application/wasm' } }));
        }
        if (url === 'inline://game.pck') {
            if (!_pckBytes) { _pckBytes = _b64ToBytes(PCK_B64); }
            return Promise.resolve(new Response(_pckBytes));
        }
    }
    return _realFetch(url, opts);
};
""" % (wasm_b64, pck_b64)
    # 插在第二个 <script>（config 脚本）之前：即内联 js 的 </script> 之后
    marker = new_cfg
    html = html.replace(marker, hook + marker, 1)

    out_name = sys.argv[1] if len(sys.argv) > 1 else "dungeon-rogue-v01-single.html"
    out = WEB_DIR / out_name
    out.write_text(html, encoding="utf-8")
    print(f"built {out} ({out.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()


if __name__ == "__main__":
    sys.exit(main())
