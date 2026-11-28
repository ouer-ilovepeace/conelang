module main

import os

// cone 0.8prelease：命令行与工具链驱动。
//
//   -m              生成 .asm 后编译（读 cone.exe 同目录的 compile 脚本，不存在则创建默认）
//   -l              链接 .obj（读 link 脚本，不存在则创建默认）
//   -lw             忽略 link 脚本，直接 link.exe /subsystem:windows <obj...>
//   -lc             忽略 link 脚本，直接 link.exe /subsystem:console <obj...>
//   -ml             等同 -m -l
//   -s              include / includelib 用短名，不带 cone 安装目录全路径
//   -v              输出版本信息
//   -addm[内容]     在【编译命令】与【被编译的 .asm 文件】之间插入附加参数
//   -addl[内容]     在【链接命令】与【被链接的 .obj 文件】之间插入附加参数
//
// 源码里的 `__compile__ "..."` / `__link__ "..."` 与 -addm / -addl 等价，
// 参数文本（不含引号）由 main() 汇入 opts.addm / opts.addl。
//
// 多文件：cone [参数] a.cone b.cone c.cone -> a.asm b.asm c.asm，
//         -m / -l 时把所有 .asm / .obj 一次性传给同一条编译 / 链接命令。
//
// compile / link 脚本默认内容【不含 %1】：cone 运行时把当前生成的 .asm / .obj
// 追加在命令末尾。仍兼容用户手写 `%1.asm` / `%1.obj`（%1 = 全部输入文件）。

const cone_version = '0.9.p'

struct CliOpts {
mut:
	compile       bool
	link          bool
	link_windows  bool
	link_console  bool
	short_include bool
	show_version  bool
	src_paths     []string
	out_paths     []string
	addm          string // 汇合后的附加编译参数（-addm + 源码 __compile__）
	addl          string // 汇合后的附加链接参数（-addl + 源码 __link__）
	no_default_seh bool  // cone 0.84：-noseh 不挂默认全局 try-except
	o1            bool  // cone 0.9.4：实验性 -O1 优化（默认关闭）
	o1_opts      string // cone 0.9.6：-O1:子开关（逗号分隔，默认空 = A 组）
	llvm_arch    string // cone 0.9.f：'' / 'x64'（x86 已取消）
	llvm_opt     string // cone 0.9.f：'0'/'1'/'2'/'3'/'s'/'z' -> llc -O<级别>
	llvm_opt_set bool   // cone 0.9.f：用户显式写过 -O0/2/3/s/z
	llvm_ir_only bool   // cone 0.9.f：-s -> 只生成 .ll
	defsyms      []string // cone 0.9.f：-D[NAME] 编译期符号
	out_name     string   // cone 0.9.f：-out[NAME] 多文件联合链接的 exe 名
	cone_dir      string
}

fn cone_dir_of() string {
	return os.dir(os.executable())
}

fn print_version() {
	println('cone ${cone_version}')
	println('Cone compiler for MASM32 (Windows x86) + LLVM (Windows x64)')
	println('Usage: cone [-m] [-l] [-lw] [-lc] [-ml] [-s] [-v] [-noseh] [-O0|-O1[:子开关]|-O2|-O3|-Os|-Oz] [-D[NAME]] [-out[NAME]] [-llvm[:x64]] [-addm[...]] [-addl[...]] <a.cone> [b.cone ...]')
}

// ---------- 字符串小工具（手写，避免依赖各版本 string API 差异） ----------

fn has_prefix(s string, p string) bool {
	if s.len < p.len {
		return false
	}
	mut i := 0
	for i < p.len {
		if s[i] != p[i] {
			return false
		}
		i = i + 1
	}
	return true
}

fn ends_with_cone(s string) bool {
	if s.len < 5 {
		return false
	}
	return eq_ci(s[s.len - 5..], '.cone')
}

fn bracket_content(a string) string {
	// '-addm[' / '-addl[' 都是 6 字节；去掉这 6 字节与末尾的 ']'
	if a.len < 7 {
		return ''
	}
	return trim_ws(a[6..a.len - 1])
}

fn append_arg(cur string, add string) string {
	a := trim_ws(add)
	if a.len == 0 {
		return cur
	}
	if cur.len == 0 {
		return a
	}
	return cur + ' ' + a
}

fn default_out_path(src string) string {
	return stem_of(src) + '.asm'
}

// cone 0.9.f：-llvm:x64 输出 .ll，默认 MASM32 路径输出 .asm（一字不改）
fn out_path_for(o CliOpts, src string) string {
	if o.llvm_arch.len > 0 { return stem_of(src) + '.ll' }
	return default_out_path(src)
}

