// ESLint flat config:质量门禁的核心目标是防死代码回归(no-unused-vars)
// 与未定义引用(no-undef);风格类规则从简,与 esbuild 的 Safari 16.4 目标一致。
import globals from 'globals'

export default [
    {
        files: ['src/**/*.js'],
        languageOptions: {
            ecmaVersion: 2023,
            sourceType: 'module',
            globals: { ...globals.browser },
        },
        rules: {
            // catch 绑定豁免是仓库约定(错误体不需要时的省写);
            // 下划线前缀为有意留空的占位形参
            'no-unused-vars': ['error', { caughtErrors: 'none', argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
            'no-undef': 'error',
            'no-constant-condition': 'error',
            'no-dupe-keys': 'error',
            'no-fallthrough': 'error',
            'no-unreachable': 'error',
            'no-var': 'error',
            'prefer-const': 'error',
        },
    },
]
