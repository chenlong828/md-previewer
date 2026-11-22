// Lean 4 语法（refractor 5 的 common/all 都未收录 Lean，故在仓库内自带一份）。
// 只产出 typora.css 调色板已有的 token 类，不新增需要配色的类；语言 id "lean" 与
// Swift 侧 FileSupport.codeLanguages 的条目同名，由 selftest「双端语言清单一致」守门。
//
// 覆盖：行注释与块注释（含 /-! /-- 文档注释）、字符串/字符、数字、@[attr] 属性、
// #print/#check 等命令、声明与命令关键字、常用 tactic、大写开头的类型/构造子、
// sorry/admit，以及运算符与标点。不做语义分析：上下文敏感的标识符按词表着色，
// 未收录的名字保持原文，宁可少染也不误染。
lean.displayName = 'lean'
lean.aliases = ['lean4']

// 声明、命令与控制结构：这些在 Lean 里是保留字或语法命令。
const KEYWORDS = [
    'abbrev', 'axiom', 'by', 'calc', 'class', 'def', 'deriving', 'do', 'else', 'end',
    'example', 'extends', 'fun', 'if', 'import', 'in', 'inductive', 'infix', 'infixl',
    'infixr', 'instance', 'lemma', 'let', 'macro', 'match', 'mutual', 'namespace',
    'noncomputable', 'notation', 'opaque', 'open', 'partial', 'postfix', 'prefix',
    'private', 'protected', 'rec', 'section', 'set_option', 'structure', 'syntax',
    'then', 'theorem', 'universe', 'variable', 'where', 'with',
].join('|')

// 证明里的常用 tactic/term；词表方式着色，未收录的名字按普通标识符处理。
const TACTICS = [
    'apply', 'assumption', 'cases', 'contradiction', 'decide', 'exact', 'have',
    'induction', 'intro', 'intros', 'native_decide', 'norm_num', 'obtain', 'omega',
    'rcases', 'refine', 'rename', 'repeat', 'rfl', 'ring', 'rw', 'show', 'simp',
    'subst', 'trivial', 'try', 'unfold',
].join('|')

/** @param {import('refractor').Refractor} Prism */
export default function lean(Prism) {
    Prism.languages.lean = {
        comment: [
            // 块注释（/- … -/）先于行注释，避免 /-! 与 /-- 文档注释被拆开。
            { pattern: /\/-[\s\S]*?-\//, greedy: true },
            { pattern: /--[^\n\r]*/, greedy: true },
        ],
        string: /"(?:[^"\\]|\\.)*"/,
        char: /'(?:\\.|[^\\'\n])'/,
        number:
            /\b(?:0[xX][\da-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)\b/,
        boolean: /\b(?:true|false)\b/,
        attribute: {
            pattern: /@\[[^\]]*\]/,
            inside: {
                keyword: /@/,
                'attr-name': /[^@\s,[\]]+/,
            },
        },
        // #print / #check / #eval 一类命令以 # 开头，与保留字同色。
        keyword: new RegExp(`#\\w+|\\b(?:${KEYWORDS})\\b`),
        important: /\b(?:sorry|admit)\b/,
        'class-name': /\b[A-Z][\w']*\b/,
        builtin: new RegExp(`\\b(?:${TACTICS})\\b`),
        operator:
            /:=|=>|->|<-|→|←|↔|⇒|⇐|↦|∀|∃|λ|≤|≥|≠|≈|∧|∨|¬|⁻¹|∘|⊢|·|×|∑|∏|∫|[=<>+\-*/^%|!?:&~@]+/,
        punctuation: /[()\[\]{},.;]/,
    }
    Prism.languages.lean4 = Prism.languages.lean
}