fn parse_cli(args []string) !CliOpts {
	mut o := CliOpts{
		cone_dir: cone_dir_of()
		llvm_opt: '0'
	}
	mut pos := []string{}
	mut i := 1
	for i < args.len {
		a := args[i]
		if a == '-v' {
			o.show_version = true
		} else if a == '-m' {
			o.compile = true
		} else if a == '-l' {
			o.link = true
		} else if a == '-ml' {
			o.compile = true
			o.link = true
		} else if a == '-lw' {
			o.link = true
			o.link_windows = true
		} else if a == '-lc' {
			o.link = true
			o.link_console = true
		} else if a == '-s' {
			o.short_include = true
		} else if a == '-noseh' {
			o.no_default_seh = true
		} else if a == '-O1' {
			o.o1 = true
		} else if has_prefix(a, '-O1:') {
			o.o1 = true
			sub := trim_ws(a[4..])
			if sub.len > 0 {
				if o.o1_opts.len > 0 { o.o1_opts += ',' }
				o.o1_opts += sub
			}
		} else if a == '-O0' || a == '-O2' || a == '-O3' || a == '-Os' || a == '-Oz' {
			o.llvm_opt = a[2..]
			o.llvm_opt_set = true
		} else if has_prefix(a, '-D[') || a == '-D' {
			mut nm := ''
			if a == '-D' {
				if i + 1 >= args.len {
					return error('-D 后面缺少符号名')
				}
				i++
				nm = trim_ws(args[i])
			} else {
				if a[a.len - 1] != 93 {
					return error('-D[NAME] 缺少右括号 ]')
				}
				nm = trim_ws(a[3..a.len - 1])
			}
			if nm.len == 0 {
				return error('-D[ ] 内容为空')
			}
			o.defsyms << nm
		} else if has_prefix(a, '-out[') || a == '-out' {
			mut nm := ''
			if a == '-out' {
				if i + 1 >= args.len {
					return error('-out 后面缺少输出名')
				}
				i++
				nm = trim_ws(args[i])
			} else {
				if a[a.len - 1] != 93 {
					return error('-out[NAME] 缺少右括号 ]')
				}
				nm = trim_ws(a[5..a.len - 1])
			}
			if nm.len == 0 {
				return error('-out[ ] 内容为空')
			}
			o.out_name = nm
		} else if has_prefix(a, '-llvm') {
			// x64 只出 -llvm:x64；x86 走默认 MASM32 后端
			if a == '-llvm' {
				o.llvm_arch = 'x64'
			} else if has_prefix(a, '-llvm:') {
				sub := trim_ws(a[6..])
				if sub == 'x86' {
					return error('x86 请不带 -llvm 直接编译（默认 MASM32 后端）；-llvm 只出 x64')
				}
				if sub != 'x64' {
					return error('-llvm 只支持 x64：收到 -llvm:${sub}')
				}
				o.llvm_arch = 'x64'
			} else {
				return error('无法识别的选项 ${a}；可用 -llvm:x64 / -O0..-O3 / -Os / -Oz / -D[NAME] / -out[NAME] / -addl[...] / -addm[...] / -s / -O1 / -v')
			}
		} else if has_prefix(a, '-addm[') || has_prefix(a, '-addl[') {
			key := a[..5]
			mut buf := a[6..]
			if buf.len > 0 && buf[buf.len - 1] == 93 {
				buf = buf[..buf.len - 1]
			} else {
				for {
					i = i + 1
					if i >= args.len {
						return error('${key}[ 缺少右括号 ]；例：${key}[/libpath:Z:\\masm64\\lib64 user32.lib]')
					}
					nxt := args[i]
					if nxt.len > 0 && nxt[nxt.len - 1] == 93 {
						buf += ' ' + nxt[..nxt.len - 1]
						break
					}
					buf += ' ' + nxt
				}
			}
			content := trim_ws(buf)
			if content.len == 0 {
				return error('${key}[ ] 内容为空；例：${key}[/libpath:Z:\\masm64\\lib64]')
			}
			if key == '-addm' {
				o.addm = append_arg(o.addm, content)
			} else {
				o.addl = append_arg(o.addl, content)
			}
		} else if a == '-addm' || a == '-addl' {
			if i + 1 >= args.len {
				return error('${a} 后面缺少内容；写法：${a}[内容] 或 ${a} "内容"')
			}
			i = i + 1
			if a == '-addm' {
				o.addm = append_arg(o.addm, trim_ws(args[i]))
			} else {
				o.addl = append_arg(o.addl, trim_ws(args[i]))
			}
		} else if a.len > 0 && a[0] == 45 {
			return error('无法识别的选项 ${a}；可用 -llvm:x64 / -O0..-O3 / -Os / -Oz / -D[NAME] / -out[NAME] / -addl[...] / -addm[...] / -s / -O1 / -v')
		} else {
			pos << a
		}
		i = i + 1
	}
	if o.link_windows && o.link_console {
		return error('-lw and -lc cannot be used together')
	}
	if o.llvm_arch.len > 0 {
		if o.compile || o.link || o.link_windows || o.link_console {
			return error('-llvm 与 -m/-l/-ml/-lw/-lc 互斥（-llvm 自己驱动 llc + lld-link）')
		}
		o.llvm_ir_only = o.short_include       // -s -> 只出 .ll
		if o.o1 && !o.llvm_opt_set { o.llvm_opt = '1' } // -O1 -> llc -O1（未被 -O2 等覆盖时）
		o.o1 = false                           // MASM -O1 pass 不进入
		o.o1_opts = ''
	}
	if o.show_version {
		return o
	}
	if pos.len < 1 {
		return error('没有输入文件：cone [-m] [-l] [-lw] [-lc] [-ml] [-s] [-v] [-noseh] [-O0..-O3] [-D[NAME]] [-out[NAME]] [-llvm[:x64]] [-addm[...]] [-addl[...]] <a.cone> [b.cone ...]')
	}
	// cone 0.8prelease：多文件编译。
	//   1 个位置参数                     -> 单文件，输出 <stem>.asm
	//   2 个且第二个不是 .cone          -> 单文件 + 显式输出名（向后兼容）
	//   其余（2 个都是 .cone / 3 个以上）-> 全部按 .cone 源文件处理
	if pos.len == 1 {
		o.src_paths << pos[0]
		o.out_paths << out_path_for(o, pos[0])
	} else if pos.len == 2 && !ends_with_cone(pos[1]) {
		o.src_paths << pos[0]
		o.out_paths << pos[1]
	} else {
		for p in pos {
			if !ends_with_cone(p) {
				return error('Multiple sources require all positional arguments to be .cone files; got ${p}')
			}
			o.src_paths << p
			o.out_paths << out_path_for(o, p)
		}
	}
	return o
}

