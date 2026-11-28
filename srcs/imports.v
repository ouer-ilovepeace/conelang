module main

import os

// dir_of: 取源文件所在目录（返回时带尾部分隔符），无目录则返回空串。
// 同时认 / 与 \ 两种分隔。
fn dir_of(path string) string {
	mut last := -1
	mut i := 0
	for i < path.len {
		if path[i] == 47 || path[i] == 92 { // / 或 \
			last = i
		}
		i = i + 1
	}
	if last < 0 {
		return ''
	}
	return path[..last + 1]
}

// ImportExpander: 阶段 2 —— 源码级导入展开
//
//   import os        -> 读取 os.cone、单独 lex、递归展开，把 token 序列【就地替换】。
//                       token 各自保留 file/line/col，报错仍能定位到库文件。
//                       cone 0.6 fix2：「调用必须在声明之后」不再比较源码行号，
//                       而是比较声明 / 调用 token 在【展开后流】里的绝对位置，
//                       因此库内行号（如 os.cone 的 31 行）不会跟主文件行号混比。
//   cone 0.8prelease：import xxx.dll 已移除（改写成 include xxx.lib），
//                      带点号的 import 一律报错，不再放行给 parser。
struct ImportExpander {
	base_dir string // 主 .cone 源码所在目录（兜底查找）
	std_dir  string // cone 0.8preview：cone.exe 目录\std（优先查找）
mut:
	seen      map[string]bool
	x64_mode  bool   // cone 0.9.f：库文件也要用同一套标识符规则
}

fn (mut e ImportExpander) expand(toks []Token) ![]Token {
	mut out := []Token{}
	mut i := 0
	for i < toks.len {
		t := toks[i]

		if t.kind == TokenKind.kw_import && i + 1 < toks.len {
			if toks[i + 1].kind == TokenKind.ident {
				// cone 0.8prelease：带点号的 import（旧 import xxx.dll）不再支持。
				if i + 2 < toks.len && toks[i + 2].kind == TokenKind.dot {
					return error('第 ${t.line} 行: import 现在只支持 `import 名字`（导入 std/名字.cone 或源码目录/名字.cone）；`import 名字.dll` 已移除，链接 .lib 请写 `include 名字.lib`')
				}

				// cone 库形式：kw_import IDENT —— 就地展开
				name := toks[i + 1].lit
				local_path := e.base_dir + name + '.cone'
				std_path := os.join_path(e.std_dir, name + '.cone')
				// cone 0.8preview：import os 优先读 cone.exe 目录\\std\\os.cone，
				// 没有再退回 .cone 源码同目录，都没有才报错。
				mut path := local_path
				if os.exists(std_path) {
					path = std_path
				}
				mut already := false
				if path in e.seen {
					already = true
				}
				if already {
					i = i + 2
					continue
				}
				e.seen[path] = true
				content := os.read_file(path) or {
					return error('cone 库 ${name} 未找到（已尝试 ${std_path} 与 ${local_path}；import ${name} 会把它展开到当前文件后再编译）')
				}
				lib_toks := lex(content, path, e.x64_mode) or {
					return error('[库 ${name} 词法] ' + err.msg())
				}
				inner := e.expand(lib_toks) or { return error(err.msg()) }
				// 剥掉库文件自带的 eof，主文件的 eof 留在末尾
				mut j := 0
				for j < inner.len {
					if inner[j].kind != TokenKind.eof {
						out << inner[j]
					}
					j = j + 1
				}
				i = i + 2
				continue
			}
		}

		out << t
		i = i + 1
	}
	return out
}

fn expand_imports(toks []Token, src_path string, cone_dir string, x64_mode bool) ![]Token {
	mut e := ImportExpander{
		base_dir:  dir_of(src_path)
		std_dir:   os.join_path(cone_dir, 'std')
		seen:      map[string]bool{}
		x64_mode:  x64_mode
	}
	result := e.expand(toks) or { return error(err.msg()) }
	return result
}