// ---------- 路径 / 文本小工具 ----------

fn trim_ws(s string) string {
	mut a := 0
	mut b := s.len
	for a < b && (s[a] == 32 || s[a] == 9 || s[a] == 13 || s[a] == 10) {
		a = a + 1
	}
	for b > a && (s[b - 1] == 32 || s[b - 1] == 9 || s[b - 1] == 13 || s[b - 1] == 10) {
		b = b - 1
	}
	return s[a..b]
}

fn split_lines(s string) []string {
	mut res := []string{}
	mut start := 0
	mut i := 0
	for i < s.len {
		c := s[i]
		if c == 10 || c == 13 {
			if i > start {
				res << s[start..i]
			}
			start = i + 1
			if c == 13 && i + 1 < s.len && s[i + 1] == 10 {
				i = i + 1
				start = i + 1
			}
		}
		i = i + 1
	}
	if start < s.len {
		res << s[start..]
	}
	return res
}

// stem_of: 去掉最后一段路径里的扩展名（foo.asm -> foo），没有扩展名则原样返回。
fn stem_of(path string) string {
	mut dot := -1
	mut i := path.len - 1
	for i >= 0 {
		c := path[i]
		if c == 47 || c == 92 {
			break
		}
		if c == 46 {
			dot = i
			break
		}
		i = i - 1
	}
	if dot > 0 {
		return path[..dot]
	}
	return path
}

fn obj_path_of(asm_path string) string {
	return stem_of(asm_path) + '.obj'
}

// files_arg_text: 把多个输入文件渲染成命令行参数串（每个都加引号）。
// ext 非空时按 `%1.<ext>` 语义改写成 <stem>.<ext>。
fn files_arg_text(paths []string, ext string) string {
	mut parts := []string{}
	for p in paths {
		if ext.len > 0 {
			parts << '"' + stem_of(p) + '.' + ext + '"'
		} else {
			parts << '"' + p + '"'
		}
	}
	return parts.join(' ')
}

// expand_cmd_template: 兼容用户脚本里的 %1 占位符。
//   `%1.asm` / `%1.obj` -> 所有输入文件改写成带引号的 <stem>.<ext>
//   `%1`                -> 所有输入文件（带引号，空格分隔）
//   整行没有 %1          -> 在末尾追加所有输入文件
// extra（-addm / -addl / 源码指令）插在【命令与文件之间】：
//   - 有 %1 时插在第一个 %1 之前
//   - 无 %1 时插在追加文件列表之前
fn expand_cmd_template(line string, paths []string, extra string) string {
	add := trim_ws(extra)
	mut res := ''
	mut i := 0
	mut had := false
	mut inserted := false
	for i < line.len {
		if i + 1 < line.len && line[i] == 37 && line[i + 1] == 49 {
			if !inserted && add.len > 0 {
				res = res + add + ' '
				inserted = true
			}
			had = true
			mut j := i + 2
			mut ext := ''
			if j < line.len && line[j] == 46 {
				j = j + 1
				st := j
				for j < line.len {
					c := line[j]
					if (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) {
						j = j + 1
					} else {
						break
					}
				}
				ext = line[st..j]
			}
			res = res + files_arg_text(paths, ext)
			i = j
			continue
		}
		res = res + line[i..i + 1]
		i = i + 1
	}
	if !had {
		if add.len > 0 {
			res = res + ' ' + add
		}
		res = res + ' ' + files_arg_text(paths, '')
	}
	return res
}

// ---------- 默认脚本 ----------

fn default_compile_text(cone_dir string) string {
	ml := os.join_path(cone_dir, 'masm32', 'bin', 'ml.exe')
	return '"${ml}" /c /coff /nologo\n'
}

fn default_link_text(cone_dir string) string {
	lnk := os.join_path(cone_dir, 'masm32', 'bin', 'link.exe')
	return '"${lnk}" /subsystem:console\n'
}

// ensure_cmd_file: 文件存在直接读，不存在则创建默认脚本。只在缺失时写，绝不覆盖用户自定义。
fn ensure_cmd_file(path string, default_text string) !string {
	if os.exists(path) {
		content := os.read_file(path) or {
			return error('Cannot read ${path}')
		}
		return content
	}
	os.write_file(path, default_text) or {
		return error('Cannot create ${path}')
	}
	println('[cone] created ${base_name(path)}: ${trim_ws(default_text)}')
	return default_text
}

// run_commands: 逐行执行脚本（跳过空行与 ; / # 注释行），失败立即返回错误。
fn run_commands(text string, paths []string, extra string, label string) ! {
	for raw in split_lines(text) {
		line := trim_ws(raw)
		if line.len == 0 {
			continue
		}
		if line[0] == 59 || line[0] == 35 {
			continue
		}
		cmd := expand_cmd_template(line, paths, extra)
		println('[cone] ${label}: ${cmd}')
		rc := os.system(cmd)
		if rc != 0 {
			return error('${label} failed with exit code ${rc}: ${cmd}')
		}
	}
}

// run_toolchain: 全部 .asm 生成完之后调用；编译 / 链接各只执行一次，带上所有文件。
fn run_toolchain(opts CliOpts, asm_paths []string) ! {
	compile_path := os.join_path(opts.cone_dir, 'compile')
	link_path := os.join_path(opts.cone_dir, 'link')

	if opts.compile {
		txt := ensure_cmd_file(compile_path, default_compile_text(opts.cone_dir)) or {
			return error(err.msg())
		}
		run_commands(txt, asm_paths, opts.addm, 'ml') or {
			return error(err.msg())
		}
	}

	if opts.link {
		// 链接阶段同样保证 link 脚本存在（即使 -lw / -lc 忽略它的内容）。
		txt := ensure_cmd_file(link_path, default_link_text(opts.cone_dir)) or {
			return error(err.msg())
		}
		mut obj_paths := []string{}
		for a in asm_paths {
			obj_paths << obj_path_of(a)
		}
		for o in obj_paths {
			if !os.exists(o) {
				return error('Cannot find ${o}; run with -m first to produce it, or use -ml for one-step compile+link')
			}
		}
		if opts.link_windows || opts.link_console {
			lnk := os.join_path(opts.cone_dir, 'masm32', 'bin', 'link.exe')
			mut sub := '/subsystem:console'
			if opts.link_windows {
				sub = '/subsystem:windows'
			}
			mut cmd := '"${lnk}" ${sub}'
			if trim_ws(opts.addl).len > 0 {
				cmd = cmd + ' ' + trim_ws(opts.addl)
			}
			cmd = cmd + ' ' + files_arg_text(obj_paths, '')
			println('[cone] link: ${cmd}')
			rc := os.system(cmd)
			if rc != 0 {
				return error('link failed with exit code ${rc}: ${cmd}')
			}
		} else {
			run_commands(txt, obj_paths, opts.addl, 'link') or {
				return error(err.msg())
			}
		}
	}
}
